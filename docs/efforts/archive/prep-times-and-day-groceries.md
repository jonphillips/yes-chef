# Effort — Prep times, day-sized grocery adds, and one recipe toolbar

Status: Ready
Summary: Today's Prep always shows each step's approximate time, and the menu's Prep Plan gets a **Show Times** switch (ADR-0034 Amd 4). Each menu day gets **Add Day to Groceries**, which opens the Add Ingredients sheet for that day with the optional split, and the Calendar's **Add Day to Groceries** opens the sheet too instead of adding straight away (ADR-0068 Amd 1). Fixes the duplicate recipe toolbar buttons in Today's Prep and the cook session. **Prep** gets the `flame.gauge.open` glyph. No schema change.

Origin: Jon, 2026-11-11, looking at Thanksgiving Week's dinner hour and the Groceries flow. One dispatch, one PR. No
persistent model change. Jon's advance grocery trip is around **Thu Nov 19**, and Thanksgiving is Thu Nov 26, so the
grocery half matters first.

Decisions: [ADR-0034 Amendment 4](../../decisions/ADR-0034-prep-plan-work-session-timeline.md) (E1–E3),
[ADR-0068 Amendment 1](../../decisions/ADR-0068-two-trip-grocery-split.md) (F1–F2), and the glyph line in
[ADR-0067](../../decisions/ADR-0067-todays-prep.md) D1. Read them first. Precedent: the archived
[`grocery-two-trips`](grocery-two-trips.md) brief built the sheet this effort reuses.

## Where things are (architect, 2026-11-11, `origin/main` 55cc1a5)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `MenuPrepPlanBands.swift`: `MenuPrepPlanBandStep` (`sessionLabel`), `MenuPrepPlanBanding.bands(…)`, which has the
  session-only heading rule twice (the Flexible band and each day), and `TodayPrepLayout.make(…)`, whose nested
  `labeledSteps` repeats it a third time.
- `MenuPrepPlan.swift`: `PrepPlanTime` (`"HH:mm"` ⇄ minutes).
- `GroceryRepository+Generation.swift`: `addMenu(menuID:groceryListID:in:now:uuid:includedIngredientLineIDs:)`
  (line 169), which adds every recipe item on the menu.
- `GroceryCore.swift`: `GroceryMenuRecipeIDsRequest` (line 76), which gives the sheet's recipes for a menu.
- `AppHelp.swift`: `AppHelpPage.menus` ("Prep plan" section) and `.groceries` ("Adding ingredients").

**App (`YesChefApp/`)**
- `RecipeDetailView.swift`: `recipeToolbar` (line 165), attached at line 75. It adds **Groceries**, **Plan** and the
  hand-off menu to whatever navigation bar hosts the view.
- `TodayPrepView.swift`: `readerPane` (around line 305), a page-style `TabView` with one `RecipeDetailView` per dish,
  selected by `selectedReaderID`. `sectionRows` (around line 203) draws `row.sessionLabel`. The layout comes from
  `TodayPrepLayout.make` (line 73).
- `CookSessionView.swift`: the same page-style `TabView` of `RecipeDetailView`s (around line 100), selected by
  `model.selectedItemID`.
- `MenuViews.swift`: the menu toolbar's **Prep** button (line 194, `systemImage: "checklist"`). The Prep Plan
  section's **⋯** menu (around line 459). `MenuPrepPlanSessionBandView` draws `presentation.sessionLabel` (around
  line 572).
- `MenuDetailSections.swift`: `MenuDaySection` (line 206). Its header row has **Add Recipe to Day N** (`plus.circle`)
  and the **Hand off** menu.
- `GroceryModels.swift`: `GroceryIngredientSelectionContext.Source` (around line 1004), `selectMenuButtonTapped`
  (line 364), `selectMealRowsButtonTapped` (line 352), `loadIngredientSelection` (line 404),
  `confirmIngredientSelectionButtonTapped` and its `addSelectedIngredients` helper (the split titles its lists from
  `context.title`), and `addMealRowsImmediately` (line 576) and `addMenuImmediately` (line 543).
