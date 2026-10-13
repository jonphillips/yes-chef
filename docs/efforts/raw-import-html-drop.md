# Effort — Drop the raw import HTML and the dead photo rows, re-upload what never synced, re-link the calendar

Status: Designed 2026-10-13, queued behind #348. **Schema change on a synced table, and two data deletes Jon
approved on 2026-10-13.** The architect escalates the PR to Jon.
Summary: Stop storing the raw page HTML (`Recipe.originalImportText`) in any build, and drop the column and its data
before the CloudKit Production deploy. Nine browser captures exceed CloudKit's 1 MB record limit, so they never
uploaded. Re-upload them, along with any child rows that never reached the server, then re-link the three calendar
rows that sync broke. Capture stops saving photo rows it never downloads, and the 1,527 existing ones are deleted.
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
  the same path **deletes the local row**, which is why S3's ordering rule exists.
- **1,527 photo rows have no image bytes.** `RecipeBodyImageExtractor` runs on every capture and collects every
  `<img>`, srcset and CSS background on the page. Every URL becomes a `RecipePhoto`, but only the hero is ever
  downloaded (`hydrateHeroImage`). Keema Palak has 88 such rows: 6 are size variants of its own photo, and about
  82 are other recipes from carousels. That's 1,526 extracted gallery rows on 28 recipes, plus one hero whose
  download failed (Pistachio Crackle Oil). Each one is a synced record. Nothing displays them, and no recipe uses
  one as its cover.

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

## S2 — Capture keeps only photos it downloads

The rule: **a `RecipePhoto` row exists only with image bytes.**

- `ParsedRecipePage.makeRecipeBundle` emits a photo only for an image in `processedImages`, which today means the
  hydrated hero. If the hero download fails, the recipe has no photo row, the same placeholder as now.
- The candidate list still matters, because it picks the hero. `RecipeBodyImageExtractor` runs only when JSON-LD,
  meta, microdata and the per-site extractors found no image. The body scrape is a fallback, not an addition.
- Tests: an NYT-shaped fixture with structured images plus a carousel yields one photo row, the hero, and the body
  scrape doesn't run. A page with no structured image still finds its body image. A failed hero download yields no
  photo row.

## S3 — Delete dead photos, re-upload, re-link (post-engine, idempotent)

Add one pass to the existing `runsPostEngineDataPasses` block in `Schema.swift`, reporting through
`AppLog.dataIntegrity` with the same `hasFindings`/`logSummary` shape as its neighbors. It uses the attached
metadatabase. A row is **"on the server"** when its `SyncMetadata` has a `lastKnownServerRecord`.

0. **Delete every `recipePhotos` row with neither `displayData` nor `thumbnailData`, first** (Jon-approved).
   This is a normal write, so the deletes sync. Running it first keeps step 3 from uploading junk it is about to
   delete. Clear any `coverPhotoID` that points at a deleted row. There are none today, but the pass must not
   leave a dangling cover.
1. **Skip the whole pass** unless at least one recipe is on the server. A device that has never synced, or has
   sync off, has nothing to repair and must not rewrite the library on every launch.
2. **Recipes not on the server:** re-queue them with `UPDATE "recipes" SET "id" = "id"`, SQLiteData's own
   re-sweep idiom (`SyncEngine.uploadRecordsToCloudKit`). It fires the after-update trigger, and the primary-key
   trigger stays quiet because it's guarded `WHEN old.pk != new.pk` (verified in 1.9.0
   `Internal/Triggers.swift`). Don't bump `dateModified`, because it drives "Newest".
3. **Children not on the server, of recipes that are:** re-queue the same way the rows of every synced
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
parent isn't on the server; the pass does nothing when no recipe is on the server; byte-less photos are deleted and
photos with bytes, of any kind and source, are kept.

## Done when

- S1–S3 land in one PR, with the tests above green and `declaredSchemaVersion` at 52.
- No `originalImportText` or `preserveRawImportHTML` remains in `Sources/` or `YesChefApp/`.
- A fresh capture of an NYT recipe stores exactly one photo row.
- The `PROD-CUTOVER.md` Phase 1 box for this is ticked, `DONE-LOG.md` has the entry, `NEXT_UP.md` is advanced, and
  the device pass below is in `device-passes.md`.

**Device pass to add:** export a backup from each device first. Install on the iPad, launch twice with sync on, then
the iPhone. The nine recipes (Camarones a la Diabla, Coconut-Caramel Braised Tofu, Keema Palak, …) now appear on the
iPhone with ingredients, steps and hero photo. Both Keema calendar rows and the Coconut-Caramel row show a
thumbnail and open on both devices. Every recipe still shows the same hero as before. Capture one NYT recipe and
confirm its photo gallery holds just the hero. Check the `dataIntegrity` log line for unmatched rows and the deleted
photo count (1,527 on the iPad). Library counts match.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build (`Recipe`'s shape changes), and
`YesChefTests`.
