# Effort — Retry parked sync records from their saved copy (vendored SQLiteData patch)

Status: Dispatched
Summary: SQLiteData re-downloads every record parked on a missing parent each time a batch arrives, which
throttles the iPhone's first sync to a standstill; retry parked records from their locally saved server copy,
and make SQLiteData's reported issues readable in Release logs.
Related: [PROD-CUTOVER](../PROD-CUTOVER.md) Step 11 (the iPhone download this was found on) ·
[archive/sqlite-data-reference-violation-patch.md](archive/sqlite-data-reference-violation-patch.md) (the first
vendored patch; same vendor directory, same override) · [sync-activity-log.md](sync-activity-log.md) if plan PR
#410 has merged (an app-side ledger of arrivals; complementary, separate effort)

Schema-free, but **changes sync behavior**: the architect escalates the PR to Jon before merge.

## The problem (2026-11-01)

**The iPhone is stuck, not slow.** Its fresh TestFlight install (Step 11) against the iPad's 2026-10-31 backup:

| Table | iPhone, 11:31 | iPad backup |
|---|---|---|
| recipes | 1,934 | 2,223 |
| ingredientSections | 10 | 2,551 |
| ingredientLines | 111 | 27,613 |
| instructionSections | 2,062 | 2,340 |
| instructionSteps | 1,749 | 11,330 |
| recipePhotos | 11 | 2,107 |

Settings → Sync on the iPhone reads **"11753 couldn't be saved here"**: rows in
`sqlitedata_icloud_unsyncedRecordIDs`. Those records downloaded, and SQLiteData parked them because a row they
reference wasn't on the device yet (`ingredientLines.sectionID` is `NOT NULL REFERENCES ingredientSections`, and
so on). CloudKit delivers zone changes in server order, not parents first, so a first sync parks children
routinely. Jon also reports the counts have stopped moving.

**Why it stops (vendored `Vendor/sqlite-data/Sources/SQLiteData/CloudKit/SyncEngine.swift`, 1.8.2):**

- `handleFetchedRecordZoneChanges` (around line 1531), on **every** fetched batch, reads every parked record ID
  and re-downloads all of them with `syncEngine.database.records(for:)`, 150 per request, before applying the
  batch. At 11,753 parked that is about 79 CloudKit requests per incoming batch.
- That burst is what CloudKit rate-limits. The whole retry sits in one `withErrorReporting`, so one throttled
  request throws away every record the retry had already fetched, and reports one issue. The 47-minute log
  archive shows exactly that: one `com.apple.runtime-issues:SQLiteData` fault per fetch cycle (redacted to
  `<private>` in Release), two or three seconds before CloudKit's `requestRateLimited` (code 7) ends the engine's
  own fetch.
- Each cycle then applies only the new batch, parks more children, and makes the next burst bigger. Re-opening
  the app restarts the same cycle.

Upstream `main` has the same code; its last change there (#359) added the 150-per-request batching.

**What makes a local retry possible.** `upsertFromServerRecord(_:force:db:)` (around line 1987) inserts the
record's `SyncMetadata` row, carrying the full server record in `lastKnownServerRecord` and
`_lastKnownServerRecordAllFields`, **before** it tries the row upsert. The foreign-key branch (around line 2054)
catches the failure and parks the ID, and the metadata row stays. So a parked record's server copy is already on
the device, and retrying it needs no network.

## The patch (vendored `SyncEngine.swift`)

1. **Keep the saved copy current.** In `upsertFromServerRecord`'s foreign-key branch, also store this
   `serverRecord` on the record's metadata (the call the success path makes, `setLastKnownServerRecord`). Today a
   re-delivered version of an already-parked record leaves the older copy in place, because the insert's
   `onConflict` doesn't refresh it for a known table. A retry must never apply an older version than the device
   has received.
2. **Retry from the saved copy, not CloudKit.** Replace the per-batch network re-fetch. For each parked ID not in
   the current batch, read its metadata's saved record and add it to the batch's modifications, which are already
   sorted parents-first and applied in one write. Success already removes the ID from the parked table; a
   foreign-key failure leaves it parked.
3. **Retry only what could now succeed.** On an ordinary batch, retry the parked records whose table has a
   foreign key to a table that received at least one record in this batch (`foreignKeysByTableName`). On the
   **first fetched batch after the engine starts**, retry every parked record once. That drains a device that
   parked records under the unpatched build (the iPhone's 11,753, some of whose parents have since arrived).
4. **The network only as a fallback.** Fetch from CloudKit only the parked records whose saved copy is missing
   or can't be applied: no saved record, or one whose asset file is gone (a saved `CKAsset` points at a file
   CloudKit may have removed; that is the "Asset data not found on disk" path). At most one 150-record request
   per batch. Any error there, a throttle included, ends the fallback for this batch only; it never discards
   records the local retry applied, and it never aborts the batch. A record CloudKit reports `unknownItem` is
   still dropped from the parked table, as today.
5. **Log each batch** through the engine's `logger`, at `.notice` (`logger.log`), every value marked
   `privacy: .public`: the batch's record count, parked before, retried locally, applied, still parked, network
   fallback count and outcome, and the duration. `.debug` and `.info` lines don't survive a `log collect`, and a
   Release build redacts anything not marked public.

Change nothing else: not the send path, not the reference-violation patch, not deletions.

## Readable issues in Release builds (Yes Chef app)

SQLiteData reports its failures through IssueReporting. In a Release build the default reporter writes them as
redacted faults, so the log shows that something failed, never what. Add a reporter, installed once at app
launch before the sync engine starts, that **appends** to `IssueReporters.current` (never replaces it, so Debug
runtime warnings keep working) and logs each issue's message and `fileID:line` at `.error`, public, under Yes
Chef's subsystem in a `sync` category (reuse `AppLog.sync` if the sync-activity-log effort has added it).
GRDB errors don't include bound values by default; keep it that way, and log no record field values.

## Wiring

- Same vendor directory and override as the first patch. Update `Vendor/sqlite-data/YESCHEF-PATCH.md`: name the
  second changed function(s), describe this patch, and widen the exit condition: return to the remote package
  only when an upstream release fixes **both** #547 and this re-fetch (the architect files the upstream issue
  and adds its link).
