# Sync: migration writes bypass the sync triggers — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** A migration write to a new table duplicates per device; to an existing table it never uploads. Unverified on device: whether the 2026-07-14 prep-plan move duplicated steps. Read it before any migration that writes rows.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Sync — migration writes bypass the sync triggers (found 2026-07-28, auditing ADR-0014's migration)

> **Status: NOT FIXED. No code has changed.** This is a **going-forward** constraint on every future data
> migration, not a post-mortem on one shipped bug. The prep-plan instance below is the only *already-shipped*
> occurrence found; the bootstrap ordering that caused it is untouched and will do the same thing to the next
> migration that writes to a synced table — starting with ADR-0014's `isHeader` promotion.

**Root cause, confirmed in code.** [`Schema.swift`](../../../YesChefPackage/Sources/YesChefCore/Schema.swift)
runs `migrator.migrate(database)` **before** `makeSyncEngine`, and SQLiteData installs its per-table sync
triggers at engine *construction*. **A migration's writes therefore fire no trigger and get no
`SyncMetadata` row.** At `start()` the engine sweeps only **brand-new tables** — `uploadRecordsToCloudKit`
issues `UPDATE <table> SET pk = pk` for tables missing from the cached `RecordType` list, firing the
now-installed triggers. Nothing sweeps migration-inserted rows in a table that already existed. This cuts
two opposite ways, and **both** are live design constraints for any future data migration:

- **New table → rows upload, and each device uploads its own.** Duplication.
- **Existing table → rows never upload.** Silent per-device divergence. (This is the one that would have
  bitten ADR-0014's `isHeader` → section promotion; see
  [ADR-0014 Amd1-D3](../../decisions/ADR-0014-recipe-text-editing-model.md#amd1-d3--retire-isheader-d1s-outcome-new-mechanism--and-mint-the-migrations-uuids-deterministically).)

**Suspected already-shipped instance: `"Move menu prep plans into editable step rows"`** (`cacb87f`,
2026-07-14, ADR-0040). It reads each menu's `prepPlan` BLOB and inserts `prepPlanSteps` rows with a bare
`UUID()` — the **only** data-backfill migration in `Schema.swift` that mints UUIDs. `PrepPlanStepRecord` is
sync-registered ([`CloudSync.swift:146`](../../../YesChefPackage/Sources/YesChefCore/CloudSync.swift)), and
`prepPlanSteps` was a brand-new table, so the new-table sweep uploads whatever each device produced.

The predicted symptom, if both devices crossed the 2026-07-14 boundary with prep-plan content:
**every promoted step exists twice**, once per device, with different UUIDs. A second effect compounds it —
the BLOB column survived until `0d4ea54` (2026-07-25, **11 days later**) and **had no writer after
`cacb87f`**, so a device migrating late re-promoted the *frozen 07-14* plan, resurrecting stale steps
alongside any edits made to the rows since.

> **✅ CHECKED 2026-07-28 against a live backup export — it did not fire. Nothing to repair.** The one menu
> with a prep plan holds **25 steps, `sortOrder` 0–24, all distinct**, with zero content duplicates — a single
> coherent sequence, not two interleaved promotions. Both menus predate the 07-14 migration, so they were
> exposed; either only one device promoted content, or a later regenerate cleaned it (`replaceAll` renumbers,
> so the two are no longer distinguishable and the BLOB is gone). **The root cause below is untouched and
> still governs every future migration** — the query is kept for the next audit.

**Was not verifiable from the repo — this is device state.** The mechanism is confirmed; whether it fired
depended on whether both devices ran the migration with data present. **Checked against a backup export**
(ADR-0030 S1, PR #250):

```sql
SELECT "menuID", "session", "task", COUNT(*) AS n
FROM "prepPlanSteps"
GROUP BY "menuID", "session", "task", COALESCE("serves", ''), COALESCE("sourceDish", '')
HAVING n > 1;
```

**If it fired, the repair is cheap:** `PrepPlanStepRepository.replaceAll` already deletes non-surviving rows,
so regenerating a menu's prep plan cleans it. **That repair is the whole remediation — the shipped migration
needs no code change. Everything below is the forward debt.**

### What is actually at risk, and what isn't

The other two data backfills in `Schema.swift` were audited and are **safe**, which sharpens the rule into
something usable rather than a blanket fear of migrations:

- `"Backfill grocery store areas"` (`GroceryStoreAreaCache.backfill`) and `"Add sparse learning ordering"`
  (`LearningRepository.backfillSortOrders`, a stable comparator over row content) are **UPDATE**-shaped and
  **deterministic functions of already-synced rows**. Every device runs the same migration over the same
  data and computes the **same answer**, so the tables converge *even though nothing uploads*. The missed
  upload is invisible because there is nothing to disagree about.
- `"Move menu prep plans into editable step rows"` mints `UUID()`. Two devices computing the same *content*
  arrive at **different rows**. That is the whole difference.

**The rule, for the house migration guidance:** a migration whose write is a deterministic function of
already-synced data is safe as-is. A migration whose write is **non-deterministic** (fresh UUIDs, timestamps,
model output) or depends on **local-only state** must (a) derive its identifiers deterministically so
concurrent devices converge on identical rows, and (b) run the **data** pass *after* the sync engine is
constructed — guarded and one-time — so the rows actually upload. Schema DDL may stay in the migrator.

**Open:** does this become a written house rule in `jon-platform` (Galavant runs the same SQLiteData +
CloudKit stack, so the seam is shared — [[seam-ledger-append-on-sight]]), a lint/review checklist item, or
just this note? **Not decided.**
