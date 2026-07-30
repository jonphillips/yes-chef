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
**[[llm-vs-determinism-surface-boundary]]**. **Amendment 1 (2026-07-28) is WITHDRAWN — refuted by
measurement. Amendment 2 (2026-07-29, accepted): restore is *authoritative*. Re-enabling sync on a restored
store re-pushes the entire restored library and the restored values win every collision, so the restored
device becomes the source of truth for iCloud and every peer — including resurrecting rows deleted since the
backup. This corrects D2, whose "never risks a restore stomping the cloud" was wrong; it stomps the cloud by
design, which is what makes the net cover a *poisoned* zone and not merely a lost one. Accepted as Jon's
explicit call. OQ1 is answered by measurement; OQ5 is closed as already-shipped behaviour. One open defect
came out of the same run — a tombstone contradiction on the peer.** See Amendments 1 and 2.

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
attached metadatabase and its SQLite sidecars, then reopens with sync disabled. **Corrected by Amendment 2:**
this clause originally claimed the reconciliation "never risks a restore stomping the cloud." It does stomp
the cloud — wiping the metadatabase makes every table look new, so re-enabling re-pushes the whole restored
library and the restored values win. That is the accepted design (it is what lets a restore beat a *poisoned*
zone), but it makes **re-enabling sync the consequential act, not the restore** — a second, separate decision
behind its own gate and confirmation, and the UI must say that the restored library wins.

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
- **The net covers a poisoned zone, and the cost is that restore rewrites every peer (Amendment 2).** The
  opening framing — "a corruption or an erroneous erase can propagate rather than protect" — is recovered
  from: restore, re-enable, and the good data overwrites the bad in iCloud and on every device. Measured, not
  assumed. The price is that a restore is **never** confined to one device once sync comes back on, and it
  **resurrects rows deleted since the backup**. Accepted deliberately — a durability net that loses to the
  thing it is recovering from is not a net — which is why the enablement gate, its confirmation, and the copy
  all treat *re-enabling sync* as the destructive step rather than the restore.
- **Accepted share-extension coordination risk.** Restore replaces the app-group store without an
  `NSFileCoordinator` or a lock that waits for the share extension's connection. An in-flight extension save
  can therefore write to the unlinked prior inode and lose that write when its WAL is discarded. This is an
  accepted v1 risk for a rare, destructive, user-initiated operation; the user should not restore while a
  share-sheet save is in progress. See [[extension-sync-construct-not-run]].
- **Plaintext at rest.** The SQLite store is unencrypted, so a backup file is plaintext recipe data
  (+ images) wherever the user puts it. For a personal recipe app in the user's own iCloud Drive this
  is acceptable; called out in OQ3 rather than assumed.

## Amendment 1 — WITHDRAWN: refuted by measurement (2026-07-28, withdrawn 2026-07-29)

