# Effort — Family cookbooks

Status: Designed (S2 not yet briefed).
Summary: Browse family members' recipes read-only and copy one into yours. S0 (transport spike) passed on device and S1 (bundle v2 and copy-import) is merged; S2 (mirror and read-only visiting) is next to brief.

Origin: Jon, 2026-11-13. Decision: [ADR-0071](../decisions/ADR-0071-family-cookbooks.md). This brief holds the slice
plan; the ADR holds the why. **S0 is a spike.** Its code is debug-only and disposable. S3 and S4 rebuild the
publisher and fetcher in `YesChefCore` with tests, and may take from the spike what survives.

## Ledger

- [x] **S0** — transport spike (this brief, below). Device pass cleared 2026-11-13; results in ADR-0071 § S0 result
- [x] **S1** — bundle v2 and copy-import (this brief, below)
- [ ] **S2** — mirror database and read-only visiting
- [ ] **S3** — publish
- [ ] **S4** — accept and fetch

## Where things are for S0 (architect, 2026-11-13, `origin/main` e5b3143)

- `YesChefApp/YesChef-Dev.entitlements`: `com.apple.developer.icloud-container-identifiers` lists only
  `iCloud.com.jonphillips.yeschef`. `project.yml` (line 173) points the Dev configuration at this file.
- `YesChefApp/YesChefApp.swift`: the `@main` `App`. There's no `UIApplicationDelegateAdaptor` and no scene delegate
  yet, and nothing handles CloudKit share metadata.
- `YesChefApp/Info.plist`: no `CKSharingSupported` key and no `UIApplicationSceneManifest`.
- `YesChefApp/SettingsViews.swift` (line 65): `Section("Developer")`. Its `#if DEBUG` block (Yes Chef Dev label,
  `modelCallInventoryRow`) is where the spike row goes.
- `YesChefPackage/Sources/YesChefCore/ChatAccessExport.swift`: `ChatAccessExport.build(in:generatedAt:device:)`
  (line 7) already builds a `RecipeBundleCoding.RecipeBundle` for every recipe in the library (line 184). The spike
  publishes those.
- `YesChefApp/ChatAccessFolderClient.swift`: the dependency-client precedent (a struct of `@Sendable` closures with a
  `DependencyKey` `liveValue`).
- `YesChefPackage/Sources/YesChefCore/CloudSync.swift`: the library's `SyncEngine` setup. **Don't touch it.**
  It's here so you can see what the spike must stay clear of.

## S0 — Transport spike

### Build

All new code is in `YesChefApp/` under `#if DEBUG`. Release builds behave exactly as they do today.

1. **Entitlement.** Add `iCloud.com.jonphillips.yeschef.cookbook` to `com.apple.developer.icloud-container-identifiers`
   in `YesChef-Dev.entitlements` only. Leave out the ubiquity list (no iCloud Drive), the Release entitlements and
   the share extension. S3 adds it to Release.
2. **Accepting shares.** Add `CKSharingSupported` = `YES` to `Info.plist`. In DEBUG, add an app-delegate adaptor that
   gives scenes a delegate class handling both ways an accepted share arrives:
   - `windowScene(_:userDidAcceptCloudKitShareWith:)` when the app is running;
   - `connectionOptions.cloudKitShareMetadata` in `scene(_:willConnectTo:options:)` on a cold launch from the
     link.
   Hand metadata whose `containerIdentifier` is the cookbook container to the spike, which accepts it on that
   container (`CKAcceptSharesOperation` or `CKContainer.accept`) and logs the result. Metadata for any other
   container is logged and ignored. Check that the SwiftUI window, `onOpenURL` (`RecipeLibraryView.swift` line 199)
   and the scene-phase behavior still work with the scene delegate in place; say in the PR if anything moved.
