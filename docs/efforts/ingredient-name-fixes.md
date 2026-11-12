# Effort — Ingredient name fixes

Status: Ready
Summary: A synced `ingredientNameFixes` table maps one ingredient key to another (`flat leaf parsley → parsley`). Every key comparison applies it after the built-in rules. You add a fix with **Same As…** on a grocery item and manage fixes from **Groceries › ⋯ › Name Fixes**. Built-in aliases stop being added by hand (ADR-0070 promotes your fixes into them). Needs a Production schema deploy.

Origin: Jon, 2026-11-12, graduating the Tandoor harvest after #499 added parsley spellings in code. One dispatch, one
PR. **Persistent model change, authorized by ADR-0069 D1.**

Decisions: [ADR-0069](../decisions/ADR-0069-ingredient-name-fixes.md) (D1–D9). Read it first. Patterns to copy:
`GroceryTripAssignment` (ADR-0068 D3: fixed-UUID row, no `source`) and the ADR-0052 area resolver (load the table once
per pass).

## Where things are (architect, 2026-11-12, `origin/main` fabff44)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `CanonicalIngredient.swift`: `canonicalName`, `comparisonKey`, `displayName`, `compoundParts`, and the built-in
  `aliases` dictionary (D7: add a comment saying entries come from promotion, not by hand, pointing at ADR-0069 and
  ADR-0070).
- `GroceryTrip.swift`: `GroceryTripAssignment`, the table to copy. `DeterministicID.swift`: add
  `ingredientNameFix(fromName:)` next to `groceryTrip(canonicalName:)`.
- `Schema.swift`: append the migration after "Add prep plan completion" (around line 1386). `CloudSync.swift`: add
  the type to **both** table lists (around lines 76 and 363, next to `GroceryTripAssignment`) and bump
  `declaredSchemaVersion` by one.
- Callers of `canonicalName` today, all of which the D6 rename breaks: `GroceryCore.swift` (consolidation,
  `addCustomItem`, pantry staple ids, `GroceryGeneratedItemDraft`, `canConsolidate`), `GroceryLogicalUniqueness.swift`
  (`canonicalPantryItem`), `GroceryPantryAssumptions.swift`, `PantrySuppression.swift`, `GroceryStoreArea.swift`
  (`seed(for:)`, the area resolver, `backfill`), `GroceryTrip.swift`, `GroceryRepository+Editing.swift`,
  `GroceryCategorization.swift`, `WorkbenchCompareCore.swift`, `GroceryCanonicalNameCache.swift`,
  `IngredientParser.swift`, `RecipeCore.swift`, `RecipeExtractionIssue.swift`, `IngredientRangeBackfill.swift`,
  `WebRecipeCapture/ParsedRecipePage.swift`.
- `AppHelp.swift`: `AppHelpPage.groceries`, the **Merging** section (D9).

**App (`YesChefApp/`)**
- `GroceryViews.swift`: the item context menu (around line 392) gets **Same As…**; the **List Actions** menu (around
  line 258, next to **How Groceries Work**) gets **Name Fixes**.

## Build

1. **Table (D1).** `IngredientNameFix` with `id`, `fromName`, `toName`, `dateModified`; data-free migration; sync
   registration; schema version bump.
2. **Fixes value (D2–D4).** A `Sendable` value type loaded from the table once per operation, with
   `canonicalName(_ text:)` (base key, then the fix), `comparisonKey(_:)`, `displayName(_:)`, and a static empty
   value for tests and callers with no database. The lookup follows chains with a cycle guard (D4).
3. **Rename (D6).** `CanonicalIngredient.canonicalName(_:)` → `baseName(_:)`. At each broken site: storing a key
   (the parser, the cached columns, `GroceryCanonicalNameCache`) uses `baseName`; comparing keys uses the loaded
   fixes. Area and trip tables are keyed and looked up by the **fixed** key. `compoundParts` keeps working on fixed
   keys.
4. **Writes (D3, D4).** A repository with `save(from:to:)` and `delete(fromName:)`. Save runs both sides through
   `baseName`, refuses when they're equal, resolves `to` through existing fixes, deletes a reverse row, re-points rows
   whose `toName` is the new `from`, and upserts by the fixed id.
5. **Same As… (D5).** On a grocery item: pick another item on the same list. Save the fix (this item's base key →
   that item's fixed key), then apply the generation rule to the two items: merge them and move the sources when
   `canConsolidate` would; otherwise give the moved item the target's title and aisle. Other lists don't change.
6. **Name Fixes sheet (D5).** From **List Actions**: every fix as "from → to", sorted by `fromName`; add and edit
   with two text fields that show the base key each side will save as; swipe to delete. Empty state says to use
   **Same As…** on a grocery item.
7. **Help (D9).** One bullet under **Merging**.
8. **Guard (D7).** Add to `docs/standing-guards.md`: built-in aliases aren't added by hand; a new spelling miss
   is a name fix, promoted per ADR-0070.

## Tests (`YesChefCoreTests`)

- With `flat leaf parsley → parsley` saved, adding two recipes with "flat-leaf parsley" and "parsley" yields one
  grocery item; deleting the fix and adding again yields two.
- The fix applies at each compare site: consolidation, area lookup (a `.user` area row on `parsley` places the "from"
  spelling), trip lookup, pantry suppression, the add sheet's pantry skip, and the Compare matrix key.
- Saving and deleting a fix writes only `ingredientNameFixes` rows; no `IngredientLine` or `GroceryItem` row changes.
- Write rules: case and hyphen fold on save; equal sides are refused; `A → B` then `B → C` gives `A → C, B → C`; a
  reverse save deletes the older row; a synced chain `A → B, B → C` resolves `A` to `C`; a cycle terminates.
- Same As…: mergeable items become one with sources moved; non-mergeable ones keep two lines with the target's
  title and aisle; another list holding the same ingredients is unchanged.
- Recipe text and `originalSnapshot` are untouched by any fix.

## Verify

`scripts/check-drift.sh`; the generic iOS build (AGENTS.md #9); `YesChefTests` on a simulator, because this touches
App model code. No simulator installs.

## Done when

- Tests above pass; check-drift and the generic build are green.
- Closeout per ADR-0005 D16 (DONE-LOG, archive this brief, advance NEXT_UP per D12).
- Gate line appended to `device-passes.md`: deploy the Production schema (one new table), then on the iPad, put
  "flat-leaf parsley" and "parsley" on a list from two recipes, **Same As…** one onto the other, see one item, rebuild
  the list and see one item with no new fix, see the fix in **Name Fixes** on the iPhone after sync, delete it there,
  and rebuild to see two items again.
