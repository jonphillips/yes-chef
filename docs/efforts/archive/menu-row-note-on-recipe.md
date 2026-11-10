# Effort — The menu row's note shows on the recipe screen

Status: Ready
Summary: When a recipe is opened from a menu row or a calendar row, the recipe screen shows that row's note in a card labeled with the menu (or the day). Opening the recipe from the library shows no card. The note stays on the row and is edited where it is today, in Edit Dish. Read-only on the recipe screen, no schema change, no change to the recipe.

Origin: Jon planning a Mediterranean dinner with ChatGPT (2026-11-10). The souvlaki's tahini-butter sauce is served
on the side for this menu only. That's a fact about the dish on this menu, not a recipe change, and it belongs in
the menu row's note. Today the note shows in the menu and on the calendar, but it disappears as soon as the
recipe opens, which is exactly when the cook needs it. One dispatch, one PR. **No schema change.**

Decisions: none new. A menu row's note is already where a menu-specific annotation lives, and the recipe stays
canonical; this brief only shows it. [ADR-0060](../../decisions/ADR-0060-chat-access-over-mcp.md) Amendment 3, proposed in a
separate plan PR, writes that down as its D1 and adds the chat tool. This brief doesn't depend on it. Related: [ADR-0063](../../decisions/ADR-0063-menus-absorb-calendar-days.md) (calendar rows that come
from a menu) · [ADR-0064](../../decisions/ADR-0064-menu-detail-declutter.md) (menu rows without buttons) ·
[[decompose-notes-into-typed-homes]] (the row note is this annotation's typed home, not the recipe's notes).

## Where things are (architect, 2026-11-10, `origin/main` 9ac187a)

**The note already exists on every row.**
- `MenuItem.notes` and `MealPlanItem.notes` (`Models.swift`). A recipe row has a note independent of its
  `recipeID`, and the same recipe twice in one menu gives two rows, each with its own note.
- Edited in the menu's **Edit Dish** sheet, the **Serving Notes** field for a recipe row (`MenuViews.swift`, about
  line 736). Shown on the menu row (`MenuDetailSections.swift`, about line 459, three lines) and on the calendar row
  (`MealCalendarMealPlanItemRow.swift`, about line 76).

**The recipe screen already knows which row opened it.**
- `ScaleContext` (`RecipeScaleCore.swift`): `.recipe(id)`, `.menuItem(id)`, `.mealPlanItem(id)`.
- These callers pass a row context:
  - the menu row's primary action (`MenuDetailSections.swift`, about line 483, `.menuItem`);
  - `MenuViews.swift`, about line 346 (`.menuItem`);
  - the calendar (`MealCalendarViews.swift`, about line 948): `.menuItem` for a row that comes from a menu,
    otherwise `.mealPlanItem`;
  - the cook session (`CookSessionView.swift`, about line 103, `item.scaleContext`).
- The library and the Power Browser pass `.recipe(id)`, so the card never shows there. No extra rule is needed.
- `RecipeDetailModel` (`RecipeModels.swift`, about lines 709–810) stores `scaleContext` and uses it for one
  `@Fetch`: `persistedScale` via `RecipeScaleRequest`. **This brief adds a second `@Fetch` beside it, in the same
  shape.**

**Layout anchors (`RecipeDetailView.swift`, `RecipeReaderView`).**
- Compact: the `VStack` at about line 360 holds `header(recipe)`, `metadata(recipe)`, the variation repair notice,
  then `compactRecipeBody` (the Ingredients/Method picker).
- Wide: `wideRecipeColumns` (about line 696). The directions column opens with `wideColumnHeader` then
  `directionsColumn`.
