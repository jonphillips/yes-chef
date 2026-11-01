# Effort — Keep fetching after a CloudKit throttle while the app is open

Status: Ready
Summary: A throttled CloudKit fetch stalls until the app is next foregrounded, and SQLiteData's per-record
failures are unreadable in device logs; add a `CloudSyncKit` catch-up loop and public sync logging, wired into Yes Chef.
Related: [PROD-CUTOVER](../PROD-CUTOVER.md) Step 11 (the iPhone download this was found on) · jon-platform
`docs/ios/persistence-and-sync.md` § the share-extension re-drain (the scene-activation hook this sits beside) ·
jon-platform `docs/agent-collaboration.md` § Dispatches whose code lands in jon-platform (the two-PR shape)

Schema-free, but **touches sync**: the architect escalates both PRs to Jon before merge.

## The problem (2026-11-01 iPhone log, 10:28–11:17)

The iPhone's fresh TestFlight install (Step 11) is downloading the Production library far more slowly than
the throttle alone explains. A 47-minute log archive shows why. Every fetch runs the same way:

1. The app comes to the foreground. `CKSyncEngine` starts a fetch.
2. It downloads for 1–17 seconds, then CloudKit returns `CKError.requestRateLimited` (code 7) with a
   `retryAfterSeconds` of 3–24 seconds.
3. **Nothing fetches again until the app is next foregrounded,** even though the app stays running. The worst
   case: throttled at 10:54:14 with a 3-second retry-after, next fetch at 11:12:41, 18 minutes later. The app
   logged network and audio-session activity through the gap, so it was running, not suspended.

The engine hands its retry to the system scheduler (the log also shows `Stored xpcActivityCriteriaOverrides is
missing or invalid`), and the scheduler runs it when it chooses. The only thing that reliably restarted a fetch
was the app returning to the foreground. **Result: about 2 minutes of downloading in 47 minutes.** The throttle
is not the cost; the missing retry is. Step 9c's advice to keep the app in the foreground didn't help for the
same reason: being in the foreground doesn't fetch, coming back to it does.

### And something is failing that no one can read

The same archive has a **fault** from `com.apple.runtime-issues:SQLiteData` in every fetch cycle, 2–3 seconds
before the throttle (eight cycles, eight faults: 10:29:26, 10:31:24, 10:37:08, 10:54:11, 11:13:01, 11:14:18,
11:14:22, 11:15:06). That is IssueReporting's default reporter recording a `withErrorReporting(
.sqliteDataCloudKitFailure)` site. The message is redacted (`<private>` live, `<compose failure>` in the
archive), so we can't tell which record or which error.

It matters because of how SQLiteData applies a fetched batch (`upsertFromServerRecord(_:force:db:)` in the
vendored `SyncEngine.swift`): each record is upserted inside its own `withErrorReporting`. A foreign-key
failure parks the record in `sqlitedata_icloud_unsyncedRecordIDs`, which the Sync screen counts as "couldn't
be saved here". **Any other error reports the issue and skips the record.** Nothing counts it. Meanwhile Jon
reports the iPhone's local record counts have stopped changing. Whether that's a stalled fetch, a fetch that
re-delivers records the device already has, or records being skipped, today's logs can't say. Upstream
SQLiteData's own event logging is `#if DEBUG`, and Galavant uses upstream, so the visibility has to come from
`CloudSyncKit`.

## The fix

While the scene is active and sync is on, call the engine's `fetchChanges()` (SQLiteData's
`SyncEngine.fetchChanges`, which wraps `CKSyncEngine.fetchChanges` for the private and shared engines). When it
throws a throttle, wait the retry-after and call it again. Stop when a fetch completes without throwing, or when
the scene leaves `.active`.

### jon-platform PR: `CloudSyncKit` (additive)

Add a function beside `redrainPendingRecordZoneChangesIfManuallyEnabled`, shaped like it. The name is a
suggestion: `CloudSync.fetchUntilCaughtUpIfManuallyEnabled(configuration:…)`.

- **Gates.** Same as the re-drain: return early when the manual gate is off, and when the account status isn't
  `.available`.
- **The loop.** Call `fetchChanges()`. On success, return. On a `CKError` whose code is `.requestRateLimited`,
  `.zoneBusy` or `.serviceUnavailable`, sleep `retryAfterSeconds` and go again. If `retryAfterSeconds` is
  missing, use a fixed fallback (5 seconds is fine). Any other error ends the loop and is returned.
- **No attempt cap.** The loop is bounded by the scene: the app ends it by cancelling the task when the scene
  leaves `.active`. A sleep must be cancellable, and a cancelled loop must not issue another fetch.
- **Testable without CloudKit.** Inject the fetch, the account status and the clock, the way the re-drain
  injects `stopSyncEngine`/`startSyncEngine` (`@Dependency(\.continuousClock)` for the sleep is fine).
- **A result enum,** like `PendingRecordZoneRedrainResult`: disabled, unavailable, caught up (with the number
  of fetches and throttles), cancelled, failed.
- **Galavant `main` must build unchanged against the branch.** Nothing existing is renamed or made required.

### jon-platform PR: logging that survives a device log collect

