# Effort — Sync status reports what didn't sync

Status: Designed 2026-10-13, queued after [`raw-import-html-drop.md`](raw-import-html-drop.md). Schema-free, but
**touches sync**, so the architect escalates both PRs to Jon. Slices 1–2 shipped (jon-platform #72, yes-chef
#355/#356). **The device pass failed 2026-10-22 on the first check: the iPad reads "44,938 items haven't synced",
which is the whole library, and the iPhone reports the same state.** Slices 3–4 below are the follow-up:
diagnose, then fix (added 2026-10-22). Slice 3 shipped (jon-platform #82, yes-chef #361), and its readout
(2026-10-23) specified Slice 4: rows rewritten with unchanged values look unsent to the date leg. Slice 4 shipped
(jon-platform #83, yes-chef #363). Its readout showed the iPad really failing to upload about 300 rows, and Bulgogi
then showed lost deletes leaving duplicate steps on the iPhone. Slice 5 (added 2026-10-23) finds those deletes.
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

## Slice 4 — Count a row only if its content differs from the server's

**What the readout showed (2026-10-23).** Both devices were running and idle, and a title edit synced normally.
- **iPad:** 54,278 rows: 9,340 confirmed, 44,749 `localEditAfterServer`, and 189 `noChangeTag` (160 of them
  `recipeSources`).
- **iPhone:** 53,935 rows: 51,140 confirmed, 2,795 `localEditAfterServer`, and none without a tag.
- Neither device has a row with a missing or undecodable server record.
- In every sample, the stamp on the cached all-fields record is before the cached `modificationDate`, and the
  local stamp is later still. On the iPad, one recipe's rows in three tables share a stamp to the second
  (2026-08-26 22:40:03): that's a bulk write, not an edit.

**Why the date leg can't work.** SQLiteData at the pinned revision (`26471412`):
- The user-table `AFTER UPDATE` trigger has no `WHEN` (`Triggers.swift`, `afterUpdate`). Every `UPDATE`,
  including one that writes the same values, sets `userModificationTime` to now and queues a send. That covers
  upserts, seeding, restore, and an editor save that changes nothing.
- At send time, `CKRecord.update(with:userModificationTime:)` starts from the cached all-fields record, and
  `setValue` changes a field, and the record's stamp, only when the value differs
  (`CloudKit+StructuredQueries.swift`). So a row with nothing changed sends a record that keeps its old stamp.
- `refreshLastKnownServerRecord` replaces the cached record only when the returned `modificationDate` is newer,
  so after a no-op send the cache doesn't move.

A write that changes nothing therefore leaves `userModificationTime` past the cached `modificationDate` for good,
and the cached record's stamp looks the same as for an edit that never left. Slice 3's branch list assumed that
stamp could tell the two apart. It can't; only the content can.

### Build

1. **jon-platform `CloudSyncKit`.** This amends Slice 1's "never decode all-fields" rule, bounded as below.
   - **Split the date leg.** `localEditAfterServer(delta:)` becomes two reasons:
     - `unsentEdit(delta:)`: the row differs from the cached all-fields record. It counts.
     - `stampOnly(delta:)`: the row matches it. It doesn't count.
     `noServerRecord`, `undecodable`, and `noChangeTag` are unchanged and still count. The report, the diagnosis,
     and `requeue` all go through this one predicate, so Retry never re-queues a stamp-only row.
   - **Compare the way SQLiteData encodes.** For each writable column, rebuild its `QueryBinding` from the table
     type, using `T.TableColumns.writableColumns` and `Value(queryOutput:).queryBinding` (the switch in
     `update(with:userModificationTime:)`). Never compare raw SQLite values: a date is TEXT in SQLite but a `Date`
     on the record, a Bool is 0/1, and a UUID is stored lowercased on the record. The rules:
     - `.null` matches only when the field is absent from both `encryptedValues` and the plain values.
     - `.blob` matches when its sha256 equals `encryptedValues["<column>_hash"]`.
     - `.uuid` matches the lowercased string.
     - Every other kind matches an equal value of the same type.
     Any differing column means `unsentEdit`. So does anything the check can't settle: a missing or undecodable
     all-fields blob, a missing row, or a `recordType` with no table type. When in doubt, count it.
   - **The tables.** The report, the diagnosis, and `requeue` take the synced table types the way `SyncEngine`
     does (a parameter pack of `PrimaryKeyedTable` types). The package stays domain-free.
   - **Cost.** Decode all-fields only for rows that fail the date leg. Read them through a cursor, one at a time,
     and never hold the blobs together. The caller owns a verdict cache, a small `Sendable` type in the package
     keyed by `(recordType, primaryKey)`. It holds the `userModificationTime`, the change tag, and the verdict;
     when both values match, the decode is skipped. A local write moves the stamp and a remote change replaces
     the tag, so either one invalidates the entry. The cache lives in memory only.
   - **The diagnosis** adds `stampOnly` and `unsentEdit` to the totals and per-type counts, plus elapsed time and
     how many rows it decoded versus took from the cache. Samples come only from rows that count. An
     `unsentEdit` sample lists the names of the columns that differ, never their values.
   - **Tests**, built in the readout's shape: a row stamped past the cached `modificationDate` that matches its
     all-fields record isn't counted or re-queued; the same row with one column changed is counted. Cover each
     binding kind (text, int, double, bool, date, uuid, null against absent, and a blob by hash), plus an unknown
     `recordType`. Build the all-fields fixture with SQLiteData's own encoding (`encryptedValues`, the
     `<column>_hash` key, `encode(with:)` through a secure archiver), and cite the SQLiteData source in a comment.
     If SQLiteData's public API can build that record from a row, use it instead. Keep the report/diagnosis
     parity test, and add a cache-hit test.
2. **Yes Chef.**
   - Pass the synced table list from `YesChefCore`'s `CloudSync` to the report, the diagnosis, and the requeue.
     Keep it the same list `makeSyncEngine` uses; a `YesChefTests` test asserts the two name the same tables.
   - `SyncHealthModel` owns the verdict cache for its lifetime.
   - The DEBUG readout prints the new counts, the elapsed time, the decoded and cached counts, and the differing
     column names on each sample. Nothing else changes.

**Out of scope:**
- The iPad's 189 `noChangeTag` rows. They still count, and they look like sends the server never confirmed. They
  get their own look after the new readout.
- Any write to SQLiteData's metadata. Lowering a stamp would fire the metadata trigger and queue a send.
- A SQLiteData fork, and any change to the triggers.

### Verification

`CloudSyncKit` tests in the jon-platform PR. In Yes Chef: `scripts/check-drift.sh`, the elevated generic iOS build,
and `YesChefTests`.

### Jon's pass

Install on both devices. On the iPad, then the iPhone: Settings → Sync → detail → **Diagnose** → **Copy**, and
paste both readouts into the architect session before tapping Retry. Expected: most of the iPad's
`localEditAfterServer` turns into `stampOnly`; what still counts is about the 189 tagless rows plus any real
unsent edits; and the iPhone is near zero. Then repeat Slice 2's status pass.

### Done when

Both PRs are merged and green. `DONE-LOG.md` has the entry, and `NEXT_UP.md` reads `Nothing dispatched.` until
the readout says what the remaining rows are. The pass is in `device-passes.md`.

## Slice 5 — Find deletes that never reached iCloud

**What happened (2026-10-23).** Slice 4's readout showed the iPad holding about 300 rows CloudKit had refused,
the iPhone healthy, and a title edit syncing normally. Jon split Beef Bulgogi's instructions into named sections
on the iPad. The new rows only reached the iPhone after he re-saved the recipe (rename + tags), and then the
iPhone showed every step twice: the old flat section and steps, then the new named sections. The iPad's deletes
of the old rows never reached iCloud. Sync status didn't flag it, and nothing on the iPad could have.

**Why the status can't see a lost delete.** SQLiteData at the pinned revision (`26471412`):
- A user `DELETE` sets `_isDeleted = 1` on the metadata row (`Triggers.swift`, `afterDeleteFromUser`), and
  `didDelete` queues a `.deleteRecord`.
- When the engine builds the send batch, `pendingRecordZoneChanges` **deletes the metadata rows for every queued
  delete** (`SyncEngine.swift`, the `SyncMetadata.findAll(deletedRecordIDs).delete()` before `return changes`).
  That happens before CloudKit answers.
- `handleSentRecordZoneChanges` re-queues a failed delete only for `.batchRequestFailed` (and parks
  `.referenceViolation` as unsynced). Every other code is a bare `break`. That is harmless for transient codes
  (network, rate limiting, `zoneBusy`, `serviceUnavailable`), because `CKSyncEngine` keeps those changes queued
  and retries them itself (Apple's "Error Handling" docs; maintainer reply on upstream #432). Permanent codes
  (`quotaExceeded`, `limitExceeded`, `invalidArguments`, `constraintViolation`, and the like) are dropped for good.
- **Same on the latest release.** Checked 2026-10-23: 1.12.1 and `main` (`37c461a`) have both the `.delete()`
  above and the same failure handling. Upstream #547 and its open fix #548 report the save side (a dropped parent
  save, then the child deleted locally by `.referenceViolation`). No issue or discussion reports lost deletes.

A delete that fails with a permanent code therefore leaves no user row, no metadata row, and no queued change.
`CloudSyncKit`'s report and `requeue` also filter `_isDeleted = 0`, but that isn't the real gap: once the batch
is built, there is nothing local left to count. **The only remaining evidence is in iCloud:** a record that still
exists there but that this device deleted. This slice adds an on-demand check against iCloud.

### Build

1. **jon-platform `CloudSyncKit` (additive).**
   - **`CloudSync.leftoverCheck`**: list every record ID in the private zones the metadatabase names (the
     distinct `zoneName`/`ownerName`). Use `recordZoneChanges(inZoneWith:since: nil)` with `desiredKeys: []`,
     paging until `moreComing` is false, so you get IDs, types, and `modificationDate` only. Put the CloudKit
     calls behind a small protocol so tests can run against a fake.
   - **A record is a leftover only if all of these hold:**
     - its `recordType` is in the `SyncedTables` passed in;
     - there's no metadata row for it (record name is `"<primaryKey>:<recordType>"`, as in SQLiteData's
       `SyncMetadata`);
     - there's no row in its table with that key;
     - it isn't in `sqlitedata_icloud_unsyncedRecordIDs` (that's an inbound row not yet applied, not a lost
       delete);
     - its `modificationDate` is before the check's start (anything newer may simply not have been fetched yet).

     Group record types that aren't in `SyncedTables` (for example `categorySeedStates`) separately, by count.
     They are never deleted.

     One false positive remains: a record this device never received because SQLiteData swallowed an error
     applying it. It looks just like a lost delete. That's why the check runs only when tapped, shows every
     item's content, and deletes only what the user confirms.
   - **Preconditions**, so a record that hasn't arrived yet isn't mistaken for a lost delete: the engine is
     running, the pending count is zero, and it isn't sending. Otherwise return `.notIdle`. The caller runs a
     fetch first (below).
   - **Detail for confirmation.** For leftovers only, fetch the full records in batches of 200 or fewer, so the
     app can show each one (step text, line text, section name, and the parent recipe's title). Return those
     plus counts per table.
   - **`CloudSync.deleteLeftovers(_:)`**: delete exactly the IDs the user confirmed, directly through
     `CKDatabase.modifyRecords(deleting:)` and in batches. Leave SQLiteData's engine untouched. Other devices
     then receive the deletions as normal fetched changes. Report per-record failures; never retry
     automatically.
   - **Tests** against the fake. Cases:
     - a record with no local row and no metadata is listed;
     - one whose metadata is present isn't;
     - one in `unsyncedRecordIDs` isn't;
     - one with a `modificationDate` after the start isn't;
     - an unregistered type is counted separately and never offered for deletion;
     - `.notIdle` when anything is pending;
     - the delete sends only the IDs passed in.
2. **Yes Chef.**
   - In Sync detail, add **Check iCloud for leftovers**, which runs only when tapped. It calls
     `syncEngine.fetchChanges()`, then the check. Show progress, since a full listing is about 54k IDs.
   - Group results by recipe title, and list each item's kind and text (for example "Step: Marinate the
     beef…"). Leftovers without a recipe go under their table name.
   - **Delete from iCloud…** opens a confirmation that states the count and says the copies on Jon's other
     devices will be removed. Nothing is deleted without it.
   - Pass the same `syncedTables` the report uses.
   - The "Up to date" row stays local-only. The check needs the network and is too slow for every refresh, and
     the row's detail text says the check exists.

**Out of scope:**
- Why CloudKit refuses the iPad's sends in the first place. That needs the `🛑 Save failed` error code from
  the iPad's log (subsystem `SQLiteData`, category `CloudKit`, debug level). It's captured separately; the fix
  follows from it.
- Retry vs. re-save. A re-save moved Charred Broccoli's and Bulgogi's stuck sections when Retry hadn't. That waits
  on the same log.
- Any SQLiteData fork, trigger change, or write to its metadata.
- An upstream issue for "metadata deleted before the delete is confirmed". Raise it with the error code in hand.

### Verification

`CloudSyncKit` tests in the jon-platform PR. In Yes Chef: `scripts/check-drift.sh`, the elevated generic iOS build,
and `YesChefTests`.

### Jon's pass

On the iPad (the device whose deletes were lost), with sync idle, tap **Check iCloud for leftovers**. Expected:
Beef Bulgogi's old flat instruction section and steps are listed, unless they were already removed from the
iPhone, plus any other recipe restructured on the iPad since July. Confirm the delete. Then, on the iPhone,
check that those recipes show each step once. Run the check again on the iPad: it should list nothing except the
separately counted unregistered types.

### Done when

Both PRs are merged and green, `DONE-LOG.md` has the entry, `NEXT_UP.md` is advanced, and the pass is in
`device-passes.md`.