3. **`CookbookSpikeClient`**, a dependency client on `CKContainer(identifier: "iCloud.com.jonphillips.yeschef.cookbook")`.
   It never touches the library container. Operations:
   - **Create Share.** Create zone `Cookbook` in the private database, then a zone-wide `CKShare(recordZoneID:)`
     with `publicPermission = .none` and title "<device owner>'s Recipes". Present `UICloudSharingController` limited
     to private, read-only participants. If the zone and share already exist, reuse them and show the share's
     participants.
   - **Publish N.** Read `ChatAccessExport.build(in:…).recipes`. Write one `CookbookRecipe` record per bundle with
     record name = recipe ID, a `payload` `CKAsset` (the bundle's JSON) and a `contentHash` string (SHA-256 of the
     JSON). If N is more than the library holds, repeat bundles with record names `<recipeID>-<n>` to reach N.
     Save in batches of at most 400 with `CKModifyRecordsOperation` and `.changedKeys`. Also write one
     `CookbookProfile` record (display name, recipe count). Log the time for each batch and the total. N defaults
     to 2000.
   - **Republish One.** Change one record's payload (append a marker to the title in the JSON), recompute its hash,
     and save it.
   - **Fetch Changes.** List `sharedCloudDatabase.allRecordZones()`. For each zone, fetch zone changes from the stored
     change token until `moreComing` is false. Count changed and deleted records, log the time, and store the new
     token (DEBUG `UserDefaults` key, one per zone). **Reset Token** clears it, so the next fetch is a full one.
   - **Try to Write.** Save a `CookbookRecipe` into the first shared zone. The expected result is a permission
     failure: log the `CKError` code either way.
   - **Delete My Cookbook.** Delete the `Cookbook` zone (which removes its share), so the spike can be rerun from
     scratch.
4. **Settings › Developer › Cookbook Spike**: one row per operation, a field for N, and a timestamped log with a
   **Copy Log** button, so Jon can paste the results into the PR. Keep it plain; it's a test screen. The model for
   it is an `@Observable @MainActor` class; the view binds and delegates (guardrail #2).

### Keep

- No change to `CloudSync.swift`, `Schema.swift`, the `SyncEngine` configuration, any synced table, or any migration.
- No `YesChefCore` change. The spike's code carries a header comment: *ADR-0071 S0 spike, DEBUG-only; S3/S4 replace
  it.*
- Errors are logged in the spike screen, never swallowed. A failed batch logs its `CKError` and stops.

### Done when

- `scripts/check-drift.sh` is green, and the generic iOS build and `YesChefTests` pass (guardrail #9; the spike adds an
  App-layer model).
- The PR body lists the device pass below as owed.
- Closeout runs with `--keep-brief`. It ticks S0 in the ledger, sets this brief's `Status:` to **Blocked** (on Jon's
  S0 device pass) and sets `NEXT_UP.md` to `Nothing dispatched.`

### Device pass (Jon, about 30 minutes)

Before (**done**, Jon, 2026-11-13): in the developer portal, create container `iCloud.com.jonphillips.yeschef.cookbook` and tick it on both App
IDs (`com.jonphillips.yeschef` and `com.jonphillips.yeschef.dev`).

Both devices run **Yes Chef Dev**, installed from Xcode, with library iCloud sync turned on. Dev has its own bundle
ID, so Wendy's TestFlight app and library aren't touched. On her iPhone, turn on Developer Mode (Settings › Privacy &
Security) first.

1. **Jon's device:** Cookbook Spike › **Create Share**, and invite Wendy through Messages.
2. **Wendy's phone:** tap the link. Yes Chef Dev opens, and the spike log shows the share accepted. Try it once with
   the app running and once with it quit.
3. **Jon's device:** **Publish N** with N = 2000. Note the total time.
4. **Wendy's phone:** **Fetch Changes**. The log shows 2001 changed records (2000 recipes and the profile). Note
   the time.
