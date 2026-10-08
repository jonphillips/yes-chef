# Effort — Lift backup & restore into `CloudSyncKit`

Status: Done 2026-10-06 (jon-platform #66, yes-chef #341). Schema-free (no table or column changes), but **touches sync**, so the architect
escalates both PRs to Jon before merge.
Summary: Move `YesChefDatabaseBackup` (ADR-0030) and the restore hold out of Yes Chef into jon-platform's
`CloudSyncKit`, per jon-platform ADR-0006, so Galavant can adopt it for its CloudKit Production cutover. It is
a move, not a copy. Two additions ride along: an owner-only restore guard (D3) and a schema-version marker that
survives a migration squash (D4). Yes Chef's behavior and its backup files are unchanged.
Related: [ADR-0030](../decisions/ADR-0030-local-backup-and-restore.md) (the design being moved) ·
[ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md) (the cutover that depends on it; D4
must land before its squash) · jon-platform `docs/adr/0006-lift-backup-restore-into-cloud-sync-kit.md` (the
decision, read it first) · jon-platform `docs/adr/0003-extract-cloud-sync-kit.md` (the facade pattern this
follows)

## Shape: two PRs, in order

Yes Chef CI checks out jon-platform `main`, so the Yes Chef PR can only go green after the jon-platform PR
merges.

1. **jon-platform, branch `effort/cloudsynckit-backup-lift`: additive.** New code in
   `packages/CloudSyncKit`. Nothing existing is renamed or made required: **Galavant `main` must still build
   unchanged against it.** Check by building `GalavantLibrary` against the branch locally (both apps resolve
   `CloudSyncKit` by relative path).
2. **yes-chef, branch `effort/cloudsynckit-backup-lift`: the rewire.** Delete the moved code, forward through
   the `YesChefCloudSync` facade, keep the views. Open it as a draft alongside PR 1 and mark it ready once
   PR 1 is on `main`.

This replaces the usual one-PR-per-dispatch, as the ADR-0003 lift did. The Yes Chef PR is the completing PR:
it ticks this brief, adds the `DONE-LOG.md` entry, and sets `NEXT_UP.md` to `Nothing dispatched.`

## What moves (jon-platform PR)

From `YesChefCore/DatabaseBackup.swift`, `DatabaseStorage.swift` and `CloudSync.swift`:

- the snapshot, restore preparation, live-store swap, sidecar and metadatabase removal, and pre-restore
  snapshot, undo, and stale-candidate cleanup;
- the metadatabase lookup (`pragma_database_list`, plus the naming fallback);
- `YesChefDatabaseBackupExportModel` and `YesChefDatabaseBackupRestoreModel`, de-prefixed and taking a
  configuration. **Keep `isPrepared` read-only**, along with its doc comment (the alert-binding bug it records
  is why);
- the restore hold: `disableForRestore`, `isDisabledByRestore`, clearing the hold when sync is deliberately
  enabled, and **skipping the launch-environment mirror while held**. These become `CloudSync` functions
  taking the `CloudSyncConfiguration`, next to the existing switch.

**Configuration.** Per-app values the facade supplies. Names are suggestions; pick what reads best beside
`CloudSyncConfiguration`:

| Value | Yes Chef |
| --- | --- |
| display name for errors | `Yes Chef` |
| filename prefixes (backup, pre-restore, restore staging) | `YesChef-Backup-`, `YesChef-PreRestore-`, `YesChef-Restore-` |
| identifying tables | `recipes` (plus `grdb_migrations`, which the kit always requires) |
| live store URL | `YesChefDatabaseStorage.liveSharedDatabaseURL()` |
| migrate closure | `DependencyValues.migrateRestoreCandidate(at:)` |
| declared schema version (D4) | today's applied-migration count |
| restore-hold defaults key | `YesChefCloudKitSyncRestoreRequiresManualEnablement`, **exact string** |
| last-pre-restore defaults key | `YesChefDatabaseBackupLastPreRestorePath`, **exact string** |

The two defaults-key strings must not change. A device in the middle of a restore hold, or holding an
undoable restore, would otherwise lose that state on update. Adding the hold key to `CloudSyncConfiguration`
must stay source-compatible (optional, or a separate backup configuration), which is how Galavant `main` keeps
building.

## D3: owner-only restore guard (new)

SQLiteData's own test is `zoneID.ownerName == CKCurrentUserDefaultName` (`SyncEngine.swift`), and
`SyncMetadata` (`sqlitedata_icloud_metadata`) stores `ownerName` and `isShared` per row.

- **Live-store check, before preparing a restore:** any metadata row whose `ownerName` is not
  `CKCurrentUserDefaultName` → refuse with *"This device has a library shared with you by someone else. Only
  that library's owner can restore it."*
- **Snapshot marker:** at export, write a one-row marker table into the **snapshot only** recording whether
  the live store held foreign-owned rows. `prepareRestore` reads it, **drops it** before migrating (it must
  never reach the live store), and refuses a file marked foreign-owned. A file with no marker is a pre-lift
  backup and counts as owner-made, since Yes Chef has never shared.
- **Owner holding shares** (any `isShared` row): restore proceeds, and the restore model exposes a flag the
  app's confirmation can use to say shares may need re-sending. Yes Chef never sets it, so its copy is
  unchanged.
- Keep both predicates as pure queries over a `Database` so they test without CloudKit. If seeding a
  metadata table in a test needs a live engine, test against a fixture database with the same table shape.

## D4: a declared schema version

Today `schemaVersion(in:)` counts `grdb_migrations` rows and the snapshot stamps that in `PRAGMA
user_version`. ADR-0056's baseline squash would give a fresh install a lower count than an old device's
backup, so the fresh install would refuse it.

- The facade declares the current schema version. **Yes Chef's value is today's applied-migration count**, so
  every existing backup (stamped with the count) remains valid as-is.
- A backup's version is its stamped `user_version`. Still validate that it is a SQLite file with
  `grdb_migrations` and the identifying tables. Refuse a stamp of 0, or one above the declared version.
- After migrating a candidate, stamp the declared version.
- Add a Yes Chef test that the declared version equals the migrator's registered count. ADR-0056's squash PR
  then owns changing that rule, and the test makes it impossible to forget.

## Yes Chef PR (the rewire)

- `YesChefDatabaseBackup*` symbols go. `SettingsViews.swift` and `SyncStatusSection.swift` call the kit's
  models through the facade. **The UI and its copy are unchanged.**
- `YesChefCloudSync` keeps `migrateRestoreCandidate` (it is Yes Chef's migrator) and gains the configuration
  values above.
- Generic backup tests now live in the kit. Yes Chef keeps the ones that are about Yes Chef: its configuration
  identifies a Yes Chef store, rejects a non-Yes Chef SQLite file, and a seeded store with photo BLOBs
  round-trips through snapshot, prepare, and restore.

## Done when

- `CloudSyncKit` carries backup and restore, with the D3 guard and D4 version, and its tests cover every case
  `DatabaseBackupTests.swift` covers today plus D3 (foreign-owned live store refused, marked file refused,
  marker dropped before the swap, `isShared` flag raised) and D4 (a count-stamped pre-lift backup restores, a
  newer one is refused, a candidate is stamped with the declared version after migrating).
- Galavant `main` builds unchanged against the jon-platform branch.
- Yes Chef has no copy of the moved code, its tests are green, and backups exported before the lift still
  restore.
- No UI or copy changes in Yes Chef.

## Verification

- jon-platform: `swift test` in `packages/CloudSyncKit` through `quiet-run`. Plus `swift build` of Galavant's
  `GalavantLibrary` against the branch.
- Yes Chef: per [`../verification.md`](../verification.md). This changes `YesChefApp/` call sites and package
  model code, so run the generic app build and the `YesChefTests` target, elevated on the first attempt.

## Out of scope

- The enforced quiesce procedure (ADR-0030 Amd 3). Still a follow-on; it belongs in the kit when built.
- Moving the Settings rows into the kit (converge later, per ADR-0006 D2).
- Galavant's adoption (Galavant ADR-0049 S1, dispatched separately once this merges).
- ADR-0056's squash itself.
