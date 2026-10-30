# Effort — Recover the 241 instruction steps from the Step 4 backup (PROD-CUTOVER Step 10a)

Status: **Done → done-log** — implementation and verification complete 2026-10-29; device pass remains owed. Schema-free.
Summary: The Step 9c re-seed left the iPad 241 instruction steps short of the Step 4 backup. They are steps the
first, unpatched attempt deleted, and Production still held those deletes, so the re-seed's download deleted them
again. Add a temporary Settings action that reads a chosen backup and inserts only the instruction steps missing
from this device whose recipe and section are present, keeping their original IDs. The normal write path queues
them for upload. Remove the action once the cut is done.
Related: [`PROD-CUTOVER.md`](../../PROD-CUTOVER.md) Steps 9–10 ·
[ADR-0056 Amd 2](../../decisions/ADR-0056-move-to-production-and-data-carry.md) ·
[`sqlite-data-reference-violation-patch.md`](sqlite-data-reference-violation-patch.md) ·
[ADR-0030](../../decisions/ADR-0030-local-backup-and-restore.md) (backup and restore)

## Why

Step 10's row-count audit (2026-10-29, iPad backup `YesChef-Backup-2026-10-29.sqlite` against the Step 4 iPad
backup):

- Every synced table matches Step 4, except that `recipeCategories` has the 2 extra rows the cuisine/course backfill
  adds, and **`instructionSteps` is 241 short** (11,089 against 11,330).
- All 241 are among the 244 steps the first attempt lost. That attempt's `referenceViolation` handler deleted 41
  `instructionSections` on the device, and the local cascade took their steps. Steps have two foreign keys, so they
  had no CloudKit parent reference and most had already uploaded. The cascade queued deletes for them, so
  Production deleted them too.
- In 9c the restore brought them back. The most likely path (from the counts; no log shows it): the fresh sync state
  downloaded Production's zone, those deletes included, and the steps were deleted again. The 3 steps that never reached Production had no delete, so they
  survived. So did the 41 sections and everything else the first attempt lost: they never reached Production either.
- All 241 steps' recipes and sections are on the iPad now. No step is new on the iPad. None of the 40 recipes has
  a variation.

A full restore can't fix this: it replaces the whole library, discards a day's sync state, and would meet the same
deletes. The rows have to go back by themselves, **with their original IDs**, because variations point at steps by
ID ([[recipe-variations-overlay]]).

## The action

### Core (`YesChefCore`)

A new `InstructionStepRecovery` with two entry points:

1. **Plan:** given a backup file URL, copy it to a temporary directory and bring the copy up to the current schema
   with `migrateRestoreCandidate(at:)`, the same as restore's prepare step. Never open the chosen file itself. Read
   every `InstructionStep` from the copy into memory (about 11k rows). Then, in one read of the live database, keep
   the steps whose:
   - `id` isn't in the live `instructionSteps`;
   - `recipeID` is in the live `recipes`;
   - `sectionID` is in the live `instructionSections`, belonging to that same recipe.
   Return the kept steps, how many recipes they span, and how many backup steps were skipped because their recipe or
   section isn't on this device. Delete the temporary copy before returning.
2. **Apply:** in one live `database.write`, check each planned step's three conditions again (to cover the time
   between Plan and Apply), and insert each step that still passes, unchanged: `id`, `recipeID`, `sectionID`, `text`,
   `sortOrder`, `isOptional`. Insert through the normal StructuredQueries `insert`, so SQLiteData's triggers create
   the sync metadata and queue the upload. Return how many steps were inserted.

Don't attach the backup to the live connection, and don't write anything to the live database except
`instructionSteps` inserts. Don't touch sync metadata. **Don't renumber `sortOrder`**: the iPad has no new steps in
these sections, so the original order is correct as it stands. Running it again must insert nothing.

### App (Settings → Import & Export)

- A button under **Restore from a Backup**: **Recover Missing Instruction Steps**. It reuses the backup file
  importer's content types. Add a separate `fileImporter` only if sharing the existing one gets awkward.
- After a file is picked, run Plan and show one confirmation alert: "Recover 241 instruction steps in 40 recipes?",
  with the skipped count in the message when it isn't zero. When nothing is missing, show "No missing steps in this
  backup." and nothing else.
- Confirming runs Apply and shows the inserted count. Errors use the same alert pattern as restore.
- Keep the logic in Core and the view thin. Mark the button and its model `// TEMPORARY: PROD-CUTOVER Step 10a`,
  because Step 13 removes them.

## Tests (`YesChefCoreTests`)

On a temporary backup database and a separate live one:

- Missing steps whose recipe and section are present are inserted with every field equal to the backup's.
- A step whose recipe is missing, or whose section is missing, or whose section belongs to a different recipe, is
  skipped and counted in the skipped total.
- A step that already exists live is left alone, even when its text differs from the backup's.
- Running Plan and Apply a second time inserts nothing.
- The chosen backup file is byte-identical afterward.

## Out of scope

Any other table (every other table matches Step 4). A general row-level "merge from backup". Changing restore, sync,
or the vendored SQLiteData. The "Up to date" blind spots and the launch-time passes (`open-questions.md`).

## Verification

- `YesChefCoreTests` for the new suite, then the whole `YesChefPackage` test run once.
- `YesChefAppTests`, if the app model gets logic beyond calling Core ([[app-test-target-not-in-verification]]).
- `scripts/check-drift.sh`, plus the generic device build from `docs/AGENTS.md`.
- No simulator or device installs. Jon does the device pass (below).

## Done when

- One Yes Chef PR with the Core type, its tests, and the Settings button, all verification above green.
- It sets `NEXT_UP.md` to `Nothing dispatched.`, adds a `DONE-LOG.md` entry, and ticks PROD-CUTOVER **10a**'s
  build item.
- **Device pass (Jon, then the architect):** upload with `testflight`, install it on the iPad, then Settings →
  Recover Missing Instruction Steps → the Step 4 iPad backup (`YesChef-Backup-2026-10-27 ipad.sqlite`). Expect
  **241 steps in 40 recipes**, with nothing skipped. Afterward, Local record counts show `instructionSteps` at 11,330, and
  **American, French, and Frozen Custard Style Vanilla Ice Cream** has its 37 steps back. Keep Yes Chef open until
  Sync lists nothing not uploaded, then export a backup. The architect re-runs the Step 4 comparison.
