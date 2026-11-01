# Effort — Sync activity log

Status: Ready
Summary: The TestFlight build records when synced rows arrive and how many, in a local ledger shown in Settings → Sync and written to the console, so a first sync that takes days can be watched without a Debug build.

No schema change, no migration, no vendored-SQLiteData patch, no sync-model change. Drafted 2026-11-01, during
PROD-CUTOVER Step 11. Queued behind [sqlite-data-parked-retry.md](sqlite-data-parked-retry.md), which fixes
why the iPhone's sync is stuck (11,753 parked records re-downloaded on every batch).

Related: [`PROD-CUTOVER.md`](../../PROD-CUTOVER.md) Step 11 ·
[`archive/sync-failure-surfacing.md`](sync-failure-surfacing.md) · jon-platform ADR-0003 (the sync-health
row) · [`YesChefApp/SyncHealthModel.swift`](../../../YesChefApp/SyncHealthModel.swift) ·
[`YesChefApp/SyncStatusSection.swift`](../../../YesChefApp/SyncStatusSection.swift)

## Why

The iPhone's fresh TestFlight install (Step 11) is pulling the whole Production library. On 2026-11-01 at least
20,000 rows were still to come, and Production throttles a first sync, so this takes days. The Release build
can't answer the questions Jon has while he waits:

- **Is it still moving, and when did rows last arrive?**
- **How fast is it going,** in rows per hour and per day?
- **What's behind a gap?** Either the app wasn't running (in the background or terminated), or it was fetching
  and getting nothing back (throttling).

What the Release build has today:

- The status row, and **Local record counts**. Those cover only 11 of the 34 synced tables and load only when
  the sheet opens. They show a snapshot, not a rate or a history.
- SQLiteData's per-event log (`SyncEngine.swift` `handleEvent`, `Internal/Logging.swift`) and the **Sync
  diagnosis** section are behind `#if DEBUG`, so they aren't in TestFlight builds.
- Console.app shows Apple's `com.apple.cloudkit` lines, but only while the phone is plugged in and Console is
  open, with nothing kept for later.

## Design

1. **`SyncActivityLedger` (YesChefCore), a pure value type.** Each entry holds a date, a kind, the total row
   count, and a count for each table. The kinds are `launch`, `foreground`, `background`, `fetchStarted`,
   `fetchEnded` and `sample`. It keeps at most 1,000 entries and drops the oldest first. It derives:
   - **last arrival**: the latest entry whose total is above the entry before it
   - **rows in the last hour** and **rows in the last 24 hours**
   - **rows since the ledger began**
   - **fetches in the last 24 hours**, and how many of them brought zero rows
   - a **CSV** export: one row per entry, with a column per table
2. **Kept in a local JSON file, never the database.** Put it in the app's own Application Support directory, not
   the app group. It must not sync, it must not go into a backup, and a restore must not bring it back. Deleting
   the app clears it. If the file won't decode, start an empty ledger and log one `AppLog.sync` warning. It's
   diagnostics, not user data.
3. **A recorder that lives as long as the app (YesChefApp).** It's one `@MainActor` object owned by `YesChefApp`,
   not by Settings: `SettingsView`'s `SyncHealthModel` only exists while Settings is on screen. It records only
   while sync is turned on (`YesChefCloudSync.isManuallyEnabled()`).
   - It watches the engine's `isFetchingChanges` and records `fetchStarted` and `fetchEnded` when it flips.
   - It watches scene phase and records `foreground` and `background`.
   - It records `launch` once when the app starts.
   - While a fetch runs, it adds a `sample` every 60 seconds.
   - Counting is a `SELECT COUNT(*)` for each name in `YesChefCloudSync.syncedTables.recordTypes`, run in a
     `database.read`, never the writer (see the SQLiteData @Fetch writer-convoy note). Count at most once every 30
     seconds. A flip inside that window records an entry that reuses the last counts.
   - Feed it the fetch state through an injected source, so tests don't need a real CloudKit engine.
4. **A console line for each entry.** Add an `AppLog.sync` category. Each entry logs once at `.notice` with a
   public payload, for example `sync-activity fetchEnded total=41210 delta=+312
   ingredientLines+280,instructionSteps+32`. These lines show up next to Apple's `com.apple.cloudkit` lines in
   Console.app, so Jon can compare our counts with CloudKit's throttling messages.
5. **A Download activity section in Settings → Sync.** Add it to `SyncStatusDetailView` above Local record
   counts, outside `#if DEBUG`. It shows:
   - **Last rows arrived** (relative time)
   - **Last hour** and **Last 24 hours** (rows)
   - **Since** the first entry's date (rows)
   - **Fetches (24 h)**, as "n, m with nothing new"
   - a **Copy activity log** button that puts the CSV on the pasteboard

   The section reads the recorder's state, so it updates while the sheet is open. **Local record counts** now
   lists every synced table and uses the recorder's latest counts. That closes the 11-of-34 gap, and the list
   refreshes as rows arrive instead of only when the sheet opens.

## Not in scope

- **A count of what's still to come.** Production has no `recordName` index, and CloudKit has no cheap way to
  count a zone. Jon compares against the iPad.
- **CKSyncEngine fetch errors in the app.** The parked-retry effort already adds the second vendored patch
  (with a public per-batch log line) and an issue reporter that logs SQLiteData's reported issues readably. If
  it has added `AppLog.sync`, reuse that category here.
- **Lifting this into CloudSyncKit.** It's noted on the existing sync-failure-surface row in jon-platform's
  `SEAM-LEDGER.md`.

## Shipping it during Step 11

Shipping this while the sync is still running is safe, but only by this route:

- **The schema gate is met.** The Lens record types were created in Development and deployed to Production on
  2026-11-01; the Production export matches Development.
- **Install it as a TestFlight update over build 1180. Never delete the app.** The store, the metadatabase and
  the CKSyncEngine state all carry over, because the bundle id and container are unchanged. The update
  restarts the app, which the engine handles like any other termination: it picks up from its last saved
  state. A TestFlight update isn't an Xcode Run and isn't a user edit, so the cut's rules and the freeze still
  hold.
- **Before updating, write down the iPhone's Local record counts.** The ledger starts on the new build, so it
  measures from the update onward.

## Done when

- **Core tests:** the cap drops the oldest entry. Last arrival skips entries that brought nothing. The hour and
  24-hour windows count from the right entries. Fetches with zero rows are counted. The CSV has a header and one
  column per table. The JSON round-trips. A corrupt file gives an empty ledger and one warning.
- **`YesChefTests`:** the recorder records `fetchStarted` and `fetchEnded` when the injected fetch state flips.
  It throttles counting to once every 30 seconds. It records nothing while sync is off. Its counts include
  every table in `syncedTables`.
- **Verification** per [`verification.md`](../../verification.md): `scripts/check-drift.sh`, the elevated generic
  iOS build (run `xcodegen generate` first, for the new files), and `YesChefTests`.
- **Device pass.** The PR adds this to `device-passes.md`: *After the TestFlight update on the iPhone, the Local
  record counts match the ones written down before the update. Download activity fills in within an hour of
  having the app open. Copy activity log pastes a CSV.*
