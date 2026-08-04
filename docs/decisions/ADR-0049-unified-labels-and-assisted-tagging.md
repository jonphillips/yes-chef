# ADR-0049 — One **hierarchical label** system, and the LLM **proposes** labels against your existing tree

Status: **Accepted** — opened 2026-07-30 from Jon's "I still need to get my tags organized … best way to
autosuggest tags, at capture and at edit, smart LLM vs determinism?"; **ratified the same day with all three
open questions answered** (see Resolved). S1 is dispatchable. The design converged in that session:
tags and categories **merge into one thing**, the label proposer is **one engine surfaced in three places**,
and capture-vs-share is forced by the extension networking gate. Supersedes the two-entity tag/category split.
**Amendment 1 (2026-07-30, accepted): D7's persisted deletion model is retired — seed starter categories in
place by fixed id, make them non-deletable, and drop `categorySeedStates` + `categorySeedTombstones`. See
Amendment 1.**
**Amendment 2 (2026-08-01, proposed): D1's "the parent is the dimension" is superseded — a **facet** becomes
an explicit synced entity and structured values carry `facetID`; loose labels are `facetID == nil`. Amendment 2
**absorbs unbuilt Amendment 1** — do not implement Amd 1 separately. Supersedes OQ2. See Amendment 2.**
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

## Amendment 1 — D7 over-built for the audience: seed in place, starters non-deletable, retire the seed-state + tombstone tables (2026-07-30)

Status: **Accepted** — 2026-07-30, pre-production. **Supersedes D7's persisted model** (`categorySeedStates`
and `categorySeedTombstones`). Keeps D7's *starter vocabulary* and its fixed-UUID cross-device convergence;
retires the machinery around deletion.

