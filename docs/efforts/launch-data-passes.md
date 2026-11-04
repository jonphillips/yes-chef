# Effort — Take the data passes off the launch path

Status: Ready
Summary: Five data passes run in one write transaction on the main thread, before the first frame, on every launch
(about 5 s or more when measured 2026-10-28). Run them after launch and before sync starts, and only when their
version has changed.

One small local table, one append-only migration, and nothing added to CloudKit.
Related: ADR-0030 (restore) · ADR-0056 (the cut). `Schema.swift`'s `bootstrapDatabase`, in its
`runsPostEngineDataPasses` block, is where the passes run today.

## The problem

`YesChefApp.init` calls `bootstrapDatabase()` inside `prepareDependencies`. Once the sync engine is built, the live
app runs these in one `database.write`:

1. `CategoryRepository.seedStarterFacets`
2. `RecipeRepository.backfillVariationAnchors`
3. `RecipeRepository.reparseIngredientRanges`, which loads all ~27,600 ingredient lines
4. `RecipeRepository.backfillCuisineCourseFacets`
5. `RecipeSyncRepair.run`, inside a savepoint, which reads every recipe's sync metadata

The passes are idempotent, so on most launches this is a long way of changing nothing. A thrown error from passes
1–4 also crashes the launch, through `try!`.

## Decisions

- **Passes must still finish before sync starts.** Today they run before `startIfManuallyEnabled`. Keep that
  order, because `RecipeSyncRepair` reads and requeues sync metadata and shouldn't race an engine that's sending.
  Sync may start a few seconds later on a launch that runs them.
- **The version lives in the database, not in `UserDefaults`.** A restored backup can predate a pass. Keeping the
  version in the store means a restore brings back the older number, and the passes run again. A `UserDefaults`
  value would stay current and skip them. `PRAGMA user_version` isn't available: `DatabaseBackup` uses it for the
  schema version.
- **Keep the passes; don't retire any in this effort.** The version check takes the launch cost to zero. Retiring
  one means deciding which old backups still need it, and that can wait.
- **A failed pass doesn't stop the launch.** Log it through `AppLog.dataIntegrity`, report it as an issue, leave the
  version unchanged so the next launch retries, and still start sync. Today's savepoint handling for
  `RecipeSyncRepair` stays.

**Persistent model change (AGENTS.md).**
- **What:** a new local table, `localDataPassState`, with one row holding an integer `version`. It is not in
  `syncedTables`, so nothing changes in CloudKit.
- **Existing data:** untouched. A store with no row counts as version 0, so the first launch after the update runs
  the passes once.
- **Migration:** one appended migration, and `declaredSchemaVersion` goes from 55 to 56.
- **Simpler alternative:** moving the passes off the main thread with no version check needs no schema, but it holds
  the write lock for several seconds on every launch, which stalls the first edit and any incoming sync. Rejected.

## Build

1. **Move the passes** out of `bootstrapDatabase` into a Core function such as
   `YesChefDataPasses.runIfNeeded(in:)`, and remove the `runsPostEngineDataPasses` parameter. Previews, tests and the
   share extension already skip them, and nothing calls the new function for those.
2. **Call it off the main thread, then start sync.** In `YesChefApp.init`'s existing launch `Task`, await the passes
   before `startIfManuallyEnabled`. The database writer provides the isolation.
3. **Use a separate write for each pass**, with `RecipeSyncRepair` keeping its savepoint, so an edit made during the
   run waits for one pass rather than all five. Write the version in a final step, only after all five succeed. A
   crash partway through just repeats idempotent work.
4. **The version** is a Core constant that starts at 1, with a comment saying to raise it when a pass changes or a new
   one is added.
5. **Log each pass's duration** with `AppLog.performance`, plus one line when the check skips them. That replaces the
   2026-10-28 estimate with a real number.

## Tests

In `YesChefCoreTests`:
- A store with no row runs the passes and records the current version.
- A store at the current version skips them. Prove it with a row a pass would repair, left unchanged.
- A store at a lower version runs them again, which is the restored-backup case.
- A failing pass leaves the version unchanged and still runs the other passes. Inject the failure rather than
  corrupting data.
- The new table isn't in `syncedTables`.
- The existing per-pass tests still pass unchanged.

**Verification:** `scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator (guardrail #9;
the commands are in [`verification.md`](../verification.md)).

**Done when:** the build items are in, the tests pass, and closeout runs.

## Device pass (Jon)

On the iPad, on a build with this change:

1. Launch once after the update. The library appears right away, and the log shows the passes running with their
   durations.
2. Force-quit and launch again. The log shows them skipped.
3. Make an edit on the iPad and confirm it reaches the iPhone, so sync still starts.
