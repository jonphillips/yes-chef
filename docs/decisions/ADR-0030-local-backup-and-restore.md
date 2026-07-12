# ADR-0030 — Local backup & restore: a CloudKit-independent durability net

> **One-line:** The whole ~2,163-recipe library — including every image — lives in exactly two
> places today: the devices and the **CloudKit Development** private zone. There is **no user-facing
> export**, so a bad migration, a Development-environment reset, or a device-migration mishap could
> lose it with no way back. Add a **backup that does not depend on CloudKit**: a consistent
> whole-database snapshot (`VACUUM INTO` a single `.sqlite` file) the user writes to Files / iCloud
> Drive, plus a restore that reads one back. Images ride along for free — they are BLOBs **inside**
> the database file, not separate assets — so this is a byte-exact copy, **not** a serialization
> surface. A structured/portable (JSON) export is an explicitly separate, later concern.

Status: **Proposed** — 2026-07-12. Extends **[ADR-0001](ADR-0001-persistence-sqlitedata.md)**
(SQLiteData persistence) and **[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (CloudKit sync, no
server). Depends on the images-in-DB model from **[ADR-0005](ADR-0005-image-storage-and-processing.md)**.
Motivated by [[post-browser-sync-vs-features-tension]] (the solvable sync/**backup** gate) now that
sync itself round-trips E2E (M4). De-risks the held **prod-schema promotion** ops step in
`docs/CURRENT_HANDOFF.md`. Related cautionary context: **[[debug-erase-vs-sync-triggers]]**,
**[[llm-vs-determinism-surface-boundary]]**.

## Context

Sync is done and holding — two-device E2E round-trip, honest status indicator (ADR-0028), footguns
gated. What is **not** covered is durability *independent of CloudKit*:

- **Single logical copy.** The library exists on the devices and in one CloudKit private zone. We
  deliberately stay in the CloudKit **Development** environment so the schema keeps evolving; but
  Development can be reset, and every device is a peer of the same zone, so a corruption or an
  erroneous erase can propagate rather than protect. There is no snapshot that sits *outside* the
  sync system.
- **No export exists.** Audited on main: `PaprikaRecipeBackupSupplement` is *import* (one-way in),
  `Exports.swift` is module re-exports, and the only "export" symbol is a per-recipe debug DOM dump
  (`OriginalSnapshotView`). Nothing writes the whole library anywhere the user controls.
- **The storage shape makes this easy.** The entire library is a **single WAL-mode SQLite file** —
  `YesChefDatabaseStorage.databaseFileName = "SQLiteData.db"` in the app-group container
  (`group.com.jonphillips.yeschef`). Crucially, **images are stored as BLOBs in the row**
  (`RecipePhoto.displayData` / `.thumbnailData`, `Models.swift`), not as files on disk. So one file
  is the whole thing — recipes, menus, meal plans, notes, and every photo byte. A copy of that file
  is a complete, verifiable backup with **zero serialization code** to drift out of sync with the
  model.

This reframes the initial "serialization pass" instinct: for a *durability net*, copying the
database beats re-encoding it. Re-encoding to JSON is a large, error-prone, per-model surface (44k+
rows) and is exactly the reproducible-data-merge shape [[llm-vs-determinism-surface-boundary]] says
to keep deterministic — a whole-DB copy sidesteps that surface entirely.

## Decision

**1. Backup = a consistent whole-database snapshot to a single file.**
Produce a self-contained `.sqlite` file via SQLite `VACUUM INTO` (or GRDB's
`DatabaseWriter.backup`), which reads a **consistent transaction** and folds any `-wal`/`-shm` state
into one file — no torn snapshot even while the app is writing. The user chooses the destination
(Files / iCloud Drive / AirDrop) through `fileExporter` / a document picker; the app never silently
phones a file home. Default filename carries a timestamp, e.g. `YesChef-Backup-2026-07-12.sqlite`.
This captures **every** synced *and* local table and every image BLOB, byte-for-byte.

**2. Exclude sync-internal state from what a restore trusts.** The live DB carries SQLiteData's
SyncEngine metadata and the `PendingRecordZoneChange` bookkeeping (the tables ADR-0028 and
[[extension-sync-construct-not-run]] revolve around). A restored file must **not** masquerade as an
already-synced peer of the CloudKit zone. Chosen approach (see OQ1): the snapshot may contain those
tables, but **restore strips/ignores sync metadata and lands the app data into a fresh local store
with sync disabled**; the user then re-enables sync, which reconciles the restored rows against
CloudKit through the normal path. This keeps restore a *local* operation and never risks a restore
stomping the cloud.

**3. Restore = import one snapshot, deliberately and reversibly.** Restore is a destructive,
explicitly-confirmed action (it replaces the current local library). Before swapping, the app takes
an **automatic pre-restore snapshot** of the current store so a mis-click is undoable. Restore
validates the incoming file (is it a YesChef DB? is its schema version restorable by the current
migrator?) before touching the live store.

**4. Manual first; automatic later.** S1/S2 ship a Settings affordance — "Export a backup" and
"Restore from a backup." **Automatic/periodic** snapshots (e.g. a rolling local backup on a cadence,
or on app-update boundaries) are a **separate S3**, not required for the durability net.

**5. Non-goal (for now): structured/portable export.** A human-readable JSON/zip export for interop
with *other* apps is a real but **different** goal (portability, not durability) with a real
serialization cost. It is **out of scope** here and parked as a future effort; the DB-snapshot
backup does not block it and vice-versa.

## Slices

- **S1 — Export.** Snapshot writer (core, `VACUUM INTO`/`backup`, consistent read) + a Settings row
  that runs it and hands the file to `fileExporter`. Stamp a `schemaVersion` / app-version marker
  the restore path can read (a `PRAGMA user_version` or a one-row `backupMeta` table). Package-level
  logic is unit-testable (snapshot a seeded temp DB, reopen it, assert row counts match).
- **S2 — Restore.** Validation (magic/marker + schema-compat check), auto pre-restore snapshot,
  atomic swap of the store file, sync-metadata strip, re-open with sync **off**. Confirm-and-undo UX.
- **S3 (optional, later) — Automatic snapshots.** Cadence/trigger + retention (keep N), local-only.

## Consequences

- **A real safety net that outlives CloudKit.** The user can recover the full library — images and
  all — from a file, with no server, no account, no zone. This is what makes staying in CloudKit
  **Development** and continuing to iterate the schema *safe*, and it de-risks the eventual
  prod-schema promotion.
- **Schema-version coupling (the main tradeoff of a raw-DB backup).** A `.sqlite` snapshot is tied to
  the schema that produced it. A backup taken on schema N restored into an app expecting schema N+K
  must run the migrator forward — fine as long as migrations stay additive/forward-only (they are).
  The `schemaVersion` marker + a restore-time compat check turns "silent breakage" into an honest
  "this backup is newer/older than this app can restore." A far-future backup restored into a
  much-older app is refused, not corrupted.
- **No new sync schema, no zone rebuild.** This is orthogonal to the sync pipeline; it reads the same
  store everything else uses. Explicitly **not** [[debug-erase-vs-sync-triggers]] territory.
- **Plaintext at rest.** The SQLite store is unencrypted, so a backup file is plaintext recipe data
  (+ images) wherever the user puts it. For a personal recipe app in the user's own iCloud Drive this
  is acceptable; called out in OQ3 rather than assumed.

## Open questions

- **OQ1 — Restore ↔ CloudKit reconciliation semantics.** The chosen "restore local, sync off, user
  re-enables" path is the safe default, but the exact reconcile behavior when re-enabling sync onto a
  restored store (does CloudKit treat restored UUID-PK rows as updates to existing records, or does
  it need a fresh association?) must be confirmed on device before S2 is called done. Interacts with
  the same SyncEngine internals as ADR-0028.
- **OQ2 — Snapshot mechanism.** `VACUUM INTO` (simplest, one file, defragments) vs. GRDB
  `DatabaseWriter.backup` (online backup API). Pick in S1; both give a consistent copy. Confirm WAL
  checkpoint behavior so the snapshot needs no sidecar files.
- **OQ3 — Encryption / redaction.** Leave the backup plaintext (recommended for v1), or offer a
  passphrase? Deferred; note the tradeoff, don't build encryption in S1.
- **OQ4 — Should restore be able to *merge* rather than *replace*?** v1 is replace-only (simplest,
  matches "recover from disaster"). Selective/merge restore is a later, harder question and stays out
  of S1/S2.
