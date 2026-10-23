# Effort — Sync status reports what didn't sync

Status: Designed 2026-10-13, queued after [`raw-import-html-drop.md`](raw-import-html-drop.md). Schema-free, but
**touches sync**, so the architect escalates both PRs to Jon. Slices 1–2 shipped (jon-platform #72, yes-chef
#355/#356). **The device pass failed 2026-10-22 on the first check: the iPad reads "44,938 items haven't synced",
which is the whole library, and the iPhone reports the same state.** Slices 3–4 below are the follow-up:
diagnose, then fix (added 2026-10-22).
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

- **Not uploaded:** non-deleted rows of SQLiteData's `metadata` table that aren't **server-confirmed**, with
  `userModificationTime` older than a grace window (default 30 minutes). Server-confirmed means CloudKit confirmed
  the row's *latest* change: `lastKnownServerRecord?.recordChangeTag != nil` **and** `userModificationTime` no later
  than that record's `modificationDate` (plus a 5-minute clock-skew tolerance). **Not** `hasLastKnownServerRecord`:
  SQLiteData 1.9 stores the outgoing record there before CloudKit answers and never clears it on `.limitExceeded`, so
  a record that failed for good looks uploaded (that's how the first raw-HTML repair missed all nine recipes). And
  **not** the tag alone: a row that was already on the server keeps its old tag when a later edit fails, which is
  exactly the device pass below (edit an existing recipe offline). Testing the change tag
  means decoding the system-fields column, so compute this on demand and off the main actor (status refresh,
  Settings), never at launch. Decode only `lastKnownServerRecord`, never `_lastKnownServerRecordAllFields`. Count them only while the engine is
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
- **`CloudSync.requeue(recordType:primaryKeys:)`** sets the rows' metadata `lastKnownServerRecord` and
  `_lastKnownServerRecordAllFields` to NULL, as SQLiteData's own `setLastKnownServerRecord(nil)` does. The metadata
  after-update trigger queues the save, and the resend builds a fresh `CKRecord`, so a stale cached field (like a
  dropped oversize column) can't ride along. Only a row with no metadata row uses `UPDATE <table> SET <pk> = <pk>`,
  which creates one. **Never clear a row that has a change tag.** That would discard the tag and turn the next
  save into a conflict. Such a row is re-queued by touching its metadata row instead, which re-sends the cached
  record with its tag.
- It stays domain-free, with no app table names in the package. Both apps load `CloudSyncKit` by local path, so
  the new `SyncDisplayStatus` case reaches their exhaustive switches as soon as it lands: each app's sync row
  handles `.needsAttention` (dot, detail line, explanation) alongside slice 1.

## Slice 2 — Yes Chef

- The Settings sync row shows the new state. The sync detail lists not-uploaded rows by table under a readable
  name (recipe titles for `recipes`, a recipe's title for its child rows, the count otherwise), each with a
  **Retry** that calls `requeue`. Retrying a permanent failure, like an oversize record, just fails again. That's
  fine: the list tells Jon what to report.
- No automatic retry loop. The raw-HTML brief's post-engine pass is already the targeted repair for that incident.

## Done when

- jon-platform: the signal, the reducer case, `requeue`, and tests (the reducer is pure; the query is tested
  against a migrated metadatabase with seeded rows). The package's own tests are green.
- Yes Chef: the row and detail as above, built against jon-platform `main` (Slice 1 is jon-platform#72; local path,
  so there's no package version to bump). The rest per `docs/verification.md`.
- `PROD-CUTOVER.md` Phase 2 has its box ticked, `DONE-LOG.md` has the entry, `NEXT_UP.md` is advanced to
  [`chat-access-mcp.md`](chat-access-mcp.md) S0 (the next queued effort), and the
  device pass is in `device-passes.md`.

**Device pass:** this ships after the raw-HTML fix, so both devices should read "Up to date", with no false
positives on a real library. Then, in Airplane mode, edit a recipe and wait past the grace window. The row reads
"1 item hasn't synced" and the detail names the recipe. Turn the network back on: it uploads and returns to "Up to
date", with or without Retry. On the iPhone the not-applied count is zero, or the detail names what's stuck.

## Verification

jon-platform: the `CloudSyncKit` package tests. Yes Chef: `scripts/check-drift.sh`, the elevated generic iOS build,
and `YesChefTests`.

## Slice 3 — Explain why a row counts as not uploaded (diagnostic)

**What happened.** On a real library, `syncFailureReport` flags essentially every row on both devices. Ordinary
sync looks healthy in day-to-day use; the readout pass below confirms that with a title edit. So one leg of **server-confirmed** fails
for nearly every row. The legs are: a server record is cached, it decodes, it has a change tag, and
`userModificationTime ≤ modificationDate + 5 min`. Reading the code didn't settle which leg. The tests missed it
because SQLiteData's test runtime archives a stand-in change tag and never sets a modification date, so
`isServerConfirmed` trusts the tag and skips the date leg entirely. The app's backup excludes the metadatabase,
and Xcode's container download can't reach the app group, so the evidence has to come from the device. This slice
is a **discriminating probe**: its readout decides Slice 4.

Some leads, which are not conclusions:
- **A cached server record older than the local stamp.** One way this happens: SQLiteData's metadata update
  trigger, and its `setLastKnownServerRecord` `max(...)`, raise `userModificationTime` while the cached record
  stays the pre-existing server version. That could follow a restore, which rebuilds the metadatabase, or a
  conflict resolved without a new save.
- A cached record without a change tag.
- A modification date the check misreads.

### Build

1. **jon-platform `CloudSyncKit`** (additive, read-only):
   - Refactor `isServerConfirmed` so it returns a **reason**, not a `Bool`. The cases are `confirmed`,
     `noServerRecord`, `undecodable`, `noChangeTag`, and `localEditAfterServer(delta:)`. `syncFailureReport` keeps
     its exact behavior: everything but `confirmed` counts. Because the report and the diagnosis share one
     predicate, they can't drift.
   - Add `CloudSync.syncFailureDiagnosis(in:isEngineRunning:isSendingChanges:isFetchingChanges:now:sampleLimit:)`.
     It reads the same row set as the report: non-deleted, older than the grace period, and only while the engine
     is quiescent. It returns:
     - the total rows considered, and the count for each reason;
     - for `localEditAfterServer`, the minimum, median, and maximum delta, plus a histogram (under 1 h, 1 h–1 d,
       1–7 d, over 7 d);
     - the count for each `recordType` and reason;
     - **up to `sampleLimit` (default 10) sample rows**, spread across record types. Each sample carries the record
       type, primary key, `userModificationTime` as a date, and the cached record's `modificationDate` and
       `creationDate`, plus whether it has a change tag. It also carries **`userModificationTime` read from
       `_lastKnownServerRecordAllFields`, the value SQLiteData stamped on the record it sent.** Decode the
       all-fields blob for the samples only, never the whole library (Slice 1's cost rule).
   - Tests: decoding a real `CKRecord` that has a change tag and a modification date. Build it with
     `encodeSystemFields` through a secure archiver, the same way SQLiteData does, so the date leg is actually
     exercised; the test runtime's stand-in doesn't do that. Cover each reason case, and check that the report's
     counts equal the diagnosis's non-`confirmed` total.
2. **Yes Chef (DEBUG only):** a **Diagnose** button in the sync detail. It runs the diagnosis off the main actor
   and shows the totals, histogram, per-type table, and samples, with a **Copy** button that puts the whole readout
   on the clipboard as plain text, ready to paste back to the architect. No other behavior changes, and nothing
   writes.

**Out of scope:** any change to what the row reports, any requeue, and any SQLiteData fork. Those belong to
Slice 4, and only if the readout calls for them.

### Verification

`CloudSyncKit` tests in the jon-platform PR. In Yes Chef: `scripts/check-drift.sh`, the elevated generic iOS
build, and `YesChefTests` (the sync detail's model changes).

### Jon's pass (the readout)

First, edit a recipe title on the iPhone and check that it reaches the iPad, which shows ordinary sync works.
Then, on the iPad and then the iPhone: Settings → Sync → detail → **Diagnose** → **Copy**. Paste both readouts
into the architect session. Don't tap Retry before that, because a retry changes the evidence.

### Done when

Both PRs are merged and green. `DONE-LOG.md` has the entry, and `NEXT_UP.md` reads `Nothing dispatched.`, because
Slice 4 is specified only from the readout. The readout pass is in `device-passes.md`.

## Slice 4 — Fix the false positive

Specified after Slice 3's readout. The likely branches, so that the specification is quick:

- **Mostly `localEditAfterServer`, with the all-fields `userModificationTime` at or after the metadata's (the
  server already has this edit):** the date leg is the wrong test. Compare the metadata's
  `userModificationTime` with the `userModificationTime` SQLiteData stamped on the cached server record. Both
  values come from SQLiteData's own clock, so the skew tolerance goes away. Do the cheap change-tag check first,
  and decode all-fields only for the few rows that fail it.
- **Mostly `localEditAfterServer`, with the stamped time older (the edit really never left):** the rows are
  genuinely unsent. The fix is then a throttled re-send of the affected rows, not a reporting change, and it gets
  its own brief because it pushes the whole library.
- **Mostly `noChangeTag` or `noServerRecord`:** the cached server records are missing or stale, probably since a
  restore. The fix is a confirm-from-server pass (fetch, then reconcile the metadata), specified then.

Whichever branch it is, Slice 4 adds a regression test that builds the readout's exact shape, and repeats
Slice 2's device pass.