**Why.** D7 is correctly engineered — for a robustness bar it doesn't have. The tombstone + monotonic-deletion
reconciliation exists to survive offline peers racing to clear each other's deletions and late-peer leaf-first
convergence; that bar is far beyond ~10 friendly users on one or two devices each. Two tells confirm the drift:
`categorySeedStates.isDeleted`/`dateModified` are already **vestigial** (the struct's own comment says so), and a
table whose entire job is to record the *absence* of default rows is a recurring confidence tax every time the
schema is read — schema you re-read and distrust is a liability even when it works. We are pre-prod with an
erasable DB and a known, tiny install base, so this is the cheapest it will ever be to fix; deferring is how it
reaches production and locks forever ([[withdraw-not-defer-orphaned-schema]]).

**New model.**
- **Seed the `Category` rows directly with their fixed seed UUID** (`category.id == seed.id`), insert-if-absent,
  idempotent, run post-`SyncEngine` with deterministic IDs so convergence is preserved
  ([[migration-writes-bypass-sync-triggers]]). The mapping table becomes an identity function and disappears.
- **Rename is in place:** edit `category.name`; the id is unchanged, so the re-seed pass skips it. No state row.
- **Starter categories are not deletable.** Renaming covers "I don't want *Thai*" (rename or repurpose the row);
  user-authored categories (non-seed ids) delete **freely**, with zero seed bookkeeping and no tombstone.
- **Retire `categorySeedStates` and `categorySeedTombstones` entirely** — tables, reconciliation, and CloudSync
  registration.
- **Defer, don't build, "hide a starter outright":** if a user ever wants a starter *gone* rather than renamed,
  add a synced `hidden: Bool` **column** on `Category` at that point — strictly cheaper than a table, and only
  if the need is real.

**What we give up.** Cross-device "delete a starter and it stays deleted." Accepted: rename covers the real
need, and a future `hidden` column is a far cheaper way to buy back removal than two synced tables and ~800
lines of convergence logic. The D7 "leave the physical table dormant" caution (S1) was about the **production**
tag tables with real rows; it does not apply to pre-prod seed tables no user data depends on.

**Do the clean teardown; do not let a disposable test library dictate the schema.** Jon's ~2000-recipe device
library is a *rebuildable test database* (ADR-0030 backup/restore + CloudKit resync), and preserving it is not
worth carrying compatibility scaffolding we dislike on sight. Crucially, this change's blast radius is only the
~24 seed rows and their two bookkeeping tables — **recipes and every recipe→category join ride through
untouched** — so "keep my 2000 recipes" and "clean code" are not in tension here; the scary row count is a red
herring for this change.

**New model.**
- Seed `Category(id: seed.id, …)`, **insert-if-absent, every boot**. Deterministic ids already give cross-device
  convergence (CloudKit dedupes by record id), so no mapping table is needed. Runs post-`SyncEngine`,
  deterministic ([[migration-writes-bypass-sync-triggers]]).
- **Physically drop `categorySeedStates` and `categorySeedTombstones`** — delete the structs, the migration
  drops the tables, remove both from `CloudSync` registration. No dormant-table theater.
- Starters are **non-deletable** (multi-device + no tombstone forces this: a plain-deletable starter resurrects
  on any fresh reinstall-after-delete, which is exactly what the tombstone existed to stop). The humane escape
  is a **synced `hidden: Bool` column on `Category`** — folded into this slice, because "remove a default I
  never use" is a real, stated want and one additive column completes the "hideable not deletable" design
  rather than forcing a second trip.
- `RecipeCategoryRepository` collapses from ~849 lines to seed + normal CRUD.

**Migration on the live device.** A normal forward migration (add `categories.hidden`; drop the two seed tables;
reseed by id) is safe for recipes and needs no erase — `eraseDatabaseOnSchemaChange` stays opt-in/off
([[debug-erase-vs-sync-triggers]]). Worst case is two *cosmetic* artifacts on starter categories only: a
duplicate root if a seed had been adopted onto a same-named user category, and the reappearance of a
previously-deleted starter. Both are fixed by hand in the UI in minutes; neither touches a recipe. If a
zero-artifact result is wanted, the alternative is a deliberate restart — but it MUST follow the enforced
restore procedure ([[restore-is-authoritative]]): quiesce **both** devices, restore on one, reinstall the other
fresh, or a peer's queued delete can silently re-delete restored rows.

## Amendment 2 — the namespace is a **facet**, and a facet is a row, not a tree position (2026-08-01)

Status: **Proposed** — 2026-08-01, pre-production. **Supersedes D1's "no `kind` column — the parent *is* the
dimension"** and **OQ2**. **Absorbs Amendment 1**, which is accepted but unbuilt: its teardown ships inside this
migration, not ahead of it. Keeps everything else D1 bought — one assignment store, one reconciler, open-ended
user-authored dimensions, loose labels, `color` on `categories`, the retired tag tables, D2's propose-review-commit
boundary, D3's anchoring, D6's harvest. Triggered by [ADR-0050](ADR-0050-recipe-power-browser.md), which is the
first consumer that has to ask a question tree position cannot answer.

### Why the D1 mechanism fails now, and why its *goal* survives

D1's argument was about **open-endedness**: don't hardcode a Cuisine/Course enum, because Jon wants Cookbook,
Author, Season, Occasion and dimensions nobody has thought of yet. That argument was correct and is untouched —
a `facets` **table** is as open-ended as a parent node, since a user-authored dimension is just a row. What D1
picked was a *mechanism*, and the mechanism has one defect: **a parentless category row is six things at once.**

`Cuisine` (a dimension), `Taco` (a value that hasn't been filed yet), `Milk Street` (a harvested publisher
keyword), `Beach Week` (a loose label), a structural grouping node, and a folded former tag are **the same shape
in the same table**, distinguishable only by convention. Nothing reads the convention, so nothing enforces it.

**The proposer already had to invent the distinction to do its job, and the schema is the only layer that still
refuses it.** [`SuggestedLabel.Kind`](../../YesChefPackage/Sources/YesChefCore/LabelProposer.swift) has four
cases — `existingCategory`, `newChild`, `loose`, `namespace` — and `.namespace` exists *because creating a
dimension is a different act with a different confirmation*. PR #269's Finding 3 then had to teach it to carry
`[dimension, firstChild]` and file the recipe under the **child**, because filing under a bare dimension root is
meaningless — which is the schema-level truth "a facet is not assignable" being enforced by hand, in the
proposer, one call site at a time. **Every layer above storage already knows facets are a different kind of
thing.** Amendment 2 stops making each of them re-derive it.

**Accidental promotion is the concrete failure.** `Taco` arrives as a loose root. A month later the user adds
`Taco > Birria`. Under D1 the app now believes Taco is a classification dimension, because that is all
"has children" can mean. It isn't; it is a value inside Dish Type that acquired a specialization. There is no
edit the user could have made to express the difference, and no query that can recover it afterward.

### D8 — A facet is an explicit synced entity

```swift
@Table("facets")
public struct Facet: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var sortOrder: Int
  public var hidden: Bool          // Amd 1's escape hatch, at the dimension grain
  public var dateCreated: Date
}
```

`Category` gains exactly two columns:

```swift
public var facetID: Facet.ID?      // non-nil = structured facet value; nil = loose label
public var hidden: Bool            // Amd 1, folded in here
```

- **`facetID != nil` → a facet value. `facetID == nil` → a loose label.** That single field replaces the
  convention D1 asked readers to hold in their heads.
- **A `Facet` is not a `Category` and has no row in `categories`.** `Cuisine` and `Course` stop existing as
  category rows; they become facet rows. This is the migration's one structurally interesting move (§ Migration).
- **Open-endedness is preserved literally.** A user-authored facet is an insert. Nothing is hardcoded, and the
  seeded facets are ordinary rows with fixed ids.

**What is deliberately *not* in that record**, and what would put it there:

| Deferred | Why not now | Trigger that earns it |
| --- | --- | --- |
| `selectionMode` (single vs multi) | D1 already decided we do not enforce single-valued dimensions in the schema; a recipe is legitimately Korean **and** Mexican. Nothing today wants the constraint. | A picker that must *prevent* a second value — not one that merely looks single-ish. |
| `maximumValueDepth` | No consumer. Depth is emergent; a cap is a rule with no rule-breaker. | A real two-level-deep vocabulary that someone actually over-nests. |
| `isAssignable` on a value | ADR-0050 D3's descendant matching means an intermediate value is *findable* whether or not it is *assignable*, so the column would only gate a picker. | A facet where assigning the parent is genuinely wrong, demonstrated on real data. |
| `isSystemProvided` | **Derivable** — the starter ids are fixed constants in Core. A stored copy is a second source of truth that can disagree with the first. | Never; use the id set. |
| per-facet coverage thresholds | ADR-0050's ranking is deterministic and works off measured coverage. | Measured coverage proving a global rule is wrong for one facet. |

This table is the amendment doing to itself what Amendment 1 did to D7. The draft this amendment was written
from carried all six fields plus the sentence *"the initial implementation may support a limited subset of this
metadata, but the architecture must permit it"* — which is precisely the shape of the tombstone machinery: schema
justified by a robustness bar we do not have, for an audience of ~10 friendly users
([[withdraw-not-defer-orphaned-schema]], [[synced-table-cost-calibration]]). **One table and two columns is the
whole cost of this amendment.** If it grows past that in implementation, the growth is the defect.

### D9 — Four invariants, enforced in Core, not in convention

1. **Facet membership.** A structured value belongs to exactly one facet.
2. **Parent consistency.** If a value has a `parentCategoryID`, both rows carry the **same** `facetID`. A value
   may not have a parent from another facet, and may not have a loose-label parent.
3. **Loose labels are leaves.** `facetID == nil` implies no children. Nesting under a loose label is not a
   parent edit; it is an explicit *convert-to-facet* or *file-under-facet* operation, which is exactly the
   accidental-promotion failure made deliberate.
4. **Facets are not assignable.** `recipeCategories` may reference a facet value or a loose label, never a
   facet — which is now enforceable by construction, since a facet has no category row to reference.

These live with `reconcileCategories`, which stays **the sole writer and sole creator of nodes** (D2 unchanged),
and are unit-tested there. An invariant that only the UI upholds is a convention wearing a costume.

### D10 — Assignment is most-specific; ancestor matching is **derived**

A recipe classified `Protein = Beef > Tenderloin` stores **one** join, to `Tenderloin`. Filtering on `Beef`
matches it, because the query layer walks descendants ([ADR-0050](ADR-0050-recipe-power-browser.md) D3). We do
**not** additionally store the ancestor join.

The alternative — materializing ancestor joins on write — was rejected: it doubles the join rows, makes a
re-parent a multi-row rewrite that must converge across devices, and creates a state where the derived rows can
disagree with the tree. `descendantIDs(of:in:)` already exists in
[`CategoryHierarchy`](../../YesChefPackage/Sources/YesChefCore/CategoryHierarchy.swift).

Corollary the migration owes: a recipe that ends up joined to **both** `Beef` and `Beef > Tenderloin` is not
wrong, just redundant. Report it in the audit; do not silently collapse it, since the parent assignment may be a
second, real classification the user made before the child existed.

### D11 — The proposer gets typed facets, and a path string stops being the interface

D2's boundary is unchanged: the model **proposes**, determinism **writes**. What changes is what crosses the
boundary in each direction.

- **In:** the prompt carries facets and their values as **structured** vocabulary, not an undifferentiated tree.
- **Out:** `SuggestedLabel` resolves against facet identity before it reaches reconcile. Its four `Kind` cases
  survive nearly unchanged — `.namespace` is renamed and **means something now**: a proposal to create a `Facet`
  row, which keeps PR #269's elevated `item:`-binding confirmation.
- **Path strings stay legal exactly where they are unavoidable** — model output and import — and are **resolved
  and validated at that boundary**, never persisted as the canonical interface. A `String` that means
  `"Protein > Beef > Tenderloin"` is a serialization ([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md):
  the human never authors the serialization format, and neither does the repository API).
- **A model-generated path may never implicitly create a facet.** Under D1 it structurally could — a two-component
  path where the root didn't exist minted a root, and only the proposer's own tiering stopped it. Now the facet
  must already exist or be confirmed as a facet.
- **Hidden vocabulary follows the product cascade.** The proposer receives visible facets and visible values
  only. A hidden category group is deliberately out of scope for fresh model suggestions. If a user accepts a
  new-value suggestion that case-insensitively collides with a hidden row in the identified facet, reconciliation
  reuses **and unhides** that row: the user deliberately chose it again. This is limited to an accepted
  suggestion; ordinary imported text does not reactivate hidden vocabulary.

### D12 — Import maps into facets; unknown vocabulary stays loose

D6's harvest is unchanged in what it collects and stricter in where it files:

- `recipeCuisine` → the **Cuisine** facet.
- `recipeCategory` → a known facet **only when confidently interpretable**; otherwise loose.
- publisher `keywords` → **loose labels**, as today.
- **A delimiter in an imported string is not a hierarchy signal.** `"Dinner > Weeknight"` from a publisher does
  not create a facet, a value, or a parent link; it is one loose label until a human files it. Import is the
  highest-volume, lowest-intent writer in the app, and D1's convention gave it the power to define dimensions.

### D13 — OQ2 is superseded

OQ2 resolved: *`taco` is a loose label that co-occurs with `Cuisine: Mexican` / `Cuisine: Korean`.* That was the
right answer **given no facets** — it dodged the sub-cuisine trap by refusing to file `taco` anywhere. With an
explicit Dish Type facet the dodge is unnecessary and now actively wrong: `taco` is
`Dish Type > Handheld > Taco`, a Korean beef taco carries `Cuisine = Korean` **and** `Cuisine = Mexican`
alongside it, and the OQ2 note that Jon "may later author a `Form Factor` namespace" is exactly this decision,
arrived at from the other side.

The rest of OQ2 stands: cuisine multiplicity is not enforced (D8), and the user re-files freely.

**OQ1 stands, and the copy already exists.** The surfaced umbrella stays **Categories**. A facet surfaces as a
**category group** — which is not new copy, it is what `SuggestedLabel.reviewTitle` already says for
`.namespace`. `Facet` / facet value / loose label are internal architecture terms.

### Migration — one pass, absorbing Amendment 1

**Amendment 1 must not ship first.** Its plan (seed the ~24 starter *categories* in place by fixed id, drop the
two seed tables, add `hidden`) and this one both rewrite the same rows, and Amd 2 changes what two of those rows
*are*. Sequenced separately that is two synced data passes and two two-device verification passes over ~24 rows
for one outcome. Absorbed, the teardown is free: the seed pass being written is the facet-aware one.

Schema DDL, pre-engine, in `registerMigration` — structure only, no data movement
([[migration-writes-bypass-sync-triggers]]):

- create `facets`; add `categories.facetID`, `categories.hidden`;
- **drop `categorySeedStates` and `categorySeedTombstones`** (Amd 1), remove both structs and both `CloudSync`
  registrations, and take them **off** the prod-promotion list.

Data pass, post-`makeSyncEngine`, deterministic ids, idempotent, insert-if-absent:

1. **Seed the facets** with fixed ids. Initial set is deliberately **Cuisine and Course only** — the ones that
   exist and carry real assignments. The larger editorial taxonomy (Dish Type, Protein, Technique, …) is a
   *content* decision and does not ride a schema migration; see § Open.
2. **Promote the two namespace roots.** For `Cuisine` and `Course`: create the facet row, set every child's
   `facetID`, set every child's `parentCategoryID` to `nil`, then delete the old root **category** row.
   **Child UUIDs are preserved, so every `recipeCategories` join rides through untouched** — the same
   blast-radius argument Amd 1 made, and the reason "keep my ~2000 recipes" and "clean model" are not in
   tension here either.
3. **Recipes joined directly to a namespace root** — possible via harvest or a hand-file under D1 — are the one
   genuinely lossy case. **Remap, never drop**: re-point to a designated child if one is unambiguous, otherwise
   re-point to a loose label carrying the root's name and **list every one in the audit**. A dimension
   assignment is not information we are entitled to discard because the model got tidier.
4. **Every other parentless category becomes a loose label** (`facetID = nil`) — including all folded former
   tags, which is where S1 already put them and where they belong.
5. **A parentless category *with* children** is the ambiguous case and is **not auto-promoted**. Report it; Jon
   files it by hand. Auto-promotion here would enshrine the exact accidental-facet inference this amendment
   exists to remove.

**The audit report is a deliverable of the slice, not a nicety.** Per original category: new classification,
affected recipe count, parent changes, merges, deletions, unresolved rows, and every remapped root assignment.
Jon reviews it before the second device is allowed to converge.

**Starters stay non-deletable and hideable** (Amd 1, unchanged) — now at both grains, since `hidden` lands on
`Facet` and `Category` in the same pass. Cleanup of poor starter values is a **hand pass in the UI**, not
migration logic.

### Consequences

**Positive.** Facets are a fact, not an inference. ADR-0050 gets stable dimensions to query. The proposer's
existing four-case shape gets a storage counterpart instead of a convention it enforces alone. Import can no
longer define dimensions. Loose labels stay unstructured without polluting the taxonomy. One assignment store,
one reconciler, all recipe joins preserved.

**Negative, honestly.** One new synced table and two columns, on a model that was unified eight PRs ago —
churn on recent work, and this amendment reverses a mechanism D1 argued for explicitly, which is a real cost to
the decision log's credibility and is why the argument above is about *why the mechanism failed*, not why the
new one is nicer. The repository API and proposer schema both move. The management UI must now present two
structurally different creation acts. Some existing category trees need a hand pass. And the invariants are
new validation code that did not exist.

**Accepted because pre-production is the whole reason.** ~2000 recipes on one erasable, restorable test library
([ADR-0030](ADR-0030-local-backup-and-restore.md)), ~10 friendly users, no production CloudKit schema. The
alternative is that every subsequent labeling run, AI backfill and taxonomy expansion deepens the dependency on
the ambiguous model — which is the same reasoning that carried Amendment 1 six days ago, applied to a defect one
layer up.

### Rejected alternatives

- **Keep D1's parent-as-dimension.** Rejected on the accidental-promotion failure above: tree position cannot
  distinguish a dimension from a value that grew a child, and no user edit can express the difference.
- **A `kind` enum on `Category`.** The cheapest fix, and genuinely close. Rejected because it answers "what is
  this row" but not "what does this dimension do" — every facet-level property (`sortOrder` among dimensions,
  `hidden`, later `selectionMode`) would live on a row that is *also* pretending to be assignable, and the
  invariant "a facet has no recipe joins" would stay unenforceable rather than becoming structural. **A separate
  table makes rule 4 impossible to violate instead of merely illegal.**
