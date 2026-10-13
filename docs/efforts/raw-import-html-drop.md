# Effort — Drop the raw import HTML, re-upload what never synced, re-link the calendar

Status: Designed 2026-10-13, queued behind #348. **Schema change on a synced table, and a data delete Jon approved
on 2026-10-13.** The architect escalates the PR to Jon.
Summary: Stop storing the raw page HTML (`Recipe.originalImportText`) in any build, and drop the column and its data
before the CloudKit Production deploy. Nine browser captures exceed CloudKit's 1 MB record limit, so they never
uploaded. Re-upload them, along with any child rows that never reached the server, then re-link the three calendar
rows that sync broke.
Related: [ADR-0010 Amendment 1](../decisions/ADR-0010-cloudkit-sync-enablement.md#amendment-1--raw-import-html-is-not-kept-in-any-build-2026-10-13) ·
[`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Phase 1 · precedent [`prod-dead-column-drop.md`](prod-dead-column-drop.md)

## What happened (from Jon's iPad backup, 2026-10-13)

- ADR-0010 stopped persisting raw HTML in **release** builds. The DEBUG DOM export revival (PR #51) kept it in
  DEBUG, and Jon dogfoods DEBUG, so 2,143 recipes carry it (36 MB).
- **Nine recipes are over 1 MB** (largest 1.56 MB). This is TEXT, so it counts inline toward CloudKit's 1 MB
  per-record limit. The upload fails with `.limitExceeded`, which SQLiteData 1.9 ignores (`SyncEngine.swift`,
  the bare `continue` list). These nine have never reached the server, and nothing told us.
- A child saved later gets `.referenceViolation`, because its parent isn't on the server. For a single-FK table,
  SQLiteData answers by **applying the FK's `ON DELETE` locally** (`SyncEngine.swift` around line 1705). For
  `mealPlanItems.recipeID` (`SET NULL`) that blanked the link on 3 calendar rows: Keema Palak ×2 and
  Coconut-Caramel Braised Tofu. Those rows show no image and don't open on either device. For a `CASCADE` child
  the same path **deletes the local row**, which is why S2's ordering rule exists.

## S1 — Stop writing it; drop the column

- Remove every write and the switch: `preserveRawImportHTML` in `WebRecipeCaptureClient.importCapturedRecipe`,
  `RecipeModels.prepareImport` (Paprika), `ParsedRecipePage.makeRecipeBundle`, and `PaprikaHTMLImport`. Also the
  copy in `RecipeAdjustment` (new-recipe-from-revision) and the nil-ing in `RecipeBundleCoding`. The parsers keep
  their **in-memory** `originalHTML`, since they parse it. Only persistence goes.
- Delete the DEBUG DOM export from `OriginalSnapshotView` (the export function, its state and its button). No
  replacement: Jon debugs a bad capture live, in place.
- Remove `originalImportText` from `Recipe`: the property, init parameter, `CodingKeys` and decode line. Old
  backups and transfer JSON that carry the key still decode, because unknown keys are ignored. Add a test for it.
- Append one migration, `Drop raw import HTML`: `ALTER TABLE "recipes" DROP COLUMN "originalImportText"`,
  guarded on `pragma_table_info` the same way as `Drop legacy recipe cooking columns`. No `VACUUM`.
  `declaredSchemaVersion` goes **51 → 52**.
- Update the tests that pass `preserveRawImportHTML: true` (`WebRecipeCaptureTests`, `PaprikaHTMLImportTests`).
  Assert instead that a captured bundle's `Recipe` has no raw page. #343's dead-column test covers whether the
  model and the disk agree.

## S2 — Re-upload and re-link (post-engine, idempotent)

Add one pass to the existing `runsPostEngineDataPasses` block in `Schema.swift`, reporting through
`AppLog.dataIntegrity` with the same `hasFindings`/`logSummary` shape as its neighbors. It uses the attached
metadatabase. A row is **"on the server"** when its `SyncMetadata` has a `lastKnownServerRecord`.

1. **Skip the whole pass** unless at least one recipe is on the server. A device that has never synced, or has
   sync off, has nothing to repair and must not rewrite the library on every launch.
2. **Recipes not on the server:** apply a no-op `UPDATE` (for example `SET "title" = "title"`). Don't bump
   `dateModified`, because it drives "Newest". SQLiteData's after-update trigger has no `WHEN` clause, so any
   `UPDATE` re-queues the row (verified in 1.9.0 `Internal/Triggers.swift`).
3. **Children not on the server, of recipes that are:** apply the same no-op touch to the rows of every synced
   table with a `recipeID` FK to `recipes`. **Never touch a child whose recipe isn't on the server yet.** It would
   hit `.referenceViolation`, and SQLiteData would null or delete it locally. Waiting for a later launch is the
   ordering guarantee: step 2 uploads the recipe this launch, and step 3 picks up its children on the next one.
4. **Re-link:** take `mealPlanItems` and `menuItems` rows with `kind = recipe` and `recipeID IS NULL`. If
   exactly one non-archived recipe has an identical title **and is on the server**, set `recipeID` with a normal
   write, so it syncs. Leave zero or several matches alone and log the counts. The same step-3 rule applies: never
   link to a recipe that isn't on the server.

Keep the decisions pure and testable. A thin shell reads the set of on-server IDs from `SyncMetadata`, and Core
functions take that set as input. Tests cover: the oversize-text migration keeps every other value; re-link with
one match, none, several, and a match whose recipe isn't on the server yet; children are skipped while their
parent isn't on the server; the pass does nothing when no recipe is on the server.

## Done when

- S1 and S2 land in one PR, with the tests above green and `declaredSchemaVersion` at 52.
- No `originalImportText` or `preserveRawImportHTML` remains in `Sources/` or `YesChefApp/`.
- The `PROD-CUTOVER.md` Phase 1 box for this is ticked, `DONE-LOG.md` has the entry, `NEXT_UP.md` is advanced, and
  the device pass below is in `device-passes.md`.

**Device pass to add:** export a backup from each device first. Install on the iPad, launch twice with sync on, then
the iPhone. The nine recipes (Camarones a la Diabla, Coconut-Caramel Braised Tofu, Keema Palak, …) now appear on the
iPhone with ingredients, steps and hero photo. Both Keema calendar rows and the Coconut-Caramel row show a
thumbnail and open on both devices. Check the `dataIntegrity` log line for unmatched rows. Library counts match.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build (`Recipe`'s shape changes), and
`YesChefTests`.