Status: **Withdrawn.** Superseded by Amendment 2. Raised in review of
PR [#252](https://github.com/jonphillips/yes-chef/pull/252); it predicted that re-enabling sync on a restored
store would resolve **in the cloud's favour**, silently undoing the restore. **Two-simulator measurement in an
isolated CloudKit container disproved that.** Kept as a record rather than deleted, because half of its
mechanism is correct and load-bearing, and because the way it was wrong is instructive.

**What held — and it is the engine of everything in Amendment 2.** Restore deletes the attached metadatabase,
so `sqlitedata_icloud_recordTypes` comes back **empty**; `start()` therefore evaluates `newTableNames` to
*every* synced table (`SyncEngine.swift:633`) and runs `UPDATE <table> SET pk = pk` on **every row**
(`:676`), queueing the entire restored library at the live zone. Observed exactly: `recordTypes` 0 → 33,
metadata 0 → 39, all 39 gaining server records in one `start()`.

**What was refuted.** The claim that a missing `_lastKnownServerRecordAllFields` baseline collapses
`upsertFromServerRecord` (`:1958`) into a whole-record overwrite **in the server's favour**. It does not. Every
collision resolved toward the **local, restored** value. The reasoning traced a real code path and drew the
wrong conclusion about which side wins; the falsifier written into this amendment ("if SQLiteData backfills a
baseline before the first push, the amendment softens") pointed near the right place for the wrong reason.

**The process worked.** This shipped as **Proposed**, with a named falsifier and a hard gate that the
confirmation run happen in a scratch container and explicitly **not** against the live zone. That gate is why
being wrong cost one evening on two simulators instead of a ~44k-record push and resurrected rows across
Jon's real devices.

## Amendment 2 — Restore is **authoritative**: the restored library wins everywhere (2026-07-29)

Status: **Accepted** — 2026-07-29, on two-simulator measurement in an isolated CloudKit container
(`iCloud.com.jonphillips.yescheftest`, fresh Apple ID, fresh installs). Supersedes Amendment 1 and **corrects
D2**. Jon's explicit call: *"If I'm restoring from backup, it means something went wrong and I need to return
fully to the previous state."* Interacts with the same SyncEngine internals as
[ADR-0028](ADR-0028-multi-foreign-key-sync-loss.md).

**The measured answer to OQ1.** Re-enabling sync on a restored store re-pushes the **entire** restored library
at the zone, and the restored values **win every collision**. The restored device becomes the source of truth
for iCloud and for every other peer.

**The experiment.** Two simulators, converged, 3 recipes, 39 metadata rows each. Backup taken on A. Then on B:
one recipe renamed (`EDIT v1-BACKUP` → `EDIT v2-CLOUD`) and one recipe **hard-deleted** (archived, then
*Delete Permanently* from the Archive — the library "delete" is only an `archived = true` update, so the purge
is a deliberate second step). A fetched both changes, so the backup was genuinely stale. A then restored, and
re-enabled sync with a single `start()` and no relaunch.

| | Before re-enable | After convergence |
| --- | --- | --- |
| Sim A (restored) | 3 recipes, `recordTypes` **0**, all-fields baselines **0** | 3 recipes, 39/39 baselines |
| Sim B (authoritative peer) | 2 recipes, 39/39 baselines | **3 recipes — matches A** |
| `EDIT` conflict | A held the stale `v1-BACKUP` | **`v1-BACKUP` won**, on B and in the zone |
| Purged `DELETE-target` | absent from zone and from B | **resurrected on both**, server record accepted |

**Two consequences, and the second is the one to design around.**

1. **The durability net covers a poisoned zone after all.** This reverses Amendment 1 and restores the
   Context section's original promise: if bad state reached CloudKit, restoring a good backup and re-enabling
   sync *does* recover — the good data overwrites the bad. This is what makes staying in CloudKit
   **Development** safe.
2. **Restore is not a local operation, and D2's "never risks a restore stomping the cloud" was wrong.** It
   stomps the cloud by design. One device's restore silently rewrites the shared library and **undoes
   deliberate deletions on every peer**. Accepted as the design — a durability net that loses to the thing it
   is recovering from is not a net — but it makes re-enabling sync the genuinely consequential act, not the
   restore. Hence the enablement gate (`isDisabledByRestore()`) and its confirmation, and hence the UI copy
   must say that the restored library wins. **The copy shipped in S2 said the opposite and was inverted on
   2026-07-29.**

**OQ5 is closed, not parked.** "Should restore be able to assert itself over the zone?" — it already does,
without a zone reset. No slice needed; nothing to build.

**Open defect found by the same run — the tombstone contradiction.** After convergence, Sim B holds
`_isDeleted = 1` for `recipes/63a6f904` **and its five child rows** while those rows exist locally *and* carry
`lastKnownServerRecord`. B simultaneously believes the record is deleted, holds it, and thinks the server has
it. Nothing is queued (`pending = 0`), but the flags persist, so a later full re-push — exactly what a restore
triggers — could act on them and silently re-delete resurrected data. **This state looks converged and is not
stable.** Tracked as its own investigation; it is a latent data-loss path, not a documented behaviour, and it
is the one thing standing between this design and full confidence in restore.

## Amendment 3 — OQ6 + OQ7 resolved by measurement; restore authority is bounded, and the app must enforce a restore procedure (2026-07-29)

Status: **Accepted** — 2026-07-29, two-simulator measurement in the isolated container
(`iCloud.com.jonphillips.yescheftest`), protocol in
[`efforts/adr-0030-oq6-oq7-measurement.md`](../efforts/adr-0030-oq6-oq7-measurement.md). Closes OQ6 and OQ7 and
**bounds Amendment 2's "restored values win every collision."**

### OQ7 — CLOSED clean: images survive the re-push byte-intact on the peer

Re-ran the OQ1 flow **with photos attached** (the OQ1 run had none). Backup froze P1; the cloud/peer held a
different P2 for the same recipe, plus an asset-level deletion (a photo removed, recipe kept) and a
record-level deletion (a whole recipe + children). After restore + re-enable + peer relaunch, **all four
photos were byte-identical on both devices** — the restored P1 came back on the peer at its exact
`displayData`/`thumbnailData` lengths and JPEG header, no truncation, no empty asset. The
asymmetric-asset-failure mode the OQ was hunting **did not occur**; asset- and record-level resurrection both
succeeded. **Caveat to record:** a photo *replaced* since the backup produces a **duplicate** after restore —
the swap is delete-row + insert-row (distinct primary keys), so restore resurrects the old photo row *alongside*
the surviving new one rather than overwriting it. Not data loss; a duplication artifact. **Still unmeasured:**
volume — one asset says nothing about ~2,163 recipes' assets re-uploading at once (the CKError 429 shape). That
stays a real-device unknown for the device pass.

### OQ6 — CONFIRMED as a real data-loss path; restore is authoritative only against *settled* peer state

The original OQ6 framing (a lingering `_isDeleted = 1` flag silently re-deleting on a *later* re-push) is one
face of a larger issue. What the measurement established:

1. **The resting tombstone is real.** Captured 7 records (`recipes/…` + 6 children) at `_isDeleted = 1` with
   `lastKnownServerRecord` present, by reading the database while the app was crashed mid-delete (before the
   reconciling relaunch that had been destroying it).
2. **In the ordinary flow it self-heals.** On the next relaunch the engine **sends the delete before it
   fetches** (`syncChanges` order), the server confirms, and the metadata row is **hard-removed** — a clean
   deletion, no lingering flag. Measured: 7 tombstones → 0 after one relaunch.
3. **The data loss (measured end-to-end).** Arm a peer with an **unsent** delete (crash-held: on this app every
   delete crashes the UI until relaunch, so held deletes are routine), then restore + re-enable on the *other*
   device **while the peer is still holding it**. The restore re-pushes the record alive; on the peer's next
   relaunch its held delete **sends and wins the collision**, silently re-deleting the restored record **on
   every peer**. Confirmed: `EDIT v1-BACKUP` was authoritatively restored on A, then re-deleted everywhere by
   B's held tombstone — A, B, and the zone all converged with the recipe **gone** (verified by B cleanly
   fetching back the *other* restored recipes but never `EDIT`).

**This bounds Amendment 2, it does not reverse it.** Both outcomes are last-writer-wins. Amendment 2's run had
the peer's delete **already settled** (A had fetched it) before the restore, so the restore was the newest
write and won — that result stands. The loss happens only when a peer carries an **unsettled** change
(pending / held / offline) that syncs *after* the restore. So: **restore wins against settled peer state;
it loses to a concurrent unsettled delete.** "Restored values win every collision" is corrected to "…win every
collision with state that was already settled at the moment of restore."

**Root cause (code, reading only to *explain* the measured result — SQLiteData 1.8.2):** two upstream
behaviours in `SyncEngine.swift` / `Triggers.swift`, both in tombstone handling:
- `syncChanges` sends pending changes before fetching, so a held delete is pushed and wins before any
  resurrection can arrive — this is the measured data-loss path.
- `upsertFromServerRecord` (conflict-update path) writes a resurrected row back **without clearing
  `_isDeleted`**, so where a resurrection *does* land over a still-present tombstone you get the alive-row +
  `_isDeleted = 1` contradiction the prior run saw. The reset the original OQ6 suspected "simply absent" is
  confirmed absent.
Both are **upstream SQLiteData**, not Yes Chef code. Deliverable is a **bug report to point-free** (restore /
resurrection should reconcile the peer's tombstone), not a local patch — a migrator-side fix would violate
[[migration-writes-bypass-sync-triggers]] anyway.

### The resolution: the app enforces a restore procedure (do not depend on understanding CloudKit)

CloudKit's conflict internals stay opaque; the honest posture is to **define a restore procedure that cannot
collide**, rather than trust an "authoritative" guarantee that only holds against settled state. Restore must
become *one authoritative source, every other peer rebuilds from the cloud*:

1. **Quiesce every other peer first — delete the app on each.** That discards the peer's local store and its
   unsent CKSyncEngine queue, so it has nothing that can override the restore.
2. **Restore + re-enable sync on the one device.** It becomes the source of truth for the zone.
3. **Reinstall the app on the other peers.** Each starts empty and fetches the restored cloud state.

**The app should enforce this**, not leave it to a documented manual procedure (Jon's call, 2026-07-29) — e.g.
restore gates on / instructs the user through quiescing the other devices before it re-enables sync. Scoped as
a follow-on slice; see the effort doc and CURRENT_HANDOFF.

**One assumption to verify before trusting the procedure:** that deleting the app actually clears the
**app-group** container (the store and pending ops live there, not in the app sandbox). iOS should clear a
group container when its last owning app/extension is removed, and Yes Chef's group is only the app + its share
extension — but verify once on a throwaway install. **Not** on the two measurement simulators: reinstalling
them repoints the binary at the *real* container ([[simulator-run-needs-signing]] / the effort doc's reinstall
warning). And the procedure only holds if **all** peers are reachable — a powered-off device with a pending
delete will still override the restore when it wakes.

**OQ6 status: resolved.** Real data-loss path under naive restore; mitigated to safe by the enforced procedure;
underlying defect reported upstream. The real-device restore pass is unblocked **once the procedure gates it**
(a naive real-device restore now rewrites the live zone and can be silently clobbered by any peer's in-flight
delete).

## Open questions

- **OQ1 — Restore ↔ CloudKit reconciliation semantics. CLOSED 2026-07-29 by measurement; see Amendment 2.**
  Re-enabling sync onto a restored store re-pushes the *entire* restored library and the **restored values win
  every collision**, so the restored device becomes the source of truth for the zone and every peer. Confirmed
  on two simulators in an isolated CloudKit container with a fresh Apple ID — never against the live zone.
- **OQ2 — Snapshot mechanism.** `VACUUM INTO` (simplest, one file, defragments) vs. GRDB
  `DatabaseWriter.backup` (online backup API). Pick in S1; both give a consistent copy. Confirm WAL
  checkpoint behavior so the snapshot needs no sidecar files.
- **OQ3 — Encryption / redaction.** Leave the backup plaintext (recommended for v1), or offer a
  passphrase? Deferred; note the tradeoff, don't build encryption in S1.
- **OQ4 — Should restore be able to *merge* rather than *replace*?** v1 is replace-only (simplest,
  matches "recover from disaster"). Selective/merge restore is a later, harder question and stays out
  of S1/S2.
- **OQ5 — Should restore be able to assert itself over the zone? CLOSED 2026-07-29 — it already does.**
  Asked as a future slice ("reset the CloudKit zone and re-upload"). Measurement showed restore is
  authoritative *without* any zone reset: wiping the metadatabase makes every table look new, the whole
  library re-pushes, and local wins. **Nothing to build.** OQ4 (merge vs replace) remains the *local* version
  of the question and stays open.
- **OQ6 — The tombstone contradiction. CLOSED 2026-07-29 by measurement; see Amendment 3.** Resolved as a
  **real data-loss path**, broader than the original "lingering flag" framing: a peer's **unsent/held** delete
  that syncs *after* a restore's re-push **wins the collision and silently re-deletes the restored record on
  every peer** (measured end-to-end). Restore is authoritative only against peer state that was **settled** at
  the moment of restore. Underlying cause is upstream SQLiteData tombstone handling (`upsertFromServerRecord`
  never clears `_isDeleted`; `syncChanges` sends before it fetches). Mitigated by the **enforced restore
  procedure** (quiesce peers → restore on one → reinstall peers); underlying defect goes to point-free as a bug
  report.
- **OQ7 — Images through a restore's re-push. CLOSED 2026-07-29 by measurement; see Amendment 3.** Re-ran with
  photos attached: images survive the re-push **byte-intact on the peer** (all four photos byte-identical on
  both devices, no truncated/empty asset), and asset- and record-level resurrection both succeed. One caveat: a
  photo *replaced* since the backup resurrects as a **duplicate** (old row + surviving new row), not an
  overwrite. **Volume remains a real-device unknown** — one asset says nothing about ~2,163 recipes' assets
  re-uploading at once (the CKError 429 shape); that belongs in the device pass.
