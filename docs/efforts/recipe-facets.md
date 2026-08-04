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

## After this effort

Jon's hand pass (Dispatch 4), then the editorial-taxonomy session (Amd 2 OQ4), then the S5/S6 labeling backfill
— which is [ADR-0050](../decisions/ADR-0050-recipe-power-browser.md) D6's coverage gate and the real
prerequisite for the Power Browser. **The browser's S1 is not dispatchable until coverage is real.**
