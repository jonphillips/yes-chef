# Effort: Calendar day-rail actions and recipe-editor columns

Status: **Planned — 2026-10-13.**
Summary: Give the Calendar day rail one clear primary action (Ask and Add move to the toolbar, Add also appears in the empty state), and fold the editor's short fields (timing/yield, library/cuisine/course) into adaptive columns on wide layouts.
Related: jon-platform `docs/ios/swiftui-forms.md` (stacked labels), `docs/ios/ui-and-platforms.md`; the thumbnail-clip fix (`fix/recipe-thumbnail-clip`) that preceded this.

## Why

Jon's 2026-10-13 iPad screenshots (Calendar month view with the day rail; empty Create Recipe):

- **Day-rail header** ([`MealCalendarDayHeader.swift`](../../../YesChefApp/MealCalendarDayHeader.swift)) has four controls and two filled
  buttons in a ~330pt rail. "Cook these" sits alone, centred: `.frame(maxWidth: .infinity)` widens a capsule
  button's frame, not the capsule. **Add appears twice**: the header's Add menu and the toolbar `+`
  ([`MealCalendarNavigationToolbar`](../../../YesChefApp/MealCalendarViews.swift)) both add to the selected day, and their labels differ
  ("Add Note" vs "Note"). Menu detail and Workbench put Cook/Ask in the toolbar; the Calendar is the odd one out.
- **Day rows** spend a line on the kind label "Recipe", which the thumbnail already conveys, and titles wrap to 6+ lines
  at Jon's Dynamic Type size.
