# Current Handoff

Last updated: June 26, 2026.

Use this as the short entry point when starting a fresh Yes Chef conversation.
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Current Checkpoint

The current slice scaffolds meal planning, menus, and grocery lists with
source-preserving generated grocery items and a review step before adding
generated ingredients.

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
- Recipe detail groups the `Plan` and `Groceries` actions in the toolbar, and the
  groceries action opens a shoppable-ingredient review sheet before adding
  selected lines to the selected/default grocery list.
- Recipe detail shows the `Start Cooking` flame action in the recipe body near
  servings/time instead of in the toolbar.
- Generated grocery ingredients consolidate conservatively when title, unit,
  aisle, notes, and quantity shape are compatible. Compatible numeric quantities
  are added together, while each contributing origin remains represented as its
  own `GroceryItemSource` row.
- Purchased items and prep/comment-sensitive rows stay separate when generating
  groceries.
- Grocery rows expose their source breakdown in the list. Each source now has an
  actions menu that can remove only that source; the repository deletes the
  grocery row when its last source is removed and recalculates generated numeric
  quantities when a consolidated recipe/menu/calendar contribution is removed.
- Recipe detail `Shop`, grocery add-from-calendar-day, and grocery add-menu flows
  now open an ingredient-selection sheet before generating grocery rows. All
  shoppable lines start selected, and the repository can restrict generation to
  selected `IngredientLine` IDs while preserving source provenance and
  consolidation behavior.
- The ingredient-selection sheet now applies conservative pantry assumptions:
  likely staples such as salt, pepper, water, ice, common cooking oils, and
  cooking spray remain visible in a "Skipped Pantry Staples" review section but
  start deselected and can be added back with a tap.
- Settings exposes an editable Pantry list backed by app storage; one item per
  line controls which pantry staples are skipped by default in grocery selection.
- The meal-calendar recipe picker supports adding multiple recipes in one save.
- Ingredient parsing avoids treating food words like red/celery/anchovy as units,
  splits comma preparations into notes, and normalizes anchovy fillets into the
  shoppable title "anchovies".
- Core tests cover meal calendar, menus, grocery source provenance, and generated
  grocery consolidation/source-removal/ingredient-selection/pantry-assumption/
  ingredient-parsing behavior.

Deferred from this slice:

- Drag/drop or direct manipulation inside the calendar grid.
- Restaurant reservation-specific UI.
- iCal import/export/sync.
- Rich menu editing: reordering dishes, editing existing menu dishes, and
  duplicating menus.
- Higher-level source-aware grocery removal flows, such as removing a recipe's
  full contribution from a grocery list without deleting unrelated sources.
- Quantity-based pantry inventory.
- Reminders/Siri integration, store/category learning, and shopping workflow
  polish.
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

Polish grocery generation and shopping workflow around the newly visible source
model.

Suggested next scope:

- Jon should do the primary UI pass on iPad and iPhone.
- Create a multi-day menu, place it on the calendar, shift the placement, remove
  the placement, and confirm the calendar/source relationship remains legible.
- Polish the grocery source breakdown if Jon's UI pass finds the per-source
  actions too subtle or too noisy.
- Broaden source-aware removal from the current per-source action into higher-level
  "remove this recipe/menu/calendar contribution" flows where useful.
- Continue pantry polish if Jon's UI pass finds the conservative staple list too
  narrow or too aggressive. Do not build quantity-based pantry inventory as part
  of this slice.
- Treat Grocy as inspiration for shopping locations/assortments and product/barcode
  workflows, but keep Yes Chef recipe/planning-first rather than inventory-first.
- Revisit drag/drop from recipe rows into either the calendar, a menu, or
  groceries after the source model is visible to users.

Reasoning:

- The storage model can now represent multiple origins for one grocery row, and
  the UI has a first review step before generation. The next pressure point is
  making source-aware removal and skipped pantry staples equally legible.
- Paprika's grocery flow allows recipe ingredients to be chosen before adding and
  recipes to be removed from the grocery list later; Yes Chef now has the
  ingredient-selection affordance and still needs the broader removal/review
  affordances while keeping richer provenance intact.
- Source-aware removal is the next pressure test for consolidation because a
  single row may contain quantities from several recipes, menu placements, and
  calendar items.
- Pantry value comes first from making skipped known staples reviewable and easy
  to add back, not from tracking exact on-hand quantities.
