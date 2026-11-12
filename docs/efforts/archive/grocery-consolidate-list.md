# Effort — Consolidate List

Status: Ready
Summary: Grocery items merge on the fixed key and units alone (notes and store area no longer block). **List Actions › Consolidate List** re-runs that merge on the current list. Items sort by name within each store area. No schema change.

Origin: Jon, 2026-11-12, on the Thanksgiving Advance list, with three **unsalted butter** lines that wouldn't merge.
One slice, one PR.

Decisions: [ADR-0069 Amendment 1](../../decisions/ADR-0069-ingredient-name-fixes.md#amendment-1--notes-and-store-areas-dont-block-a-merge-consolidate-list-2026-11-12)
(A1–A5). Read it first, then ADR-0069 D2 (base vs fixed keys) and D5 (Same As).

## Where things are (architect, 2026-11-12, `origin/main` 61147b0)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `GroceryCore.swift`:
  - `GroceryItem.canConsolidate(with:fixes:)` (around line 988): the merge test. It compares the fixed key, `aisle`,
    `notes` and `canMergeMeasure`.
  - `existingItemCompatibleWithGeneratedDraft` (around line 545) and its caller (around line 479): generation folds a
    draft into the first compatible unchecked item, adds the amounts and inserts the source.
  - `areGroceryItemRowsInIncreasingOrder` (around line 933): row order. Today it's list, unchecked first, `sortOrder`,
    then title.
- `GroceryRepository+Editing.swift`: `sameAs(itemID:targetItemID:in:now:)` and `sameAsMeasuresCanMerge`. Its
  `compatible` check repeats the aisle and notes tests, and its merge half (add amounts, move sources, delete the item)
  is what Consolidate List needs.
- `GroceryGeneratedItemDraft.swift`: `IngredientLine.groceryNotes` (preparation + comment), the notes a recipe line
  gives an item.
- `Models.swift`: `GroceryItem` and `GroceryItemSource` (`ingredientLineID`, `ingredientText`).
- `AppHelp.swift`: `AppHelpPage.groceries`.

**App (`YesChefApp/`)**
- `GroceryViews.swift`: the **List Actions** menu (around line 255) with **How Groceries Work** and **Name Fixes**.
- `GroceryModels.swift`: `GroceryLibraryModel` and the Same As route; `GroceryNameFixModel.swift` holds `nameFixesButtonTapped()`.

## Build

1. **One merge test (A1).** Replace the aisle and notes conditions with nothing: two unchecked items, or an item and a
   draft, merge when their fixed keys match and their measures merge (or both have no amount and no quantity text).
   Put this in one Core function that generation, `sameAs` and Consolidate List all call, so the three can't drift.
   `sameAs` loses its own `compatible` copy. It still saves the fix first, and when the two items can't merge, it
   still renames the item as now.
2. **One merge action (A2).** One Core function folds an item into a survivor: add the amounts, set the survivor's
   notes per A2, move the sources, delete the merged-away item. The survivor keeps its id, title and aisle.
   - Notes: an item's notes are **recipe notes** when they equal (by `CanonicalIngredient.canonicalText`) the
     `groceryNotes` of one of its sources' ingredient lines; otherwise they're **typed**. A source whose line is gone
     doesn't count as a match, so those notes are treated as typed and kept.
   - The survivor's notes become its typed notes plus the other item's typed notes (distinct, joined with "; "),
     followed by the recipe notes only if every merged part's recipe notes are equal. Nil when nothing is left.
   - Generation uses the same rule when a draft folds into an existing item: the draft's notes are recipe notes.
3. **Consolidate List (A3).** `GroceryRepository.consolidate(listID:in:now:)` in Core. Take the list's unchecked items
   in `sortOrder`, then id. For each, merge it into the first earlier survivor it can merge with (step 1), or keep it
   as a survivor. Write only rows that change. Return the number of items merged away.
4. **App.** **Consolidate List** in **List Actions**, after **Name Fixes**, symbol `arrow.triangle.merge`. The model
   runs it on the selected list in one write. No dialog. If nothing merged, nothing changes.
5. **Sort (A4).** `areGroceryItemRowsInIncreasingOrder`: list, unchecked first, then title by
   `localizedStandardCompare`, then `sortOrder`, then id.
6. **Help (A5).** Use this text exactly, and keep the cap test green (it comes to 1,799 characters):
   - Adding ingredients, bullet 1: `**Add Ingredients** adds a calendar day or a menu to this list. You pick which
     lines to add first. **Add Day to Groceries** on a menu or Calendar day does the same for one day.`
   - Adding ingredients, bullet 3: end with `The app remembers your switch.`
   - Merging, replacing its first two bullets with three:
     - `The same ingredient from different recipes becomes one item with the amounts added up, when the units can be
       added. Notes and areas don't keep items apart.`
     - `Use **Same As…** when two names mean one ingredient; fixes are in **List Actions › Name Fixes**.`
     - `**List Actions › Consolidate List** merges this list again, such as after a new fix.`
   - The long-press bullet stays as it is.

## Tests

`YesChefCoreTests`:
- **Generation:** two recipes' `unsalted butter` lines with different notes and different areas become one item with
  the amounts added. The survivor keeps its own area and has no recipe notes. The same notes on both are kept.
- **Same As:** two items with different notes and areas now merge, and the sources move.
- **Consolidate List:**
  - the Thanksgiving case: three butter items (2, 6 and 6 tablespoons, three different notes) become one 14-tablespoon
    item. The survivor is the earliest item and keeps its id, all three sources point at it, and the other two rows
    are gone;
  - a name fix added after the items were created makes Consolidate List merge them;
  - checked items, units that can't be added, and items on another list are left alone;
  - typed notes survive a merge; a source whose ingredient line is deleted counts as typed;
  - a second run changes nothing (no `dateModified` churn).
- **Sort:** within one area, unchecked rows come out by title regardless of insertion order.
- The help page stays under the cap and names `Consolidate List`.

## Verify

`scripts/check-drift.sh`, the generic iOS build, and `YesChefTests` on a simulator, because `GroceryLibraryModel`
changes (AGENTS.md #9). No simulator installs.

## Done when

- Tests above pass; check-drift, the generic build and `YesChefTests` are green.
- Closeout per ADR-0005 D16 (DONE-LOG, archive this brief, advance NEXT_UP per D12).
- Gate line appended to `device-passes.md`: on the iPad's Thanksgiving Advance list, tap **List Actions ›
  Consolidate List** and confirm the three unsalted butters become one 14-tablespoon item showing all three recipes on
  long-press. Then add one more recipe with butter and confirm it merges straight in.
