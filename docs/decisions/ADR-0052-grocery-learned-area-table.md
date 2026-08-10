# ADR-0052 — Grocery store-area placement gets a **persistent, synced learned table**; corrections stick, and the LLM **auto-promotes** into it while losing to both the seed and you

> **Vocabulary.** The *seed* is `GroceryStoreArea.seedAreas` — the small in-code `[canonicalName: GroceryStoreArea]`
> dict that pins a store area for common names before the model is consulted ([ADR-0035](ADR-0035-grocery-store-area-grouping.md),
> the reviewed deterministic floor). The *classifier* is the on-device `GroceryCategorizationClient` (ADR-0035 S2)
> that fills the long tail. The *aisle column* is `GroceryItem.aisle` — the per-row string the list renders from.
> This ADR adds the missing piece: a durable `canonicalName → area` **learned table** that turns a placement —
> whether the classifier guessed it or you fixed it — into cross-generation memory instead of a fact that dies
> when the item leaves the list.

Status: **Accepted** — 2026-08-05 (Proposed same day; ratified same day — Jon, *"I am good with your decisions"*,
including the two the architect resolved on his behalf: **auto-promote over a hard review gate** (D4) and
**Design B**, seed stays in code / table holds only learned rows (D6)). Origin: Jon, mining open-source recipe tooling (recipe-scrapers, RecipeSage,
Mealie), on Mealie's persistent *foods* database — *"I want to make sure we're not being cocky about some grocery
db. We miss a lot of things right now."* Extends [ADR-0035](ADR-0035-grocery-store-area-grouping.md) (store-area
grouping) and amends [ADR-0037](ADR-0037-grocery-seed-coverage-diagnostic.md) (the seed-coverage diagnostic, whose
"export Swift literal → paste into `seedAreas`" loop this supersedes as the *primary* way a placement sticks).
Governed by [ADR-0022](ADR-0022-grocery-merge-stays-deterministic.md) (grocery placement stays reproducible),
[ADR-0043](ADR-0043-model-call-chokepoint.md) (every model call declares itself), and the migration-ordering rule
that migration data writes bypass sync triggers ([[migration-writes-bypass-sync-triggers]]).

**Amendment — 2026-08-10.** Jon reversed S3's "confirm is a no-op" detail: a confirmation is durable review
metadata, not a placement correction. The audit now separates unreviewed and confirmed `.model` placements. This
does not reopen the auto-promote decision — model rows still take effect before review and remain below user and seed
precedence — it records which learned placements have received human attention.

