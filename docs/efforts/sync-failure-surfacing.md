# Effort — Sync status reports what didn't sync

Status: Designed 2026-10-13, queued after [`raw-import-html-drop.md`](raw-import-html-drop.md). Schema-free, but
**touches sync**, so the architect escalates both PRs to Jon.
Summary: The sync row said "Up to date" for weeks while nine recipes had never uploaded. `CloudSyncKit` gains a
"not synced" signal: rows that never reached the server, and rows from the server that couldn't be applied here.
"Up to date" now requires both to be zero, and Yes Chef's sync detail lists them by name with a Retry. Two PRs:
jon-platform (additive), then Yes Chef.
Related: jon-platform `docs/adr/0003-extract-cloud-sync-kit.md` Amendment 1 (the decision) · jon-platform
`docs/ios/persistence-and-sync.md` § "SQLiteData fails silently" · [ADR-0028](../decisions/ADR-0028-multi-foreign-key-sync-loss.md) (the last time
the indicator lied: download side) · [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Phases 2 and 4d

## Why the status can't see it today

SQLiteData 1.9 handles CloudKit save errors inside its own delegate, and the app never sees them:

- `.limitExceeded` (a record over 1 MB) and about twenty other codes are a bare `continue`. The record is dropped
  from the send queue with no report.
- On `.referenceViolation` it applies a single-FK child's `ON DELETE` locally (`SET NULL` or a delete).

`SyncHealth` only knows the pre-start pending queue, whether the engine is fetching, and start errors. A record that
failed for good leaves all three quiet, so the reducer reads "Up to date". We can't get the error itself without
forking SQLiteData. We **can** observe the result, because the metadatabase records whether each row reached the
server. That catches every cause, including ones we haven't met yet.

## Slice 1 — jon-platform `CloudSyncKit` (additive)

- **Not uploaded:** rows of SQLiteData's `metadata` table with `hasLastKnownServerRecord = 0`, `_isDeleted = 0`,
  and `userModificationTime` older than a grace window (default 30 minutes). Count them only while the engine is
  running and not `isSendingChanges` or `isFetchingChanges`, so a batch in flight never counts. Return the counts
  grouped by `recordType`, plus up to 50 primary keys per type for the app to name. **It reports a fact, not a
  cause.** Offline for an hour, or throttled during a bulk upload, it says these items haven't synced. That's true,
  and the count clears when they upload. Without the CloudKit error we can't tell transient from permanent, and
  we don't pretend to.
- **Not applied:** the row count of `unsyncedRecordIDs`. These are records that came down from the server and
  couldn't be written locally, usually because their parent is missing.
- **`SyncHealth`** gains both counts. The reducer gets a new case, `.needsAttention(notUploaded:notApplied:)`,
  summary "N items haven't synced". Its precedence is after `.downloading` and before `.upToDate`: in-progress
  states still win, but **"Up to date" requires both counts to be zero.** Reducer tests cover every new
  precedence edge.
- **`CloudSync.requeue(recordType:primaryKeys:)`** re-queues rows with `UPDATE <table> SET <pk> = <pk>`. That's
  SQLiteData's own re-sweep idiom (`SyncEngine.uploadRecordsToCloudKit`). It fires the after-update trigger, and
  the primary-key-change trigger is guarded `WHEN old.pk != new.pk`, so it stays quiet (verified in 1.9.0
  `Internal/Triggers.swift`).
- It stays domain-free, with no app table names in the package. Galavant gets it when it bumps the package, and
  nothing there changes until then.

## Slice 2 — Yes Chef

- The Settings sync row shows the new state. The sync detail lists not-uploaded rows by table under a readable
  name (recipe titles for `recipes`, a recipe's title for its child rows, the count otherwise), each with a
  **Retry** that calls `requeue`. Retrying a permanent failure, like an oversize record, just fails again. That's
  fine: the list tells Jon what to report.
- No automatic retry loop. The raw-HTML brief's post-engine pass is already the targeted repair for that incident.

## Done when

- jon-platform: the signal, the reducer case, `requeue`, and tests (the reducer is pure; the query is tested
  against a migrated metadatabase with seeded rows). The package's own tests are green.
- Yes Chef: the row and detail as above, on the new package version. The rest per `docs/verification.md`.
- `PROD-CUTOVER.md` Phase 2 has its box ticked, `DONE-LOG.md` has the entry, `NEXT_UP.md` is advanced, and the
  device pass is in `device-passes.md`.

**Device pass:** this ships after the raw-HTML fix, so both devices should read "Up to date", with no false
positives on a real library. Then, in Airplane mode, edit a recipe and wait past the grace window. The row reads
"1 item hasn't synced" and the detail names the recipe. Turn the network back on: it uploads and returns to "Up to
date", with or without Retry. On the iPhone the not-applied count is zero, or the detail names what's stuck.

## Verification

jon-platform: the `CloudSyncKit` package tests. Yes Chef: `scripts/check-drift.sh`, the elevated generic iOS build,
and `YesChefTests`.