5. **Jon's device:** **Republish One**. **Wendy's phone:** **Fetch Changes** shows exactly 1 changed record.
6. **Wendy's phone:** **Try to Write** fails with a permission error.
7. **Sync left alone, both devices:**
   - Settings › Sync status shows no new errors or unknown record types.
   - In the CloudKit Console (Development), `CookbookRecipe` and `CookbookProfile` exist only in the cookbook
     container, never in `iCloud.com.jonphillips.yeschef`.
   - A recipe edit on Jon's Dev device still reaches his other Dev device as before.
8. Paste both devices' **Copy Log** output into the PR.

**Pass:** every step holds. **Fail:** the share can't be accepted, a write succeeds, or anything shows up in library
sync. Either way, the architect records the result and timings in ADR-0071. A pass makes S1 Ready. A fail moves the
plan to the snapshot-file fallback (ADR-0071 D3).

## S1 — Bundle v2 and copy-import

Package-only: everything is in `YesChefPackage/Sources/YesChefCore` with package tests. There's no App change, no
CloudKit, no UI and no schema change. S2 builds the mirror and the Copy button on top of this, and S3 publishes this
payload, so S1 has to settle the payload's shape and what a copy does.

### Where things are (architect, 2026-11-13, `origin/main` 47d7a06)

- `RecipeBundleCoding.swift`: `RecipeBundle` (line 4) has synthesized `Codable`. `snapshotData` (line 68) writes
  `Recipe.originalSnapshot` at version 1, and `decodeSnapshot` (line 98) reads it.
- `RecipeRepository+Import.swift`: `importBundle` (line 197) is the Paprika path. It **keeps the bundle's IDs**, and
  its `matchingImportRefs` (line 519) **deletes** content-empty duplicate recipes as a side effect. Copy must use
  neither. `rawMatchingImportRefs` (line 606) is the read-only matcher.
- `RecipeAdjustment.swift`: `createStandaloneRecipe` (line 1565) is the existing fresh-ID clone, with ID maps for
  sections and photos. Follow it, but its force-unwrapped map lookups (`ingredientSectionIDs[line.sectionID]!`) must
  become thrown errors. A payload from someone else's device is input, not trusted state.
- `RecipeVariationPayload` (`RecipeAdjustment.swift` line 193). Its ops anchor to base rows by ID, with text
  fallback: `RecipeIngredientReference.id` (an `IngredientLine.ID`), `RecipeMethodStepReplacement.id` and
  `RecipeStepReference.id` (`InstructionStep.ID`s), and `.insert(after:sectionID:text:)`'s `InstructionSection.ID`
  (line 744).
- `RecipeCategoryRepository.swift`: `reconcileCategories` (line 875) and `findOrCreateImportedCategory` (line 917)
  already do find-or-create by `"Facet > Parent > Child"` path, but turn a path whose facet you lack into one loose
  label named `"Cuisine > Thai"`. `CategoryHierarchy.pathComponents` (line 148) gives a category's path.
- `RecipeRelatedRecipe.swift`: one undirected row per pair (`canonicalPair`, line 67; `linkRelatedRecipes`,
  line 139). `RecipeServeWith` rows have an optional `linkedRecipeID`, so a text-only serve-with is already a valid row.
- `RecipeImportIdentity.swift`: `RecipeImportIdentityKey(sourceURL:title:)` is the normalizer for matching.

### Build

1. **`RecipeBundle` version 2** (ADR-0071 D5). Add `RecipeBundleCoding.currentVersion = 2`. Add these fields, all
   decoded with `decodeIfPresent` and an empty default (write the `init(from:)` the way `RecipeVariationPayload`
   does), so every existing snapshot decodes unchanged:
   - `labels: [LabelPath]`, where `LabelPath` is `facet: String?` plus `path: [String]` (root to leaf). A nil
     facet means a loose label.
   - `serveWith: [RecipeServeWith]` and `relatedRecipes: [RecipeRelatedRecipe]` (every pair touching this recipe).
   - `variations: [RecipeVariation]`, with `deltas` carried as-is.
   - `linkTargets: [LinkTarget]` (`recipeID`, `title`, `sourceURL`) for every recipe a serve-with or related row
     points at. It makes a payload self-contained: copying needs the target's identity, and Phase 1's "send a copy"
     file has no mirror to look it up in.

   `categoryNames` stays filled as today, so v1 readers still show labels. `snapshotData` keeps writing version 1
   and leaves the new fields empty: `originalSnapshot` is provenance, not a cookbook payload.