- **Commit the patch on its own,** separate from the reporter and the docs, so the vendor change reads as one
  diff.
- Don't edit `YesChefPackage/Package.swift` or jon-platform's `CloudSyncKit/Package.swift`.

## Not in this effort

- **The throttle re-fetch loop** this brief first proposed. It only helps once batches stop provoking their own
  throttles. Reconsider if the activity log shows fetches stalling after this ships.
- **Galavant.** It uses upstream SQLiteData through `CloudSyncKit`, so it has the same re-fetch; the architect
  records it on jon-platform's `SEAM-LEDGER.md` row for the patched SQLiteData.
- **A Sync-screen count of records skipped by non-foreign-key errors.** The readable issues will show whether
  any exist; size it then.

## Done when

- Tests in `Vendor/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/` (`ForeignKeyConstraintTests.swift` or
  `FetchRecordZoneChangesTests.swift`), with `MockCloudDatabase`:
  - a child arrives before its parent and is parked; the parent arrives in a later batch, and the child is
    applied **with no `records(for:)` call** to the mock;
  - a newer version of a still-parked child arrives, and once the parent arrives the row has the newer values;
  - a parked record with no saved copy falls back to the network, at most 150 per batch;
  - a throttled fallback leaves the local retries applied and the rest parked, and the batch's own records are
    applied;
  - the first batch after start retries every parked record, and a parked child whose parent is already present
    is applied then;
  - every existing test passes unchanged.
- The issue reporter has an app test: an issue reported after installing reaches it, the default reporter is
  still installed, and installing twice adds it once.
- The completing PR appends this gate to `device-passes.md`:
  > **Parked-record retry** ([effort brief](efforts/archive/sqlite-data-parked-retry.md), schema-free). Install
  > the TestFlight build on the iPhone **as an update; never delete the app**. Write down Settings → Sync's
  > "couldn't be saved here" number and the record counts first. Keep Yes Chef open for an hour: the parked
  > number falls, `ingredientSections`, `ingredientLines` and `instructionSteps` climb toward the iPad's, and
  > the whole library eventually arrives (then Step 11's count check). Run
  > `sudo log collect --device-udid <udid> --last 1h` and hand the archive to the architect: each batch has a
  > public parked-retry line, and SQLiteData issues read as text, not `<private>`.
- Closeout per ADR-0005 D16 (`jon-platform/scripts/closeout`), advancing `NEXT_UP.md` per ADR-0005 D12.

## Verification

- `scripts/quiet-run swift test --package-path Vendor/sqlite-data --filter 'ForeignKeyConstraintTests|FetchRecordZoneChangesTests'`,
  then the package's whole suite once. If its CloudKit tests can't run on macOS, run them with `xcodebuild test`
  on an iOS simulator and say so.
- `scripts/check-drift.sh`, the generic iOS build, and `YesChefTests` (the reporter is app code).
- No simulator installs or screenshots. **Fail fast:** if a build or toolchain step fails, paste the error and
  stop; don't retry with variations.
- If the saved copy turns out **not** to be present for parked records (the metadata insert rolls back with the
  failed upsert, for example), stop and ask in the PR with the `question-for-architect` label. The patch
  depends on it.
