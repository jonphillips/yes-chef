# ADR-0030 — Local backup & restore: a CloudKit-independent durability net

> **One-line:** The whole ~2,163-recipe library — including every image — lives in exactly two
> places today: the devices and the **CloudKit Development** private zone. There is **no user-facing
> export**, so a bad migration, a Development-environment reset, or a device-migration mishap could
> lose it with no way back. Add a **backup that does not depend on CloudKit**: a consistent
> whole-database snapshot (`VACUUM INTO` a single `.sqlite` file) the user writes to Files / iCloud
> Drive, plus a restore that reads one back. Images ride along for free — they are BLOBs **inside**
> the database file, not separate assets — so this is a byte-exact copy, **not** a serialization
> surface. A structured/portable (JSON) export is an explicitly separate, later concern.

Status: **Accepted** — 2026-07-12; accepted 2026-07-27. Extends **[ADR-0001](ADR-0001-persistence-sqlitedata.md)**
(SQLiteData persistence) and **[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (CloudKit sync, no
server). Depends on the images-in-DB model from **[ADR-0005](ADR-0005-image-storage-and-processing.md)**.
Motivated by [[post-browser-sync-vs-features-tension]] (the solvable sync/**backup** gate) now that
sync itself round-trips E2E (M4). De-risks the held **prod-schema promotion** ops step in
`docs/CURRENT_HANDOFF.md`. Related cautionary context: **[[debug-erase-vs-sync-triggers]]**,
**[[llm-vs-determinism-surface-boundary]]**. **Amendment 1 (2026-07-28, proposed): re-enabling sync on a
restored store resolves *in the cloud's favour*, not the restore's. D2's "the user re-enables sync, which
reconciles the restored rows through the normal path" is true in direction and wrong in outcome — the normal
path overwrites the restored rows with the server's, because restore deletes the very `lastKnownServerRecord`
baselines the field-level merge depends on. The net therefore covers a **lost or blank** zone, not a
**poisoned** one. OQ1 is answered by code reading and awaits confirmation in an isolated container.**
See Amendment 1.

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

**2. Exclude sync-internal state from what a restore trusts.** SQLiteData keeps SyncEngine metadata and
the `PendingRecordZoneChange` bookkeeping (the tables ADR-0028 and
[[extension-sync-construct-not-run]] revolve around) in a sibling attached metadatabase. A `VACUUM INTO`
snapshot copies only the main store, so it does not contain that peer state. A restored main file must still
**not** inherit the old local peer: after the main file is atomically replaced, restore removes the actual
attached metadatabase and its SQLite sidecars, then reopens with sync disabled. The user re-enables sync —
but **that reconciliation is not neutral, and Amendment 1 documents which way it falls.** Restore never
stomps the cloud; the cloud stomps the restore. Re-enable is therefore a **second, separately-consequential
decision**, not a formality, and the UI must say so.

**3. Restore = import one snapshot, deliberately and reversibly.** Restore is a destructive,
explicitly-confirmed action (it replaces the current local library). Before swapping, the app takes
an **automatic pre-restore snapshot** of the current store so a mis-click is undoable. Restore
validates the incoming file (is it a YesChef DB? is its schema version restorable by the current
migrator?) before touching the live store.

**4. Manual first; automatic later — but one automatic trigger is privileged.** S1/S2 ship a
Settings affordance — "Export a backup" and "Restore from a backup." **Automatic/periodic** snapshots
(e.g. a rolling local backup on a cadence, or on app-update boundaries) are a **separate S3**, not
required for the durability net. The **one** automatic trigger worth singling out is a
**pre-migration snapshot** taken immediately before `migrator.migrate` runs: schema-change is exactly
where the library's most-feared footgun bites (the `-YesChefEraseDatabaseOnSchemaChange` erase that
has wiped the dogfood store, [[debug-erase-vs-sync-triggers]]), so a rolling auto-snapshot at that
boundary is the single cheapest catch for that class of bug. It rides in S3, not S1/S2, but it is the
*first* auto-trigger to build.

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
  atomic swap of the store file, removal of the prior attached sync metadatabase, re-open with sync **off**.
  Confirm-and-undo UX.
- **S3 (optional, later) — Automatic snapshots.** Cadence/trigger + retention (keep N), local-only.
  **Build the pre-migration snapshot first** (Decision 4): a rolling local snapshot taken right before
  `migrator.migrate` runs, keep N, so a bad/erasing migration is always recoverable from the step
  before it. App-update-boundary and periodic snapshots follow.

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
- **The net covers a lost zone, not a poisoned one (Amendment 1).** The opening framing — "a corruption or
  an erroneous erase can propagate rather than protect" — describes a scenario this ADR as built does **not**
  recover from: if the bad state reached CloudKit, restoring a good backup and re-enabling sync re-imports
  the bad state. What the net *does* cover is total loss of the zone (Development reset, account loss, new
  device) and any period the user is willing to stay local-only. That is still the majority of the risk it
  was built for, and it is worth having — but the guarantee is narrower than the Context section implies,
  and the UI must not imply otherwise.
- **Accepted share-extension coordination risk.** Restore replaces the app-group store without an
  `NSFileCoordinator` or a lock that waits for the share extension's connection. An in-flight extension save
  can therefore write to the unlinked prior inode and lose that write when its WAL is discarded. This is an
  accepted v1 risk for a rare, destructive, user-initiated operation; the user should not restore while a
  share-sheet save is in progress. See [[extension-sync-construct-not-run]].
- **Plaintext at rest.** The SQLite store is unencrypted, so a backup file is plaintext recipe data
  (+ images) wherever the user puts it. For a personal recipe app in the user's own iCloud Drive this
  is acceptable; called out in OQ3 rather than assumed.

## Amendment 1 — Re-enabling sync resolves in the cloud's favour (2026-07-28)

Status: **Proposed** — accepted only after the isolated-container confirmation below. Raised in review of
PR [#252](https://github.com/jonphillips/yes-chef/pull/252) (S2). Interacts with the same SyncEngine
internals as [ADR-0028](ADR-0028-multi-foreign-key-sync-loss.md) and [[sqlitedata-single-fk-sync-limit]].

**OQ1 asked the wrong half of the question.** It asked whether CloudKit would treat restored UUID-PK rows as
*updates to existing records* or need *a fresh association*. The answer is "updates" — but the consequential
part is not the association, it is **who wins**, and the answer is: the server, essentially always.

**The mechanism, in four steps.** All references are to SQLiteData's `CloudKit/SyncEngine.swift` at the
pinned revision.

1. Restore deletes the attached metadatabase file (D2). That file holds `sqlitedata_icloud_recordTypes` and
   every row's `lastKnownServerRecord`. After a restore both are **gone**.
2. On `start()`, `previousRecordTypes` is read from that metadatabase — now empty — so `newTableNames`
   evaluates to **every synced table** (`:633`). For each, SQLiteData runs `UPDATE <table> SET pk = pk`
   (`:676`), a no-op self-update that fires the after-update trigger on **every row**, creating a
   `SyncMetadata` row and enqueueing a `saveRecord`. **The entire restored library — all 31 tables — is
   queued at the live zone.**
3. Each pushed record collides with the zone's existing record of the same `recordName` (it is derived from
   the UUID primary key) and comes back `.serverRecordChanged` → `upsertFromServerRecord(serverRecord)`
   (`:1686`).
4. That function only performs a **field-level merge** inside
   `if !force, let allFields = metadata._lastKnownServerRecordAllFields, …` (`:1958`). After a restore there
   is no baseline, so the branch is skipped, `columnNames` remains *all writable columns*, and the server
   record is written over the local row **wholesale**.

**So restore + re-enable yields the cloud's library, not the backup's** — plus resurrection of anything the
backup holds that the cloud has since deleted (those come back `.unknownItem` → clear server record →
re-save, i.e. **recreated in the zone** and propagated to every peer, `:1698`).

**What survives a restore, precisely.** Only rows that are **absent from the zone**. Which yields:

| Zone state | Outcome of restore + re-enable |
| --- | --- |
| Gone / blank (Development reset, account loss, new device) | **Full recovery.** Exactly as designed. |
| Live and healthy | Restore is silently overwritten. Rows the backup has and the zone lacks are **created** — including resurrections of deliberate deletions. |
| Live and **poisoned** | The poison wins. The restore is undone by the thing it was meant to undo. |

**Why this is not a device test.** The obvious next step — restore on the iPhone and turn sync on — costs a
~44k-record push at the live zone (the shape of the 2026-07-10 CKError 429 incident, deliberately
triggered), can resurrect deleted rows on both devices, and has **no undo**: "Undo Last Restore" swaps the
local file back, it cannot retract records already pushed. The confirmation belongs in a **scratch CloudKit
container** — one line in `YesChefCloudSync.configuration.containerIdentifier` plus a new container in the
dashboard — against a small seeded library on two simulators. Minutes, zero blast radius, and it confirms or
refutes the reading above before anything real is touched.

**What this amendment changes, and what it deliberately does not.**

- **It narrows the claim, it does not stop S2.** Restore is correct and useful for the lost-zone case, which
  is the bulk of what the ADR was built for. S2 ships.
- **It makes re-enable a decision, not a formality (D2).** The restore confirm alert and the restart cover
  must state plainly that turning sync back on will reconcile against iCloud and that **iCloud's copy will
  win** where both have a row. Two sentences of copy; the only product change this amendment demands of S2.
- **It does not build the cure.** Restore-authoritative (reset the zone, re-upload) is parked as OQ5, not
  designed here. Per [[withdraw-not-defer-orphaned-schema]] the failure mode to avoid is building it on this
  ADR's momentum: it is irreversible, it stomps every peer, and it deserves its own slice and its own
  justification — or none at all.
- **It stays honest about provenance.** The four steps above are a **code reading, not an observed run.**
  The isolated-container pass is what promotes this amendment from Proposed to Accepted.

**Confidence and the one thing that would change it.** The decisive claim is step 4 — that a missing
`_lastKnownServerRecordAllFields` collapses the merge into a whole-record overwrite. If SQLiteData in fact
backfills a baseline before the first push (it does not, as far as the read goes:
`enqueueUnknownRecordsForCloudKit` touches only rows *without* a server record and does not fetch one), the
outcome would be a genuine field-level merge and this amendment softens considerably. That is the single
thing the scratch-container pass should watch.

## Open questions

- **OQ1 — Restore ↔ CloudKit reconciliation semantics. ANSWERED (2026-07-28) by code reading; see
  Amendment 1.** Re-enabling sync onto a restored store re-pushes the *entire* restored library at the zone
  and then loses every collision to the server record. Confirmation in an isolated CloudKit container is
  still owed; it must **not** be discovered against the live zone (Amendment 1, "Why this is not a device
  test").
- **OQ2 — Snapshot mechanism.** `VACUUM INTO` (simplest, one file, defragments) vs. GRDB
  `DatabaseWriter.backup` (online backup API). Pick in S1; both give a consistent copy. Confirm WAL
  checkpoint behavior so the snapshot needs no sidecar files.
- **OQ3 — Encryption / redaction.** Leave the backup plaintext (recommended for v1), or offer a
  passphrase? Deferred; note the tradeoff, don't build encryption in S1.
- **OQ4 — Should restore be able to *merge* rather than *replace*?** v1 is replace-only (simplest,
  matches "recover from disaster"). Selective/merge restore is a later, harder question and stays out
  of S1/S2.
- **OQ5 — Should restore be able to assert itself over the zone?** The only true cure for a poisoned zone
  is *restore-authoritative*: reset the CloudKit zone and re-upload the restored library. That is precisely
  what D2 forbids, for good reason — it is irreversible and it stomps every peer. Deliberately **not** built
  in S1/S2. If it is ever built it is its own slice with its own confirmation, and it is the one place in
  this ADR where "never risk stomping the cloud" is knowingly traded away. Related: OQ4 (merge vs replace)
  is the *local* version of the same question.