2. **Payload builder.** `CookbookPayload.bundles(in db:) -> [RecipeBundle]` builds a v2 bundle for every recipe that
   isn't archived, with the owner's own IDs (the mirror needs them, D2). Photos keep `thumbnailData` and drop
   `displayData` (D5: display images travel as their own asset in S3). Rating and favorite stay as they are; they're
   the owner's and the mirror shows them as theirs. Also add `encodedPayload(_:) -> Data` (sorted keys, every array
   in a fixed order) and `contentHash(_:) -> String` (SHA-256 hex of those bytes). S3 compares hashes, so the same
   library must always produce the same bytes. Reading the whole library is fine, the way `ChatAccessExportBuilder`
   does it; S3 measures before anyone optimizes.
3. **Decoding a payload.** `RecipeBundleCoding.decodePayload(_:)` throws `.newerVersion(n)` when `version` is
   greater than `currentVersion`. It never decodes it partially. S4 counts these ("12 recipes need a newer Yes Chef",
   D4).
4. **Copy-import** (D7). Put `RecipeRepository.copyCookbookRecipe(_ bundle:, ownerName:, displayImages:
   [RecipePhoto.ID: Data], in db:, now:, uuid:) throws -> CookbookCopyResult` in a new
   `RecipeRepository+CookbookCopy.swift`. It's a pure database operation (guardrail #2), one transaction, and it
   always copies. Asking "Open Mine / Copy Anyway" first is S2's job, using item 5.
   - **Fresh IDs** for every row, through explicit old-to-new maps: recipe, source, ingredient and instruction
     sections, lines, steps, notes, photos, serve-with rows and variations. Remap `coverPhotoID` and each line's
     and step's `sectionID`. A child that points at a parent missing from the bundle throws.
   - **Kept verbatim:** `originalSnapshot` (it still holds the owner's IDs, which is fine because it's passive
     provenance), each line's `originalText`, the source URL, `makeAhead`, `chefItUp`, notes with their types and
     pins, and `libraryPlacement`.
   - **Reset:** `rating` is nil, `favorite` false, `archived` false, `viewScale` 1, and `dateCreated` and
     `dateModified` are `now`. No `RecipeActiveVariation` is copied: which variation is showing is the owner's view
     state.
   - **Provenance:** `RecipeSource.importedFrom = "Copied from <ownerName>'s cookbook"` and `dateImported = now`.
     If the bundle has no source, create one with just those two fields. Any earlier `importedFrom` value is still
     in `originalSnapshot`.
   - **Photos:** thumbnails come from the bundle. `displayData` comes from `displayImages` when it holds that
     photo's (old) ID, and stays nil otherwise. S4 fetches it before copying.
   - **Variations:** remap every anchor ID in the decoded `RecipeVariationPayload` through the line, step and
     instruction-section maps. An anchor ID that's not in the map (already dangling on the owner's side) becomes nil,
     and its text fallback is kept. The op is never dropped. A `deltas` blob that won't decode is copied unchanged
     and named in the result's warnings.
   - **Labels:** a v2 bundle uses `labels`. Find or create the facet by name (case-insensitive), creating it if
     you don't have it, then find or create each path component under it. A nil facet finds or creates a loose
     label. Your existing labels win wherever names match. A v1 bundle falls back to today's
     `reconcileCategories(categoryNames, looseNames: tagNames)`.
   - **Serve-with:** a row whose `linkedRecipeID` resolves (item 6) points at your recipe. Otherwise it's kept as a
     text-only row (title and note, `linkedRecipeID` nil) and listed in the result.
   - **Related recipes:** each pair whose other end resolves is linked to your recipe through `linkRelatedRecipes`.
     A pair that doesn't resolve can't be a row (`relatedRecipeID` is required), so it isn't stored. It's listed in
     the result by title, and S2 shows it at copy time with an offer to copy that recipe too (ADR-0071 D7 Amendment).
   - **Import ref:** write a `RecipeImportRef` keyed on the bundle's `RecipeImportIdentityKey`, so the recipe reads as
     In My Recipes afterwards. A second ref with the same key after Copy Anyway is expected.
   - The result carries the new recipe ID, `textOnlyServeWith: [String]`, `unlinkedRelated: [String]` and
     `warnings`.