- **Editor** ([`RecipeEditorFields`](../../../YesChefApp/RecipeEditorView.swift)) gives Servings, Yield, Prep, Cook, Library, Cuisine, and Course
  each a full-width row (~1500pt on a 13" iPad). Prep/Cook are 5-minute steppers (90 min = 18 taps) with inline labels.
  The Library/Cuisine/Course pickers use inline labels too. Both break the house stacked-label rule.

## Dispatch shape

**One dispatch, one PR, two slices.** Both are view-layer polish with no schema change, and Jon checks them in one
iPad device pass. Slice 2 doesn't depend on Slice 1.

## Invariants

- No persisted-model or draft-shape change. `prepTimeMinutes`/`cookTimeMinutes` stay `Int`, clamped to the current `0...600`.
- Every current day action stays reachable: Cook these, Ask (inspector on wide, sheet on compact), Add Recipe,
  Add Note, Add Day to Groceries, and the four hand-off/paste items.
- `RecipeEditorFields` remains the single field implementation shared by Create Recipe and the recipe editor sheet
  (ADR-0051 D1 / ADR-0053 D2). Save, dirty tracking, focus behaviour, and the ingredient fraction accessory are unchanged.
- Compact width (iPhone) keeps today's stacked editor rows. The calendar changes apply at every width.

## Slice 1 — Calendar day rail

1. **Toolbar = screen actions.** `MealCalendarNavigationToolbar` shows **Today · Ask · Add**. Ask (`sparkles`) calls
   the existing `chatButtonTapped` and appears only when chat is available, as it does today. Add keeps its
   Recipe/Note menu; standardize the item labels to **Recipe** and **Note** everywhere.
2. **Rail header = this day.** In `MealCalendarDayHeader`, remove `chatButton` and `addMenu`. The action row is
   **Cook these** (`.borderedProminent`, present only when the day has a cook session) followed by the existing
   `⋯` Day actions menu, left-aligned. Drop the full-width/centred treatment. Give the `⋯` a bordered, ≥44pt hit target
   so it reads as a button and not a stray glyph. Keep `ViewThatFits`: wide puts the actions trailing on the title's row;
   narrow stacks them, leading-aligned, under the title.
3. **Title block.** Replace the single `.largeTitle` "Tuesday, October 13" with a weekday eyebrow (secondary,
   `.subheadline.weight(.semibold)`) over the month/day in `.title.bold()`, then the item count. Derive both strings beside
   `selectedDateTitle` in `MealCalendarModel` using the same `.formatted(.dateTime…)` style. Leave `selectedDateTitle`
   as is: chat context and the complement action use it.
4. **Empty day.** The "No Meals Scheduled" `ContentUnavailableView` in `MealCalendarDayAgendaView` gains actions:
   **Add Recipe** (`.borderedProminent`) and **Add Note** (`.bordered`), both calling `model.addItemButtonTapped(kind:)`.
   This is Add's one in-context home, shown when there is nothing to cook.
5. **Rows.** In `MealPlanItemRowView`, drop the kind `Label` for `.recipe` rows (notes keep it). Cap the title at
   `lineLimit(3)`.

**Checkpoint:** At 11" and 13" iPad landscape, with large Dynamic Type, a filled day's rail shows one filled control
(Cook these) plus `⋯`, with no Ask or Add in the rail. An empty day shows Add Recipe in the empty state. Thumbnails
stay inside their 56pt box. On iPhone, Ask is in the toolbar and still opens the chat sheet.

## Slice 2 — Editor columns on wide layouts

1. **Adaptive row helper.** Add a small view in [`FormFields.swift`](../../../YesChefApp/FormFields.swift) that lays out N stacked
   fields in one Form row: all in one row when they fit, else a 2-column grid, else stacked. Use `ViewThatFits(in: .horizontal)`
   with an explicit `minWidth` per cell (~150pt). **Caveat:** `TextField`'s ideal width is tiny, so without that
   `minWidth` the widest option always "fits". Measuring the row with `onGeometryChange` is an acceptable alternative.
   Base it on the available width, not the size class, so the narrower editor sheet degrades by itself.
2. **Timing and Yield → one row:** Servings | Yield | Prep time | Cook time. Servings and Yield stay `StackedTextField`.
   Prep and Cook become `StackedFormField` wrapping a number `TextField(value:format: .number)` with a trailing "min"
   and a compact `Stepper` (labels hidden, step 5). Clamp to `0...600` in the binding. Number pad has no return key,
   so make sure focus can still be dismissed (existing keyboard toolbar or tap-out). Don't trap the field.
3. **Organization → one row:** Library | Cuisine | Course, each a `StackedFormField` with a `.menu` picker
   (`.labelsHidden()`). `RecipeFacetSingleSelectPicker` keeps its binding and disabled-when-empty behaviour.
   Categories stays its own full-width row.
4. **Photo row:** In `RecipeHeroPhotoPickerRow`, change the button `HStack` alignment from `.firstTextBaseline` to
   `.center` (`PasteButton` has no matching baseline, which is why it sits low). Give `PasteButton`
   `.buttonBorderShape(.capsule)` so it matches the bordered Add Photo capsule. Its disabled look when the clipboard
   has no image is system behaviour and stays.

**Checkpoint:** On a 13" iPad, Create Recipe's Timing and Yield is one row and Organization is two (pickers, then Categories).
In the recipe editor sheet, the same sections fall back to 2×2 or stacked without clipping. On iPhone the rows stay stacked.
Every field keeps a visible stacked label and a VoiceOver label. Typing "90" into Prep saves 90.

## Done when

Both checkpoints hold. `scripts/check-drift.sh` and the generic iOS build pass. `YesChefTests` runs too, because Slice 1
adds `MealCalendarModel` properties (`docs/verification.md`). The PR adds a DONE-LOG entry and records Jon's iPad + iPhone
device pass as owed in `docs/device-passes.md`.

## Out of scope

- Ingredients and Instructions side by side on iPad (cookbook-page editor). It needs a custom layout instead of `Form`.
  Tracked as a candidate in `docs/open-questions.md`.
- Per-meal-slot add (a `+` on the "Dinner" header). `addItemButtonTapped` takes no slot today.
