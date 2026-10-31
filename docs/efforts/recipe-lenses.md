# Effort — Recipe Lenses

Status: Dispatched
Summary: Saved Lenses in the Power Browser: a base query plus ordered shelves of recipes, each shelf a query intersected with the base. Replaces ADR-0050 S4 (saved browsers); slices L1 + L2 in one PR.

Implements: [ADR-0050 Amendment 1](../decisions/ADR-0050-recipe-power-browser.md#amendment-1--saved-browsers-become-lenses-a-base-query-plus-ordered-shelves-2026-10-31).
The amendment is the design; read A1-D1 through A1-D7 before starting. This brief only adds where things go and
what done looks like. **Synced-schema change: two new tables.**

## L1 — Core and schema

- **Tables.** `recipeLenses` and `recipeLensShelves` as A1-D6 lists them, in one new migration appended to
  `Schema.swift` (never edit a shipped migration). `recipeLensShelves.lensID` cascades on delete. Add both
  types to `CloudSync.syncedTables`.
- **Query encoding.** `RecipeBrowserQuery` is already `Codable`. Wrap it in a small versioned envelope
  (`{"v":1,"query":…}`) stored as TEXT. Decode at read time in the feature, never in the migrator. A failed
  decode yields a **broken** shelf (or a broken Lens, if it's the base), never an empty query.
- **Evaluation**, in a new `RecipeLens.swift` beside `RecipeBrowser.swift`, using the existing engine:
  - each shelf = `matches(base) ∩ matches(shelf)`, as two separate engine evaluations, never one merged query
    (A1-D2);
  - the remainder = `matches(base) − ⋃ shelves`, when `showsRemainder` is on (A1-D3);
  - each shelf's state is `.ready(ids)`, `.empty` or `.unresolved(reasons)` (A1-D4). Unresolved means a
    referenced facet, value or label id no longer exists, or the facet is hidden (D9), or the decode failed.
    An unresolved base makes every shelf unresolved.
- **Suggestions** (A1-D5): for a base query, the facet values the engine already reports as available, with
  their counts, in the engine's existing ranking order. No model call.
- **Repository:** create, rename, delete a Lens; add, rename, reorder, remove a shelf; set `showsRemainder`.
  Reorders rewrite `sortOrder` on the moved rows only, and keep row ids stable (guardrail #4).

## L2 — iPad/macOS surface

- **Where it lives:** in the Power Browser tab. A Lens picker in its toolbar lists saved Lenses and
  "All recipes". Choosing a Lens with shelves replaces the facets-and-results split with the shelf view;
  choosing a zero-shelf Lens loads its base query into the ordinary browser. "All recipes" returns to the
  browser. No new `AppSection`.
- **Shelf view:** the base query's chips at the top; then one horizontally scrolling row per shelf, in order,
  each with its title, a count and **See all** (a full grid of that shelf, inside the Lens); then **Everything
  else** if it's on and not empty. Empty shelves are hidden. Unresolved shelves are shown, with a **Fix** action
  that opens the shelf in the editor. Recipe taps route to recipe detail as the browser's results do.
- **Save as Lens:** a toolbar action in the browser. It names a new Lens and uses the current query as its base,
  with no shelves.
- **Lens editor** (sheet): name; base query (shown as chips, with an action to edit it in the browser);
  shelves with drag to reorder, rename and delete; **Add shelf** from the suggestions list, or from the current
  browser query; the remainder toggle. The editor shows every shelf, including empty ones with a count of 0.
- **Not in scope:** compact width (the Power Browser is hidden there until S5), and Lens editing on the phone.

## Done when

- Core tests cover: the same-facet base/shelf case (base `Cuisine: Mexican`, shelf `Cuisine: Oaxacan` gives
  the Oaxacan recipes, not all of Mexican); a recipe on two overlapping shelves appears on both and not in the
  remainder; a corrupt shelf encoding reports as unresolved, not empty; a deleted value and a merged value in
  a shelf both report as unresolved; an unresolved base marks every shelf unresolved; reorder keeps row ids.
- `PowerBrowserModel` (or a new `LensModel`) tests for choosing a Lens, Save as Lens, and returning to the
  browser, run in the `YesChefTests` app target.
- Verification per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build, and
  `YesChefTests`. iPad simulator screenshots of a Lens with three shelves and the remainder, and of the editor,
  in the PR.
- The PR appends a held-ops block to `docs/device-passes.md`: before the next TestFlight build, create a Lens
  with a shelf on a simulator Debug build against Development (so both record types and every field upload
  with a non-nil value), re-export and diff per PROD-CUTOVER Reference A, then deploy Development → Production.
  Then the iPad device pass for the shelf view and the editor.
