# Effort — Move Grocery Items

Status: Ready
Summary: **List Actions › Select Items** puts a grocery list into Select mode. A square checkbox replaces each row's purchase circle, and **Move to** sends the selected lines to another list, merging each with a same-ingredient line already there. No schema change.

Origin: Jon, 2026-11-19, while working the Thanksgiving Advance and Fresh lists.
One slice, one PR.

Jon's decisions (2026-11-19, don't re-litigate):

- **Collisions merge.** A moved unpurchased line folds into an unpurchased line on the destination when the two could
  merge. It's the same test and the same merge that Consolidate List uses
  ([grocery-consolidate-list](grocery-consolidate-list.md), ADR-0069 Amd 1). Lines that can't merge move
  as they are.
- **The marker replaces the circle.** In Select mode a square checkbox sits where the purchase circle was, and a
  tap anywhere on the row selects it. Select mode never checks items off.
- **A move is only a move.** It never writes `groceryTripAssignments`, even between a "— Advance" and a "— Fresh"
  list. A trip switch that sticks still comes only from the trip tag on the Add sheet (ADR-0068 D3).

## Where things are (architect, 2026-11-19, `origin/main` dc35107)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `GroceryRepository+Editing.swift`: `canConsolidate(_:_:fixes:)` (line 22) is the merge test. The private
  `merge(_:into:in:now:)` (line 125) adds the amounts, merges the notes, moves the sources and deletes the merged-away
  row. `consolidate(listID:in:now:)` (line 155) shows the survivor loop to copy.
- `Models.swift`: `GroceryItem` (`groceryListID`, `isPurchased`, `sortOrder`).
- `AppHelp.swift`: `AppHelpPage.groceries`. Its plain text is 1,799 characters, and `GroceryTripTests` caps it at 1,800.

**App (`YesChefApp/`)**
- `GroceryViews.swift`: `GroceryDetailView` (the list, its toolbar and `GroceryRapidAddField`),
  `GroceryListActionsMenu`, `GroceryItemsSection` (swipe actions) and `GroceryItemRowView` (the purchase circle,
  the context menu).
- `GroceryPantryReviewViews.swift`: `GroceryPantryReviewSection` uses `GroceryItemRowView`.
  `GroceryAssumedPantrySection` has its own `AssumedPantryRowView`.
- `GroceryModels.swift`: `GroceryLibraryModel` (`selectedListID`, `listRows`, `pantryAddBackItemIDsByListID`).
  `GroceryNameFixModel.swift` has `consolidateListButtonTapped`, the shape for one write from a menu action.

## Build

1. **Core: `GroceryRepository.moveItems(_ itemIDs:toListID:in:now:) throws -> Int`.**
   - Fail with the existing error if the destination list doesn't exist. Skip IDs that are missing or already on
     the destination.
   - Process the moved items in `sortOrder`, then by id. The survivors start as the destination's unpurchased items
     in the same order.
   - An unpurchased item merges into the first survivor it `canConsolidate` with, using the existing `merge`. The
     destination row survives and keeps its id, title and area.
   - Any other item (purchased, or nothing to merge with) keeps its id, sources, area and purchased state. Its
     `groceryListID` becomes the destination, its `sortOrder` is the destination's highest plus one, and
     `dateModified = now`. An unpurchased item moved this way joins the survivors, so two butter lines moved
     together become one.
   - Return how many lines were merged away. Write nothing else. Never touch `groceryTripAssignments`.
   - Make `merge` reachable from the new function (same file or `internal`); don't copy it.
2. **Model (`GroceryLibraryModel`).**
   - State: `isSelectingItems: Bool` and `selectedItemIDs: Set<GroceryItem.ID>`.
   - `selectItemsButtonTapped()` enters Select mode with nothing selected. `doneSelectingButtonTapped()` leaves it and
     clears the selection. Changing `selectedListID` also leaves it.
   - `toggleItemSelection(itemID:)`. `selectAllButtonTapped()` selects every row on the screen, purchased and
     assumed-in-pantry rows included. Once all are selected, it deselects them all.
   - `moveSelectedItemsButtonTapped(toListID:)` runs step 1 in one `database.write`, then leaves Select mode. It
     drops moved IDs from `pantryAddBackItemIDsByListID`. Report errors the way the other grocery writes do.
3. **View.**
   - **List Actions** gets **Select Items** (symbol `checkmark.square`) as its first item, above **Share List**.
   - In Select mode the navigation title is "N Selected", or the list title when N is 0. The toolbar is replaced by:
     **Move to** (a menu of the other lists in `listRows` order, disabled when nothing is selected or there's
     only one list), **Select All** or **Deselect All**, and **Done**. On iPhone, the list picker section hides.
   - `GroceryItemRowView` gets `isSelecting` and `isSelected`. In Select mode the leading image is `square` or
     `checkmark.square.fill` (tinted with the accent color) in the circle's 32-point frame. The whole row is the tap
     target and toggles selection. The context menu is off. The accessibility label is "Select" or "Deselect".
   - In Select mode, `GroceryItemsSection` and `GroceryPantryReviewSection` drop their swipe actions, and
     `GroceryRapidAddField` hides. `AssumedPantryRowView` swaps its archivebox for the same square, and in Select
     mode its row toggles selection instead of **Add Back**.
4. **Help.** In **Merging**, replace the bullet `**List Actions › Consolidate List** merges this list again, such as
   after a new fix.` with:
   `**List Actions › Consolidate List** merges this list again, such as after a new fix. **Select Items** moves lines to another list and merges them there.`
   Raise the cap in `GroceryTripTests` from 1,800 to 1,900. The text grows past 1,800 and nothing else should be cut.

## Tests

`YesChefCoreTests` (`GroceryConsolidationTests.swift` or a new `GroceryMoveTests.swift`):
- A plain move keeps the line's id, sources, area and purchased state, changes `groceryListID`, and puts the line
  after the destination's highest `sortOrder`. The source list keeps its other lines.
- Butter at 2 Tbsp on Advance, moved to Fresh where butter is 6 Tbsp, becomes one 8-Tbsp line. The Fresh row
  survives with its id, both sources point at it, and the Advance row is gone.
- Two butter lines moved together onto a list with no butter become one line.
- A purchased line, or one whose units can't be added, moves without merging, and a purchased destination line never
  takes a merge.
- `groceryTripAssignments` is unchanged after a move between "X — Advance" and "X — Fresh".
- Moving to the list the lines are already on changes nothing (no `dateModified` churn). A missing destination
  throws.

`YesChefAppTests` (`GroceryLibraryModel`, next to `GroceryTripModelTests.swift`): select two items, move them, and
check that Select mode ended, the selection is empty and the lines are on the destination. Changing the selected list
leaves Select mode.

## Verify

`scripts/check-drift.sh`, the generic iOS device build, and the `YesChefTests` app target on a simulator
(`docs/verification.md`). The model changes, so the app tests are required.

## Not in this slice

- **New List…** in the Move to menu. Make the list first.
- Drag and drop between lists.