- `variationMethodNote` (about line 834) is the precedent: a labeled `.attentionCard()` (`AttentionCard.swift`).
- Glyphs: `AppSymbol` has `.menu` and `.calendar` (ADR-0065; don't hand-roll SF Symbol names).

## The slice

### Core

- **`RecipeRowNote`**, a small value: `text: String` and `origin`, which is one of:
  - `.menu(title: String)`, the menu's title;
  - `.day(date: Date, slot: MealPlanItemSlot)`, for a calendar row that isn't from a menu.
- **`RecipeRowNoteRequest: FetchKeyRequest`** with `context: ScaleContext` and `recipeID: Recipe.ID`. It returns
  `RecipeRowNote?`:
  - `.recipe`: `nil`.
  - `.menuItem(id)`: find the row; `nil` if it's missing, **if its `recipeID` isn't the `recipeID` being shown**,
    or if its note is `nil` or empty after trimming. Otherwise the note (trimmed) and its menu's title.
  - `.mealPlanItem(id)`: the same checks, with the row's `scheduledDate` and `mealSlot`.
  - The `recipeID` check means a card can never show a note from a row that has since been pointed at another
    recipe (Edit Dish can swap it).
- Put it beside `RecipeScaleRequest` in `RecipeScaleCore.swift`, or in a new file next to it. Either is fine.

### App

- **`RecipeDetailModel`** gains `@ObservationIgnored @Fetch var rowNote: RecipeRowNote?`, initialized in `init`
  beside `_persistedScale`, with `RecipeRowNoteRequest(context: self.scaleContext, recipeID: recipeID)` and
  `animation: .default`. It's a live observation, so editing the note in Edit Dish (or a sync) updates an open
  recipe screen (guardrail #1).
- **A `RecipeRowNoteCard` view**, `.attentionCard()`:
  - Label: **"For <menu title>"** with `.menu`, or **"For <weekday, month day> · <slot title>"** with `.calendar`.
  - Body: the full note as plain `Text`, with no line limit, selectable.
  - **Read-only.** There's no edit button on the recipe screen. The note is edited in Edit Dish, where it's stored.
  - The label is the guard against confusing it with the recipe: it names whose note it is. Don't use the words
    "Notes" or "Recipe notes" in the card.
- **Placement:**
  - Compact: after `metadata(recipe)` and the variation repair notice, **before** `compactRecipeBody`, so it shows
    above both Ingredients and Method.
  - Wide: at the top of the directions column, after `wideColumnHeader` and before `directionsColumn`.
  - It isn't part of the Playbook and doesn't move with a variation. Choosing a variation leaves it in place.
- **The recipe is never written.** No path from the card writes to `recipes` or its children.

### Out of scope

- Editing the note from the recipe screen. Edit Dish is the one editor.
- Showing the card anywhere besides the recipe screen (grocery sources, prep plan, chat context).
- Anything on the chat side. That's Amd 3's tool, which gets its own brief once Amd 3 is accepted.

### Tests

**Core (`YesChefCoreTests`)** for `RecipeRowNoteRequest`:
- A menu row with a note returns the note, trimmed, and the menu's title.
- A note that's `nil`, empty, or only whitespace returns `nil`.
- `.recipe` returns `nil`.
- **The same recipe twice in one menu with different notes:** each row's context returns its own note.
- A row whose `recipeID` is a different recipe returns `nil`.
- A missing row returns `nil`.
- A calendar meal-plan row returns `.day` with its date and slot.

**App (`YesChefTests`):** `RecipeDetailModel` built with a `.menuItem` context exposes the row's note, and built with
`.recipe` exposes `nil`. This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- Opening a recipe from a menu row that has a note shows the card labeled with the menu, in both layouts and in the
  cook session. Opening it from the library shows nothing.
- No write path touches the recipe.
- Tests above; verification per [`verification.md`](../../verification.md), including the generic app build and
  `YesChefTests`; closeout (ADR-0005 D16).
- **Jon's device gate:** on Thanksgiving Week, open the souvlaki from the menu (card shows), from the calendar
  (card shows), and from the library (no card); then change the note in Edit Dish, reopen the recipe from the
  menu, and see the new text.