- `GroceryViews.swift`: `GroceryIngredientSelectionView.canSplitIntoTrips` (around line 1021).
- `RecipeLibraryView.swift`: `init` wires `mealCalendarModel.onAddDayToGroceries` to `addMealRowsImmediately`
  (line 46). The grocery sheet presenter is attached at root (line 141), so a sheet opened from the Menus or Calendar
  tab presents there.
- `MealCalendarDayHeader.swift`: the Calendar day's **⋯ › Add Day to Groceries**.

## The slice

### 1. One recipe toolbar in paged readers (bug)

Today's Prep and the cook session show their dishes as pages, and each page's `RecipeDetailView` adds its own
toolbar items. The page beside the current one is often loaded too, so two identical **Groceries** carts (and two
**Plan** buttons) sit in the bar until the swipe settles. Only the page you're on should contribute buttons.

- Give `RecipeDetailView` a `showsToolbar: Bool = true` parameter. When it's false, `recipeToolbar` adds nothing.
- `TodayPrepView.readerPane` passes `dish.id == selectedReader?.id`. `CookSessionView` passes
  `item.id == model.selectedItemID` (the model starts it on the first item).
- Other callers keep the default.

### 2. Prep glyph (ADR-0067 D1)

- The menu toolbar's **Prep** button uses `systemImage: "flame.gauge.open"`. It's a literal, not an `AppSymbol`,
  because it's still on one surface. Leave every other glyph alone.

### 3. Times in the headings (ADR-0034 Amd 4)

**Core (E3):** one heading function in `MenuPrepPlanBands.swift`, used by all three places that build headings now:

- Input: steps in display order, plus `showsTimes: Bool`.
- A step's heading is `(time: Int?, session: String)`, where `time` is the step's `timeOfDay` when `showsTimes`,
  else nil. A step shows its heading when the pair differs from the step above. With `showsTimes == false` that's
  exactly today's session-only rule.
- `MenuPrepPlanBandStep` gains `headingTime: Int?`, set only on a step whose heading shows. `sessionLabel` keeps its
  meaning (non-nil means a heading shows).
- `MenuPrepPlanBanding.bands(…)` and `TodayPrepLayout.make(…)` take `showsTimes: Bool = false` and pass it through.

**App:**
- A shared view draws a heading: `"5:30 PM · <session>"` when `headingTime` is set, else just the session. Format the
  time from minutes using `Date.FormatStyle` with `.hour().minute()`, so the device's 12- or 24-hour setting applies.
  Use it in `TodayPrepView.sectionRows` and `MenuPrepPlanSessionBandView`.
- **Today's Prep (E1):** `TodayPrepLayout.make(…, showsTimes: true)`, always.
- **Menu Prep Plan (E2):** `@AppStorage("menuPrepPlanShowsTimes")`, default false. In the Prep Plan's **⋯** menu,
  above **Rebuild with Yes Chef…**, add `Toggle("Show Times", isOn:)`, shown only when some step has a `timeOfDay`.
  Pass the value to `bands(…)`.

### 4. Add Day to Groceries on a menu day (ADR-0068 Amd 1, F1)

**Core:**
- `GroceryRepository.addMenu` gains `dayOffset: Int? = nil`. When it's set, only recipe items with that
  `dayOffset` are added.
- `GroceryMenuRecipeIDsRequest` gains the same optional `dayOffset`.

**App:**
- `GroceryIngredientSelectionContext` gains `tripListTitle: String`, which defaults to `title`. The split names its
  lists `"\(context.tripListTitle) — \(trip.title)"`.
- `Source` gains `.menuDay(CoreMenu.ID, dayOffset: Int)`. `addSelectedIngredients` calls `addMenu(…, dayOffset:)`
  for it, and `canSplitIntoTrips` includes it.
- `GroceryLibraryModel.selectMenuDayButtonTapped(menuID:dayOffset:)` loads the sheet the way
  `selectMenuButtonTapped` does, using that day's recipes. Set `title` to `"Day \(dayOffset + 1)"`, followed by
  `" · <date>"` when the menu has exactly one placement, formatted as `MenuDaySection`'s `dayTitle` formats it. Set
  `subtitle` to the menu title and `tripListTitle` to the menu title. If the day has no recipe dishes, do nothing,
  as `selectMealRowsButtonTapped` does.
