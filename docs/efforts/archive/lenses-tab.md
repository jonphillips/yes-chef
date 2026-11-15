# Effort — The Lenses tab

Status: Ready
Summary: Lenses move out of the Power Browser into their own tab: a gallery of your Lenses and your family's, each Lens built and edited on its own screen with a tray of suggested shelves, and a family cookbook opening on its owner's Lenses. No schema change.

Implements: [ADR-0050 Amendment 2](../../decisions/ADR-0050-recipe-power-browser.md#amendment-2--lenses-get-their-own-tab-and-a-lens-is-built-on-its-own-screen-2026-11-15).
The amendment is the design; read A2-D1 through A2-D6 first, and Amendment 1 for what a Lens is. This brief adds
where things go and what done looks like. Builds on [recipe-lenses](recipe-lenses.md) (L1 + L2, #403) and
family-cookbooks S4 (#521), which carried Lenses into the cookbook.

**No schema change.** `recipeLenses` and `recipeLensShelves` already hold everything here. If you find you need a
column, stop and ask.

## Models

- **`LensesModel`** (`@Observable @MainActor`, guardrail #2), one per library, built with a `scope: LibraryScope`
  like `PowerBrowserModel(scope:)`. It owns the Lens library, the evaluation, the open Lens, edit mode and one
  `Destination` enum (house rule: no `isShowingX` booleans). The Lens code in `PowerBrowserLensModel.swift` moves
  here; that file goes away.
- **Every write action does nothing unless `scope == .mine`.** That's the guard pattern the Power Browser uses now.
- **The model builds recipe presentations** (`recipeTapped(_:) -> RecipeDetailPresentation`), always with its own
  scope, so the view can't drop it again (the bug fixed in the preceding fix PR).
- **Cookbook scope:** `CookbookLibraryModels` gains `lenses`, built inside the same `withDependencies` block over the
  mirror database.
- **The gallery reads several libraries.** Mine comes from the main database. Each cookbook section comes from that
  cookbook's `LensesModel`, so its Lenses, recipes and thumbnails come from its mirror (set `recipeImageDatabase` on
  that section, as the cookbook detail does).

## The tab and the gallery (A2-D1)

- `AppSection.lenses`, titled **Lenses**, with a new `AppSymbol.lens`. Use `camera.aperture` unless Jon picks
  another in review. It goes in the sidebar right after Recipes on iPad, and after Menus on iPhone. Mind the
  ten-child limit on `TabContentBuilder`: it goes in the existing `Group`. Visible by default on iPad. On iPhone it
  starts hidden from the tab bar (like Power Browser), so Jon can choose which tab it replaces.
- **The root is a full-width `NavigationStack`**, never a split view. Tapping a card pushes the Lens with
  `navigationDestination`.
- **Card:** the name; the base chips (reuse `selectionLabels(for:)`); "5 shelves"; and a 2×2 mosaic of thumbnails
  from the first recipes of the first shelves (or of the base, for a Lens with no shelves). Without photos, the
  mosaic falls back to the existing no-photo treatment, not an empty frame. A broken Lens's card says it needs
  repair.
- **Sections:** **My Lenses**, then one per accepted cookbook, titled with the owner's display name, in
  `cookbookLibraryModel.contexts` order. Leave out sections with no Lenses. **New Lens** is a toolbar button for My
  Lenses. Owner cards have a context menu with Rename and Delete (Delete asks first), and the gallery's edit mode
  reorders My Lenses with `reorderContainer`, writing `sortOrder` (jon-platform `ui-and-platforms.md`). Cookbook
  cards have no context menu.
- **Empty state** when you have no Lenses: a short explanation and New Lens.

## The Lens screen and edit mode (A2-D2)

- **Viewing** is today's `RecipeLensShelvesView`, pushed instead of swapped in, plus a **Browse all** toolbar
  action (A2-D4). A Lens with no shelves shows its base recipes as one grid.
- **New Lens** opens a sheet listing facet values with counts over the whole library, grouped by facet, with a
  search field, and a **Build a custom base** row that opens the base-query sheet (A2-D3). Picking a value creates
  the Lens named after it (rename later), then pushes it in edit mode.
- **Edit** (owner only) switches the same screen into edit mode:
  - shelf titles become text fields that save on submit;
  - shelves reorder with `reorderContainer` (resolve IDs from the displayed shelves, house rule) and delete by swipe
    or context menu;
  - empty shelves show with 0, broken ones with **Fix**, which opens the query sheet on that shelf;
  - **Everything else** shows with its count even when the remainder toggle is off, and the toggle sits beside it;
  - the Lens name and **Edit base** are at the top;
  - a **suggestion tray** offers A1-D5's suggestions for the base, leaving out values that already have a shelf.
    On regular width it's a trailing panel; on compact width it's a section below the shelves. Each row shows the
    value and its count. Tapping one adds a shelf titled with the value's name, at the end, and the shelf's recipes
    appear at once.
  - **Add custom shelf** opens the query sheet (A2-D3).
- Every change writes as it's made, through `RecipeLensRepository` (row-grain, stable IDs, guardrail #4). **Done**
  only leaves edit mode.

## Query sheets (A2-D3)

- One sheet, hosting the Power Browser's filter controls. Lift `PowerBrowserFacetsView` and the attribute, usage and
  source sections out of `PowerBrowserView.swift` so the browser and the sheet share them. Don't copy them.
- **For a shelf**, the sheet's engine is built over the base's recipes only: filter `RecipeBrowserData` to the base
  IDs before building `RecipeBrowserEngine`. Put that in Core (e.g. `RecipeBrowserData.restricted(to:)`) so it's
  tested. The sheet shows "14 recipes in this Lens" as the cook narrows. Its title field defaults to the selections
  joined with " · " (reuse `lensTitle`), until the cook types their own.
- **For the base**, the same sheet runs over the whole library.
- Cancel discards. Save writes the query through the existing repository functions.

## The Power Browser (A2-D4)

- Remove the Lens picker, `isShowingLensShelves`, `selectedLensID`, `queryEditTarget` and the Save query button,
  along with the `editLens` and `seeAll` destinations.
- **Save as Lens** stays. It still asks for a name, defaulting to the query's first selection. It then creates
  the Lens and calls a new `onLensCreated: (RecipeLens.ID) -> Void` closure. The app root switches to `.lenses` and
  opens that Lens in edit mode.
- **Browse all** from a Lens opens the Power Browser on the base query. From your own Lens, the root switches to
  `.powerBrowser` and sets the query. From a cookbook Lens, the cookbook's switcher moves to Power Browser with the
  query. Use closures, as `onRecipeSelected` is passed today. Models don't reach into the root.

## In a family cookbook (A2-D5)

- `CookbookLibrarySurface` becomes `lenses`, `recipes`, `powerBrowser`. A cookbook opens on `lenses` when its
  mirror has any Lens, and on `recipes` otherwise.
- The cookbook's Lenses surface is the same gallery section and the same Lens screen, read-only: no Edit, no New
  Lens, no context menus on cards.
- **Shelf cards** have a context menu: **Copy to My Recipes** (`CookbookCopyModel.copyButtonTapped`), or **Open
  Mine** when S5's In My Recipes status says it's already there.
- **Copy shelf** is in the shelf header's menu and in See all, titled "Copy 9 to My Recipes", with the count of
  recipes not yet in your library. It's hidden when that count is 0. It asks first, then copies one recipe at a time
  through the same copy path, showing "Copying 3 of 9". At the end it reports how many copied and names any that
  failed. A failed recipe never stops the rest. It doesn't run Copy Them Too.

## Out of scope

- Copying a Lens (ADR-0071 Amendment 4; A2-D5).
- Any change to the Lens engine, intersection, remainder or suggestion semantics.
- Making the Power Browser itself work at compact width (ADR-0050 S5).

## Done when

- **Core tests:**
  - a restricted engine's counts equal the base ∩ value counts;
  - a restricted engine's suggestions leave out values with no recipes in the base.
- **`LensesModel` tests in `YesChefTests`** (they replace the Lens cases in `PowerBrowserModelTests`):
  - New Lens from a value creates the Lens named after it and opens it in edit mode;
  - a suggested shelf adds with the value's title and leaves the tray;
  - a custom shelf's default title comes from its selections;
  - shelf rename and reorder keep row IDs;
  - every write is a no-op in cookbook scope;
  - `recipeTapped` carries the scope in both scopes;
  - Save as Lens calls `onLensCreated` with the new ID;
  - Copy shelf skips recipes already in your library, keeps going past a failure and reports it (stub the copy
    client).
- `CookbookScopeTests` covers a cookbook opening on Lenses when its mirror has one, and on Recipes when it doesn't.
- **Verification** per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build, and
  `YesChefTests` on a simulator.
- **`closeout` appends the device pass:**
  - On iPad: build a Lens from New Lens with three suggested shelves and one custom shelf. Check the tray, the
    Lens-scoped counts and Everything else shrinking.
  - On iPad: Save as Lens from the Power Browser lands in edit mode.
  - On iPhone (or on Wendy's device, as a viewer): browse Jon's cookbook Lenses from the Lenses tab and from the
    cookbook. Open a shelf recipe, Copy shelf, and build a Lens of your own from copied recipes.