- **Materialized ancestor joins.** Rejected in D10.
- **Restore separate tag and category tables.** Rejected — reintroduces two assignment stores and two
  reconcilers, which is the disease D1 cured.
- **A closed, hardcoded facet enum.** Rejected — this is D1's original open-endedness argument, and it still
  wins.
- **Defer until ADR-0050 needs it.** Rejected: the backfill that makes the browser worth building is the thing
  that would encode thousands of assignments against the ambiguous model first.

### Resolved

- **OQ5 — source metadata stays typed; `Cookbook:` and `Author:` are NOT facets (closed 2026-08-01).** D1
  invited `Cookbook: Milk Street 365` and `Author: Samin Nosrat` as namespaces, which was reasonable when a
  namespace cost nothing but a parent row. It is now a **contradiction with
  [ADR-0006](ADR-0006-taxonomy-source-and-library-placement.md)**, which already gave source, author and
  publication typed homes — and D1's invitation would have made them *both*, so a Milk Street recipe could be
  filed twice, in two stores, with two spellings, and no reconciler between them. **The facet vocabulary is for
  things a cook classifies; source is something a recipe already carries.** ADR-0050 filters source from the
  typed fields (its D7). Practical consequences for the slice: **do not seed a Cookbook, Author, Publication or
  Website facet**, and D12's import mapping sends publisher identity to the typed source fields, never to a
  facet.

  What we give up: a user who *wants* `Cookbook` as a browsing dimension has to get it from source filters
  rather than the taxonomy. Accepted — source filters give the same browsing power without a second store, and
  ADR-0006's typed fields are the ones capture already populates.