- Wire the menu to it the way the Calendar is wired: an `onAddMenuDayToGroceries: (@MainActor (CoreMenu.ID, Int) ->
  Void)?` on `MenuLibraryModel`, set in `RecipeLibraryView.init`, so neither model holds the other.
- `MenuDaySection`'s header row: after **Add Recipe to Day N**, an icon-only button labeled **Add Day to Groceries**
  using `AppSymbol.addToGroceries`, with accessibility label "Add Day \(dayNumber) to Groceries". Show it only when
  the day has a recipe dish and the hook is set.

### 5. The Calendar's Add Day to Groceries opens the sheet (F2)

- `RecipeLibraryView.init` wires `onAddDayToGroceries` to `selectMealRowsButtonTapped(rows)`. Fix the comment there.
- Delete `addMealRowsImmediately`. `addMenuImmediately` already has no caller, so delete it too. Delete any tests that
  only covered them.

### 6. Help pages (ADR-0066 D5)

Architect copy, measured at 1,448 (Menus) and 1,383 (Groceries) characters against the 1,800 budget. **Check each
changed sentence against the app as built.** Fix a label that doesn't match and list each fix in the PR body. Don't
add bullets.

- **Menus › Prep plan**, second bullet: "On a menu longer than one day, steps are grouped by the day you do the work.
  The Prep Plan's **⋯ › Show Times** adds each step's approximate time."
- **Menus › Prep plan**, third bullet, first sentence: "**Prep** opens a checklist of steps due now, with their
  times."
- **Groceries › Adding ingredients**, first bullet: "**Add Ingredients** adds a calendar day or a menu to this list.
  You pick which lines to add first. **Add Day to Groceries**, on a menu day or a Calendar day, opens the same
  choices for one day."

## Tests

**Core**
- Headings: on one day's steps with times 17:00, 17:30, 17:30, 17:45 and sessions A, B, B, B, `showsTimes: true`
  gives headings on steps 1, 2 and 4 (step 4 has a new time with the same session) and puts `headingTime` on those
  three only. `showsTimes: false` gives headings on steps 1 and 2 only, which is today's output. A step with no time
  compares as `(nil, session)`: after a timed step it gets a session-only heading.
- `TodayPrepLayout.make(…, showsTimes: true)` in dated mode puts times on the Today section's headings.
- `addMenu(…, dayOffset: 1)` on a two-day menu adds only day 2's recipes. When the same recipe sits on both days,
  it's added once, from day 2's item.
- `GroceryMenuRecipeIDsRequest(menuID:dayOffset:)` returns only that day's recipes.
- Both help pages: the existing `plainText.count <= 1_800` tests still pass.

**App (`YesChefTests`)**
- A split add from a `.menuDay` source writes to "<menu title> — Advance" and "— Fresh". A second split add from
  another day of the same menu reuses those two lists.
- `selectMealRowsButtonTapped`, reached through `onAddDayToGroceries`, presents the sheet and writes nothing.

This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- Today's Prep and the cook session show one set of recipe buttons at a time.
- **Prep** shows the `flame.gauge.open` glyph.
- Today's Prep headings show times. The menu's Prep Plan shows them when **⋯ › Show Times** is on, and the setting
  stays on the device.
- A menu day's **Add Day to Groceries** opens the sheet for that day, and a split fills the menu's two lists. The
  Calendar's **Add Day to Groceries** opens the sheet.
- The help pages match the app. Label fixes, if any, are listed in the PR body (ADR-0066 D5).
- Tests above. Verification per [`verification.md`](../../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- **Jon's device gate (before Nov 19 for the grocery half):** on the iPad, open **Thanksgiving Week 2026**. Tap Day 5's
  **Add Day to Groceries**, turn on **Split into two trips**, and add. Then add Day 4 the same way, and confirm both
  land on "Thanksgiving Week 2026 — Advance" and "— Fresh". On the Calendar, **⋯ › Add Day to Groceries** opens the
  sheet. Open **Prep**: the button shows the new glyph, Thursday's dinner-hour headings show times, and swiping
  between recipes never shows two carts. In the menu's Prep Plan, turn on **⋯ › Show Times** and read Thursday.
