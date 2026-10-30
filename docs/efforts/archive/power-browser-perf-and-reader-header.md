# Effort — Power Browser responsiveness + reader header wrapping around the photo

Status: Drafted 2026-10-04 (architect). Schema-free. App layer plus one `YesChefCore` fetch.
Summary: Two dogfood fixes from Jon (2026-10-04, iPad). (1) The Power Browser takes seconds to respond when a
selection is removed. Once it has been opened, it also slows unrelated writes elsewhere, such as moving a
category in Settings (3–4 s). Neither is a slow SQL query. The cost is main-thread derivation in Swift that
is quadratic in library size (~2,185 recipes), and it re-runs on every library write because the visited tab
stays mounted. (2) In the wide reader, the hero photo is a fixed 360 pt wide. In a narrow directions column
that leaves about 100 pt for the title and metadata, so the title hyphenates, the servings chip wraps to three
lines, and the tag strip clips "Edit Tags".
Related: ADR-0050 (Power Browser) · [`recipe-reader-density.md`](recipe-reader-density.md) · memory
precedent: the ADR-0029 Finding 8 writer convoy (always-on whole-library `@Fetch`)

## Fix 1 — Power Browser: stop the quadratic main-thread work

### Why it's slow (architect read, 2026-10-04; confirm with the timing log below)

1. **`PowerBrowserModel.sourceFilterOptions(for:)` is O(fields × distinct values × matching recipes).** It
   calls `normalizedSourceValue` (locale-aware `folding`) in the innermost loop. It also computes the
   **`.website`** field, whose values are about one per recipe (URLs), and then
   `PowerBrowserSourceFilters` drops `.website` and never shows it (`PowerBrowserView.swift`,
   `sourceFields`). That alone is roughly 2,185² ≈ 4.8 M string foldings per body evaluation. This is the
   main suspect for the multi-second hitch on every tap.
2. **`looseCategoryOptions(for:)` is O(categories × matching recipes).** It's cheaper, but the same
   shape. Do it in one pass.
3. **The derivations aren't cached.** `result` is memoized on `(browserData, query)`. The option lists and
   `recipeRows(for:)` (which rebuilds a dictionary of every row) run again on every body evaluation.
4. **The visited tab never unmounts.** `AppMainLayout` uses `TabView`, so after the first visit
   `PowerBrowserView` stays in the hierarchy. Any write to recipes, categories, sources, photos, or the
   calendar re-fires `RecipeBrowserDataRequest`, `browserData` changes, and the hidden view re-derives all
   of the above on the main actor. That is the Settings "move category" lag, and it explains why the lag
   only appears *after* the Power Browser has been opened.
5. **`RecipeBrowserDataRequest` fetches every photo's `thumbnailData` BLOB** just to test it for non-nil
   (`RecipeBrowserPhotoRow`). The request runs twice per write: once in `RecipeLibraryModel` and once in
   `PowerBrowserModel`.
6. Same disease, Recipes tab: `RecipeLibraryModel.visibleRecipeRows` and `recipeCount(for:)`
   (`RecipeLibraryListState.swift`) build a fresh `RecipeBrowserEngine` on every access. The engine's init
   computes descendant and ancestor sets for every category. That tab is always mounted.

### Do

- **Measure first.** Add DEBUG `AppLog.performance` timing around the Power Browser derivations (result,
  source options, loose-category options, rows) and around `visibleRecipeRows`. Log before and after in the
  PR description, using the seeded sample library or a large fixture. The Finding 8 lesson was that the
  obvious theory was wrong three times, so don't skip this step.
- **Source options in one pass.** Normalize each source value once, then group by `(field, normalized
  value)` to count matching recipes. Don't compute `.website` at all, because nothing displays it (take it
  out of the option derivation, not out of `RecipeBrowserSourceField`). Keep today's displayed values,
  counts, ordering, and selected-value retention exactly as they are.
- **Loose-category options in one pass** over the matching recipes.
- **Memoize the derived lists in the model**, keyed on the same `(browserData, query)` identity as
  `cachedResult`, so a body evaluation with nothing changed costs a dictionary lookup. One cache struct for
  result + options + rows is fine.
- **Don't derive while hidden.** Only evaluate the Power Browser's derived content when its tab is
  selected. Query state already lives in the model, so unmounting or gating the view loses nothing. Pick the
  simplest mechanism and say which one in the PR.
- **Photo fetch: test the BLOB in SQL.** Select `recipeID` where `thumbnailData IS NOT NULL` and the kind
  isn't `.referenceDocument`. Never select the BLOB itself.
- **Cache the engine on the Recipes tab** (`visibleRecipeRows`, `recipeCount(for:)`), keyed on
  `browserData` the way `PowerBrowserModel.browserEngine()` already does.
- While in there: `PowerBrowserModel.browserEngine()` doesn't pass `recipeIDsWithPhotos` into the engine.
  Pass it.

Don't merge the two `RecipeBrowserDataRequest` observers into a shared store in this dispatch. Note in the
PR whether it still matters once the work above lands.

### Tests

- `PowerBrowserModelTests`: source and loose-category options give the same values, counts, ordering, and
  selected-value retention as before. Write the expectations from the current behavior *before* the
  rewrite. Cover diacritics and case-folded duplicates ("Café" / "cafe").
- `RecipeBrowserDataRequest`: `recipeIDsWithPhotos` is unchanged. A photo with a nil thumbnail and a
  reference document are both excluded.

## Fix 2 — reader header: text wraps around the photo, then the full width below it

In `wideColumnHeader` (`RecipeDetailView.swift`), only **title, subtitle, and summary** sit beside the
photo. **Stats chips, tags, Edit Tags / Undo, source, notes, and the variation selector** go in a
full-width block *below* the title+photo row, so they never share a line with the hero.

- **Size the hero from the column, not from a constant.** `wideRecipeColumns` already knows
  `directionsWidth`, so pass the content width in. Beside the text, the hero width is
  `min(360, ~45% of content width)`. When that leaves the text column below a readable minimum (about
  280 pt), stack the hero full-width above the title, with its height capped. Use explicit width math,
  not `GeometryReader`.
- **Wrap the chip strip; don't scroll it.** Replace the horizontal `ScrollView` in `wideMetadata` with a
  real flow layout (a small `Layout` that wraps to new lines), so "Edit Tags" is never clipped.
  `WrappingLabels` is all-HStack-or-all-VStack, not wrapping. Back it with the same flow layout and put the
  layout with the shared view treatments, so it's centralized rather than hand-rolled a second time.
- The compact (`header` + `metadata`) path doesn't change, apart from `WrappingLabels` picking up the flow
  layout.

## Out of scope

- True text flow around an image (magazine float). SwiftUI can't do it, and the above-then-below split is
  the intended look.
- Any change to the Power Browser's ranking, facets, or self-excluding counts (ADR-0050 D4).

## Done when

Both fixes land with the tests above, the PR shows before/after timings, `check-drift.sh` is green, and the
generic iOS build passes. `YesChefTests` runs (model code changes). Owed device pass (iPad, full library):
removing a Power Browser selection feels immediate. After visiting the Power Browser, moving a category in
Settings is as fast as before visiting it. The Whipped Feta recipe in a narrow directions column shows a
readable title, a one-line servings chip, and an unclipped "Edit Tags".