Two rules for every line below: **log at `.notice` (`logger.log`) or higher**, because `.debug` and `.info`
lines don't persist into a `log collect` archive (today's per-record CloudKit lines didn't), and **mark every
interpolation `privacy: .public`**, because a Release build otherwise redacts it. The subsystem comes from the
app's configuration (`com.jonphillips.yeschef` for Yes Chef); use a `sync` category.

1. **Every fetch attempt in the loop:** the attempt number, its duration, and how it ended (caught up,
   throttled with code and `retryAfterSeconds`, cancelled, or failed with the error). Each attempt also logs a
   **progress snapshot before and after**: the count of `SyncMetadata` rows (records this device knows from the
   server) and the count of `sqlitedata_icloud_unsyncedRecordIDs` rows. If an attempt downloads but neither
   number moves, the log shows it: that separates "slow" from "re-delivering the same records" from "skipping
   them".
2. **A public issue reporter.** A function the app calls once at bootstrap (suggested name
   `CloudSync.installIssueLogging(configuration:)`) **appends** a reporter to `IssueReporters.current`. It never
   replaces it: the default reporter must keep running, so Debug builds still show runtime warnings. The reporter
   logs every reported issue at `.error` with its message and `fileID:line`, public. That turns each redacted
   `com.apple.runtime-issues:SQLiteData` fault into a readable line naming the failing table and SQLite error.
   Errors from GRDB don't include bound values by default, so record contents don't reach the log. Keep it that
   way, and don't add record field values to any line.

### Yes Chef PR: the wiring (completing PR)

- Forward both functions through the `YesChefCloudSync` facade, as the re-drain is forwarded.
- Install the issue logging once at bootstrap, before the sync engine starts, in Debug and Release.
- Call it from `ExternalDatabaseChangeReloadModifier` on scene `.active`, **after** the pending re-drain
  finishes (the re-drain may stop and start the engine; the fetch loop should run against the restarted one).
- **Cancel it when the scene leaves `.active`.** Today's `onChange` handler starts an unowned `Task {}`; the
  loop needs a task that is cancelled on the next phase change (hold the task and cancel it, or move to a
  `.task(id: scenePhase)`). Don't change the re-drain's behavior or the model reloads.
- No UI. The Sync status section is untouched.

## Not in this effort

- **Galavant's wiring.** The kit change reaches Galavant through the shared package, but calling it on scene
  activation is a one-line change in Galavant's own repo and goes through Galavant's own queue.
- **"Up to date" reading green mid-download** (`open-questions.md`). Related, separate.
- **Counting skipped records on the Sync screen.** A record skipped by a non-foreign-key error is a silent
  failure, and the Sync screen should say so. Decide its shape once the new logs say what is actually failing.
- **Fixing whatever the issue reporter reveals.** That is the next effort, sized by what the logs show.
- **Background fetching.** The loop runs only while the scene is active. Background time stays the system's
  call.

## Done when

- `CloudSyncKit` has the function, and its tests cover: two throttles then success (three fetches, sleeps equal
  to each retry-after); a throttle with no retry-after uses the fallback; a non-throttle error ends the loop and
  is returned; cancellation during a sleep issues no further fetch; the gate off or the account unavailable
  issues no fetch.
- The issue reporter has tests: an issue reported after installing reaches it (inject its log sink), the
  default reporter is still installed, and installing twice adds it once.
- Galavant `main` builds unchanged against the jon-platform branch.
- Yes Chef installs the issue logging at bootstrap, calls the loop on scene activation after the re-drain, and
  cancels it when the scene leaves `.active`.
- The completing Yes Chef PR appends this gate line to `device-passes.md`:
  > **Sync throttle re-fetch** ([effort brief](efforts/archive/sync-throttle-refetch.md), schema-free). On the
  > first TestFlight build with it, on a device mid-download (the iPhone's Step 11 install, or a fresh install
  > or restore), keep Yes Chef open and in the foreground without switching apps. Settings → Sync local record
  > counts keep climbing across several minutes. Then run
  > `sudo log collect --device-udid <udid> --last 30m` and check the `com.jonphillips.yeschef` `sync` lines:
  > each throttle is followed by a new attempt after its retry-after, each attempt shows its before/after
  > progress counts, and any SQLiteData issue appears as a readable line instead of `<private>`. Hand the
  > archive to the architect.
- Closeout per ADR-0005 D16 (`jon-platform/scripts/closeout`), advancing `NEXT_UP.md` per ADR-0005 D12.

## Verification

- jon-platform: `scripts/quiet-run swift test --package-path packages/CloudSyncKit`, plus a `swift build` of
  Galavant's `GalavantLibrary` against the branch. List both in the PR body (no CI in jon-platform).
- Yes Chef: `scripts/check-drift.sh` and the generic iOS build. The change is in a view modifier, not model
  code, so `YesChefTests` is not required unless the wiring moves into a model.
- No simulator installs or screenshots. **Fail fast:** if a build or toolchain step fails, paste the error and
  stop; don't retry with variations.
- **If `fetchChanges()` turns out not to surface the throttle `CKError`** (for example, it returns normally and
  the error only reaches the engine's delegate), stop and ask in the PR with the `question-for-architect`
  label. The design depends on seeing it.
