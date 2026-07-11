# ADR-0028 — Sync status indicator lies during a throttled bulk initial sync (and the multi-FK false lead)

> **One-line:** A fresh device syncing a large library (~44k child rows + 2.5k photo assets) gets
> **rate-limited by CloudKit** (`CKError 7/2062 Request Rate Limited`) and pulls it down slowly over
> hours. During that pull the Settings **"Up to date"** indicator is **wrong** — it reads only
> upload-pending + engine-running + account and ignores incomplete/throttled *download*, so it flips
> green mid-fetch. **Fix the indicator.** A separately-investigated theory — that two-foreign-key content
> tables were being *dropped* by SQLiteData's single-FK-parent modeling — was **disproven** by the debug
> count row and is recorded here as a cautionary tale. **No schema change.**

Status: **Accepted (scope corrected)** — 2026-07-10. Original proposal (multi-FK content loss + a schema
rebuild) **withdrawn** the same day after the debug count row showed the "missing" tables were **climbing,
not zero**. Extends **[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (CloudKit sync, no server). Holds
**[[sqlitedata-single-fk-sync-limit]]** (corrected). Related: **[[debug-erase-vs-sync-triggers]]** (the
migration risk we are now glad to avoid).

## Context

Two-device dogfood, 2026-07-10. The iPad holds the real ~2,163-recipe library; a fresh iPhone was brought
online. After a few hours the iPhone showed correct recipe *shells* (title, source, times, servings) but
mostly **empty ingredients / directions**, empty Menus, placeholder photos — while both devices reported
**"Up to date."** CloudKit Dashboard confirmed the real records (real-UUID `ingredientLines`, etc.) were on
the server. So: producer healthy, consumer apparently missing content, indicator claiming done.

## The false lead (recorded so we don't repeat it)

Reading the schema, the recipe-*content* tables each carry **two** `NOT NULL … ON DELETE CASCADE` foreign
keys (`ingredientLines`/`instructionSteps`: `recipeID` + `sectionID`; `menuItems`: `menuID` + `recipeID`),
and SQLiteData's `SyncEngine` models a CloudKit **parent** only for a table with **exactly one** FK
(`foreignKeysByTableName[tableName]?.count == 1`, SyncEngine.swift ~958/1708/1968/2324). It was tempting —
and I concluded, too eagerly — that the two-FK tables were being *silently dropped* on the consumer, and I
proposed reducing every child to ≤1 real FK plus a CloudKit zone rebuild.

**That was wrong.** The single-FK-parent rule governs CloudKit **parent references / record-sharing
hierarchies**, not whether a record syncs into a private zone. The tell was a *snapshot* mistaken for a
*steady state*: CloudKit pulls a bulk initial sync smallest-tables-first, so an early look (recipes done,
huge child tables barely started) looks identical to permanent loss.

## What is actually happening

The **debug "Local record counts"** sheet (built as the diagnostic) settled it — the iPhone's child tables
were **not zero, they were climbing**:

| table | iPad | iPhone (mid-sync) |
|---|--:|--:|
| recipes | 2,163 | 2,159 |
| ingredientSections | 2,438 | 1,970 |
| **ingredientLines** | **26,720** | **2,540 ↑** |
| **instructionSteps** | **10,733** | **69 ↑** |
| recipePhotos (CKAssets) | 2,494 | 264 ↑ |
| menus / menuItems | 1 / 14 | 0 / 0 (not reached) |

The iPhone device console showed the cause directly: repeated `CKError 7/2062 "Request Rate Limited"`
("Operation throttled by previous server http 429 reply. Retry after 9–22 seconds") and `6/2009 "Service
Unavailable"` on `willFetchRecordZoneChanges`. A ~44,000-row + 2,494-asset first sync is simply being
**throttled** by CloudKit and drip-fed over a long window. Sync is **correct**; it is **slow and
incomplete**, and it will converge. Incremental syncs afterward won't hit this.

## Decision

1. **Fix the status indicator (the real bug).** `SyncHealth.displayStatus` (in **CloudSyncKit**, shared
   with galavant) computes "Up to date" from **upload**-pending count + engine-running + account only. It
   must also reflect **download** state: feed `SyncEngine.isFetchingChanges` (SyncEngine.swift:411) into the
   reducer so the row stays **"Syncing…"** while a fetch is in flight and never claims "Up to date"
   mid-pull. CloudKit exposes **no** total/percentage, so this is *don't-lie*, not a progress bar. Pure
   reducer logic — testable in the CloudSyncKit value type.

   **Shipped (2026-07-10).** Added a boolean `isFetchingChanges` input to `SyncHealth` and a new
   `SyncDisplayStatus.downloading` case, gated *after* the upload-pending check (an outbound upload with a
   count is the more useful thing to surface; both are honest "in progress" states). The app's
   `SyncHealthModel.refresh()` now feeds `syncEngine.isFetchingChanges`; the existing
   `onChange(of: isSynchronizing)` hook (which already covers `isFetchingChanges`) drives the re-fold, so no
   new view wiring was needed. Summary reads "Syncing…" for both upload and download; the detail sheet
   distinguishes them ("Downloading changes from iCloud", plus a first-large-sync-takes-a-while footnote).
   15 CloudSyncKit reducer tests pass.

   **Scope limit found in-flight (worth recording).** There is **no** public **rate-limit/backoff** signal
   to feed the reducer: SQLiteData's `SyncEngine` *swallows* the throttle `CKError`s internally
   (`.requestRateLimited`/`.serviceUnavailable` fall into `continue`/`break` arms at SyncEngine.swift
   ~1794/1830) and exposes nothing observable for "paused by iCloud, will resume". So the row cannot say
   *why* it paused, and in the brief gap **between** throttled fetch batches (`isFetchingChanges` momentarily
   false, nothing pending) it can still flash "Up to date" before the next batch flips it back. That
   micro-flicker is an **accepted limitation**, not a regression — the steady-state lie (green for hours
   mid-pull) is fixed; a truthful "paused, will resume" would need SQLiteData to surface backoff state (a
   possible upstream ask, parked).
2. **Keep the demo-seed gate** (already shipped, Phase 0) — an independent, minor real bug: seeding demo
   recipes with deterministic `00000000-…` keys into the live synced store collides across devices. Now
   gated to non-`.live` contexts / `-YesChefSeedSampleData`.
3. **Keep the debug "Local record counts" sheet** — it earned its place; it's the tool that told data
   from design *and* caught this misdiagnosis.
4. **Do NOT change the schema and do NOT rebuild the zone.** The withdrawn multi-FK migration would be real
   risk (trigger rebuild — [[debug-erase-vs-sync-triggers]]) for no benefit.

## Consequences

- **No data at risk** — the iPad is untouched; the iPhone just needs to finish (foregrounded, on wifi/power;
  watch the counts converge). No migration, no zone rebuild, no backup-and-restore dance required.
- The indicator fix lands in **CloudSyncKit** (benefits galavant too). Ship the count-row diagnostic as-is.
- **Open follow-on (not this ADR):** a bulk initial sync being throttled for hours with a silent indicator
  is a poor first-run experience; consider a first-sync affordance ("Downloading your library…") once the
  indicator honestly reports fetching. Parked.

## Open questions

- **OQ1 (was: are photos/menus/meals the same root cause?)** — **Resolved:** no separate bug; they're
  simply later in the throttled queue (menus/menuItems not yet reached; photos/steps early).
- **OQ2** — Only revisit the two-FK shape if/when adopting CloudKit household **sharing**
  ([ADR-0003](ADR-0003-private-libraries-recipe-transfer.md)), where parent references matter. Not now.
