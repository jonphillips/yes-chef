# Effort — Automatic daily backups (S1: `CloudSyncKit` + Yes Chef)

Status: **Complete** — 2026-10-25. Schema-free. It publishes the iCloud container to Files and owes device gates,
so the architect escalates the Yes Chef PR to Jon.
Summary: Yes Chef backs itself up. When the app comes to the foreground and the newest automatic backup is over
24 hours old, `CloudSyncKit` takes the same `VACUUM INTO` snapshot a manual export takes and writes it to
iCloud Drive › Yes Chef › Backups. It keeps 14 daily and 6 monthly snapshots and never prunes the last one
taken before the library shrank by half. Settings shows the last backup and has Back Up Now. Two PRs:
jon-platform (additive), then Yes Chef.
Related: jon-platform `docs/adr/0008-automatic-scheduled-backups.md` (the decision; read it first, D1–D10) ·
jon-platform `docs/adr/0006-lift-backup-restore-into-cloud-sync-kit.md` (the snapshot and restore this reuses) ·
[`cloudsynckit-backup-lift.md`](cloudsynckit-backup-lift.md) (the same two-PR shape) ·
[ADR-0060](../../decisions/ADR-0060-chat-access-over-mcp.md) D2 (the container, now published) ·
[ADR-0059](../../decisions/ADR-0059-yes-chef-dev-variant.md) (Dev shares the container; ADR-0008 D10)

## Shape: two PRs, in order

Yes Chef CI checks out jon-platform `main`, so the Yes Chef PR goes green only after the jon-platform PR merges.

1. **jon-platform, branch `effort/automatic-backups`: additive.** New code in `packages/CloudSyncKit`. Nothing
   existing is renamed or made required. **Galavant `main` must still build unchanged** (build
   `GalavantLibrary` against the branch locally).
2. **yes-chef, branch `effort/automatic-backups`: adoption.** Open it as a draft alongside PR 1. Mark it ready
   once PR 1 is on `main`. It's the completing PR: it ticks this brief, adds the `DONE-LOG.md` entry, adds the
   device pass, and sets `NEXT_UP.md` to `Nothing dispatched.`

## Kit PR (jon-platform)

Names are suggestions. Pick what reads best beside `DatabaseBackupConfiguration`.

- **Configuration, optional and additive.** An `AutomaticBackupConfiguration` the facade passes or doesn't
  (`nil` = off, which is how a Dev variant opts out, D10): the backup filename prefix (`YesChef-Auto-`), the
  library-count table (`recipes`), retention (`daily: 14, monthly: 6` default), the install-id defaults key,
  and the on/off defaults key. The container is `cloudSync.containerIdentifier`. The folder is
  `Documents/Backups/`.
- **The routine** (D1–D4). `runIfDue()` and `backUpNow()`. In order: the toggle is on; no restore is preparing
  or restoring; the live store holds no foreign-owned rows (`containsForeignOwnedRows`); the container URL is
  non-nil (resolved off the main actor); the newest automatic file in the folder is over 24 h old (skipped by
  `backUpNow()`). Then `DatabaseBackup.snapshot` into a temporary file, `validateAppSchema` on the result,
  count the library-count table, and move it into the folder with an `NSFileCoordinator` write as
  `<prefix>YYYY-MM-DD-<install>.sqlite`. `<install>` is 4 characters of a random id kept under the
  install-id key. No colons in any name. Prune only after a validated snapshot lands.
- **The manifest and the shrink pin** (D6). `Backups/manifest.json`, one entry per snapshot: filename, date,
  bytes, row count. A new count below half the previous one pins the previous file and raises a warning
  until it's dismissed. A missing or unreadable manifest is rebuilt from the filenames with unknown counts.
  It never blocks a backup.
- **Pruning** (D5) as a pure function: entries + now + calendar + policy + pins → the files to delete. Keep
  the newest per day for the 14 most recent days *that have a file*, the first of each of the 6 most recent
  months, and every pinned file. **It only ever matches the automatic filename pattern.** A manual export
  saved in the same folder is never touched.
