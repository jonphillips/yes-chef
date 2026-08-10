# Effort: backfill free-text `Recipe.cuisine` / `Recipe.course` into Cuisine/Course facet assignments (2026-08-10)

**Type:** ADR-0050 **OQ5 step (a)** — the synced data pass that retires the typed `cuisine`/`course` columns.
**One dispatch.** No schema — no new tables, no new columns, nothing added to the promotion list. A new *post-engine
data pass* plus its Core tests. It writes `RecipeCategory` link rows and *empties* the matched `cuisine`/`course`
column; it adds no column and drops none.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Designed. Land this before PR #303 reaches the device** (or keep the Fields → Cuisine/Course filter
alive until it does — see Sequencing). PR #303 shipped OQ5 steps **(b)** drop the editor's free-text inputs and
**(c)** delete the Fields → Cuisine/Course filters, but **not (a)**. Until (a) runs, a recipe whose cuisine/course
lives only in the free-text column is **unfilterable by the new facet picker** and shows **"None"** in the editor,
even though the value is still present (and still text-searchable). Nothing is lost; it is a transitional recall gap
that the ADR explicitly did not want opened alone.
**Source:** ADR-0050 **OQ5** ([`ADR-0050-recipe-power-browser.md`](../decisions/ADR-0050-recipe-power-browser.md),
lines ~283–299) and the PR #303 architect review.
**Summary:** Existing libraries carry cuisine/course as *free text* on the `Recipe` row — populated at import from
JSON-LD `recipeCuisine`/`recipeCategory` and by hand in the old editor Fields section. ADR-0049 D6 routes those onto
the **Cuisine** and **Course** facets. This pass reads each recipe's free-text `cuisine`/`course`, resolves the value
against the **existing** facet's values, writes the matching `RecipeCategory` assignment with a **derived id**, and —
because this is a *move, not a copy* — **clears the matched free-text column** so it stops being a shadow source of
truth. All of it happens **once, deterministically, after the SyncEngine is constructed**. Unmatched values are left
untouched and reported.

**Required invariant:**

> Two devices that each run this pass over the same library converge to the **same** `RecipeCategory` rows — no
> per-device duplicate assignments, no invented facet vocabulary. A matched value ends up as a facet assignment *and*
> an empty free-text column, so a user who later removes that assignment sees it **stay removed** — there is no
> surviving column for a later launch (or the other device) to re-derive it from.

**Related:**
[[migration-writes-bypass-sync-triggers]] (why this is a **post-engine** pass, not a `registerMigration` — a migration
runs before `makeSyncEngine`, so a new `RecipeCategory` row it writes gets no `SyncMetadata` and is either swept as
drift or silently never uploaded) ·
[[synced-table-cost-calibration]] (no new table — this only writes existing `RecipeCategory` rows) ·
the variation-anchor-repair effort and `backfillVariationAnchors` (the precedent post-engine pass this one sits beside) ·
ADR-0049 **D6** (recipeCuisine → Cuisine facet) and Amd 2 (the facet model) ·
ADR-0022 (deterministic reads; a backfill that mints per-device UUIDs violates convergence).

**Read before starting:**
- [`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) lines **1273–1285** — the
  `runsPostEngineDataPasses` block inside `bootstrapDatabase`, run inside a single `database.write` **after**
  `makeSyncEngine`. This is where the new pass is invoked, beside `backfillVariationAnchors`.
- [`RecipeCategoryRepository.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeCategoryRepository.swift):
  `starterFacets` (~line 776 — **Cuisine = `starterCategoryID(1)`, Course = `starterCategoryID(2)`**, both with
  deterministic seeded values: Thai, Dinner, Dessert, …), `reconcileCategories` (~963) and
  `findOrCreateImportedCategory` (~1005) — the canonical assignment path, and the reason we **cannot** reuse it
  verbatim (its `uuid:` closure is `() -> UUID`, non-deterministic and blind to the row it is minting).
- `CURRENT_HANDOFF.md` Verification Pattern. This is a **Core** change; `YesChefCoreTests` is the correctness signal,
  and the two-device convergence property is the point.

---

## The context (by reading — no device repro needed)

A recipe has `Recipe.cuisine = "Thai"` (free text) but **no** `RecipeCategory` linking it to a `Category` under the
Cuisine facet. Before PR #303 the library's **Fields → Cuisine** filter read the free-text column directly, so the
value was reachable. PR #303 deleted that filter and the editor input in favor of the facet picker, which reads
**only** facet assignments. So today that recipe:

1. still matches a **text** search for "Thai" (the browser engine's `matchesText` still reads `recipe.cuisine`), but
2. does **not** appear under the new Cuisine facet filter, and
3. shows **"None"** in the editor's Cuisine picker, over a non-empty column.

The value is preserved, just orphaned from the taxonomy. This pass moves it onto the facet. It is the missing third
of a retirement the ADR wanted done together.

---

## The findings

### Finding 1 — the assignment must be a *post-engine* pass, deterministic-UUID

The single hard part. Both devices run `bootstrapDatabase` and will each execute this pass. If the pass mints the
`RecipeCategory` link with a fresh `uuid()`, device A and device B produce **different** row IDs for the *same*
(recipe, category) fact, and sync lands them as **two** assignment rows — the exact per-device duplication
[[migration-writes-bypass-sync-triggers]] describes. Therefore:

- The pass runs in the **`runsPostEngineDataPasses`** block (Schema.swift:1273), never in a `registerMigration`.
- Every `RecipeCategory` row it writes uses an **id derived deterministically** from stable inputs
  (`recipeID` + `categoryID`), not `uuid()`. Upserting a derived-id row from both devices converges to one row.

There is **no** deterministic-UUID helper in the package today (no UUIDv5). Add a small, well-named one (e.g.
`DeterministicID.recipeCategory(recipeID:categoryID:)` producing a UUIDv5 over a fixed namespace + a stable key
string like `"recipeCategory:\(recipeID.uuidString):\(categoryID.uuidString)"`). Keep it in Core, unit-tested for
stability. This is why the pass **cannot** just call `reconcileCategories` — that path's `() -> UUID` closure is
parameterless and cannot see which (recipe, category) pair it is minting an id for.

### Finding 2 — match only *existing* facet values; never invent vocabulary

An imported `recipeCuisine` can be anything ("Cajun", "Modern Australian", a keyword dump). Creating a brand-new
Cuisine facet **Category** from an arbitrary string is exactly the taxonomy pollution ADR-0050 warns against
("**Missing ≠ Other**"; "Unclassified is a *derived query predicate*, never a persisted value"), and creating a new
**Category** deterministically across two devices is a second, harder convergence problem we do not need to take on
here. So:

- **Matched** (the free-text value equals an existing value under the Cuisine/Course facet, normalized) → write the
  assignment.
- **Unmatched** → **do nothing to the data.** Leave the free-text column, add the recipe to the pass's **report**
  for hand-classification (or a later proposer run). No new Category, ever.

Normalize with the same fold the browser now uses for source values: trim + `.caseInsensitive` +
`.diacriticInsensitive`. "thai " matches the seeded "Thai".

### Finding 3 — move the value, don't copy it: clear the matched column so removals stick

The pass runs on every boot, so a *surviving* free-text column is a resurrection engine. Concretely: assign
Cuisine→Thai from `cuisine = "Thai"`; the user removes the Thai assignment because they don't want it classified; next
launch the recipe has free-text "Thai" and no assignment, so a "skip-if-already-assigned" guard does **not** fire
(there is nothing to skip) and the pass **re-adds Thai**. Across two devices it is worse — the same delete-loses-to-a-
re-add race as [[restore-is-authoritative]]. Honoring "removed stays removed" while the column persists would require a
**synced** tombstone of "this pair was backfilled/dismissed" — new sync schema whose only consumer is a one-time
backfill, which is exactly the orphaned-schema cost we refuse to pay for ~10 users.

So resolve it at the source: a retirement is a **move**. On a **matched** value, after writing the assignment, **clear
the free-text column** (`cuisine`/`course` → empty). Then:

- There is no column left to re-derive from, so removals stick with **no tombstone and no new schema**, and the second
  device converges to the same cleared state.
- **Nothing is lost.** The value now lives as the Thai *facet assignment* (strictly more useful than free text); text
  search still finds "Thai" because [`matchesText`](../../YesChefPackage/Sources/YesChefCore/RecipeBrowser.swift:481)
  already searches assigned category names; and the true import value is still frozen in `originalSnapshot`
  (untouched — the clear writes only the live column), so provenance survives even for recipes with no snapshot,
  because a *matched* value is preserved as the assignment either way.
- The clear is a normal post-engine write (it gets `SyncMetadata`), and clearing an already-empty column is a no-op, so
  re-runs and both devices settle identically — idempotent by construction, no per-recipe "already done" flag needed.

Keep a light guard for the user who has already classified differently: if the recipe **already** has an assignment in
that facet, do not add a second one — but still clear the now-moot free-text column (the facet is authoritative). The
column is only ever retained on the **unmatched** path (Finding 2), where nothing else holds the value.

> This **reverses** the first draft's "do not clear the column" guardrail. That guardrail reached for provenance and
> reversibility, but provenance already lives in `originalSnapshot` and the shadow column was the defect, not the
> safety net. Whether the *columns themselves* are eventually dropped from the schema is still ADR-0050 OQ5(c) and
> stays **out of scope** — emptying a column is a routine synced write; dropping one is a schema call
> ([[never-rewrite-shipped-migration]] / [[squash-migrations-at-prod-baseline]]).

---

## The dispatch

One PR. One new Core pass, one small deterministic-id helper, its invocation, and tests.

### Pass — `RecipeRepository.backfillCuisineCourseFacets(in:) -> Report`

For each recipe with a non-empty trimmed `cuisine` **or** `course`:

1. Resolve the **Cuisine** facet (`name == "Cuisine"`, case-insensitive) and its value categories; same for **Course**.
   If a facet is absent, skip that side (seeding runs just above this in the same block, so normally present).
2. For the recipe's free-text cuisine value, find the facet value whose name matches (normalized):
   - **Matched, recipe has no Cuisine assignment yet** → upsert a `RecipeCategory` with a **derived** id
     (`DeterministicID.recipeCategory(recipeID:categoryID:)`), then **clear** `recipe.cuisine` to empty.
   - **Matched, but the recipe already has a Cuisine-facet assignment** (user already classified it) → do **not** add a
     second assignment, but still **clear** the moot `recipe.cuisine` (the facet is authoritative).
   - **Unmatched** → touch nothing; **retain** the column and record `(recipeID, .cuisine, rawValue)` in the report.
3. Same for course against the Course facet.
4. Persist the column clears (one `Recipe` update per touched recipe, folding both fields). This is a live post-engine
   write, so it carries `SyncMetadata` and propagates; leave `originalSnapshot` untouched.
5. Return a `Report` with counts (assigned, cleared, already-classified, unmatched) and the unmatched
   `(recipeID, field, rawValue)` list, carrying `hasFindings` / `logSummary` so the caller logs it exactly like
   `backfillVariationAnchors`.

**Invocation:** in Schema.swift's `runsPostEngineDataPasses` block, after `backfillVariationAnchors`:

```swift
let cuisineCourseBackfill = try RecipeRepository.backfillCuisineCourseFacets(in: db)
if cuisineCourseBackfill.hasFindings {
  AppLog.dataIntegrity.warning("\(cuisineCourseBackfill.logSummary, privacy: .public)")
}
```

Order note: it runs **after** `seedStarterFacets` (already first in the block) so the Cuisine/Course facets and their
seeded values exist before we match against them.

### Tests (Core — the real signal; assert rows and convergence, not counts alone)

1. **Matched value assigns and clears the column.** Recipe with `cuisine = "Thai"`, no Cuisine assignment → after the
   pass it has exactly one `RecipeCategory` pointing at the seeded Cuisine→Thai category **and** `recipe.cuisine` is now
   empty. Assert the *actual* categoryID (the seeded Thai id), not just a count, and assert the cleared column.
2. **Normalized match.** `cuisine = "  thaï "` still resolves to Thai (trim + case + diacritic fold) and clears.
3. **Unmatched value touches nothing.** `cuisine = "Cajun"` (no such facet value) → no `RecipeCategory` written, no new
   `Category` created, column **retained** as `"Cajun"`, and it appears in `report`'s unmatched list.
4. **Removed stays removed (the point of the move).** Run the pass on `cuisine = "Thai"` → Thai assigned, column
   cleared. Delete that `RecipeCategory`. Run the pass again → the recipe has **no** Cuisine assignment and is **not**
   re-added (the column is empty, nothing to re-derive).
5. **Determinism / convergence.** Assert `DeterministicID.recipeCategory(...)` is stable for the same inputs, and that a
   second literal run over the already-migrated state is a full no-op (no duplicate `RecipeCategory`, column already
   empty so the clear is a no-op).
6. **Respects prior classification.** Recipe with `cuisine = "Thai"` but already assigned to Cuisine→Mexican by the user
   → pass leaves it Mexican (does **not** add Thai) but **does** clear the moot `cuisine` column.
7. **Course path** mirrors (1) against the Course facet (e.g. `course = "Dinner"` → seeded Course→Dinner, column
   cleared).
8. **Both fields on one recipe** resolve independently and clear independently in a single pass (matched cuisine +
   unmatched course → cuisine cleared, course retained).
9. **Provenance survives.** A recipe whose `originalSnapshot` recorded `"Thai"` still has that snapshot intact after the
   live column is cleared.

---

## Guardrails a dispatch must not undo

- **Do not use `uuid()` for the assignment rows.** Derived ids only. A per-device UUID here is the whole bug this
  effort exists to avoid.
- **Do not create facet Categories from free text.** Match-only. Unmatched → report, not a new row.
- **Do not run this in a `registerMigration`.** Post-engine block only ([[migration-writes-bypass-sync-triggers]]).
- **Clear the column only on a *matched* value; never on an unmatched one.** Unmatched is the only value with no other
  home — losing it would be data loss. Clearing a matched value is a move, not a loss (the assignment holds it).
- **Do not add a synced tombstone/opt-out table.** The move (clear-on-match) is what makes removals stick; a tombstone
  is the schema we are deliberately not paying for.
- **Do not touch `originalSnapshot`, and do not drop the `cuisine`/`course` *columns*.** Emptying a column is in scope;
  deleting the column is ADR-0050 OQ5(c), a separate schema call.
- **Do not fold this into a recipe-edit or Power-Browser slice.** It is its own dispatch, gated with the ADR-0050
  D6 backfill sequencing.

## Parked fork — route unmatched values through the label proposer (do not build here)

This dispatch leaves an **unmatched** free-text value (Finding 2) reported and untouched — deterministic match-only,
no LLM in the boot path. The natural next step, deliberately **out of scope**, is to hand the unmatched remainder to
the existing proposer: [`LabelProposer`](../../YesChefPackage/Sources/YesChefCore/LabelProposer.swift) already reads
the Cuisine facet vocabulary (`categories(inFacetNamed: "Cuisine", …)`, ~line 386) and is the sanctioned surface for
"map this loose string onto the taxonomy." Reasons it is a **separate** effort, not a widening of this one:

- **No LLM on the boot path.** This backfill runs inside `bootstrapDatabase`'s post-engine `database.write` on every
  launch; it must stay deterministic and offline. A proposer run is asynchronous, model-backed, and advisory — it
  belongs to a user-triggered review surface, not app startup.
- **Curation, not silent write.** Consistent with [[llm-curation-not-synthesis]] and the ADR's "explicit facets →
  proposer re-pointed at facets → a real backfill run": the proposer should *suggest* a facet value for Jon to accept,
  producing a `model`-precedence assignment the user can override — never auto-persist a guessed cuisine.
- **It needs the report this dispatch already emits.** The unmatched list (recipeID, field, rawValue) is the exact
  input a later proposer pass consumes, so shipping the deterministic pass first is the prerequisite, not a throwaway.

Trigger for the fork: after this pass ships and Jon has seen the real unmatched volume in the log summary. If the tail
is small, hand-classification may be enough and the fork stays parked.

## Verification

- `swift build` the package; the **generic app build is required evidence** (Verification Pattern);
  `scripts/check-drift.sh`; SwiftLint clean.
- **`YesChefCoreTests` carries correctness** — the nine tests above; the determinism/convergence and removed-stays-
  removed ones are the point.
- **`YesChefTests` (app model target)** — required whenever Core model behavior changes
  ([[app-test-target-in-verification]]); this pass touches the model, so run it.
- **No new table**, so nothing is owed to the promotion list. This pass *adds* `RecipeCategory` rows and *empties* an
  existing column on matched recipes — both ordinary post-engine writes, no schema step of its own.
- **Device pass (Jon):** on a library with imported/hand-entered cuisines, launch once → recipes that had free-text
  Cuisine/Course now appear under the facet filters and show the value selected in the editor, and their old Fields
  value is gone (moved, not doubled); unmatched ones keep their text value and appear in the log summary for hand-
  classification. Confirm a second launch changes nothing, and that a facet assignment you *remove* stays removed
  across a relaunch.

## Sequencing with PR #303

The ADR wanted OQ5 (a)+(b)+(c) landed together. #303 carries (b)+(c). Two acceptable orders:

1. **Preferred:** land this backfill, then #303 — or land both and only device-test once (a) has run, so the deleted
   Fields → Cuisine filter is never the *only* path to an un-migrated value on a real device.
2. **Interim if #303 lands first:** keep the Fields → Cuisine/Course filter (revert only that deletion from #303)
   until this pass ships, so no un-migrated value becomes unreachable in between.

Either way, this pass should not trail #303 onto the device by more than a build.
