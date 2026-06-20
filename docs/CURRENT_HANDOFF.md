# Current Handoff

Last updated: June 19, 2026.

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Current Checkpoint

The current slice scaffolds menus and connects them to the meal calendar.

Implemented behavior:

- A durable `mealPlanItems` SQLite table and `MealPlanItem` core model.
- Meal plan items support recipes and freeform notes now, with a reserved
  `reservation` kind and optional start/end time fields for later restaurant or
  iCal-style work.
- A month-first Meal Calendar workspace in the existing app shell, with month,
  week, and day display modes.
- On regular-width iPad, Meal Calendar uses a two-column sidebar + workspace
  layout instead of the app's recipe-style content/detail split.
- Month/week planning views own the main workspace, with the selected-day agenda
  in a right rail on wide layouts and below the calendar on compact/narrow
  layouts.
- A selected-day agenda grouped by meal slot: breakfast, lunch, dinner, snack.
- Add recipe and add note flows from the calendar.
- A `Plan` toolbar button on recipe detail that starts a preselected recipe plan
  item for the calendar's selected date.
- Edit/reschedule support for existing meal plan recipe and note items.
- Delete support for meal plan items.
- Core request/repository tests covering add, validation, fetch, sort order, and
  update/delete behavior.
- A durable menu schema with `menus`, `menuItems`, and `menuPlacements`.
- Menu items support recipe dishes and freeform note dishes, each assigned to a
  menu day offset and meal slot.
- A menu can be placed on the calendar with a start date. Multi-day menus project
  each menu item onto the correct calendar day automatically.
- Calendar rows projected from a menu preserve provenance through menu placement
  data and show as menu-derived instead of editable standalone meal plan items.
- Menu-derived calendar rows can open the source menu from the selected-day
  agenda.
- A minimal Menus section in the app shell for creating menus, adding dishes, and
  placing a menu on the calendar.
- Menu placements can be shifted to a new start date or removed from the
  calendar without deleting the menu.
- Core menu tests covering menu creation, item validation, placement, and calendar
  projection behavior, including placement update/delete behavior.

Deferred from this slice:

- Drag/drop or direct manipulation inside the calendar grid.
- Restaurant reservation-specific UI.
- iCal import/export/sync.
- Shopping list, prep strategy, and menu generation integrations.
- Rich menu editing: reordering dishes, editing existing menu dishes, and
  duplicating menus.
- Importing Paprika menus from backup/export data, if that data is recoverable.

## Verification Pattern

Before checkpointing UI work:

- Run `xcodegen generate` after adding Swift source files.
- Build `YesChef` for `iPad Air 13-inch (M4)`.
- Run `scripts/check-drift.sh`.
- Install and launch on both active iOS 27 simulators:
  - `iPad Air 13-inch (M4)`
  - `iPhone 17 Pro`

Jon performs the primary UI testing pass.

## Recommended Next Larger Task

Scaffold grocery/shopping lists while the menu/calendar source relationships are
fresh.

Suggested next scope:

- Jon should do the primary UI pass on iPad and iPhone.
- Create a multi-day menu, place it on the calendar, shift the placement, remove
  the placement, and confirm the calendar/source relationship remains legible.
- Use Paprika's grocery docs as inspiration, but preserve Yes Chef's source model:
  grocery rows should know whether they came from a recipe, a menu placement, a
  calendar item, or a custom item.
- Scaffold grocery lists, grocery items, and a minimal Groceries section before
  implementing consolidation, pantry interactions, or Reminders/Siri integration.
- Revisit drag/drop from recipe rows into either the calendar or a menu after the
  grocery source model is standing.

Reasoning:

- The high-risk model question is now represented in code: menu placement projects
  rows into the calendar without erasing their source relationship, and placement
  changes update the projection instead of copying anonymous calendar rows.
- Groceries are the next source-of-truth pressure test because recipe/menu/calendar
  inputs, ingredient scaling, consolidation, purchased state, and custom items all
  need to coexist.
- The calendar can later give `lastCookedAt` a principled source of truth: a
  recipe scheduled on a past date can drive or supplement that field instead of
  relying only on a manual "mark cooked" flow.
