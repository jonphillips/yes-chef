# Effort — Family cookbooks

Status: Ready
Summary: Browse family members' recipes read-only and copy one into yours. S0–S2 are done, and S2's device pass found three gaps. S2b fixes the two left after the architect's Copy Anyway fix: the cookbook's filter and sort buttons, and showing where a copy came from. S3 then publishes your library to the cookbook zone.

Origin: Jon, 2026-11-13. Decision: [ADR-0071](../decisions/ADR-0071-family-cookbooks.md). This brief holds the slice
plan; the ADR holds the why. **S0 is a spike.** Its code is debug-only and disposable. S3 and S4 rebuild the
publisher and fetcher in `YesChefCore` with tests, and may take from the spike what survives.

## Ledger

- [x] **S0** — transport spike (this brief, below). Device pass cleared 2026-11-13; results in ADR-0071 § S0 result
- [x] **S1** — bundle v2 and copy-import (this brief, below)
- [x] **S2** — mirror database and read-only visiting (this brief, below)
- [ ] **S2b** — visiting fixes from the S2 device pass (this brief, below)
- [ ] **S3** — publish (this brief, below)
- [ ] **S4** — accept and fetch. Carries from S2: In My Recipes on list rows, copy-them-too for unlinked related recipes, display images fetched on open, cook mode in a cookbook, an Open action on the copy toast (the reader's button always copies and asks Open Mine / Copy Anyway when you have a copy, since #516), and applying payloads off the main actor (the S2 file load runs on it)

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

## S2 — Mirror and read-only visiting

S2 makes a cookbook browsable without any CloudKit. A mirror database is filled from a payload file, and the Recipes
list, the Power Browser and the reader run against it read-only. **Copy to My Recipes** brings a recipe across using
S1. A DEBUG-only file export and load gets Jon's real library onto Wendy's phone for the device pass. S4 later fills
the same mirror from the shared zone instead of a file. The mirror code is permanent; only the file loader is
DEBUG-only.

### Where things are (architect, 2026-11-13, PR #514 head f594c86)

- `YesChefCore/Schema.swift`: `bootstrapDatabase(path:syncMode:eraseDatabaseOnSchemaChange:)` (line 65) builds the
  migrator inline (lines 87–1401) and sets `defaultDatabase`. Its `prepareDatabase` attaches the **library
  container's** metadatabase (line 72). `migrateRestoreCandidate` (line 1420) is the precedent for running the
  migrator against another file. No list, browser or reader query reads sync metadata. Only `Schema.swift`,
  `RecipeSyncRepair.swift` and `SyncHealthModel` do.
- `YesChefCore/CookbookPayload.swift` and `RecipeRepository+CookbookCopy.swift` (S1): `bundles(in:)`,
  `copyCookbookRecipe`, `existingCopies`, and the private `copyCookbookLabels` (find or create by facet and path).
- `YesChefApp/RecipeLibraryView.swift`: `AppContainer` (line 11) owns `RecipeLibraryModel`, `PowerBrowserModel` and
  the root presenters, `presentedRecipe` (line 33, `.fullScreenCover` at line 101) and `presentedCookSession`.
- `YesChefApp/AppNavigationModels.swift`: `RecipeDetailPresentation` (line 4) and `AppSection` (line 56, a
  `String`-backed `CaseIterable` enum).
- `YesChefApp/RecipeDetailView.swift`: `init` (line 25) builds `RecipeDetailModel` inside the view's initializer and
  takes your `RecipeLibraryModel`, `MealCalendarModel` and `GroceryLibraryModel`.
- `YesChefApp/RecipeModels.swift`: `RecipeLibraryModel` (line 12) and `RecipeDetailModel` (line 695). **Reading
  writes:** changing the scale persists it (`persistScaleFactor`, line 1067).
- `YesChefApp/RecipeImageLoader.swift`: `RecipePhotoDisplayDataLoader.load` (line 12) resolves
  `@Dependency(\.defaultDatabase)` inside a static function called from a view. It sees whatever the dependency is
  *where it's called*, not the model's.
- `YesChefApp/PowerBrowserModel.swift`: the saved-lens library (line 106) is your state, and it's empty in a mirror.
- Models capture `@Dependency` values when they're created. A model created inside
  `withDependencies { $0.defaultDatabase = mirror }` reads the mirror; a view, static helper or `@Fetch` declared in a
  view doesn't.

### Build — core (`YesChefCore`, package tests)

1. **Extract the migrator.** Move the migration registrations out of `bootstrapDatabase` into
   `YesChefSchema.migrator()`, and have `bootstrapDatabase` call it. This is a move, not a rewrite: every migration
   body and identifier stays byte-identical and in the same order: shipped migrations are never rewritten. Library
   bootstrap behaves exactly as before.
2. **`CookbookMirror`** (new file). One per cookbook, at `Application Support/Cookbooks/<id>.sqlite`, with the
   directory excluded from backup.
   - **Open:** if the file's applied migrations aren't exactly `YesChefSchema.migrator()`'s, delete the file
     (with `-wal` and `-shm`) and create it fresh. Never migrate a mirror: it's a cache (D2). Create it through a
     short-lived plain connection that runs the migrator and closes. Then open the guarded `DatabasePool` below, **without** the metadatabase attach and with no
     `SyncEngine`.
   - **Read-only guard:** use one `DatabasePool` for both the screens and the writer, not a second read-only
     connection. Observation (`@Fetch`) only sees writes made through the same pool, and a separate writer would
     leave an open cookbook stale after S4's fetch. Set `PRAGMA query_only = 1` on the pool's writer after the
     pool opens and before it is exposed; the pool's readers are opened read-only. Only `apply` lifts it,
     inside one `writeWithoutTransaction` block: `query_only = 0`, then
     the transaction, then `query_only = 1` in a `defer`. The writer is serialized, so no other write can land in
     between. Any other `write` throws `SQLITE_READONLY`. That's the D6 backstop.
   - **`apply(upserting: [RecipeBundle], deleting: [Recipe.ID])`**, one transaction. It uses the owner's IDs as
     they are. For each bundle: upsert the recipe, source and children, and delete that recipe's children that are
     no longer in the payload. Rebuild its labels with the S1 facet-and-path find-or-create (extract
     `copyCookbookLabels` into a shared helper; don't copy it). Upsert serve-with rows as they are
     (`linkedRecipeID` isn't a foreign key, so a link to a recipe not yet in the mirror is fine). Insert a related
     pair only once its `recipeID` row exists. The pair arrives in both recipes' payloads, so it's inserted by
     whichever comes second. After all upserts, delete the recipes in `deleting` (children cascade) and any related
     pair whose `relatedRecipeID` was deleted. Then prune labels and facets that no mirror recipe uses.
   - **`deleteMirror()`** removes the files.
3. **Single-recipe bundle.** `CookbookPayload.bundle(for: Recipe.ID, in:)` shares code with `bundles(in:)`. Copy
   reads its bundle from the mirror this way.
4. **Payload file** (DEBUG callers, but the type is plain core code): `CookbookFile` holds `ownerName`,
   `generatedAt` and `payloads: [Data]`, each one an `encodedPayload`. Loading decodes each payload with
   `decodePayload` and counts `.newerVersion` instead of failing the load.

### Build — app

5. **Scope.** Add `LibraryScope` (`.mine` / `.cookbook(CookbookContext)`), where `CookbookContext` holds the owner's
   name and the mirror. `RecipeDetailPresentation` gains `scope`, so a serve-with or related tap inside a cookbook
   opens the linked recipe in the same cookbook. The root cover builds `RecipeDetailView`'s model inside
   `withDependencies { $0.defaultDatabase = mirror.database }` when the scope is a cookbook.
6. **Every database access in scope.** For each file the cookbook screens reach, list every `defaultDatabase`
   resolution and `@Fetch` in the PR body, with how it gets the mirror. Models are created inside the scoped
   `withDependencies`. Static helpers and view-level fetches take the database from the model, or from an
   environment value the cookbook root sets. `RecipePhotoDisplayDataLoader` is the known case. A missed one reads or
   writes **your** library while you're looking at someone else's, and nothing on screen would show it.
7. **Write affordances.** In `.cookbook` scope, the list, browser and reader show no edit, rate, favorite, label,
   archive, delete, import, chat, ask, adjust, variation editing, enrichment, workbench, cover photo, reader-feedback
   editing, add to menu, calendar or groceries actions, and no lens saving. Choosing a variation to view and scaling
   still work, **in memory only**: `setScaleFactor` never persists in a cookbook. Cook mode stays out of S2. For
   each `database.write` reachable from those three screens, say in the PR body whether it's hidden or kept in
   memory. The `query_only` guard is the backstop, not the plan.
8. **Copy to My Recipes.** It's the reader's one primary action in a cookbook. The action lives in a root-owned
   `CookbookCopyModel`, created outside the mirror scope, so it holds **your** library database (the cover's
   `defaultDatabase` is the mirror). It reads `bundle(for:)` from the mirror, then checks
   `existingCopies(of:)` in your library:
   - no match: copy, then show a toast with **Open**;
   - a match: ask **Open Mine / Copy Anyway** (several matches: Open Mine opens the newest);
   - after copying, show the result's `textOnlyServeWith` and `unlinkedRelated` in one plain alert ("Related recipes
     not in your library: …"). There's no copy-them-too action yet; it's in S4.

   When you have a copy, the reader shows **In My Recipes** and the button reads **Open Mine**. Marking rows in the
   list is in S4.
9. **Where a cookbook appears.** Add `AppSection.cookbooks` ("Family Cookbooks"). It's shown only when at least one
   mirror exists, so TestFlight users see nothing. It lists the mirrors by owner name. Choosing one shows the Recipes
   list and the Power Browser against that mirror, under a header "Jon's Recipes · read-only · loaded <date>".
10. **DEBUG file transport.** Settings › Developer gets two rows, DEBUG-only. **Export My Cookbook File** writes a
    `CookbookFile` from `CookbookPayload.bundles` and offers the share sheet. **Load Cookbook File** uses
    `fileImporter`, opens or replaces the mirror for that owner, applies every payload, and logs the counts
    (applied, newer-version skipped, time). The S0 spike rows stay.

### Keep

- No synced table, column or migration change (D8). No CloudKit and no change to the S0 spike.
- `.mine` behaves exactly as today: every scope check defaults to `.mine`.
- No mirror rows ever enter your library except through `copyCookbookRecipe`.

### Tests

- **Package:** `YesChefSchema.migrator()` registers the same identifiers in the same order as before, checked against
  a list captured from `main`. A mirror from an older migration list is recreated, not migrated. A plain `write` on
  the mirror throws, and `apply` succeeds while an observation on the same pool sees the change. Applying the same
  bundles twice changes nothing. A republished bundle with a removed line deletes that line. A deleted recipe takes
  its children and both directions of its related pairs. A related pair inserts whichever recipe arrives second.
  Labels are pruned when unused. A `CookbookFile` with one version-3 payload loads the rest and counts one skipped.
- **App (`YesChefTests`):**
  - A `RecipeDetailModel` built in cookbook scope reads the mirror while `defaultDatabase` outside it is a different
    database, and it writes nothing to that database.
  - Scale changes in cookbook scope don't persist.
  - `CookbookCopyModel` copies into the library database, not the mirror, and takes the Open Mine / Copy Anyway
    branch when a copy exists.

### Done when

- `scripts/check-drift.sh` is green, the generic iOS build passes, and `YesChefTests` passes on a simulator (this
  slice changes App-layer models; guardrail #9).
- The PR body has the database-access list (item 6) and the write-affordance list (item 7).
- Closeout (ADR-0005 D16) runs with `--keep-brief`. It ticks S2, appends the device pass below, and advances
  `NEXT_UP.md` per ADR-0005 D12.

### Device pass (Jon and Wendy, about 30 minutes)

Both devices run **Yes Chef Dev**, as in S0.

1. **Jon's iPad:** Settings › Developer › **Export My Cookbook File**, then AirDrop it to Wendy's iPhone.
2. **Wendy's iPhone:** **Load Cookbook File**. The log shows about 2,200 applied and 0 skipped, with the time.
   **Family Cookbooks** appears, with Jon's Recipes.
3. Browse Jon's Recipes: search, sort by rating, filter by a label in two facets, filter by time and by source. The
   results match the same filters on Jon's iPad. Open the Power Browser on it.
4. Open a recipe with a photo, a variation and a linked serve-with. Scale it, view the variation, and follow the
   serve-with link (it stays in Jon's cookbook). There's no edit, rate, chat, menu or grocery action anywhere.
   Reopen the recipe: the scale isn't remembered.
5. **Copy to My Recipes.** It opens in Wendy's own library with fresh ratings, the variation intact, labels in her
   own facets, and the source reading "Copied from Jon's cookbook". Back in the cookbook, the recipe shows
   **In My Recipes**, and **Copy Anyway** makes a second, independent copy.
6. Edit Wendy's copy. Jon's cookbook entry doesn't change. The copy reaches Wendy's other device through normal sync.

## S2b — Visiting fixes from the S2 device pass

Jon's S2 device pass (2026-11-14) mostly worked and found three gaps. The architect fixed one in #516: the
reader's button now always runs the copy, so **Copy Anyway** can be reached. This slice fixes the other two. A
cookbook's Recipes view had no filter or sort buttons, and nothing showed that a copy came from Jon's cookbook.
No schema change.

### Where things are (architect, 2026-11-14, `origin/main` 206a635)

- `YesChefApp/AppMainLayout.swift`: `cookbooksTab` (line 164) hosts `FamilyCookbooksView`. `RecipesTab` (line 224)
  is the pattern to follow: a `NavigationSplitView` placed directly in the tab, with `RecipeListView` in the sidebar.
  `RecipeListView` brings its own Filter, Sort and View Options toolbar (`RecipeLibraryView.swift` line 628) and
  hides Workbench and Archived outside `.mine`.
- `YesChefApp/CookbookLibrary.swift`: `FamilyCookbooksView` (line 138) is a `NavigationStack` of cookbooks that
  **pushes** `CookbookRecipesView` (line 175). That view switches between a `NavigationSplitView` (Recipes) and
  `PowerBrowserView`, which brings its own stack or split view (`PowerBrowserView.swift` line 14). It puts the
  Recipes / Power Browser picker in a `.principal` toolbar outside both. SwiftUI doesn't support a split view
  pushed inside a stack, and the sidebar's toolbar is dropped. That's the missing filter and sort.
- `YesChefPackage/Sources/YesChefCore/RecipeRepository+CookbookCopy.swift` line 97 writes
  `importedFrom: "Copied from \(ownerName)'s cookbook"` and `dateImported`. Nothing in `YesChefApp/` reads
  `importedFrom` or `dateImported`.
- `YesChefApp/RecipeReaderSupportingViews.swift`: `SourceMetadataView` (line 4). The reader uses it at
  `RecipeDetailView.swift` lines 596, 615 and 697.

### Build

1. **The cookbook tab shows the cookbook at its root.** Drop the `NavigationStack` and the push.
   `FamilyCookbooksView` holds the selected cookbook by owner name. It defaults to the first one, and falls back
   to the first if the selected one disappears. It shows that cookbook directly in the tab:
   - **Recipes:** the `NavigationSplitView` built the way `RecipesTab` builds it. The list column's toolbar is
     `RecipeListView`'s own, so Filter, Sort and View Options appear exactly as they do in your Recipes tab.
   - **Power Browser:** `PowerBrowserView` as it is.
   - The header bar (the existing `safeAreaInset`, "Jon's Recipes · read-only · loaded <date>") also holds the
     Recipes / Power Browser segmented control. When there's more than one cookbook, it also has a menu for
     choosing one. Remove the `.principal` toolbar, so no toolbar is applied outside the split view or the Power
     Browser's own navigation.
   - Keep one `CookbookLibraryModels` per selected cookbook, made again when the selection changes. Keep the
     `recipeImageDatabase` environment value and the filter sheet.
2. **A copy shows where it came from.** In `YesChefCore`, `CookbookProvenance` is the only code that knows the
   string's format. `importedFrom(ownerName:)` builds it, and the copy calls it in place of the literal.
   `ownerName(importedFrom:)` reads it back and returns `nil` for any other value. `SourceMetadataView` shows
   "Copied from Jon's cookbook · Nov 14, 2026" (from `dateImported`, abbreviated date, no time) when the source is
   a cookbook copy. Other `importedFrom` values, such as "Paprika HTML" and "Web Recipe Capture", stay hidden
   (Jon, 2026-11-14).

### Keep

- No schema change. The `importedFrom` string stays byte-identical, so copies made during the S2 device pass show
  their line too.
- Your own Recipes and Power Browser tabs are unchanged.
- `CookbookCopyModel` and the reader's copy button stay as #516 left them.

### Tests (package)

- `CookbookProvenance` round-trips an owner name, including one with an apostrophe ("O'Brien"). It returns `nil` for
  "Paprika HTML", "Web Recipe Capture", an empty string and `nil`.
- Extend the S1 copy test: the copy's `importedFrom` reads back as the owner through `ownerName(importedFrom:)`.

### Done when

- `scripts/check-drift.sh` is green and the generic iOS build passes. The App change is view-only, so
  `YesChefTests` isn't required (guardrail #9).
- Closeout (ADR-0005 D16) runs with `--keep-brief`. It ticks S2b, appends the device pass below, and advances
  `NEXT_UP.md` per ADR-0005 D12.

### Device pass (Jon, about 10 minutes)

Use Yes Chef Dev with Jon's cookbook still loaded from S2. Check the iPad, then the iPhone:

1. **Family Cookbooks** opens straight to Jon's Recipes. Filter, Sort and View Options are in the list's toolbar.
   Filter by a label and change the sort. The results match the same filter and sort in your own Recipes. Switch
   to Power Browser and back.
2. Open a recipe you've already copied. **In My Recipes** shows. **Copy to My Recipes** asks **Open Mine / Copy
   Anyway**. Copy Anyway makes a second copy, and Open Mine opens the newest one.
3. Open your copy. The source shows "Copied from Jon's cookbook" and the date, next to the original source.

## S3 — Publish

S3 gets your library into your cookbook zone and keeps it current: the publisher (D4) and Settings › Family
Cookbook with Share My Recipes, sharing status and Publish Now. Viewers still load the S2 file until S4 fetches
from the zone. Until S4 ships, the Settings screen appears only in Yes Chef Dev.

### Where things are (architect, 2026-11-14, `origin/main` 206a635)

- `YesChefApp/CookbookSpike.swift` (DEBUG, S0, disposable; take what works):
  - `createShare` (line 105) makes the `Cookbook` zone and the zone-wide share.
  - `publish(count:)` (line 135) saves in batches of 400 with `.changedKeys`, with a `payload` `CKAsset`, a
    `contentHash` and a `profile` record named `"profile"`. Its hash is of *uncanonical* JSON, so S3's first
    publish re-uploads everything. That's expected.
  - `CookbookSharingController` (line 406) wraps `UICloudSharingController`, limited to private and read-only.
  - The app and scene delegates (line 452) accept shares.
- `YesChefPackage/Sources/YesChefCore/CookbookPayload.swift`: `bundles(in:)` (line 7) leaves out archived recipes,
  and so does `bundle(for:in:)` (line 92). `encodedPayload` (line 132) is canonical, sorted JSON. `contentHash` is
  at line 156. Bundles keep `thumbnailData` and drop `displayData` (line 80).
- `Recipe.coverPhotoID` and `RecipePhoto.displayData` (`Models.swift` lines 30 and 860).
- `YesChefApp/YesChef.entitlements` (Release) lists only the library container. `YesChef-Dev.entitlements` lists
  both (S0).
- `YesChefApp/SettingsViews.swift`: the Library section (line 70) and Developer section (line 77). `SettingsPane` is
  at `AppNavigationModels.swift` line 161.
- `YesChefApp/ChatAccessFolderClient.swift`: the precedent for a dependency client.
- `YesChefPackage/Sources/YesChefCore/CloudSync.swift`: the library's `SyncEngine`. **Don't touch it.**

### Build — core (`YesChefCore`, package tests)

1. **Record shape**, defined in one place:
   - `CookbookRecipe`, whose record name is the recipe ID's `uuidString`. Its fields are `payload` (`CKAsset` of
     `encodedPayload`), `contentHash`, `payloadVersion` (Int), and `displayImage`. `displayImage` is a `CKAsset`
     of the cover photo's `displayData`, or the first photo's by `sortOrder` if there's no cover. It's `nil` when
     the recipe has no photo.
   - `CookbookProfile`, record name `"profile"`: `displayName`, `recipeCount`, `payloadVersion` and
     `publishedAt`.
   - The hash covers the payload only. A new photo changes the payload's photo rows and thumbnail, so it uploads
     again.
2. **`CookbookPublishPlan`**, pure. It takes the library's bundles and the zone's `[recordName: contentHash]` and
   returns:
   - the records to save: recipes that are new or whose hash differs;
   - the record names to delete: any `CookbookRecipe` name that isn't a current library recipe, which covers
     archived and deleted recipes and the spike's leftovers.
   The profile isn't part of the plan.
3. **`CookbookPublisher`.** CloudKit sits behind a dependency client, so the plan and the run are tested without
   a network. One run:
   - Read every `CookbookRecipe`'s `contentHash` with a zone-changes fetch from a `nil` token and
     `desiredKeys: ["contentHash"]`. That needs no query index.
   - Build the bundles off the main actor and plan.
   - Save in batches of 400 with `.changedKeys`. Set every field, including `nil`, so a removed display image is
     cleared. Then delete, then save the profile.
   - Report progress as `published n of total`.
   Only one run happens at a time, and a trigger that arrives during a run causes one follow-up run.
   - `zoneNotFound` means sharing is off: stop without an error.
   - Per-record failures are counted and stop the run as an error that names the count and the first
     `CKError`, by name. Quota exceeded is the same. No local "what I published" state is kept: the next run plans
     again (D4).
4. **`CookbookParticipants`.** It turns a `CKShare`'s participants into display rows: name, then "invited" or
   "accepted", then "read-only" or "read-write", in words, never raw values (ADR-0071 § S0 result).

### Build — app

5. **When a device publishes.** A device publishes while the cookbook zone exists in its private database. It
   checks once per launch and caches the answer for the session, so both of Jon's devices publish without any
   per-device setup. A device that has never shared makes one zone lookup at launch and nothing more. A run
   starts:
   - at launch and on foreground;
   - from **Publish Now**;
   - 2 minutes after the last library write. Use GRDB's `DatabaseRegionObservation` over the tables `CookbookPayload`
     reads. Writes that arrive through sync count too; the hash comparison makes a duplicate run a no-op.
6. **Settings › Family Cookbook**: a new `SettingsPane`, `.familyCookbook`, in its own section. It's DEBUG-only
   until S4.
   - **Name shown to family**: a text field, required before sharing. It's stored in the `CookbookProfile`
     record, and filled in from that record when the record exists.
   - **Share My Recipes**: creates the zone and a zone-wide share if they're missing. The share is titled
     "<name>'s Recipes", with public permission none. It reuses the S0 zone and share if they exist, presents
     the sharing controller (private and read-only, as the spike does), and starts a publish.
   - **Status**: participants as `CookbookParticipants` rows, the recipe count, and one of "Published 3 min ago"
     (from the profile's `publishedAt`), "Publishing 1,200 of 2,223", or the error. Errors stay on screen until
     the next run succeeds ([[no-dead-data]]: never quietly green).
   - **Publish Now**.
   - **Stop Sharing**: after a confirmation, deletes the zone, which removes the share and every record.
   The model is `@Observable @MainActor`, and the view binds and delegates (guardrail #2).
7. **Entitlement.** Add the cookbook container to `YesChef.entitlements` (Release), as S0 planned. Leave the share
   extension alone.
8. **Spike.** Remove the spike's Create Share, Publish N and Republish One, which are replaced. Keep Fetch Changes,
   Reset Token, Try to Write, Delete My Cookbook, the share acceptance and the log. The device pass uses them on
   Wendy's phone, and S4 replaces them.

### Keep

- No synced table, column or migration (D8). `CloudSync.swift` isn't touched. The publisher only reads the library.
- No local publish state, and no change to the mirror or `CookbookCopyModel`.
- Failures are loud, never swallowed.

### Tests

- **Package:**
  - A new recipe is saved, and an unchanged hash is skipped.
  - A changed hash is saved.
  - An archived recipe and a deleted recipe are both deleted from the zone, and so are non-UUID record names
    (spike leftovers). The profile is never deleted.
  - Planning the same library twice is empty the second time.
  - The record mapping round-trips the payload to the same bundle.
  - `displayImage` uses the cover, falls back to the first photo, and is `nil` with no photos.
  - The participant rows use words.
- **App (`YesChefTests`)**, with a fake client:
  - Publish Now reports progress and ends published.
  - A partial failure shows an error with the count.
  - With no zone, a launch trigger doesn't publish.
  - Two triggers during a run cause exactly one follow-up run.

### Done when

- `scripts/check-drift.sh` is green, the generic iOS build passes, and `YesChefTests` passes on a simulator. This
  slice adds App-layer models (guardrail #9).
- The PR body lists the held op: deploy `CookbookRecipe` and `CookbookProfile`, with S3's fields, to the cookbook
  container's **Production** schema before the first TestFlight build that shows Family Cookbook. The architect
  files it under Held in `device-passes.md`.
- Closeout (ADR-0005 D16) runs with `--keep-brief`. It ticks S3, appends the device pass below, and advances
  `NEXT_UP.md` per ADR-0005 D12.

### Device pass (Jon, with Wendy's phone for one step, about 30 minutes)

All devices run Yes Chef Dev.

1. **Jon's iPad:** Settings › Family Cookbook. Enter "Jon", then **Share My Recipes**. The S0 share is reused, and
   Wendy shows as accepted and read-only.
2. **Publish Now.** The status counts up and ends at "Published just now", with your recipe count. Note how long
   the first publish takes, now with photos.
3. **Publish Now** again. It finishes quickly and uploads nothing.
4. Edit a recipe. Within about 2 minutes a publish of 1 runs. Archive a recipe: the count drops by one. Unarchive
   it.
5. **Jon's iPhone:** Family Cookbook shows the same name, participants and status with no setup. **Publish Now**
   uploads nothing.
6. **Wendy's phone:** Cookbook Spike › **Reset Token**, then **Fetch Changes**. The count is your recipes plus the
   profile and the share record.
7. Settings › Sync on both of Jon's devices shows no new errors.
