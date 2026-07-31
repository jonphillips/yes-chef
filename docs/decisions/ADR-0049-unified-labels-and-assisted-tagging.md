# ADR-0049 — One **hierarchical label** system, and the LLM **proposes** labels against your existing tree

Status: **Accepted** — opened 2026-07-30 from Jon's "I still need to get my tags organized … best way to
autosuggest tags, at capture and at edit, smart LLM vs determinism?"; **ratified the same day with all three
open questions answered** (see Resolved). S1 is dispatchable. The design converged in that session:
tags and categories **merge into one thing**, the label proposer is **one engine surfaced in three places**,
and capture-vs-share is forced by the extension networking gate. Supersedes the two-entity tag/category split.
Extends [ADR-0026](ADR-0026-review-collection-sheet.md) (the review-collection sheet is the proposer's UI),
[ADR-0023](ADR-0023-recipe-edit-proposals.md) (propose-to-preview, commit deterministically) and
[ADR-0025](ADR-0025-reader-comment-ingestion.md) (the one-by-one curation queue). Governed by
[ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) (advisory LLM vs deterministic write boundary),
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless-or-loud parse),
[ADR-0043](ADR-0043-model-call-chokepoint.md) (every model call declares itself) and
[ADR-0047](ADR-0047-llm-capture-fallback.md) (deterministic-first, LLM only where the contract is absent).

## Context

**Tags are unorganized and there is no way to get them organized.** A recipe's labels are only as useful as
their consistency: the same concept must always get the same label or browse and filter degrade. Today nothing
proposes labels, so the library accretes ad-hoc tags by hand and most recipes carry none.

**There are two near-identical entities doing one job.** `tags` (id, name, **color**, sortOrder) + `recipeTags`,
and `categories` (id, name, **parentCategoryID**, sortOrder) + `recipeCategories`. `categories` is already a
**live nested folder tree** — [`CategoryBrowserView`](../../YesChefApp/CategoryViews.swift) does drill-down,
add-child, parent-validation and move; a past migration added the hierarchy and then loosened the parent FK for
CloudKit sync. `tags` is flat. Two stores, two reconcilers
([`reconcileTags`](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift) and
[`reconcileCategories`](../../YesChefPackage/Sources/YesChefCore/RecipeCategoryRepository.swift)), both already
case-insensitive-matching to canonical rows.

**Jon's own framing collapses the two.** He wants structured labels where the parent is the hint —
`Cookbook: Milk Street 365`, `Cuisine: Mexican` — *and* loose parentless labels he can slap on without inventing
a namespace — `Jon and Wendy travel penance` — *and* more namespaces than a fixed Cuisine/Course pair. That is
exactly what `parentCategoryID` already expresses: **has-parent = structured, no-parent = loose.** So the answer
is not a new `kind` column or a second axis; it is to stop maintaining two entities.

**The cost-of-error is lopsided, which decides the LLM question.** A bad *suggestion* is one tap to dismiss
(advisory). *Vocabulary drift* — the model inventing `quick` when you have `Weeknight`, or `taco` under three
different parents — silently poisons every future browse (canonical shared state). Per ADR-0022 that puts the
LLM firmly on the advisory side of the line: it may **propose**, it may never **write**.

**The structured metadata is already on the page and thrown away.** The capture pipeline harvests
`recipeCategory` into `categoryNames`, but discards schema.org `keywords` and `recipeCuisine`, and
`ParsedRecipePage.tagNames` is dead (always `[]`). That is free, high-precision label data — the publisher's own
labels — going in the bin.

**Capture can call the model; the Share Extension cannot.** Browser capture already runs an LLM pass
(ADR-0047), so proposing labels there is riding existing momentum, not a new cost. The Share Extension must
never network ([[extension-sync-construct-not-run]] — construct-not-run); recipes it imports arrive unlabeled and
must be served by a *deferred* path, not an inline one.

## Decision

### D1 — One labeling system: the category tree, with tags folded in as **loose root nodes**

Retire the `tags` / `recipeTags` tables. Everything is a label node in `categories` / `recipeCategories`:

