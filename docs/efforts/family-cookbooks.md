# Effort — Family cookbooks

Status: Ready
Summary: S0 is a debug-only spike: a second CloudKit container, a zone-wide read-only share from one Apple ID to another, a 2000-record publish and fetch, timed, with library sync left untouched. S1–S4 get briefed after its device result.

Origin: Jon, 2026-11-13. Decision: [ADR-0071](../decisions/ADR-0071-family-cookbooks.md). This brief holds the slice
plan; the ADR holds the why. **S0 is a spike.** Its code is debug-only and disposable. S3 and S4 rebuild the
publisher and fetcher in `YesChefCore` with tests, and may take from the spike what survives.

## Ledger

- [ ] **S0** — transport spike (this brief, below)
- [ ] **S1** — bundle v2 and copy-import (ADR-0071 § Order; briefed after S0)
- [ ] **S2** — mirror database and read-only visiting
- [ ] **S3** — publish
- [ ] **S4** — accept and fetch

## Where things are (architect, 2026-11-13, `origin/main` e5b3143)

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
