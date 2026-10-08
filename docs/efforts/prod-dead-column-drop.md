# Effort — Drop the dead cook columns before the Production deploy (ADR-0056 Phase 1)

Status: Dispatched 2026-10-08. **Schema change, synced table.** The architect escalates the PR to Jon.
Summary: Before the CloudKit Production schema locks, drop `Recipe.lastCookedAt` and `Recipe.timesCooked`
(superseded by calendar-derived values) with one ordinary appended migration. Add a test that every table's
on-disk columns match its model, so no other dead column reaches Production unnoticed. There is no migration
squash: per [ADR-0056 Amendment 1](../decisions/ADR-0056-move-to-production-and-data-carry.md#amendment-1--no-squash-before-the-cut-only-the-dead-columns-are-dropped-2026-10-08),
the squash is deferred, optional cleanup.
Related: [ADR-0056](../decisions/ADR-0056-move-to-production-and-data-carry.md) D2 as amended ·
[`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Phase 1 · [`cloudsynckit-backup-lift.md`](cloudsynckit-backup-lift.md)
D4 (the declared schema version this bumps)

## Why this and nothing bigger

Production locks the **CloudKit** schema, not the local migration list. Nothing on Production stops the
local history from being squashed later, as Galavant's cutover showed (Galavant ADR-0049 D3). Before the
cut, the only thing that must change is the dead columns. A record field that isn't in the Production schema
can't be added there afterwards, so the app must stop carrying those fields before the deploy. The Phase 4a
console step then deletes them from the Development schema.

## The migration

Append one migration to `Schema.swift`:

- `ALTER TABLE "recipes" DROP COLUMN "lastCookedAt"` and `... DROP COLUMN "timesCooked"`. Every store has
  both columns, since migration 1 creates them, but guard each on `pragma_table_info` anyway, for the
  restore-candidate path. There's precedent: `Remove legacy menu prep plan BLOB` dropped a column from the
  synced `menus` table the same way. SQLiteData's sync triggers are TEMP triggers installed after the
  migrator runs, so they don't block `DROP COLUMN`.
- Remove the fields, init parameters and `CodingKeys` from `Recipe`, and update the tests that pass them
  (the `Recipe` inits in `MealCalendarTests` and `RecipeBrowserTests`). **Keep `RecipeBrowser`'s own
  `lastCookedAt`/`timesCooked`.** Those are calendar-derived, not the column. Old backup JSON carrying the
  keys still decodes, because unknown keys are ignored.
- No other migration body changes, since the rule is append-only.

## Dead-column test

Add a Core test: migrate an empty store, then for every table check that its columns exactly match its
`@Table` model's columns. Exclude local bookkeeping tables (`grdb_migrations` and any other table with no
model) through an explicit, commented list. **If it finds a dead column other than the two above, stop and
escalate.** Don't drop it on your own judgment, because the Production deploy makes it permanent.

## Declared schema version (D4)

The migrator now has 51 migrations, so `declaredSchemaVersion` becomes **51**. The existing "declared ==
registered count" test covers it unchanged. Backups stamped 50 still restore: 50 ≤ 51, and the new migration
runs on the candidate.

## Done when

- The appended migration and the `Recipe` model change land, with a test that a store with legacy rows
  (cook columns populated) migrates with every other value intact.
- The dead-column test passes, and any other dead column it found has been escalated, not dropped.
- `declaredSchemaVersion` is 51 and the existing test passes.
- `PROD-CUTOVER.md` Phase 1 boxes are ticked, `DONE-LOG.md` has the entry, `NEXT_UP.md` reads `Nothing
  dispatched.`, and the device pass below is in `device-passes.md`.

**Device pass to add:** export a backup from each device first. Then install the build and confirm the
library is intact and "Last cooked" still shows on a cooked recipe. Edit a recipe and confirm the edit syncs
to the other device.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the elevated generic iOS build (`Recipe`'s shape
changes and the app compiles against it), and `YesChefTests`.