- **Structured label** = a node with a parent. The parent is a **namespace** and renders as the hint:
  `Cuisine: Mexican`, `Cookbook: Milk Street 365`, `Author: Samin Nosrat`.
- **Loose label** = a root node with no parent: `Jon and Wendy travel penance`. Today's tags migrate here.

Namespaces are **open-ended** — Cuisine and Course are seeded, but Cookbook, Author, Season, Occasion are just
more parent nodes; nothing is hardcoded. **No `kind` column** — the parent *is* the dimension, which is what
buys open-endedness for free. `color` moves onto `categories` so loose labels keep the tag affordance. The
existing browser UI is the tool; it is "pretty good" and we lean on it rather than replacing it.

We do **not** enforce single-valued namespaces in the schema (a recipe can be in two cookbooks). Any
"one Cuisine per recipe" feel is a soft picker convention, not a constraint.

### D2 — The LLM **proposes to a review surface**; determinism **gates**; a human **taps**

One reusable engine, no UI:

```
LabelProposer(recipe, existingTree, seeds, tier) -> [SuggestedLabel]
```

- It **declares its model call** (ADR-0043) and defaults to the **on-device tier** ([[yeschef-onbard-model-tier]])
  — a small, bounded, latency-tolerant, private classification against a fixed vocabulary is precisely that
  tier's job.
- It parses model output **lossless-or-loud** (ADR-0040): a suggestion it cannot map is surfaced, never
  dropped.
- Its output is **advisory only.** Every accepted label flows through the existing case-insensitive reconcile,
  which is the sole writer and the sole creator of canonical nodes. The model never inserts a row. This is the
  ADR-0023 shape (propose → preview → deterministic commit) applied to labels.

### D3 — The proposer is **anchored on your existing tree**, with newness priced in three tiers

The anti-sprawl move is to never ask "what labels fit this recipe?" in a vacuum. The prompt carries the existing
namespaces and their children (and a seed taxonomy for cold-start), and asks the model to **prefer attaching to
what exists.** New-ness is allowed in inverse proportion to its cost:

| Tier | Example | Policy |
| --- | --- | --- |
| New child under an existing namespace | `Cuisine: Korean` | Cheap — propose freely |
| New loose root label | `travel penance` | Fine, but usually user-authored (the model won't know private labels) |
| New **namespace** | a whole new dimension | Rare — surfaced as a deliberate, distinct confirmation, not a chip |

Two defense layers stack: reconcile kills **exact-name** dups (Layer 1, always on); anchoring kills **synonym**
dups — `quick` vs `Weeknight` (Layer 2, where a model runs). **Seed namespaces** (Cuisine, Course + starter
values) are the cross-generation prior that makes anchoring work before the user's own tree is mature — the same
role grocery `seedAreas` plays ([[grocery-area-no-learned-cache]]).

### D4 — Capture proposes **inline**; the Share Extension **defers** to the queue

- **Browser capture:** after extraction, auto-invoke `LabelProposer` (its own call — kept separate from the
  extraction prompt so the ADR-0047 vote ladder stays clean and the same engine is reused everywhere; one extra
  call is free in a single-user app). Suggestions land as chips in the capture review sheet (ADR-0026). Never
  block the import on it.
- **Share Extension:** no model call, ever. Its imports arrive unlabeled and are picked up by the batch queue
  (D5). This is a designed fallback, not a gap.

### D5 — Three surfaces, **one engine**

1. **Capture chips** (D4) — in the review sheet.
2. **Detail-view mini-labeler** — a standalone lightweight sheet reachable from the recipe *detail* view, **not**
   buried in the editor (the editor is already too heavy to enter for one small thing). Its empty state is the
   "Suggest labels" CTA; on an already-labeled recipe it re-runs as "suggest more."
3. **"Needs labels" batch queue** — a library filter (reusing `RecipeActiveFilterBar`) plus a one-by-one review
   mode (the ADR-0025 curation shape) for clearing the backlog from the couch. On-device tier, no network, no
   cost. Prefetch the next recipe's suggestions while the current one is reviewed. "Needs labels" means missing
   the labels a namespace would want — not merely "zero loose tags," since loose labels are optional by nature.

### D6 — Tier-0 free structured harvest is **deterministic and independent of any model**

Wire schema.org `keywords` and `recipeCuisine` into labels (revive dead `tagNames`); `recipeCategory` already
flows to `categoryNames`. `recipeCuisine` attaches under the seeded `Cuisine` namespace; `keywords` land as loose
labels; the publisher's own labels are high-precision and cost nothing. This ships independent of the proposer
and is pure win regardless of how the model tiers land.

### D7 — The S2 starter vocabulary is durable synced data, with monotonic deletion suppression

The exact starter vocabulary is user-visible durable data, not a display-only convenience. S2 uses fixed UUIDs
and the following canonical 20-row tree:

| Namespace | Starter children |
| --- | --- |
| `Cuisine` | American, Chinese, French, Indian, Italian, Japanese, Korean, Mexican, Thai, Vietnamese |
| `Course` | Breakfast, Lunch, Dinner, Appetizer, Side Dish, Dessert, Snack, Drink |

The persisted model is additive: `categorySeedStates` maps each fixed seed UUID to the category row that
currently represents it, and `categorySeedTombstones` is a presence-only, fixed-ID record for an intentionally
deleted seed. Both tables have a loose UUID relationship rather than a foreign key: the state mapping may point
at a user-authored category, and a deletion tombstone must outlive the category it suppresses. The migration adds
the tombstone table and backfills one from any earlier `categorySeedStates.isDeleted` row, without modifying a
recipe or category row. `isDeleted` and `dateModified` remain in the state schema only as compatibility fields:
we cannot safely assume an early S2/dogfood build was never opened against a live library. Current logic never
uses them to decide deletion; once the compatibility window can be retired in a deliberately versioned migration,
the mapping's final shape is just `id` and `categoryID`.

Seeder convergence is deliberately monotonic. It checks a tombstone before it creates or maps a seed, and never
writes a non-deleted tombstone counterpart; therefore a later fresh/offline peer cannot clear a prior deletion by
writing a newer `false` field. Tombstones are reconciled independently of parent resolution and deleted leaf-first,
retaining the recipe-reference guard, so a fully deleted namespace converges even on a late peer. Category reads
exclude tombstoned deterministic rows immediately when a CloudKit tombstone arrives; physical cleanup also runs at
the next owned category write and every main-app bootstrap. Child seeds wait for their parent seed to resolve; an
absent or tombstoned parent is never interpreted as a root. Installed states still run the same-name, same-parent
total-order merge and are repointed to the survivor, so concurrent existing-category adoption and deterministic
seeding converge. These write passes run only in the main app after CloudSync installs its triggers; the short-lived
Share Extension constructs its stopped engine but performs no seed/fold data writes.

**Logical deletion is a state constraint, not a cleanup event.** Every product reader, tree validation, and
recipe-category assignment derives one **effective category set** from raw rows plus tombstones. The set excludes
each tombstoned starter identity **and its current `categorySeedStates` representative**, then repeatedly excludes
rows whose *current* parent points into that excluded set; this remains true if a parent row is physically retained
or has already disappeared. A starter row that the user actually moved outside the deleted namespace remains
eligible because this is based on the stored parent chain, not its original seed relationship. Physical reclamation
uses the same resolved roots but is deliberately separate: it removes only eligible leaf rows with no recipe
reference, and is an optimization rather than a condition for correct product behavior. The only raw-category
access is inside the effective-set source and physical seed/reclamation/merge convergence code, which must see
retained rows to repair or repoint them before deletion. A dormant tag with the UUID of an unavailable mapped
representative is skipped by the fold. A distinct-ID dormant tag that previously merged by name into a tombstoned
root starter is also skipped by that starter's canonical name, so neither fold path can recreate the logically
deleted namespace or restore its retired recipe-tag joins.

An imported publisher label only matches an effective category. If it textually reintroduces a tombstoned starter
label, reconciliation creates a fresh user-category UUID rather than attaching a recipe to the tombstoned identity.
That preserves incoming recipe metadata without resurrecting or making the deleted starter row eligible.

The rejected simpler alternative was an `isDeleted` boolean on the same synced state row used for normal
installation. SQLiteData resolves fields by database-edit timestamp, so a later fresh-device `false` write could
overwrite an earlier `true` deletion. A presence-only tombstone has no non-deleted write to win that conflict.

## Resolved

- **OQ1 — Name of the unified concept → "Categories."** The surfaced concept stays **Categories**; storage stays
  `categories`. Loose labels are just parentless categories. No rename, UI or schema.
- **OQ2 — Korean taco vs Mexican taco → loose label.** `taco` is a **loose label** that co-occurs with
  `Cuisine: Mexican` / `Cuisine: Korean`; it sidesteps the sub-cuisine trap and keeps cuisine single-ish.
  Documented convention, not enforced — the user re-parents freely (Jon may later author a `Form Factor`
  namespace; that is a user-authored parent node, **no code implication**).
- **OQ3 — Tags are subsumed into categories.** Triage below (see the revised S1). The fold is a **post-engine,
  deterministic-UUID, idempotent data pass**, not a `registerMigration` write, and the old tables go **dormant,
  not dropped**.

## Slices

- **S1 — Unify the store (OQ3 triage).** Foundational; everything downstream targets one store. Two distinct
  passes — do **not** conflate them:
  1. **Schema DDL (pre-engine, in `registerMigration`).** Add the `color` column to `categories`. Pure
     structure, no data movement — this is the only part safe inside a migration block.
  2. **Data fold (post-engine, deterministic, idempotent).** Runs *after* `makeSyncEngine` so its writes carry
     sync metadata and converge ([[migration-writes-bypass-sync-triggers]]). Each `tag` becomes a **root
     `category` reusing the tag's own UUID** (`category.id = tag.id`) — that reuse is what makes the fold
     converge even when two devices run it independently, since both land the identical id. `color`, `name`,
     `sortOrder`, `dateCreated` carry over. Each `recipeTag` becomes a `recipeCategory` (reuse `recipeTag.id`;
     `categoryID = recipeTag.tagID`). **Merge-on-name:** if a native same-named category already exists
     (case-insensitive), re-point the recipe links to it instead of minting a dup — de-sprawl is the whole
     point — and **dedupe** so a recipe that had both tag "Veg" and category "Veg" gets one `(recipeID,
     categoryID)` link, not two (`recipeCategories` has no unique index on the pair, so guard in code).
     Idempotent: gate each row on "does the target already exist," so re-running every boot is a no-op.
  3. **Retire writes; leave tables dormant.** Stop all writes to `tags`/`recipeTags` and migrate reads to
     categories. **Do not drop** the physical tables — dropping a synced table is itself a sync event; dormant
     unreferenced rows are harmless. Physical removal is a later, optional slice, or never.
- **S2 — Tier-0 harvest + seed namespaces (D6).** Revive `tagNames`; route `keywords`/`recipeCuisine`; seed
  Cuisine/Course namespaces + starter values. Deterministic, no model.
- **S3 — `LabelProposer` engine (D2/D3).** Pure Core, declares its call (ADR-0043), on-device default, loud
  parse (ADR-0040), anchored prompt + three-tier policy. Unit-tested against a fixture tree; no UI.
- **S4 — Capture integration (D4).** Auto-invoke after extraction; chips in the review sheet; Share Extension
  explicitly skips. *Batchable with S3.*
- **S5 — Detail-view mini-labeler (D5.2).** Standalone sheet, empty-state CTA, re-runnable; reuses proposer +
  reconcile.
- **S6 — "Needs labels" batch queue (D5.3).** Library filter + one-by-one review + prefetch. *Batchable with
  S5.*

Deterministic-first ordering: **S1 → S2 ship value with zero model risk**; S3 is the only new model surface;
S4–S6 are the three consumers that make S3 worth building (they decisively pass the "does a real consumer ship
with this?" test — [[synced-table-cost-calibration]]).
