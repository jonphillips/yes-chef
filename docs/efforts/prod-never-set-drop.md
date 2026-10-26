# Effort — Drop the never-set columns and retired tables before the Production deploy (PROD-CUTOVER Step 1)

Status: Designed 2026-10-26. Jon approved every drop in chat on 2026-10-26. **Schema change, synced tables.** The
architect escalates the PR to Jon. Dispatch it after chat-access-mcp S2. Under the cutover sequencing note, this
is the one synced-schema change allowed before the cut.
Summary: One appended migration drops 7 synced columns that no code path ever sets, the two equipment tables that
nothing ever fills, and the dormant `tags`/`recipeTags` tables (ADR-0049 Amd 5). It also removes their model
fields and readers, retires the two tag record types through Slice 6's purge, and deletes the every-launch tag
fold. Production then never carries them, and Development's leftovers go in the cutover's Step 5 console step.
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Step 1 and Reference A (the diff and verdict table) ·
[ADR-0049 Amendment 5](../decisions/ADR-0049-unified-labels-and-assisted-tagging.md#amendment-5--retire-tags-and-recipetags-physically-before-the-production-cut-2026-10-26) ·
[`prod-dead-column-drop.md`](prod-dead-column-drop.md) (the same shape, Phase 1) ·
[`sync-failure-surfacing.md`](sync-failure-surfacing.md) § Slice 6 (`retiredRecordTypes`)

## What drops, and why it loses nothing

Under the Persistent Model Change Rule:

| Drop | Data on devices | Why nothing is lost |
|---|---|---|
| `recipes.activeTimeMinutes`, `recipes.restTimeMinutes` | all NULL | No editor, capture or import sets them; Adjust only copies them. |
| `ingredientLines.shoppingCategory` | all NULL | The parser never sets it; it is only copied (ADR-0035 says the same). Grocery reads it as an aisle fallback that is always nil. |
| `recipeNotes.cookingSessionID` | all NULL | Only ever written as nil. |
| `categories.color` | all NULL | Its only writers copy `tags.color`, which nothing sets. No UI sets or shows it. Re-add it additively if a color UI is built. |
| `mealPlanItems.startTime`, `mealPlanItems.endTime` | all NULL | No writer anywhere. |
| tables `equipment`, `recipeEquipment` | 0 rows | No importer fills a bundle's equipment; Adjust and import only copy what is there. |
| tables `tags`, `recipeTags` (and `tags.color`) | 10 and 13 rows, already folded | Every tag has a category, and every link has an equivalent `recipeCategories` link (ADR-0049 Amd 5). |

Checked against both devices' backups (iPhone 2026-10-26, iPad 2026-10-13). **The simpler alternative, leaving
them in place, is worse.** Each one would become a permanent dead field or record type in Production. The
dormant fold also keeps re-creating deleted loose labels.

## The migration

Append one migration to `Schema.swift`, e.g. `"Drop never-set columns and retired tag and equipment tables"`:

- `ALTER TABLE … DROP COLUMN` for each of the 7 columns. Guard each on `pragma_table_info` for the
  restore-candidate path, as `"Drop legacy recipe cooking columns"` does. None of them is indexed or part of a
  foreign key, so the drops aren't blocked.
- `DROP TABLE IF EXISTS` for `recipeTags`, `tags`, `recipeEquipment` and `equipment`, children first. The precedent
  is the seed-table drop in `"Promote category namespaces to facets"`. SQLiteData's sync triggers are TEMP
  triggers installed after the migrator runs, so neither the column drops nor the implicit row deletes reach
  sync.
- `declaredSchemaVersion` goes from 53 to 54. The existing "declared == registered count" test covers it.
  Backups stamped 53 still restore, because the new migration runs on the candidate.
- No other migration body changes, since the rule is append-only.

## The code

- **Models.** Remove the 7 fields, with their init parameters and `CodingKeys`/decoder lines, from `Recipe`,
  `IngredientLine`, `RecipeNote`, `Category` and `MealPlanItem`. Remove `Tag`, `RecipeTag`, `Equipment` and
  `RecipeEquipment` entirely. Old JSON carrying the keys still decodes, because unknown keys are ignored.
- **Sync.**
  - Remove the four types from `makeSyncEngine` and `syncedTables` in `CloudSync.swift`.
  - Add `"tags"` and `"recipeTags"` to `retiredRecordTypes`, so Slice 6's purge deletes their Development
    records and metadata. The equipment types never synced, so they don't need listing.
  - Drop `"recipeTags"` and `"recipeEquipment"` from `SyncHealthModel.recipeChildRecordTypes`.
- **The fold.** Delete `CategoryRepository.foldDormantTagsIntoCategories` and its order helpers, plus its call in
  the post-engine data passes (`Schema.swift`). In `mergeCategory`, delete the `color` carry-over.
- **Readers and copiers.** Remove the dropped fields from:
  - `RecipeAdjustment` (the restore and copy paths);
  - `RecipeBrowser`'s `activeTimeMinutes` (its own row field is sourced from the column, so remove both);
  - `GroceryCore`'s aisle fallback;
  - `RecipeCore`'s line rebuilds and recipe detail (`equipment`, `recipeEquipment`);
  - `RecipeBundleCoding.RecipeBundle` (`equipment`, `recipeEquipment`);
  - `RecipeRepository+Import`: the bundle insert, the batch-undo equipment count, and the `RecipeTag` and
    `RecipeEquipment` checks in the duplicate-safety guard.

  Grep each name. This list is a map, not a guarantee.
- **Docs.** Strike the dropped fields from `docs/DATA_MODEL.md`.

## Done when

- The migration and model changes land. A test migrates a store that has populated `tags`/`recipeTags` rows and
  the full set of columns, and shows every other value intact, including `categories` and `recipeCategories`.
- The dead-column test from Phase 1 passes with the reduced models.
- The "`retiredRecordTypes` shares no name with `syncedTables`" test passes with the tag types added.
- `declaredSchemaVersion` is 54 and its test passes.
- The completing PR:
  - adds the `DONE-LOG.md` entry;
  - ticks PROD-CUTOVER Step 1's merge and device-check boxes (Jon ticks the device check);
  - lists the device pass below in `device-passes.md`, with a pointer under **Owed**;
  - advances `NEXT_UP.md` in plan order.

**Device pass to add:**
1. Export a backup from each device first.
2. Install on both devices. Confirm the library is intact and the category browser shows the same labels.
3. Delete the empty loose **beach** and **cocktail** categories, relaunch, and confirm they stay gone.
4. Confirm Sync reads "Up to date" on both devices once the purge has run, with no `tags` or `recipeTags` left.
5. Edit a recipe and confirm the edit syncs.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build (model shapes change and
the app compiles against them), and `YesChefTests`.