- **OQ4 — editorial taxonomy decided (closed 2026-08-04, Jon).** Four editorial facets earn a seat alongside
  `Cuisine` and `Course`: **Protein, Dietary, Dish Type, Technique** — seeded flat with fixed ids and starter
  values (below), the same deterministic post-`makeSyncEngine` seed shape D1 used for Cuisine/Course.

  **Declined, with reason** (the anti-sprawl bar is "will I browse by this," not "is this a plausible axis"):
  **Featured Ingredient** — an unbounded vocabulary (every ingredient); this is ingredient full-text search, not
  a curated facet, and the publisher `keywords` harvest already lands the long tail as loose labels.
  **Practical** (Quick / Make-Ahead / Freezer-Friendly / One-Pot) — these are
  [ADR-0050](ADR-0050-recipe-power-browser.md) D7 typed/derived *attributes*, not taxonomy; a "Under 60 min"
  facet value lies the moment a time changes. **Occasion** — fuzzy, and "Weeknight" collides with the declined
  Practical bucket, so it becomes a catch-all. **Season** — low classification rate, weak browse signal.

  **Shapes.** Protein / Dietary / Technique are **multi-value**; Dish Type is **single-ish** (a soft picker
  convention, *no* `selectionMode` column — D8). All **flat**; nesting (`Protein > Beef > Tenderloin`) is
  deferred until real over-nesting earns it (D8).

  **The Technique ↔ Dish Type boundary.** Dish Type is the plated **form** (a noun); Technique is the **method**
  (a verb). A word that is both lives in **Technique** — `Grill`, `Roast`, `Braise`, `Stir-Fry`, `Fry` are
  methods, not forms — and Dish Type carries only non-method forms. A dish may carry a Technique and **no** Dish
  Type (a pot roast is `Braise` with no form); Missing ≠ Other, so this is fine. **Protein carries no
  "Vegetarian/None" value** — a meatless dish simply has no Protein assignment; "Vegetarian" lives in Dietary.

  **Starter values** (the proposer's anchoring prior for the backfill — the grocery-`seedAreas` role):
  - **Protein** (multi): Chicken, Beef, Pork, Lamb, Fish, Shellfish, Turkey, Duck, Sausage, Eggs, Tofu,
    Beans & Legumes.
  - **Dietary** (multi): Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut-Free, Low-Carb, Paleo, Pescatarian.
  - **Dish Type** (single-ish): Soup, Stew, Salad, Sandwich, Pasta, Pizza, Taco, Curry, Casserole, Bowl, Bread,
    Dumpling, Pie, Cake, Cookie.
  - **Technique** (multi): Grill, Roast, Braise, Sear/Sauté, Fry, Stir-Fry, Sous Vide, Slow Cooker, Pressure
    Cooker, Air Fryer, Bake, Smoke, Steam, No-Cook.

  This closes the gate on the labeling backfill: seed these four → build the S6 batch queue → run it → the
  [ADR-0050](ADR-0050-recipe-power-browser.md) D6 coverage gate opens. The seed itself is one small deterministic
  slice, not a schema change (the `facets` table + `Category.facetID`/`hidden` already exist).

### Open

- **OQ6 — primary vs secondary value within a facet** (`Cuisine` primary Korean, secondary Mexican) affects
  card display and grouping, not matching. Deferred; no column until a surface wants it.

## Amendment 3 — the labeling surface is a per-recipe **tag editor**, not a batch march; discovery is a **D8 cleanup entry** (2026-08-04)

Status: **Accepted** — 2026-08-04, pre-production, from Jon's device pass on the built S5/S6/D8 tooling
(commits `012dc1d`/`86d8d44`). **Supersedes D5.3** (the "needs labels" batch queue as the couch tool) and
**reshapes D5.2** (the suggest-only mini-labeler). The proposer engine (S3), `reconcileSuggestedLabels` (the sole
writer), the three coverage predicates, and D8 `FacetCoverage` all stay — only the *surfaces* change. No schema.

**Why.** D5.3 scoped the backfill as a guided march reusing the main library filter bar. Built, it (a) clogged
the compact filter — the coverage filter is always-on with no "None", so the list is never unfiltered — and
(b) put a tedious "Label Recipes" march in the list toolbar. The march is choreography, and near this kind of
work the tool beats the choreography ([[automation-decays-near-the-stove]]): Jon wants to *find* under-labeled
recipes and *edit their tags*, not be marched through a queue.

- **A3-D1 — Retire the batch march and un-clog the main list.** Delete `RecipeLabelBackfillModel` /
  `RecipeLabelBackfillSheet` and its list-toolbar entry, and **remove the coverage filter from the main
  `RecipeActiveFilterBar`.** The compact filter bar returns to its pre-backfill shape.
- **A3-D2 — One labeling surface: a dedicated Tag Editor off recipe detail.** An **"Edit Tags"** action on the
  recipe detail opens a lightweight editor **separate from Edit Recipe** — honoring D5.2's "not the heavy editor"
  intent and discharging the latent `REQUIREMENTS_MVP_ROADMAP` "Edit tags/categories" requirement. It shows
  current assignments **grouped by facet**, adds/deletes inline, and carries a **Suggest** button that runs the
  proposer and offers accept chips (re-runnable as "suggest more"). This reshapes D5.2's suggest-only
  `RecipeSuggestedLabelsSheet` into a full manage-tags surface and is the **only** labeling surface — there is no
  second per-recipe review step.
- **A3-D3 — Discovery is a D8 cleanup entry point, not a main-list filter.** `FacetCoverage`'s per-facet
  "N unclassified" becomes tappable → a filtered list of under-labeled recipes → tap a recipe → Edit Tags. The
  three coverage views (Missing Protein / Missing a primary facet / No editorial labels) live **here** as the
  list's filter, each a query-time absence predicate — never a persisted `Unclassified`/`Other` row (ADR-0050
  D7). This is available now, cross-platform, and **graduates into the Power Browser's Unclassified cleanup view
  later** (ADR-0050 S6, "cleanup entry points promoted out of D8 scaffolding") — same predicate, new host. It
  resolves the coverage chicken-and-egg: Power-Browser-only discovery would be gated on the very coverage it
  exists to create.
- **A3-D4 — The proposer's effort is threaded and raised.** `LabelProposer.call()` hardcodes
  `reasoningEffort: .low`, which is too weak for the on-device Apple model — it returns an empty suggestion set
  (valid JSON, so the loud parser stays silent; a chicken recipe yielding nothing is the tell). This is **not**
  the budget-starves-thinking trap ([[reasoning-budget-starves-output]] is the opposite — high effort under a
  tight cap). The code already threads `tier` for escalation but not effort; thread effort the same way and run
  the labeling surfaces at **high** effort (latency is fine — [[personal-app-latency-tolerance]]). User-configurable
  effort/tier in AI Settings is the eventual home, not a hardcoded constant.

**Consequences.** One labeling surface instead of two; the compact list toolbar and filter stay clean; discovery
works today without the browser; ADR-0050 S6 inherits the predicate and the entry point rather than reinventing
them. The couch-scale "few hundred in a sitting" ergonomics D5.3 optimized for are given up deliberately — the
per-recipe editor is slower per recipe but is the surface Jon will actually use, and the discovery list still
makes the backlog walkable.
