# Effort — One glyph per concept: `AppSymbol` and its lint rule

Status: Ready
Summary: Add an app-layer `AppSymbol` type that owns each concept's glyph, convert every concept use (recipe becomes `richtext.page` everywhere, `book` means source, two Edit glyphs), move concept glyphs out of Core enums, and add a SwiftLint rule that rejects concept glyphs spelled as strings.

Jon asked 2026-11-10 whether the app has one icon abstraction. It doesn't. He chose the recipe glyph and the two Edit
glyphs the same day. One dispatch, one PR. No schema change. **Dispatch after #468 merges**, because it uses the
custom symbol sets #468 adds.

Decisions: [ADR-0065](../../decisions/ADR-0065-one-glyph-per-concept.md) (the vocabulary table is D2).
Related: [ADR-0064 D8](../../decisions/ADR-0064-menu-detail-declutter.md) (the custom symbols) ·
[standing guards](../../standing-guards.md).

## Where things are (architect, 2026-11-10)

- **Counts:** 393 `systemImage:` / `systemName:` literals in `YesChefApp`. Most are not concepts and stay (ADR-0065
  D3).
- **Concept glyphs in enums:**
  - `AppNavigationModels.swift`: the section `systemImage` (about line 77) and the settings-pane icons (about line
    120).
  - `RecipeActiveFilterBar.swift` (about line 40): library, sources, categories.
  - `MealPlanItemKind.systemImage` (`YesChefCore/Models.swift`, about line 297).
  - `GroceryItemOrigin.systemImage` (`Models.swift`, about line 585).
- **Known drift to fix:**
  - `book.closed` for recipe: the Recipes tab, `MenuViews` "No Recipes" and the recipe selection row,
    `MealCalendarViews` "No Recipes", and the `RecipeReaderSupportingViews` link row.
  - `fork.knife` for recipe: `AppMainLayout` "Select a Recipe", "Recipe Not Found" in `RecipeDetailView` and
    `MealCalendarViews`.
  - `tag` for "New Category" (`CategoryViews.swift`).
  - `checklist` for "Workbench These" (`RecipeLibraryView.swift`, about line 611).
- **Custom symbols:** three symbol sets in `YesChefApp/Assets.xcassets` (from #468). Xcode generates `ImageResource`
  accessors for them.
- **Lint:** `.swiftlint.yml` already has `custom_rules` (`persistence_in_views`), which is the pattern to follow.

## S1 — `AppSymbol` and the conversion (ADR-0065 D1–D4)

**Build.**
- **`YesChefApp/AppSymbol.swift`:**
  - `struct AppSymbol: Sendable, Hashable` wraps either a system name or a generated `ImageResource`.
  - It has `var image: Image`.
  - One `static let` per row of ADR-0065 D2, with the names and glyphs exactly as given.
  - Add `Label` initializers `init(_ title: LocalizedStringKey, symbol: AppSymbol)` and
    `init<S: StringProtocol>(_ title: S, symbol: AppSymbol)`.
  - Add whatever small helpers the call sites need: `ContentUnavailableView` with a symbol, and a `RecipeListMetadataLine`-style
    parameter. Prefer changing a helper's parameter type over adding parallel overloads.
- **Convert every use of a concept**, in `YesChefApp` and `YesChefShareExtension`, to `AppSymbol`.
  - Judge each use by **meaning, not glyph**. If a use of `book` means something other than a source, or `fork.knife`
    means a recipe, it gets the right concept, or keeps its literal if it isn't a concept at all.
  - List every use whose glyph changes in the PR body, with the file and the old and new glyph.
- **Enums:** app enums whose cases name concepts (`AppNavigationModels` sections and settings panes,
  `RecipeActiveFilterBar`) return `AppSymbol`. Rename the property to `symbol` where its type changes. Non-concept
  cases may wrap a system name in `AppSymbol` so the property has one type.
- **Core (D4):**
  - Delete `MealPlanItemKind.systemImage` and `GroceryItemOrigin.systemImage` from `YesChefCore`.
  - Add app-target extensions `var symbol: AppSymbol` with the same case mapping, except recipe, which becomes
    `.recipe`.
  - Leave `MealPlanItemSlot.systemImage` (meal slots aren't concepts) and `AnyChatApplyAction.systemImage` (a
    per-action field) alone.
  - First check that `YesChefMCP` and the share extension don't read the deleted properties. If one does, stop and
    ask.
- **Drift fixes:** the ones named above, using D2's concepts. Then audit the remaining uses of `pencil` and
  `square.and.pencil` against D2:
  - `.edit` opens a whole-recipe or whole-menu sheet.
  - `.editRow` edits one row or field.
  - The Create Recipe section tab moves from `square.and.pencil` to `.addRecipes` (D2).

**Acceptance.**
- No view passes a concept glyph as a string.
- The Recipes tab, recipe-kind calendar, menu and grocery items, and the recipe empty states draw `richtext.page`.
- `book` appears only for sources, and `book.closed` appears nowhere.

## S2 — The lint rule (ADR-0065 D5)

**Build.**
- Add a `custom_rules` entry, `concept_glyph_literal`, to `.swiftlint.yml`:
  - It matches a string literal equal to any system glyph in ADR-0065 D2, or starting with `custom.`.
  - Match only the literal's position as a `systemImage:` / `systemName:` argument, an enum case's return value, or an
    `Image("…")` / `image:` argument. Don't match free text.
  - Exclude `YesChefApp/AppSymbol.swift`.
  - Severity `error`.
  - Message: "Concept glyphs go through AppSymbol (ADR-0065)."
- Run it over the tree after S1. It must report zero violations.
- In the PR, show that it fires: temporarily add `Image(systemName: "trash")` to a view, run SwiftLint, paste the
  violation line, then revert.
- Add a comment above the rule saying the regex and the D2 table change together.

**Acceptance.** SwiftLint is clean on the tree and fails on a reintroduced concept literal.

## Verification and completion

- No schema, sync or migration change. Core loses two computed properties.
- Run focused tests, `scripts/check-drift.sh` (SwiftLint, package tests, app test build), and the generic device
  build per [verification.md](../../verification.md). Most of the change is view code. Run `YesChefTests` too, since
  enum properties that app model code reads change type.
- Closeout per ADR-0005 D16. This dispatch archives the brief.
- **Gate (Jon, iPad, then iPhone):**
  - The Recipes tab shows `richtext.page`.
  - Recipe-kind items in Menu and Calendar, and grocery sources, show it too. So do "Select a Recipe" and
    "Recipe Not Found".
  - A recipe's source line shows `book`.
  - The Recipe and Menu toolbar Edit is `square.and.pencil`, and row Edit is `pencil`.
  - New Category shows a folder with a plus, and the Create Recipe tab shows the page with a plus.

## Dispatch ledger

- [x] Dispatch 1 — S1 + S2, one PR. No schema.
