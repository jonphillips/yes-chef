# Current Handoff

Last updated: June 19, 2026.

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Current Checkpoint

The current slice scaffolds meal planning, menus, and grocery lists with
source-preserving generated grocery items.

Implemented behavior:

- A durable `mealPlanItems` SQLite table and `MealPlanItem` core model.
- Meal plan items support recipes and freeform notes now, with a reserved
  `reservation` kind and optional start/end time fields for later restaurant or
  iCal-style work.
- A month-first Meal Calendar workspace in the existing app shell, with month,
  week, and day display modes.
- Add recipe/add note flows from the calendar, plus a `Plan` toolbar button on
  recipe detail that starts a preselected recipe plan item.
- A durable menu schema with `menus`, `menuItems`, and `menuPlacements`.
- Menus can contain recipe dishes and freeform notes, be placed on the calendar,
  shifted to a new start date, and removed from the calendar without deleting the
  menu.
- Calendar rows projected from a menu preserve provenance through menu placement
  data and show as menu-derived instead of editable standalone meal plan items.
- A minimal Menus section in the app shell for creating menus, adding dishes, and
  placing a menu on the calendar.
- A durable grocery schema with `groceryLists`, `groceryItems`, and
  `groceryItemSources`.
- Grocery sources preserve recipe, menu, menu placement, calendar item, and
  custom origins, including source titles/subtitles and original ingredient text.
- A minimal Groceries section in the app shell supports list creation, custom
  items, purchased state, add-from-calendar-range, add-menu, and add-recipe
  flows.
- Recipe detail has a `Shop` toolbar button that adds the recipe's shoppable
  ingredients to the selected/default grocery list.
- Generated grocery ingredients consolidate conservatively when title, unit,
  aisle, notes, and quantity shape are compatible. Compatible numeric quantities
  are added together, while each contributing origin remains represented as its
  own `GroceryItemSource` row.
- Purchased items and prep/comment-sensitive rows stay separate when generating
  groceries.
- Core tests cover meal calendar, menus, grocery source provenance, and generated
  grocery consolidation behavior.

Deferred from this slice:

- Drag/drop or direct manipulation inside the calendar grid.
- Restaurant reservation-specific UI.
- iCal import/export/sync.
- Rich menu editing: reordering dishes, editing existing menu dishes, and
  duplicating menus.
- Ingredient selection before adding a recipe/menu/calendar range to groceries.
- Source-aware grocery removal, such as removing a recipe's contribution from a
  consolidated grocery row without deleting unrelated sources.
- Pantry interactions, Reminders/Siri integration, store/category learning, and
  shopping workflow polish.
- Importing Paprika menus or grocery lists from backup/export data, if that data
  is recoverable.

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

Make grocery generation source-aware in the UI, especially before and after
consolidation.

Suggested next scope:

- Jon should do the primary UI pass on iPad and iPhone.
- Create a multi-day menu, place it on the calendar, shift the placement, remove
  the placement, and confirm the calendar/source relationship remains legible.
- Add an ingredient selection step before adding a recipe, menu, menu placement,
  or calendar range to groceries.
- Show a compact source breakdown for grocery rows so consolidated items make
  their recipe/menu/calendar/custom origins visible.
- Implement source-aware removal so deleting "this recipe from the grocery list"
  removes only matching source rows and recalculates/deletes the grocery row as
  appropriate.
- Revisit drag/drop from recipe rows into either the calendar, a menu, or
  groceries after the source model is visible to users.

Reasoning:

- The storage model can now represent multiple origins for one grocery row, but
  the UI still treats generation as a blind add operation.
- Paprika's grocery flow allows recipe ingredients to be chosen before adding and
  recipes to be removed from the grocery list later; Yes Chef needs the same
  user-facing affordance while keeping richer provenance intact.
- Source-aware removal is the next pressure test for consolidation because a
  single row may contain quantities from several recipes, menu placements, and
  calendar items.
