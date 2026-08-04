# Effort — Recipe Facets (ADR-0049 Amendment 2: promote the namespace to an explicit `Facet`)

**Thin pointer, not a re-spec.** The authority is
[`ADR-0049 § Amendment 2`](../decisions/ADR-0049-unified-labels-and-assisted-tagging.md#amendment-2--the-namespace-is-a-facet-and-a-facet-is-a-row-not-a-tree-position-2026-08-01)
(D8–D13 + § Migration). Build to that. This brief carries only the deltas a dispatch needs and the guardrails a
dispatch must not undo.

**Gated on ratification.** Not dispatchable until Amendment 2 is Accepted.

## What this effort is

ADR-0049 D1 made a namespace a **root category row** and asked every reader to hold a convention in its head.
Amendment 2 makes it a **row in its own table**. After this effort: `Cuisine` and `Course` are `Facet` rows and
no longer exist in `categories`; their children carry `facetID` and a `nil` parent; every other parentless
category is a loose label (`facetID == nil`); and **every `recipeCategories` join survives untouched.**

**This walks back part of ADR-0049 S1/S2 and part of PR #268/#269 on purpose.** That is the trade: pre-production
with an erasable, restorable test library is the cheapest this correction will ever be, and the alternative is
that the AI backfill encodes thousands of assignments against the ambiguous model first. Walking back is the
work, not a sign the work went wrong.

## Dispatches

Five. **D1 is one PR and is unavoidably large** — same reason S1 was: split it and the app's category surfaces
read a model that no longer exists. D1–D3 are shipped-or-merged. **D5 is a code slice that must land before D4**
— it is what makes D4's hand pass performable at all (see D5).

### Dispatch 1 — schema, migration, Core invariants, audit *(the big one)*

**Pass A — schema DDL, pre-engine, in `registerMigration`. Structure only, no data movement**
([[migration-writes-bypass-sync-triggers]]):

- create `facets`;
- add `categories.facetID` (nullable) and `categories.hidden` (default `false`);
- **drop `categorySeedStates` and `categorySeedTombstones`** — tables, both structs
  (`CategorySeedState.swift`, `CategorySeedTombstone.swift`), and both `CloudSync` registrations. This is
  Amendment 1's teardown, **absorbed here** (see Guardrails).

**Pass B — data pass, post-`makeSyncEngine`, deterministic ids, idempotent, insert-if-absent.** Per Amd 2
§ Migration steps 1–5:

1. Seed the facet rows with fixed ids — **Cuisine and Course only**.
2. Promote both namespace roots: create the facet, set each child's `facetID`, null each child's
   `parentCategoryID`, delete the old root **category** row. **Child UUIDs are preserved** — that is what
   carries the recipe joins through.
3. Recipes joined **directly to a namespace root**: remap to an unambiguous child, else to a loose label
   carrying the root's name. **Never drop.** Every one goes in the audit.
4. All other parentless categories → loose labels.
5. **A parentless category with children is NOT auto-promoted.** Report it; Jon files it by hand.

**Pass C — invariants in Core**, alongside `reconcileCategories`, which stays the sole writer and sole node
creator (D2 unchanged). All four of Amd 2 D9, unit-tested: facet membership, parent consistency (same
`facetID`, never a loose-label parent), loose labels are leaves, facets are unassignable.

**Pass D — the audit report.** Per original category: new classification, affected recipe count, parent changes,
merges, deletions, unresolved rows, and **every remapped root assignment**. A deliverable, not a nicety — Jon
reads it before the second device is allowed to converge.

**Pass E — App reads, minimally.** Enough that the app builds and every category surface is correct against the
new model. Not the management-UI redesign (that is Dispatch 2).

### Dispatch 2 — category management UI

`CategoryViews.swift` / `CategoryModels.swift` / `RecipeCategoryFilterView.swift`. Facets and loose labels
present as structurally different things, and **creating a facet is a distinct, deliberate act** from adding a
value or a label. Adding a value inside an existing facet stays lightweight. Hidden is exposed at both grains.

### Dispatch 3 — proposer re-point (Amd 2 D11)

`LabelProposer.swift` + `RecipeCaptureModel+Labels.swift`. Typed facet vocabulary into the prompt; suggestions
resolved against facet identity before reconcile; `.namespace` now literally proposes a `Facet` row.
**PR #269's Findings 1 and 3 are re-pointed, not deleted** (see Guardrails).

### Dispatch 4 — *not a dispatch.* Jon's hand pass

Review the audit, file the reported ambiguous roots, merge/delete poor starter values, then re-run the S5/S6
labeling queue against real facets. That backfill is [ADR-0050](../decisions/ADR-0050-recipe-power-browser.md)'s
D6 gate. **Gated on Dispatch 5** — the edit path cannot file a loose label into a facet until D5 ships.

### Dispatch 5 — make facet membership editable *(unblocks D4)*

**Why it exists.** D1 plumbed an explicit `facetID` onto `createCategory` but not `updateCategory`, which derives
`facetID` from the parent — so a parentless loose label can never be filed into a facet by editing. That is not a
new decision: **D9 rule 3 already ratifies the "file-under-facet" operation** ("*Nesting under a loose label …
is an explicit convert-to-facet or file-under-facet operation*"); D1's dispatch simply never plumbed it onto the
edit path. This is that plumbing. **No schema, no migration, no new synced table, no new invariant.**

**The concrete need this unblocks.** On the real library the D1 migration was a no-op — no `Cuisine`/`Course`
parent existed to promote, so `promoteNamespaceRootsToFacets` matched nothing and only seeded the starters. The
result is **15 loose labels shadowing empty starter values**, and each shadow (loose `Chinese`, 66 recipes) is an
**exact name-collision** with a non-deletable empty starter value (`Cuisine: Chinese`, 0 recipes). The
consolidation is therefore a **merge on collision**, not a plain move — which is the deterministic reconcile-by-name
contract the whole subsystem already runs (`reconcileCategories`, `foldDormantTags`, `deduplicateFacetSiblings`),
applied at the edit boundary. It exposes **no** general "combine two arbitrary categories" verb.

**Core — `RecipeCategoryRepository.updateCategory`:**
- Add `facetID: Facet.ID?`, replacing the derive-from-existing behaviour. Semantics via the existing
  `resolvedFacetID`: `parentCategoryID` non-nil → `facetID` must equal the parent's `facetID`; `parentCategoryID`
  nil → `facetID` is taken as given, `nil` meaning loose label.
- **Cascade the new `facetID` to all descendants** (the `CategoryHierarchy.descendantIDs(of:in:)` walk
  `promoteNamespaceRootsToFacets` already uses) whenever it changes, so D9 rule 2 (parent consistency) holds.
- **Reject a move to `facetID == nil` when the category has children** — loose labels are leaves (D9 rule 3).
  Reuse `looseLabelsCannotHaveChildren`.
- **Merge on name-collision in the destination — but only when membership `(facetID, parentCategoryID)` actually
  changes.** If the move lands on an existing same-name sibling in the destination facet/parent, re-point this
  category's recipe joins and children into that sibling and delete this row, via the existing **private**
  `mergeCategory(duplicate: self, into: existing)` — the existing sibling survives, so a non-deletable starter
  value stays canonical. **A pure in-place rename that collides still throws `duplicateSibling`** (typo guard —
  the user didn't ask to move). No new error case, no public merge API, `mergeCategory` stays `fileprivate`.
- Keep all four D9 invariants. `reconcileCategories` stays the sole node creator. The repository must not grow
  materially — this is a signature change plus a branch, not new machinery.

**App — `CategoryModels.swift` / `CategoryViews.swift`:**
- `saveCategoryButtonTapped` passes `facetID: editor.facetID` into `updateCategory`.
- Add a **Group picker** to `CategoryEditorSheet`: the visible facets plus **"No group"** (loose), writing
  `editor.facetID`. Changing the group **clears** `editor.parentCategoryID`. The Parent section already renders
  only when `facetID != nil`, so "No group" hides the parent picker — leaf-ness enforced in the UI too. **Moving
  is allowed for starter categories**; delete guards are unchanged.
- Surface the thrown error inline (existing `showError`) so a rename-collision explains itself rather than
  silently no-opping.

**Tests — `RecipeCategoryRepositoryTests`:** loose → facet value; facet value → loose; facet A → facet B; each of
those with children present (the new `facetID` cascades to descendants; a move-to-loose **with** children is
rejected); **a move onto an existing same-named value merges** — recipe joins re-pointed, source row deleted, the
existing (starter) value survives, covering the empty-starter case that is Jon's 15; an **in-place rename** onto
an existing sibling still throws `duplicateSibling`; a move of a **starter** category is allowed.

**Out of scope:** a general merge-two-arbitrary-categories verb or UI, or exposing `mergeCategory`; anything
touching the proposer or the D1 migration.

**Verification:** `swift build` the package, **the generic app build is required evidence** (App-layer change —
see the handoff Verification Pattern), `scripts/check-drift.sh`. **No schema → no prod-promotion entry and no
two-device pass** — every write goes through D1's already-sync-tested reconcile/merge paths.

## Guardrails a dispatch must not undo

- **Do not implement Amendment 1 separately.** It is accepted but unbuilt; its teardown is Pass A here. Seeding
  the ~24 starter *categories* by fixed id and then immediately re-seeding two of those rows as *facets* is two
  synced data passes and two two-device verification passes for one outcome.
- **One table, two columns. That is the entire schema cost.** Amd 2 D8's deferred table is binding: **no**
  `selectionMode`, `maximumValueDepth`, `isAssignable`, `isSystemProvided`, or per-facet coverage thresholds.
  `isSystemProvided` is **derivable** from the fixed seed-id constants — a stored copy is a second source of
  truth that can disagree with the first. If the record grows past `id / name / sortOrder / hidden /
  dateCreated`, the growth is the defect ([[withdraw-not-defer-orphaned-schema]],
  [[synced-table-cost-calibration]]).
- **Preserve child category UUIDs and every `recipeCategories` row.** The blast radius is the ~24 seed rows and
  two bookkeeping tables. Recipes and their joins ride through untouched — the same argument Amendment 1 made,
  and the reason "keep my ~2000 recipes" and "clean model" are not in tension.
- **No materialized ancestor joins** (D10). A recipe stores its most specific assignment; descendant matching is
  derived at query time via the existing `CategoryHierarchy.descendantIDs(of:in:)`.
- **Do not auto-promote a parentless category that has children.** That inference *is* the defect this
  amendment removes.
- **PR #269 Findings 1 and 3 are re-pointed, not reverted.** Finding 1's `item:`-binding confirmation pattern is
  still the house pattern and still guards facet creation — do not regress to an `isPresented:`-with-payload
  setter (the ADR-0030 destructive-setter defect). Finding 3's "file the recipe under the child, not the bare
  root" was hand-enforcing the rule that is now structural; the *behavior* stays, the hand-enforcement moves
  into the schema.
- **Do not seed a Cookbook / Author / Publication / Website facet.** Source metadata stays typed
  (Amd 2 Resolved OQ5, ADR-0006).
- **Do not seed the wider editorial taxonomy.** Dish Type, Protein, Technique et al. are OQ4 content work with
  their own session. Cuisine and Course only.
- **Reconcile stays the sole writer.** Nothing here replaces the case-insensitive `reconcileCategories`
  contract; the invariants live *with* it.
- **This is not the browser.** No `RecipeBrowserQuery`, no counts, no filter-bar re-point — that is ADR-0050.

## Blast radius (sized honestly)

**Core:** `Models.swift` (`Facet`, `Category` + 2 columns), `Schema.swift` (DDL + drops),
`RecipeCategoryRepository.swift` (**the big one** — seeding, `effectiveCategorySet`, tombstone reconciliation
deletes outright, create/update/delete/move validation, merge), `CategoryHierarchy.swift`, `CloudSync.swift`
(register `Facet`, unregister both seed tables), `RecipeListRequest.swift`, `RecipeCore.swift`,
`RecipeRepository+Import.swift` (D12 mapping), `RecipeEditorDraft.swift`, `RecipeAdjustment.swift`,
`PaprikaHTMLImport.swift`, `LabelProposer.swift` (Dispatch 3). Delete `CategorySeedState.swift`,
`CategorySeedTombstone.swift`.

**App:** `CategoryViews.swift`, `CategoryModels.swift`, `RecipeCategoryFilterView.swift`,
`RecipeFilterPickerViews.swift`, `RecipeLibraryListState.swift`, `RecipeListPresets.swift`,
`RecipeEditorModels.swift` / `RecipeEditorView.swift`, `RecipeCaptureView.swift`,
`RecipeCaptureModel+Labels.swift`, `RecipeListRow.swift`, `SettingsViews.swift`. Most are incidental
references; the management browser, the library filter and the capture chips are the substantive three.

`RecipeCategoryRepository.swift` is 849 lines today and a large share of that is the tombstone/seed-state
convergence machinery Amendment 1 already condemned. **This effort should make it substantially smaller.** If
it grows, something has gone wrong.

## Verification

- `xcodegen generate` (new Swift files), `swift build` the package, **the generic app build is required
  evidence** (App read-migration — see the handoff Verification Pattern), `scripts/check-drift.sh`.
- **Core tests carry the migration's correctness:** re-running the seed/promote pass is a no-op; a promoted
  child keeps its UUID and its recipe joins; a recipe joined to a bare `Cuisine` root is remapped and reported,
  never dropped; each of D9's four invariants rejects its violation; a simulated two-device run produces no
  duplicate facet or category rows (fixed-id convergence).
- **The audit report is reviewed by Jon before the second device converges.**
- **This IS a synced-table data pass → Jon owes a two-device sync pass. Back up first**
  ([ADR-0030](../decisions/ADR-0030-local-backup-and-restore.md)). Confirm on device: (a) Cuisine/Course appear
  as facets with their values intact, (b) every recipe's category assignments are unchanged, (c) former tags
  appear as loose labels, (d) both devices converge with no duplicate rows, (e) the library filter still finds a
  recipe by its cuisine.
- **Prod-schema promotion, in this slice's own PR:** add `facets`, `categories.facetID`, `categories.hidden`;
  **remove `categorySeedStates` and `categorySeedTombstones`** from the list — Amendment 1 dropped them and
  leaving them there is how a dead record type enters the production schema and locks forever.

## Post-D5 device-pass findings (recipe-facing surfaces the facet work didn't reach)

Found on Jon's device pass 2026-08-04, after the D1–D5 merges + the Dispatch 4 hand pass. All three are that the
facet/`hidden` model is enforced in the **catalog** (`CategoryListRequest` / `FacetListRequest` filter hidden;
D2's management browser groups by facet) but **not** in the recipe-facing product reads. F1 and F2 are
dispatchable app/Core slices and should land **before** the S5/S6 labeling backfill — that is exactly when
hand-assignment volume spikes and these surfaces are worst. F3 is a cross-reference to a deferred ADR-0050
question, not a slice here.

### F1 — the recipe editor's category selector is not facet-aware *(D2 gap; app-only)*

`RecipeCategorySelectionView` renders `RecipeEditorModel.categoryRows`, which is
`CategoryHierarchy.displayRows(from: categories)` — a **flat `parentCategoryID` tree**
([`RecipeEditorModels.swift`](../../YesChefApp/RecipeEditorModels.swift) `categoryRows`,
[`CategoryViews.swift`](../../YesChefApp/CategoryViews.swift) `RecipeCategorySelectionView`). Facets are not
category rows, so a facet **value** (`Chinese`, `Dinner`) has `parentCategoryID == nil` and renders at depth 0 —
visually identical to a loose label, with the facet title (`Cuisine`, `Course`) nowhere on screen. A legacy
nested category (`Chef` → children) still nests, because it *is* a category with category children. Assignment
still works; only the presentation is facet-blind. **Fix:** give this view the same facet-sectioned shape D2 gave
the management browser (a section per visible facet with its values nested; loose labels under their own "Other
Categories" section). Also fix `selectedCategorySummary`, which filters the same flat rows and so drops facet
context. **No schema, no Core.** Once real two-level facets exist (`Protein > Beef > Tenderloin`) a flat list
also can't disambiguate same-named values, so this is not merely cosmetic.

### F2 — `hidden` leaks onto recipe rows/detail and into filter availability *(D2 defect; Core + app)*

`CategoryListRequest` / `FacetListRequest` correctly exclude hidden ([`RecipeCategoryRepository.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeCategoryRepository.swift)
lines 4–32), so the editor picker and the filter **catalog** hide correctly. But
[`RecipeListRequest.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeListRequest.swift) builds
`categoriesByID` from an **unfiltered** `Category.fetchAll` (line ~42) and derives each recipe's `displayNames`
(shown on list rows + detail) and `filterNames` (the source of `categoryFilterAvailabilityByName`) straight from
the raw `RecipeCategory` joins through that map — with **no `hidden` filter**. Result exactly as observed: hiding
a category still shows it on recipes and leaves it filterable. **Fix:** apply the same visibility predicate
(`!category.hidden && facet-not-hidden`) when building `displayNames` / `filterNames`, **keeping the join intact**
so unhide restores it (hidden = suppressed in product reads, assignment preserved — the ADR-0049 D7
"effective set" intent). Cover every product read path (list row, detail, filter availability). **The class of
bug is "one surface filters hidden, another doesn't"** — factor a single shared visible-category-ID helper both
`CategoryListRequest` and `RecipeListRequest` call, rather than a second copy of the predicate. **No schema.**

### F3 — retire the typed freeform `Cuisine` / `Course` editor fields *(→ ADR-0050 OQ5, deferred — not a slice here)*

[`RecipeEditorView.swift:72`](../../YesChefApp/RecipeEditorView.swift) still carries
`StackedTextField("Cuisine", …draft.cuisine)` and `…course` — the legacy ADR-0006-era typed `Recipe.cuisine` /
`Recipe.course` columns, sitting directly above the working category selector. They are redundant with the
Cuisine/Course facets, and unlike source metadata (kept typed on purpose — Amd 2 Resolved OQ5 / ADR-0006), D6
routes `recipeCuisine` **into** the Cuisine facet, so these two fields are on a **retirement** path. The
retirement — migrate existing typed values into facet assignments (synced, deterministic-UUID/post-engine,
[[migration-writes-bypass-sync-triggers]]); drop the two inputs; delete the redundant Fields → Cuisine/Course
filters — is [**ADR-0050 OQ5**](../decisions/ADR-0050-recipe-power-browser.md) and is sequenced with that ADR's
S3.5 filter-bar re-point, gated behind the same coverage backfill. **Do not fold it into F1/F2 or into D5.**
Interim if the redundancy bites during dogfooding: hide the two inputs (app-only) — but partial, since import
still populates the column and the Fields filter still reads it, so prefer doing the retirement whole.

**Preserve the per-facet picker affordance — rebind, don't delete (Jon, 2026-08-04).** The retirement must keep
the fast **single-select dropdown per facet** (pick one `Cuisine`, pick one `Course`) — it beats drilling the F1
tree for a flat, single-ish facet — and just bind it to the facet's *values* instead of a free-text string. No
schema: single-Cuisine is a soft picker convention (ADR-0049 OQ2/D8), so a single-select dropdown over a
still-multi-capable model is pure UI and does **not** earn the deferred `selectionMode` column. Full rationale in
[ADR-0050 OQ5](../decisions/ADR-0050-recipe-power-browser.md).

## Labeling backfill — scoping (the ADR-0050 D6 coverage gate)

*Scoped 2026-08-04 as the next facet target.* ADR-0050 D6 fixes the sequence and calls coverage "the real
schedule risk": **explicit facets → proposer re-pointed → a real backfill run over the library → the browser.**
The first two are done (D1 + D3). This section scopes the backfill.

**Build state — the "re-run the S5/S6 queue" framing is inaccurate; there is no queue yet.** Only the S3
proposer **engine** (`LabelProposer`) and its S4 **capture** integration are built. **S5 (detail mini-labeler)
and S6 ("needs labels" batch queue) are NOT built** — confirmed in the app: `LabelProposer` is invoked only from
the capture flow, there is no detail-view "Suggest labels" CTA and no batch/"needs labels" queue. ADR-0050's D8
coverage **diagnostics** are also unbuilt (they belong to ADR-0050). So the backfill first needs its *tooling*
built, then *run*.

**The gating prerequisite is the editorial taxonomy (Amd 2 OQ4), not the tooling.** The browser's value is
coverage on **Protein / Dish Type / Technique** — but those facets **do not exist**; D1 seeded only Cuisine and
Course. You cannot backfill Protein coverage before Protein is a facet. And post-Dispatch-4, Cuisine/Course are
already largely covered, so a batch queue built today would have almost nothing to chew on. **OQ4 is therefore
both the gate on the backfill's value and the thing that gives S6 a backlog to clear.** It is a *content* session
(cost-of-error is real — a bad dimension is hand-re-filed across the library), decided with Jon, seeding the
chosen facets by fixed id with starter values. Candidates (ADR-0049 Amd 2 OQ4, none ratified): Dish Type,
Protein, Technique, Featured Ingredient, Dietary, Occasion, Season, Practical.

**The arc, in order:**

0. **OQ4 — editorial-taxonomy session — ✅ DONE 2026-08-04.** Decided: seed **Protein, Dietary, Dish Type,
   Technique** (Occasion/Season/Featured Ingredient/Practical declined). Full decision, shapes, the Technique↔Dish
   Type boundary, and starter values are in [ADR-0049 Amd 2 § Resolved OQ4](../decisions/ADR-0049-unified-labels-and-assisted-tagging.md).
1. **Seed the editorial facets** *(Codex build — the live target).* One small deterministic slice: extend the
   existing `starterFacets` seed (Cuisine/Course) with the four new facets + their starter values, fixed ids,
   post-`makeSyncEngine`, insert-if-absent/idempotent — **no schema change** (`facets` + `Category.facetID`/
   `hidden` already exist). Same shape and machinery as D1's Cuisine/Course seed. Synced-data pass → owes a light
   two-device pass (deterministic ids converge; back up first).
2. **S6 — "needs labels" batch queue** *(Codex build).* Library filter (`RecipeActiveFilterBar`) + one-by-one
   ADR-0025 curation review + prefetch of the next recipe's suggestions; on-device tier, no network; reuses
   `LabelProposer` + reconcile (the sole writer). "Needs labels" is a **derived** predicate — a recipe missing a
   value a primary facet would want — never a persisted `Unclassified`/`Other` row (ADR-0050 D7, "Missing ≠
   Other"). This is the couch tool that does the actual backfilling.
3. **S5 — detail mini-labeler** *(Codex build, smaller).* Standalone sheet off the recipe detail, empty-state
   "Suggest labels" CTA, re-runnable ("suggest more"). Batchable with S6 or a fast-follow.
4. **ADR-0050 D8 coverage diagnostics** *(Codex build, ADR-0050's).* The labeling work list and the D6 gate's
   measure; ADR-0050 says ship it early, so it can precede the run to size the job and set the OQ3 threshold.
5. **The run** *(Jon, couch work — like Dispatch 4).* Clear the backlog with S6 → coverage rises → ADR-0050 D6
   gate opens → the Power Browser's S1 becomes dispatchable.

**Live target is now step 1 — the seed slice** (OQ4 is decided, so it is dispatchable to Codex). S6 follows,
because a batch queue is only worth running once the four new facets exist to label against.