**Reverses one half of a prior decision, on purpose.** The 2026-07-13 grocery call ([[grocery-area-no-learned-cache]])
had two halves: (a) *truth is deterministic; the classifier is never the source of truth*, and (b) *every classifier
answer must be human-reviewed, in code, before it counts*. Half (a) is kept and in fact hardened here. Half (b) is
reversed: mandatory in-code review was not a quality gate, it was a **bottleneck that kept the reviewed floor empty**,
because "codify a miss" meant hand-editing Swift and so rarely happened — which is the "we miss a lot" symptom itself.
See [D4](#d4--the-classifier-auto-promotes-its-answer-into-the-table-review-is-an-audit-not-a-gate).

## Context

ADR-0035 places a grocery item two ways: the **seed** (stable, free, offline, reviewed) and the on-device
**classifier** (fills what the seed misses). The result is written to `GroceryItem.aisle`
([`GroceryStoreArea.swift:366`](../../YesChefPackage/Sources/YesChefCore/GroceryStoreArea.swift) —
`applyClassified`) — a column **on one row**. That column is the *only* place a placement is remembered, and it dies
with the row. Three failures follow, and every one traces to the same missing substrate:

1. **Corrections evaporate.** `updateItem` writes a fixed aisle onto the single `GroceryItem`
   ([`GroceryRepository+Editing.swift:36`](../../YesChefPackage/Sources/YesChefCore/GroceryRepository+Editing.swift)).
   Fix "sumac → Spices" today; next week's list is a new row with `aisle == nil`, the pipeline re-runs seed→classifier
   from scratch, and your correction is gone. You re-teach the app the same fact forever.
2. **The reviewed floor is a ~110-line code constant** ([`GroceryStoreArea.swift:190`](../../YesChefPackage/Sources/YesChefCore/GroceryStoreArea.swift))
   that can only grow through a build. ADR-0037 gave it a review *queue* (the seed-coverage diagnostic) whose
   promotion step is "copy a Swift literal, paste into `seedAreas`, rebuild." In practice that loop clears far
   slower than misses arrive, so the queue is where placements go to wait, not to stick.
3. **The long tail is non-deterministic and re-billed.** The classifier isn't cached across generations — the only
   guard is a session-scoped `Set` ([`GroceryCategorization.swift:107`](../../YesChefPackage/Sources/YesChefCore/GroceryCategorization.swift),
   `GroceryCategorizationAttemptCache`). So an unusual ingredient can land in a different aisle on different weeks,
   in a surface whose entire value is a **predictable store walk** (ADR-0035's fixed department order). A
   consistently-wrong aisle you fix once; a non-deterministically-wrong aisle you can never fix.

Mealie's answer to the same problem is a persistent, user-curated *foods* table: each food remembers its
aisle/label, corrections accumulate, and unknown foods are the only ones that fall to inference. That is exactly the
substrate we're missing. And critically — **a `canonicalName → area` lookup is deterministic**. It is not an LLM on
a deterministic surface; it is the thing that lets us stop re-rolling the LLM. Adding it *strengthens* ADR-0022's
line rather than crossing it (see [D5](#d5--this-does-not-cross-adr-0022-it-makes-placement-more-deterministic-not-less)).

## Decision

### D1 — Add a synced `GroceryAreaAssignment` table: `canonicalName → area`, tagged by source

One row per learned placement. This is the durable, cross-generation, cross-device memory the aisle column never was.

```swift
@Table struct GroceryAreaAssignment: Identifiable, Sendable {
  let id: UUID
  var canonicalName: String        // the resolution key (CanonicalIngredient.canonicalName output)
  var area: String                 // GroceryStoreArea title (or custom label), same encoding as GroceryItem.aisle
  var source: Source               // .model | .user  — see D3; .seed is NOT stored (it lives in code)
  var reviewedAt: Date?            // nil until a human confirms a .model placement; review does not affect precedence
  var dateModified: Date           // last-writer-wins tie-break across devices
}
enum Source: String, Codable, Sendable { case model, user }
```

Registered as a synced table in `Schema.swift` alongside the others; a new append-only `registerMigration` creates
it. Synced tables are cheap and we have headroom ([[synced-table-cost-calibration]]); this is the cheap kind, not
the orphaned kind — its consumer (the resolver, D2) ships in the same slice.

**No unique index on `canonicalName`, by design.** CloudKit's `SyncEngine` doesn't enforce uniqueness, and our
schema is deliberately unique-index-free for sync safety ([[sqlitedata-blob-cloudkit-asset]]). Uniqueness is
**application-enforced**: a write for a canonical name replaces that name's prior row of the same-or-lower source
tier (D3), and the resolver (D2) is duplicate-tolerant — if two devices race a row in, it resolves them by source
then `dateModified`, it does not assume one. This is the same "no reserved cols / no unique indexes / reconcile in
code" posture the rest of the schema already holds.

### D2 — Placement resolves through a fixed deterministic ladder; only a genuine first sight touches the model

For a canonical name, the area is resolved in this order — **the first hit wins, and only step 4 is non-deterministic**:

1. **User row** in the table (`source == .user`) — your correction, absolute.
2. **Seed** (`GroceryStoreArea.seed(for:)`, [`GroceryStoreArea.swift:80`](../../YesChefPackage/Sources/YesChefCore/GroceryStoreArea.swift)) — the reviewed in-code floor.
3. **Model row** in the table (`source == .model`) — a placement the classifier already committed once.
4. **Miss** → run the classifier, **write a `.model` row** (D4), use its answer.

Steps 1–3 are pure lookups: free, offline, reproducible. Step 4 fires **at most once per canonical name, ever** —
after it, that name is a step-3 hit forever. This is the whole game: the classifier stops being a per-generation
coin flip and becomes a one-time cost that hardens into deterministic memory.

The table is small; the resolver loads it into a `[canonicalName: (area, source)]` dict once per generation pass
rather than querying per item. `GroceryStoreAreaCache.applyClassified` and `.backfill` are rewritten to go through
this ladder instead of writing `aisle` off seed-or-model directly. `GroceryItem.aisle` **stays** as the rendered,
materialized value — it is now *derived from* the ladder, not the sole memory of it.

### D3 — Precedence is `user > seed > model`, enforced on write as well as read

The read ladder (D2) is only half of it; writes must respect the same order so a lower tier can't clobber a higher one:

- A **`.model` write never overwrites** an existing `.user` row for that name (nor does it need to touch a seed hit —
  step 2 shadows step 3 at read time, so a seeded name simply never reaches step 4).
- A **`.user` write always wins**: it upserts a `.user` row for the name, replacing any `.model` row. A correction
  that merely *agrees* with the currently-resolved area is a **no-op** (don't record redundant `.user` rows that
  duplicate the seed — keep the table to genuine additions and overrides).
- A `.user` row overriding a **seed** value is allowed and expected (your store keeps shallots somewhere ours
  doesn't) — step 1 sits above step 2 precisely so a correction can beat the reviewed floor without a code change.

Encoding precedence as `.user`/`.model` source plus the fixed ladder makes "the model never outranks you or the
seed" an **integer comparison, not a code path** — the same discipline as ADR-0047 D6's `modelPriority = -1`.

### D4 — The classifier **auto-promotes** its answer into the table; review is an audit, not a gate

When step 4 runs, its result is written straight into the table as a `.model` row. There is **no human-review gate
between classify and stick.** This is the deliberate reversal of the 2026-07-13 half (b).

Why auto-promote is safe here, stated as the trade it is:

- **Determinism is preserved.** A promoted `.model` row is a step-3 hit forever — sticky, never re-rolled. Auto-promote
  satisfies the reproducibility requirement exactly as well as a review gate would; the gate bought nothing on that axis.
- **You still win, always.** A wrong promotion is a `.user`-row edit away (D3), and that edit outranks it permanently.
- **The error is cheap and self-correcting.** A bad first-sight guess costs one item in the wrong aisle once, then one
  tap, then it's right forever. That is the correct cost model for a single-user app; a mandatory gate spends your
  attention on every *correct* guess to save it on the rare wrong one.

**Review survives as an audit surface, not a bottleneck.** ADR-0037's seed-coverage diagnostic is repurposed: instead
of surfacing *uncovered* names (auto-promote means names stop being uncovered after first sight) and exporting Swift
literals, it becomes a **browse of `.model` rows** split into unreviewed and confirmed placements — "here's what the
classifier decided on its own; fix or confirm any that look wrong." Fixing one writes a `.user` row (D3); confirming
stamps `reviewedAt` while deliberately leaving the placement and `dateModified` tie-break untouched. The "copy → paste
into `seedAreas` → rebuild" export is demoted to optional (you *may* still promote a confirmed placement into the
reviewed code floor), no longer the only way a placement persists. See [Amendment note to ADR-0037](#amends-adr-0037).

### D5 — This does not cross ADR-0022; it makes placement *more* deterministic, not less

The classifier already runs on this surface (ADR-0035 S2) — this ADR adds **no new model call to a deterministic
path.** It takes the existing call's output and makes it *stable* instead of re-rolled every generation. So relative
to today, placement becomes strictly more reproducible: the same list produces the same walk, and a name is asked of
the model once in its life rather than repeatedly. ADR-0022 governs the reproducibility of grocery placement; this
serves that, it doesn't reopen it. The advisory-vs-canonical boundary ([[llm-vs-determinism-surface-boundary]]) is
also unmoved: aisle placement was always the model-assisted-then-corrected surface, never a reproducible *merge*.

### D6 — No seed migration and no data backfill; the table populates lazily

The seed stays in code as the reviewed floor (step 2), so there is **nothing to migrate out of it** — the table holds
only *learned* rows (`.model` + `.user`) layered on top. The creating migration writes **no data**, so it sidesteps
the migration-bypasses-sync-triggers minefield ([[migration-writes-bypass-sync-triggers]]) entirely.

Existing `GroceryItem.aisle` values are **not** backfilled into the table. Two reasons, stated plainly rather than
papered over:

- A historical aisle carries **no source tag** — we can't tell a pre-ADR user correction from a pre-ADR model guess,
  so we can't promote it to the right tier without lying about its provenance.
- It isn't needed: a name that recurs simply re-resolves through the ladder and auto-promotes a `.model` row on its
  next appearance (D4). The table self-heals forward. Existing per-row aisles remain valid on the lists they're
  already on until the name recurs.

The one honest cost of D6: **corrections you made before this ships are not retroactively learned.** The table learns
from this point forward. (A user who wants an old fix to stick just fixes it once more after shipping.)

### D7 — The classifier runs at **high effort with a budget that fits thinking + output**; `.low` on-device is banned

The categorizer runs on-device at **`.low`** effort under a 1,024-token ceiling
([`GroceryCategorization.swift:73`](../../YesChefPackage/Sources/YesChefCore/GroceryCategorization.swift), with
`maximumResponseTokens` and `maximumNamesPerRequest = 8` tuned around it). It is the **only `.low` call in the
codebase** — every other call site is `.medium` or `.high` — and it is the wrong economy. The learned table is
what makes fixing it affordable.

- **No on-device call uses `.low`.** On-device at low effort is the weakest configuration we ship, and a placement
  that is about to become permanent memory (D4) is worth more than that. This is a standing rule, not a grocery
  one ([[personal-app-latency-tolerance]]: a user-initiated action in a single-user app may take longer for a
  better answer).
- **Raise it to `.high`, and raise the budget with it.** Because `maxTokens` is shared by reasoning and output
  ([[reasoning-budget-starves-output]]), high effort under a 1,024 ceiling would starve the JSON and return an
  empty or truncated map that *looks* like a classification failure. Size the budget for reasoning **plus** the
  name→area map; keep the chunk small (8) so output stays comfortably inside it.
- **The table pays for this.** Under D2/D4 a name is classified **once in its life**, then it is a free
  deterministic lookup forever. A slower, better first-sight pass amortizes to once-per-name, not once-per-list —
  the expensive answer is bought a single time and banked. High-effort on-device classification was unaffordable
  *because* it re-ran every generation; the learned table removes exactly that, which is what turns "never run
  on-device at low effort" from an aspiration into an affordable default here.

This closes the loop with D4: auto-promote makes first-sight quality **load-bearing**, so raising it is a
prerequisite for auto-promote to be a fair trade, not a nicety.

## What this costs — stated plainly

- **A new synced table** — schema surface, a migration, a registration, sync traffic on a table that will hold at most
  a few hundred rows for one household. Cheap, but non-zero, and it's permanent once it promotes to prod
  ([[synced-table-cost-calibration]], [[squash-migrations-at-prod-baseline]] for the pre-prod squash it folds into).
- **Auto-promote can seat a wrong guess silently.** If the classifier mis-places a name and you never notice at the
  store (you just grab it wherever it is), the wrong `.model` row sits unreviewed. The audit surface (D4) is the
  release valve, and the error is one tap to fix — but it is a real behavior change from the never-without-review
  posture, and D4 owns that trade.
- **`GroceryItem.aisle` is now derived, not authoritative.** Anything that wrote it directly must route through the
  ladder (D2) or it will diverge from the learned memory. The rewrite of `applyClassified`/`backfill` is where that
  invariant lives; a stray direct write is the bug to watch for.
- **First-sight classification gets slower** (D7: `.low`→`.high` on-device, bigger budget). This is the accepted
  trade — the cost lands **once per name, ever** (D2 step 4), on the generation that first meets it, then never
  again. A list of all-already-seen names does no model work at all. [[personal-app-latency-tolerance]] is the
  license; the learned table is what keeps the slower pass from recurring.

## Amends ADR-0037

ADR-0037 built the seed-coverage diagnostic as a *review queue for curating `seedAreas` in code* — its export emits
paste-ready Swift dict literals, its explicit loop is "review → clipboard → paste → rebuild → drops off the queue,"
and its Context states outright *"there is deliberately no persistent `canonicalName → area` cache … the way to make
a placement permanently stable is to add it to `seedAreas` in code."* **This ADR is that persistent cache**, so that
sentence and that loop are superseded as the *primary* path. ADR-0037's computation and Settings surface are **kept
and re-pointed**: the same `SeedCoverageReport` machinery now audits `.model` rows (fix→`.user`, confirm→durable review metadata)
rather than exporting code. The Swift-literal export is retained as an *optional* promotion of confirmed placements into the reviewed floor
action, not the mechanism of persistence. No part of ADR-0037 is deleted; its purpose shifts from *the* stability
mechanism to *an audit over* the stability mechanism.

## Open questions

- **OQ1 — re-classify action.** A `.model` row is never re-asked (D2 step 3 shadows step 4). If a guess is wrong and
  never corrected, only the audit surface catches it. Offer a per-row "re-classify" that clears the `.model` row and
  re-runs step 4? Cheap, but it competes with just editing the aisle. Defer until the audit surface shows a real need.
- **OQ2 — alias learning is the follow-on, not this slice.** Mealie's foods table also drives dedup/merge via
  learned aliases; our `CanonicalIngredient` canonicalizes deterministically but has no learned-alias memory, so two
  spellings of one food can miss each other. The same source-tagged-table pattern extends there
  ([[decompose-notes-into-typed-homes]] adjacent). Explicitly **out of scope** — placement first, prove the pattern,
  then generalize on evidence.
- **OQ3 — the review-gate reversal (D4). RESOLVED 2026-08-05 (Jon).** Auto-promote-with-audit ratified over a
  hard gate. (Recorded here rather than deleted: a future reader wondering why the 2026-07-13 gate went away
  finds the reasoning in D4 and the sign-off here.)

## Slices

- **S1 — the table + the ladder (no new UI).** `GroceryAreaAssignment` `@Table` + `Schema.swift` registration +
  creating migration (D1); the resolver dict + rewrite of `GroceryStoreAreaCache.applyClassified`/`.backfill` to go
  through the D2 ladder; auto-promote write on step-4 miss (D4); precedence-correct writes (D3). **Raise the
  categorizer to `.high` effort and lift its token budget to fit thinking + output (D7)** — update the
  `GroceryCategorizationTests` assertion that currently pins `.low`. Fully unit-tested in `YesChefCore`: user-row
  beats seed beats model-row beats classify; a `.model` write does not clobber a `.user` row; a redundant
  correction is a no-op; duplicate rows for one name resolve by source then `dateModified`; a seeded name never
  reaches step 4. **No backfill, no data migration** (D6).
- **S2 — the correction write path.** `updateItem`'s aisle edit upserts a `.user` row keyed by canonical name
  (D3), in addition to setting the row's `aisle` for immediate display. Test: correct an item, remove it, regenerate
  a list containing it, assert the corrected area holds without a model call.
- **S3 — repoint the audit surface (amends ADR-0037).** `SeedCoverageReport`/`SeedCoverageView` browse `.model`
  rows, split into unreviewed and confirmed placements. `reviewedAt` is nullable synced review metadata (an additive,
  data-free migration): fix→`.user`, confirm stamps the model row without changing its placement or resolution
  tie-break; Swift-literal export is an optional promote-to-seed action for confirmed placements. Test the report and
  confirmation over table rows rather than the derived corpus.

Natural batch: **S1 + S2** as one Codex dispatch (the table is inert without the write paths that feed it). S3 can
ride the same dispatch or follow — it's the audit layer, not the mechanism.

## Verify

Package build + new `YesChefCore` tests + `swift test --skip-build`; `check-drift.sh`; one iPad build
(`xcodegen generate` first — new source files + schema). No simulator installs ([[lean-verification-default]]); Jon
does the device pass: place an unusual ingredient, correct its aisle, remove it, regenerate a list that includes it,
and confirm the correction **held with no model call and no flicker** — then confirm it held on a second device after
sync.