- **`AutomaticBackupModel`** (`@Observable`, dependency-backed, D7). Its status is one enum: never run · last
  backup (date, bytes) · not running (iCloud Drive unavailable, participant device, restore in progress,
  turned off) · failed (message). It also carries the shrink warning, `isRunning`, `backUpNow()`, and
  `dismissShrinkWarning()`. No flag soup.
- **A file-system seam.** The container URL, the listing, and the coordinated move sit behind a dependency, so
  tests run against a temporary directory with an injected clock. Discovery on device uses `NSMetadataQuery`
  (as ADR-0060 S1 does). A listing that lags only risks a second same-day file, which the install suffix
  and pruning absorb.

## Yes Chef PR

- **Publish the container.** In `project.yml`'s `YesChef` `info.properties` (never by hand in
  `YesChefApp/Info.plist`; see the comment on `UTExportedTypeDeclarations`), add `NSUbiquitousContainers` →
  `iCloud.com.jonphillips.yeschef` → `NSUbiquitousContainerIsDocumentScopePublic: true`,
  `NSUbiquitousContainerName: Yes Chef`, `NSUbiquitousContainerSupportedFolderLevels: Any`. The entitlement
  already exists (ADR-0060). `MCP/` is outside `Documents/` and stays hidden.
- **Facade:** `YesChefCloudSync` gains the automatic configuration: `YesChef-Auto-`, `recipes`, 14/6, and keys
  `YesChefAutomaticBackupInstallID` and `YesChefAutomaticBackupEnabled` (default on).
- **Trigger:** call `runIfDue()` when the scene becomes active, at the app root next to the existing
  `scenePhase` handling. Never on the main actor's critical path.
- **Settings:** in the existing Backup section, add an **Automatic Backups** toggle, a status line ("Last
  backup: today, 9:14 AM · <size>", or the not-running reason), **Back Up Now**, and the shrink warning with a
  dismiss. Manual Export and Restore are unchanged.
- **Device pass:** add an "Automatic backups" block to `docs/device-passes.md` with ADR-0008's gates G1, G2,
  G3, G4, G6, and G7 (G5 is Galavant-only; G8 is S3). G1 records whether Files needed a `CFBundleVersion` bump
  and the snapshot's size on Jon's iPhone.

## Done when

- `CloudSyncKit` has the routine, manifest, pruning, shrink pin, and model. Tests cover: due and not due at
  24 h; skipped for each not-running reason; a participant store writes nothing; a nil container writes
  nothing and reports it; names carry the install suffix and no colons; retention across a sparse month and
  a dense one; manual exports survive pruning; a halved count pins the previous file and warns; a lost
  manifest rebuilds; a failed snapshot leaves no partial file and prunes nothing.
- Galavant `main` builds unchanged against the jon-platform branch.
- Yes Chef publishes its container, runs the routine on foreground, and shows the rows. An automatic file
  restores through the existing importer and restore flow (a Yes Chef test: snapshot with the automatic
  routine into a temporary folder, then prepare and restore it).
- No change to manual export, restore, or their copy.

## Verification

- jon-platform: `quiet-run swift test --package-path packages/CloudSyncKit`, plus `swift build` of Galavant's
  `GalavantLibrary` against the branch.
- Yes Chef: per [`../verification.md`](../../verification.md). Run `xcodegen generate` (new sources and an
  `info` change), the generic app build, and the `YesChefTests` target, elevated on the first attempt.

## Out of scope

- Galavant's adoption: ADR-0008 S2, dispatched in Galavant once this merges.
- The "Back Up Now" App Intent and its Shortcuts automation (ADR-0008 S3, D8).
- An in-app picker for automatic snapshots (ADR-0008 OQ3) and any off-account Mac copy (OQ4).
- `BGTaskScheduler`, compression, and any local fallback when iCloud Drive is off. All are rejected in
  ADR-0008.
