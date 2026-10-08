# Effort — Production baseline squash (ADR-0056 Phase 1)

Status: Dispatched 2026-10-08. **Schema change, touches every device's live store.** The architect escalates the
PR to Jon, and it is **not merged** until the real-store gate below passes on a copy of each device's database.
Summary: Collapse Yes Chef's 50 migrations into one baseline using GRDB's `registerMigration(_:merging:)`. A
fresh install creates the final schema directly. An existing device keeps all of its data: the baseline
adopts its schema, drops the dead `Recipe.lastCookedAt` / `timesCooked` columns and the retired category-seed
tables, and refuses any store that isn't exactly at the final legacy migration.
Related: [ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md) D2 (the decision) ·
[`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Phase 1 (the runbook step this implements) ·
[ADR-0049 Amendment 1](../decisions/ADR-0049-unified-labels-and-assisted-tagging.md) (retires the seed tables) ·
[`cloudsynckit-backup-lift.md`](cloudsynckit-backup-lift.md) D4 (the declared schema version this updates)

## Why `merging:` (read this first)

GRDB 7's `registerMigration(_:merging:)` exists for this exact job. It registers one new migration that names
the old identifiers it replaces. On a store that already applied some of them, GRDB passes the applied set
into the closure and, when the migration commits, **deletes the merged identifiers from `grdb_migrations`**.
Every store, fresh or carried, ends up recording the single baseline identifier. Read the doc comment in
`GRDB/Migration/DatabaseMigrator.swift` before writing anything, and don't hand-roll identifier bookkeeping.

This is a new migration identifier, not an edit to a shipped migration body, so the
never-rewrite-a-shipped-migration rule holds.

## Step 0: freeze the legacy schema as a fixture (before deleting anything)

From current `main`, before touching `Schema.swift`:

- Run today's migrator on an empty store. Commit its `sqlite_master` DDL (tables and indexes, excluding
  `sqlite_*` and `grdb_migrations`) plus the 50 identifiers in order, as a test fixture, for example
  `Tests/YesChefCoreTests/Fixtures/legacy-schema-v50.sql`.
- Record whether today's migrator leaves **any row** in an empty store. Expected: none. If it does, stop and
  escalate, because the baseline would then have to seed those rows too.

The fixture is the frozen record of what every device has today. The tests below build a legacy store from
it, so the old migration code can be deleted.

## The baseline migration

One registration replaces all 50: `registerMigration("<new identifier>", merging: <the 50 identifiers>)`.
Don't reuse any of the old names; GRDB's docs warn against it. The 50 identifiers stay in code as a frozen
constant, since the merge and the guard both need them.

The closure has three branches, chosen by the applied set GRDB passes in:

1. **Fresh (none applied):** create the final schema. Take the DDL from the step-0 fixture **verbatim**,
   minus the dropped columns and tables. Formatting cleanup is fine, but nothing semantic changes:
   `STRICT`, `ON CONFLICT REPLACE`, defaults, foreign keys and indexes all stay as they are. The equivalence
   test is the judge.
2. **Adopt (all 50 applied):** the existing schema already *is* the baseline. Drop
   `recipes.lastCookedAt` and `recipes.timesCooked` (each guarded on `pragma_table_info`) and
   `DROP TABLE IF EXISTS` the two seed tables. Nothing else changes.
3. **Anything else → throw** a named error and change nothing. That covers a store with only some of the 50
   applied, and a store whose `grdb_migrations` holds an identifier that is neither legacy nor the baseline
   (a feature-branch build that never merged). GRDB only passes in the *merged* ones, so query
   `grdb_migrations` directly for strays. A throw is recoverable because the transaction rolls back, and
   Jon can reinstall the previous build. Adopting a store that doesn't match is not recoverable.

**What gets dropped:**
- `recipes.lastCookedAt` and `recipes.timesCooked`. Remove the fields, init parameters and `CodingKeys` from
  `Recipe`, and update the tests that pass them (`MealCalendarTests`, `RecipeBrowserTests`'s Recipe
  inits). `RecipeBrowser`'s own `lastCookedAt`/`timesCooked` are calendar-derived values. **Keep them.**
  Old backup JSON carrying the keys still decodes, because unknown keys are ignored.
- `categorySeedStates` and `categorySeedTombstones`. They are unregistered in `CloudSync` and only
  `Schema.swift` references them (ADR-0049 Amd 1).

**No other dead columns.** Add a test that every table in the baseline has exactly the columns of its
`@Table` model, with local tables like `grdb_migrations` excluded by an explicit list. If it finds a dead
column beyond the ones above, **stop and escalate**. Don't drop it on your own judgment: whatever is still
there when Production deploys is locked in for good.

Delete the old migration bodies and any helper only they used (`LegacyMenuPrepPlanRow`,
`LegacyRecipeServeWithRow`, and anything else that becomes unused). The post-engine data passes in
`bootstrapDatabase` (`seedStarterFacets`, the backfills) are **out of scope**. Leave them unchanged.

## Declared schema version (D4)

The baseline makes `declaredSchemaVersion` **51**, which is 50 legacy migrations plus 1. Backups exported
before the squash are stamped 50, so they still restore: 50 ≤ 51, and the adopt branch migrates them.
Replace the "declared == registered count" test with: declared == 50 + the number of migrations registered
after the squash (read the migrator's `migrations`). Add a comment saying any future migration bumps it.

**Consequence to record in the PR body:** a backup from *before* the final legacy migration (stamped below
50) is refused by the squash build, through branch 3. It can only be restored on a pre-squash build.

## Tests (Core)

- **Equivalence:** apply the new migrator to (a) an empty store and (b) a store built from the fixture, with
  all 50 identifiers recorded. Their normalized schemas must be identical. Compare columns by name (type,
  not-null, default, pk), `STRICT`, foreign keys, and indexes (unique and partial included). Column
  *order* may differ.
- **Adopt preserves data:** seed the fixture store with rows in every table (cook columns and seed tables
  included). After migrating, every surviving row and value matches, `PRAGMA integrity_check` is `ok`,
  `PRAGMA foreign_key_check` is empty, and `grdb_migrations` holds only the baseline identifier.
- **Refusals:** a store with 49 of the 50 throws and is byte-unchanged afterwards. The same goes for a store
  with all 50 plus a stray identifier.
- **Restore:** a fixture-built store stamped `user_version = 50` goes through
  `DatabaseBackup` prepare→migrate and is stamped 51. The `DatabaseBackupTests` round-trip still passes.

## Real-store check (the gate; the architect runs it with Jon's files)

Add a test that **skips unless `YESCHEF_REAL_STORE` points at a database file**. It copies that file to a
temp directory, records per-table row counts, and runs `bootstrapDatabase(path:)` on the copy. Then it
asserts:
- row counts are unchanged (the seed tables are gone, and that is expected);
- `integrity_check` is `ok` and `foreign_key_check` is empty;
- the normalized schema equals the fresh baseline's;
- a **stopped** `SyncEngine` can be constructed on the migrated copy, the way `DatabaseBackupTests` already
  constructs one. If that can't run against a file path, say so in the PR. Don't skip it silently.

The input is a backup Jon exports from each device. That is a byte copy of the store, minus the metadatabase.

## Done when

- One registered migration, the merged baseline. The 50 old bodies and their helpers are gone.
- The fixture, equivalence, adopt, refusal and restore tests pass, and so does the column-vs-model test,
  with no unexplained dead columns.
- `Recipe` has no cook fields, and the declared version is 51 with its new rule tested.
- `PROD-CUTOVER.md` Phase 1's code boxes are ticked. The real-store box is ticked by the architect after the
  gate run, not by the executor.
- `DONE-LOG.md` entry, `NEXT_UP.md` set to `Nothing dispatched.`, and the device pass below added to
  `device-passes.md`.

**Device pass to add:** before installing the squash build, launch the current `main` build once on every
device, then export a backup from each. Install the squash build and confirm the library is intact (counts,
photos, a recipe with variations, a menu with prep steps) and that an edit syncs to the other device.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build (because `Recipe`'s
shape changes and the app compiles against it), and `YesChefTests`. Report the real-store test as
**skipped** in CI. The architect runs it against Jon's files before approving.
