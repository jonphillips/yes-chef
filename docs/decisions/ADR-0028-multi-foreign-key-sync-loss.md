# ADR-0028 — Child records with two foreign keys silently fail to sync (recipe content lost on consuming devices)

> **One-line:** SQLiteData's CloudKit `SyncEngine` only models a parent relationship for a synced
> table that has **exactly one** foreign key. Yes Chef's recipe-*content* tables each carry **two**
> `NOT NULL … ON DELETE CASCADE` foreign keys, so their rows never apply on a consuming device — the
> producer uploads them, but a second device gets empty ingredients / directions / menu items. Fix:
> reduce every synced child table to **at most one real FK**, demoting the extras to loose `TEXT`
> pointers (the pattern already used for `recipes.coverPhotoID`). Plus a second, independent bug found
> the same session: demo-data seeding was polluting the live synced store with deterministic keys.

Status: **Proposed** — 2026-07-10 (diagnosed live during a two-device dogfood; iPad 2162 recipes ↔
iPhone 2158, iPhone shells-only). Extends **[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (CloudKit
sync, no server) — this is a sync-**correctness** defect on the one-way gate everything else precedes.
Holds **[[sqlitedata-single-fk-sync-limit]]**. Related prior FK-limit workaround: the `coverPhotoID`
loose pointer (`Schema.swift` "Add recipe cover photo pointer" migration) and
**[[debug-erase-vs-sync-triggers]]** (sync triggers × schema-change interaction — directly relevant to the
migration risk below).

## Context

Dogfooding sync across two devices (2026-07-10). The iPad held the real 2158-recipe library and had been
edited a little; the iPhone was brought online fresh. After a few hours both devices reported **"Up to
date."** The iPhone showed the **same recipe count** (2158 vs the iPad's 2162) with correct titles,
sources, times, servings — but **every recipe had zero ingredients and zero directions, no cover photos,
and the Menus and Meal Calendar were empty.**

We could not tell data-loss from an under-built compact UI by inspection, so we went to ground truth:

1. **CloudKit Dashboard (Private DB, `co.pointfree.SQLiteData.defaultZone`).** The real records **are on
   the server** — `ingredientLines` and `menuItems` with real UUIDs, in quantity. So the **producer
   (iPad) uploaded them.** Not a backfill gap.
2. **iPhone screenshots.** The recipe detail rendered every field that lives *on the recipe row*
   (title, "About 4 cups", "20 min", "Milk Street", the Ingredients/Directions tabs, "4 servings ·×1")
   but **zero child rows** under each. That is *empty scaffolding* — the UI faithfully rendering an empty
   dataset, **not** a layout bug. So the child rows are **absent from the iPhone's local database**,
   despite being in the cloud and despite 2158 recipe rows applying cleanly.

The `00000000-0000-0000-0000-…` records also seen in the zone are a **separate** bug (demo seeding — see
"Second defect" below), not the cause of the content loss.

## Root cause

SQLiteData assigns a CloudKit **parent** relationship to a synced table **only when it has exactly one
foreign key**. The gate is literal and repeated:

```swift
// SQLiteData/CloudKit/SyncEngine.swift  (≈ lines 958, 1708, 1968, 2324)
let parentForeignKey =
  foreignKeysByTableName[tableName]?.count == 1
  ? foreignKeysByTableName[tableName]?.first
  : nil
```

A table with **two** FKs gets `parentForeignKey = nil`, drops out of the hierarchy modeling **and** the
consumer-side reference-violation recovery (2-FK tables hit the `else { continue }` at ~1710 and are
skipped). Their `NOT NULL` local FK constraints then cannot be reliably satisfied when the consumer
applies the downloaded records, so the inserts are dropped — while FK-free `recipes` and single-FK
`recipeSources` apply fine.

Line up the schema (`Schema.swift`) against what is empty on the iPhone:

| Table | Foreign keys | On the iPhone |
|---|---|---|
| `recipes` | 0 | ✅ 2158 present |
| `recipeSources` | 1 (`recipeID`) | ✅ present — the "Milk Street" that *does* render |
| **`ingredientLines`** | **2** (`recipeID` + `sectionID`) | ❌ empty |
| **`instructionSteps`** | **2** (`recipeID` + `sectionID`) | ❌ empty |
| **`menuItems`** | **2** (`menuID` + `recipeID`) | ❌ empty |

The three tables holding actual recipe *content* are exactly the two-FK tables. `recipePhotos` (1 FK,
CKAssets), `menus` (0 FK), and `mealPlanItems` (1 FK) also looked empty; those are **unconfirmed** and
may be a knock-on (items gone → parents render empty) or a distinct issue. The debug count row shipped
with this ADR maps them precisely.

## Decision

**Every synced child table carries at most one real foreign key.** Redundant/secondary references become
plain `TEXT` columns (no `REFERENCES`) — "loose pointers", identical to `recipes.coverPhotoID`:

- **`ingredientLines`, `instructionSteps`:** keep **`sectionID`** as the sole FK; demote **`recipeID`**
  to a loose `TEXT NOT NULL` column. No behavior lost — the row still cascade-deletes through
  `section → recipe`, and `recipeID` (and its index) stays for direct queries.
- **`menuItems`:** keep **`menuID`** as the sole FK; demote **`recipeID`** to a loose `TEXT` column.
  `recipeID` was `ON DELETE SET NULL`; with a loose pointer a deleted recipe leaves a dangling id, which
  the app must tolerate. (This is *more* consistent with **[[menu-item-recipe-id-invariant]]**, which
  already requires recipe-kind rows to keep a `recipeID`.)

This is a schema migration plus a **CloudKit zone rebuild** (existing cloud records were uploaded under
the old, parentless structure), rolled out so the **iPad's data is never at risk**.

### The migration (written, NOT yet wired — see Rollout)

Standard STRICT-table rebuild per table: create the new table with the corrected columns, copy rows,
drop old, rename, recreate indexes. **Critical interaction:** on an existing install the previous run's
`SyncEngine` metadata **triggers** live in the DB file and reference these tables; dropping the table
drops its triggers (SQLite cascades), and `makeSyncEngine` re-creates them on the next start (bootstrap
runs the migrator *before* engine construction). This is the same class of schema-drift-×-sync-trigger
interaction that once wiped the dogfood library (**[[debug-erase-vs-sync-triggers]]**), so the migration
**must be tested against a restored iPad backup in a simulator before the iPad ever runs it.**

Exact current column lists to preserve (post-all-migrations):
- `ingredientLines`: id, recipeID, sectionID, originalText, quantity, quantityText, unit, item,
  preparation, comment, isOptional, shoppingCategory, doNotShop, isHeader, sortOrder, confidence,
  canonicalName. (`substitution` was added then dropped — absent.)
- `instructionSteps`: id, recipeID, sectionID, text, sortOrder, isOptional.
- `menuItems`: id, menuID, kind, recipeID, title, dayOffset, mealSlot, notes, sortOrder, dateCreated,
  dateModified, scale.

## Rollout (iPad is master; iPhone is disposable)

**Phase 0 — deployed with this ADR (non-destructive, no table rebuild):**
- Demo seeding gated out of the live/synced store (`SampleData.seedSampleDataIfNeeded`).
- Debug **"Local record counts"** section in the Sync detail sheet (`SyncStatusSection` +
  `SyncHealthModel.loadRecordCounts`).
- **Action:** back up the iPad **first** (Xcode → Devices and Simulators → iPad → YesChef → ⚙︎ →
  *Download Container* → save the `.xcappdata`; that bundle *is* the copy of the work done). Then install
  this build on both devices and read the counts. Expected confirmation: iPhone `ingredientLines`/
  `instructionSteps`/`menuItems` ≈ 0 while iPad ≫ 0. Capture the iPhone device console during a resync —
  expect `FOREIGN KEY constraint failed` as those records apply.

**Phase 1 — the fix (after Phase 0 confirms + backup exists):**
1. Wire the rebuild migration; **test it against the restored iPad backup in a simulator** (must retain
   all rows and re-establish sync triggers cleanly).
2. Rebuild the CloudKit zone so records re-upload with the corrected structure. Because the iPad is
   master and the iPhone is empty, drive it from the iPad: reset the zone, let the iPad re-upload its
   (migrated) library, then reset the iPhone's local store so it pulls a clean copy. **Do not run any
   zone-delete flow that can cascade-delete the iPad's local rows** — verify iPad counts unchanged after
   each step.
3. Also purge the leftover `00000000-…` demo rows (Second defect).

**Fallback if the in-place migration proves risky:** export the iPad library to a portable format
(`IMPORT_EXPORT.md`), wipe the app, install the fixed build (fresh corrected schema), reimport. Sidesteps
the trigger-rebuild interaction entirely — chosen at Phase 1 if the simulator test on the backup is not
clean.

## Second defect (independent, fixed in Phase 0)

`seedSampleDataIfNeeded()` (`YesChefApp.swift:16`) ran unconditionally at launch, seeding demo recipes
with **deterministic** primary keys (`SampleUUIDSequence` → `00000000-0000-0000-0000-<12 digits>`) into
the **live, synced** store. Every device manufactures the *same* keys, which collide across devices under
the tables' `ON CONFLICT REPLACE` primary keys (the likely source of the 2162 vs 2158 gap) and push demo
rows into the shared zone. **Fix:** seeding now only runs in non-`.live` contexts (previews/tests) or
under an explicit `-YesChefSeedSampleData` launch argument. Existing demo rows are purged in Phase 1.

## Consequences

- **Sync correctness restored** for recipe content, menus, and (pending confirmation) the remaining child
  tables — the milestone gate.
- **No data loss on the iPad**, protected by backup + master-driven zone rebuild.
- **Loose pointers** (`ingredientLines.recipeID`, `instructionSteps.recipeID`, `menuItems.recipeID`) lose
  their DB-enforced referential integrity; cascade still holds via the retained FK chain for the first
  two, and menu-item dangling ids must be tolerated in app code.
- **Design rule going forward (see [[sqlitedata-single-fk-sync-limit]]):** a synced table may declare at
  most one `REFERENCES` FK; model any second relationship as a loose `TEXT` pointer. Audit any *future*
  child table against this before it ships.
- New empty installs no longer get a demo library (acceptable; the real use case is a populated import).

## Open questions

- **OQ1:** Are `recipePhotos` / `menus` / `mealPlanItems` the same root cause or distinct? Resolved by the
  Phase 0 count row + console capture.
- **OQ2:** Is there a SQLiteData version / upstream pattern that supports multi-FK parents, avoiding the
  schema change? Check before committing Phase 1.
- **OQ3:** In-place migration vs export→wipe→reimport for the iPad — decided by the simulator test on the
  backup.
