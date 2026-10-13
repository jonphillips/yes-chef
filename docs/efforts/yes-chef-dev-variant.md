# Effort — Yes Chef Dev: Debug builds get their own app identity; backups carry their build variant

Status: Designed 2026-10-10. **Gated on the cutover:** dispatch only after ADR-0056 Phase 4e passes
(ADR-0059 D1). Touches identifiers, entitlements and the restore path, so the architect escalates both PRs to
Jon before merge. No schema change, no migration, no sync-model change.
Summary: Implements [ADR-0059](../decisions/ADR-0059-yes-chef-dev-variant.md). After the cutover, Xcode Run
(Debug) builds **Yes Chef Dev**: its own bundle IDs, app group, URL scheme, display name and icon, so it can
sit next to TestFlight Yes Chef on the same device. It keeps the real iCloud container, which puts it on
CloudKit Development. Release doesn't change. Separately, `CloudSyncKit` backups record which build variant
exported them, and the production app refuses a development backup (this answers Galavant ADR-0050 OQ2).
Related: [ADR-0059](../decisions/ADR-0059-yes-chef-dev-variant.md) · [ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md)
/ [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) · [ADR-0058](../decisions/ADR-0058-cockpit-find-referral-transport.md)
(the Cockpit pair Dev stays out of) · Galavant's precedent: `galavant/docs/efforts/galavant-dev-variant.md`
and galavant#171. Read Galavant's diff before starting; this mirrors it, apart from the differences listed
in ADR-0059.

## Before you start (Jon's part; flag it in the PR if it isn't done)

The App IDs `com.jonphillips.yeschef.dev` and `com.jonphillips.yeschef.dev.share-extension` and the app
group `group.com.jonphillips.yeschef.dev` are registered. Before the first device run, also check:

- `iCloud.com.jonphillips.yeschef` is assigned to **both** `.dev` App IDs (CloudKit).
- `group.com.jonphillips.yeschef.dev` is assigned to both. `group.com.jonphillips.cockpit-yeschef` is
  **not** (ADR-0059 D5).

The executor's builds are compile-only (`CODE_SIGNING_ALLOWED=NO`), so they don't depend on the portal.

## Shape: two PRs, in order

Yes Chef CI checks out jon-platform `main`, so the Yes Chef PR can only go green after the jon-platform PR
merges. This is the same pattern as [`cloudsynckit-backup-lift.md`](cloudsynckit-backup-lift.md).

1. **jon-platform, branch `effort/yes-chef-dev-variant`: additive.** The backup variant marker goes into
   `packages/CloudSyncKit`. **Galavant `main` must still build and pass unchanged against it.** Check this by
   building and testing `GalavantLibrary` against the branch locally (both apps resolve `CloudSyncKit` by
   relative path).
2. **yes-chef, branch `effort/yes-chef-dev-variant`: the split, plus passing the variant.** Open it as a
   draft alongside PR 1, and mark it ready once PR 1 is on `main`. This is the completing PR.

## PR 1 — CloudSyncKit: backups record their build variant (ADR-0059 D6)

- Add `public enum DatabaseBackupVariant: Sendable, Equatable { case production, development }`.
- `DatabaseBackupConfiguration` gains `variant: DatabaseBackupVariant?`. The init parameter defaults to `nil`,
  which means today's behavior exactly: no stamp on export and no variant check on restore. That default is
  what keeps Galavant unchanged. Document that an app with a dev variant should pass a non-nil value.
- **Export.** When `variant` is non-nil, stamp `PRAGMA application_id` on the snapshot in the same write
  that stamps `user_version`. Use two fixed, non-zero `Int32` constants owned by CloudSyncKit, one per
  variant (for example ASCII `CSKP` / `CSKD`). Name them and document them as the backup-format contract.
  Don't use anything that can't be told apart from `0`. A `nil` variant leaves `application_id` alone.