5. **"In My Recipes" lookup.** Add `RecipeRepository.existingCopies(of bundle:, in db:) -> [Recipe.ID]`, which is
   read-only and never deletes anything. It returns your non-archived recipes whose import ref matches the bundle's
   identity key **or** whose `RecipeSource.url` normalizes to the bundle's source URL. Import refs alone would miss a
   recipe the viewer captured from the same page on their own, because web capture writes no ref. A title-only key
   matches on refs only.
6. **Resolving link targets.** A `LinkTarget` resolves to your recipe when `existingCopies` of its identity returns
   exactly one. Zero or several means no match: it becomes text, and nothing is guessed.

### Keep

- No synced table, column or migration changes (D8). No App, CloudKit or UI code; the S0 spike stays as it is.
- `importBundle`, `matchingImportRefs` and `reconcileCategories` keep their current behavior for their current
  callers. Share helpers by extracting them, not by changing those paths.
- `ChatAccessExportBuilder` isn't switched to the new builder in this slice.

### Tests (package, `YesChefCoreTests`)

- **Compatibility:** every existing snapshot fixture and a v1 bundle still decode, and `snapshotData` output is
  unchanged for a recipe with no v2 content. A v2 bundle round-trips. `decodePayload` refuses version 3 with
  `.newerVersion(3)`.
- **Builder:** archived recipes are left out. Labels carry facet and path. A serve-with or related link to another
  recipe adds that recipe to `linkTargets`. Photos have thumbnails and no display data. Building twice from the same
  database gives byte-identical output and the same hash, and editing one recipe changes only its hash.
- **Copy, fresh IDs:** no copied row shares an ID with the bundle, and every child points at the new recipe and the
  new sections. Copying the same bundle twice gives two independent recipes, and editing one leaves the other alone.
- **Copy, preservation:** `originalSnapshot` is byte-equal, line `originalText` and the source URL are equal, notes
  keep type and pin, and rating and favorite are reset. `importedFrom` names the owner, and a bundle with no source
  gets one.
- **Copy, variations:** an ingredient substitute, a step replacement and a step insert anchored by ID all still
  resolve on the copy (apply the variation to the copy and compare it with the original applied to the original).
  This includes two identical ingredient lines, where text fallback alone would pick the wrong one. A dangling ID
  keeps its text, and an unreadable `deltas` blob is copied unchanged and warned about.
- **Copy, labels:** an existing facet and path is reused, not duplicated. A missing facet is created. A loose label
  is matched by name. A v1 bundle goes through the old path.
- **Copy, links:** a serve-with target you already copied is linked; one you haven't becomes text and is listed. A
  related target you have is paired; one you don't is listed and not stored. A target matching two of your recipes
  stays unlinked.
- **Lookup:** a recipe is found by import ref and by source URL alone, an archived one isn't found, and the lookup
  writes nothing (row counts are unchanged, including when duplicate refs exist).
- **Malformed input:** a line whose `sectionID` isn't in the bundle throws, and nothing is written.

### Done when

- `scripts/check-drift.sh` is green. No `YesChefApp/` change, so there's no generic iOS build and no `YesChefTests`
  run (guardrail #9).
- Closeout (ADR-0005 D16) runs with `--keep-brief`. It ticks S1 in the ledger and advances `NEXT_UP.md` per ADR-0005
  D12. S1 has no device pass: nothing in it is visible until S2.