- **Restore.** In the static `prepareRestore` path, before migration and therefore before the confirm alert,
  read the candidate's `application_id`. Apply ADR-0059's D6 table. The **only** refusal is a candidate
  carrying the development constant when the configuration's variant is `.production`. Throw a new
  `BackupError.developmentBackup(String)` (pass the display name), with copy along the lines of *"This
  backup came from a development build. \(displayName) won't restore it."*. Every other combination
  proceeds through the existing checks, including unmarked files, unknown values and a `nil` configuration.
  Existing checks (not-an-app-backup, schema version, participant) keep their order relative to each
  other. Put the variant check where a non-Yes Chef file still reports `notAppBackup` first.
- **Clear on install.** Reset `application_id` to `0` on the prepared store before it replaces the live
  store. The marker means "exported by", never live state.
- **Tests** (`DatabaseBackupTests`):
  - Export stamps each variant's constant. A `nil` variant leaves `0`.
  - The full D6 matrix: three markers (development, production, unmarked) × three configurations
    (`.production`, `.development`, `nil`). Only development → `.production` throws `.developmentBackup`.
  - A restored live store reads `application_id == 0`.
  - A non-app SQLite file still throws `notAppBackup`, not the new error.
- **Ledger.** Update `SEAM-LEDGER.md`'s "Post-cutover dev variant" row. Yes Chef is adopting it after its
  cut (ADR-0059 D1 reverses the row's "adopt before" wording). The second adopter means the harvest trigger
  has fired. Record that the harvest is owed; don't do it here. Add a line that Galavant adopts the variant
  marker by passing its own variant and closing its ADR-0050 OQ2.

## PR 2 — Yes Chef

### 1. Per-configuration identity in `project.yml`

Set per configuration (`configs: Debug: / Release:`) on **both** `YesChef` and `YesChefShareExtension`.
Release values must resolve to exactly what ships today. The names are suggestions:

| Setting | Debug | Release |
| --- | --- | --- |
| `PRODUCT_BUNDLE_IDENTIFIER` (app) | `com.jonphillips.yeschef.dev` | `com.jonphillips.yeschef` |
| `PRODUCT_BUNDLE_IDENTIFIER` (extension) | `com.jonphillips.yeschef.dev.share-extension` | `com.jonphillips.yeschef.share-extension` |
| `YESCHEF_APP_GROUP` | `group.com.jonphillips.yeschef.dev` | `group.com.jonphillips.yeschef` |
| `YESCHEF_DISPLAY_NAME` (app) | `Yes Chef Dev` | `Yes Chef` |
| `YESCHEF_SHARE_DISPLAY_NAME` (extension) | `Save to Yes Chef Dev` | `Save to Yes Chef` |
| `YESCHEF_URL_SCHEME` (app) | `yeschef-dev` | `yeschef` |
| `ASSETCATALOG_COMPILER_APPICON_NAME` (app) | `AppIcon-Dev` | `AppIcon` |
| `CODE_SIGN_ENTITLEMENTS` | the `-Dev` files below | the existing files |

- **Entitlements: per-configuration files, not build-setting expansion** (this is where Yes Chef departs
  from Galavant). The Release app entitlements carry the Cockpit group as a second array entry, and Debug
  must not carry it (ADR-0059 D5). An array entry can't be left out conditionally. Add
  `YesChefApp/YesChef-Dev.entitlements` and `YesChefShareExtension/YesChefShareExtension-Dev.entitlements`:
  the dev app group only, with the container and `icloud-services` literal and the same values as the
  Release files. The app file keeps `aps-environment`. **The existing Release entitlement files don't
  change by a byte.**
- **Info.plist.** The app's plist is generated from `project.yml`'s `info.properties`, so edit it there,
  never in `YesChefApp/Info.plist` (the comment in `project.yml` explains). Set `CFBundleDisplayName:
  $(YESCHEF_DISPLAY_NAME)`, set the URL scheme entry to `$(YESCHEF_URL_SCHEME)` (keep `CFBundleURLName`),
  and add `YesChefAppGroupID: $(YESCHEF_APP_GROUP)`. The extension's plist is hand-maintained
  (`INFOPLIST_FILE`): set `CFBundleDisplayName` to `$(YESCHEF_SHARE_DISPLAY_NAME)` and add the same
  `YesChefAppGroupID` key.
- **`UTExportedTypeDeclarations` don't change in either configuration.** A backup must open in both apps
  (ADR-0059 D2).
- **Icon.** Add `YesChefApp/AppIcon-Dev.icon` beside `AppIcon.icon`, using the same artwork with an orange
  **DEV** banner across the bottom that is readable at home-screen size. It's an Icon Composer bundle, so
  add the banner as a top layer in its `icon.json`. If the format won't cooperate, a single-1024
  `AppIcon-Dev.appiconset` in `Assets.xcassets` is acceptable. Don't touch `AppIcon.icon`.
- **Tests and schemes.** `YesChefTests` keeps `com.jonphillips.yeschef.tests` and is hosted by the Debug
  app. Run/Test stay Debug and Archive stays Release.
- Run `xcodegen generate` and commit the regenerated project. Never hand-edit `project.pbxproj`.

### 2. Runtime reads the app group; nothing falls back to production (ADR-0059 D3)

- `YesChefDatabaseStorage.appGroupIdentifier`
  ([DatabaseStorage.swift](../../YesChefPackage/Sources/YesChefCore/DatabaseStorage.swift)) stops being a
  literal. It reads `YesChefAppGroupID` from `Bundle.main`, which is the app's or the extension's own plist.
  Put the read behind a small pure function that takes an info dictionary, so tests don't need
  `Bundle.main`.
- **A missing or empty key is loud.** Report it with `reportIssue` and throw a `StorageError` that names the
  key. **Never fall back to `group.com.jonphillips.yeschef`.** Every store path goes through it:
  `liveSharedDatabaseURL`, the extension's open, and the backup configuration's `liveStoreURL`.
- `DatabaseChangeBeacon`'s Darwin name becomes `"\(appGroupID).databaseDidChange"`. For Release that is the
  exact string used today. A test pins it.
- **Cockpit paths don't change** (ADR-0059 D5). `FindReturnEmitter`, `RecipeLibraryView.receiveFindReferral`
  and `FindReferralMailbox`'s `scheme == "yeschef"` keep their literals. In Debug they're never reached.
- `YesChefCloudSync`'s container identifier **stays a constant** (D4). Don't parameterize it.
- `YesChefCloudSync.databaseBackupConfiguration` sets the variant under `#if DEBUG`: Debug gets `"Yes Chef Dev"`,
  `"YesChef-Dev-Backup-"` and `.development`; Release gets `"Yes Chef"`, `"YesChef-Backup-"` and
  `.production`. The other prefixes and keys don't change.
- The restore error alert shows the new `developmentBackup` message the same way it shows the existing
  errors. No new UI.

### 3. Show which build you're in

The Settings **Developer** section gets a Debug-only (`#if DEBUG`) row: *"Yes Chef Dev · CloudKit
Development"*. A screenshot then shows which world it came from. Release shows nothing new.

### 4. Tooling

- `scripts/check-drift.sh`'s bundle-ID guard: allow the two `.dev` IDs. Keep its two properties: zero hits
  must still fail, and an unknown ID must still be rejected. If you set `PRODUCT_BUNDLE_IDENTIFIER`
  through a variable instead of literal per-config values, the guard has to check the resolved values, not
  pass on `$(…)`. Literal per-config values keep the guard simple.
- `scripts/facet-taxonomy-report.sh`: default to `com.jonphillips.yeschef.dev`, because simulator runs are
  Debug, and allow an override (an env var is fine). The path argument still wins.

## Tests

1. **Package:** reading the app group from an info dictionary returns the value. A missing key and an empty
   key each report an issue (`withExpectedIssue`) and throw, and never return the production group.
2. **Package:** the beacon name for `group.com.jonphillips.yeschef` equals today's literal.
3. **Package:** the backup configuration under `#if DEBUG` (package tests run Debug) is the Dev name,
   prefix and `.development`.
4. **Build evidence (in the PR description):** a Debug/Release × app/extension table of
   `CFBundleIdentifier`, `CFBundleDisplayName`, `YesChefAppGroupID`, the URL scheme (app), the resolved
   `CODE_SIGN_ENTITLEMENTS` file with its app groups, and the icon name. Take them from the built products'
   `Info.plist` (`plutil -p`) and `xcodebuild -showBuildSettings -configuration Debug|Release`. Also
   include `git diff main --stat -- YesChefApp/YesChef.entitlements
   YesChefShareExtension/YesChefShareExtension.entitlements YesChefApp/AppIcon.icon`, which must be empty.
   This is the evidence that **Release didn't change**.

## Verification

Follow [`verification.md`](../verification.md):

- PR 1: CloudSyncKit `swift test` through `quiet-run`, plus `GalavantLibrary` building and testing against
  the branch, unchanged.
- PR 2: `scripts/check-drift.sh`, `YesChefTests` on a simulator (the host app's identity changes), and the
  generic iOS build in **both** configurations: the usual
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO build` with `-configuration Debug`, then again with `-configuration Release`.
  Compile-only, no installs.

## Done when

- jon-platform PR merged, then the Yes Chef PR on `effort/yes-chef-dev-variant`, green, with the evidence
  table from test 4.
- **Escalate:** both PRs touch identifiers, entitlements or restore. The architect reviews, then hands each
  to Jon for merge.
- The completing (Yes Chef) PR:
  - adds a DONE-LOG entry;
  - marks this brief Done in `docs/efforts/README.md`, and ADR-0059 Accepted (status line and the
    `decisions/README.md` entry);
  - ticks the ADR-0059 item under **Post-cut** in `PROD-CUTOVER.md`;
  - adds to `docs/device-passes.md`: *Xcode Run on the iPhone installs "Yes Chef Dev", with the DEV icon,
    **next to** TestFlight Yes Chef. Each opens its own library. The share sheet lists "Save to Yes Chef"
    and "Save to Yes Chef Dev", and each saves into its own app. Yes Chef Dev's Settings shows "CloudKit
    Development". A backup exported from Yes Chef Dev is **refused** by TestFlight Yes Chef with the
    development-backup message. A TestFlight backup restores in Yes Chef Dev. A Cockpit Find referral
    still opens TestFlight Yes Chef.* Add a one-line pointer under **Owed** in `NEXT_UP.md`;
  - sets `docs/NEXT_UP.md` to `Nothing dispatched.`

## Out of scope

- Galavant adopting the variant marker and closing its ADR-0050 OQ2 (Galavant's own one-line change).
- Harvesting the per-config recipe into jon-platform `docs/ios/` (the ledger records that it's owed).
- Resetting the Development environment (ADR-0059 OQ1 / ADR-0056 OQ2, Jon's console step).
- Any Release identifier, the container, or the Cockpit contract.

## Ticket (the architect sets this in `NEXT_UP.md` after Phase 4e)

```
# Next Up — Yes Chef Dev: Debug builds get their own identity; backups carry their variant

**Slices:** effort `yes-chef-dev-variant`: two PRs on branch `effort/yes-chef-dev-variant`, jon-platform
(CloudSyncKit, additive) first, then Yes Chef
**Briefs:** `docs/efforts/yes-chef-dev-variant.md` · decision `docs/decisions/ADR-0059-yes-chef-dev-variant.md`
**Done when:** per the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's portal check (container on both `.dev` App IDs, Cockpit group on neither) before the first
device run. Identifiers, entitlements and restore: the architect escalates both PRs to Jon before merge.
**Notes:** Release must not change by a byte (evidence table). No fallback to the production app group.
Galavant `main` must build unchanged against PR 1. Start from a fresh `main` in both repos.
```
