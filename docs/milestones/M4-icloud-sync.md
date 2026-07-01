# M4 — CloudKit sync enablement (Phase E)

**Phase E** of [`../implementation-plan.md`](../implementation-plan.md) — the **one-way gate**
the whole arc precedes. Build order for Codex. Architect owns this doc + the ADR; Codex
executes the slices below — **one branch + draft PR per slice, green before ready, never push
to `main`.** Label `question-for-architect` when blocked.

## Goal

Turn on **CloudKit private-database** sync via **SQLiteData's `SyncEngine`** so Jon's library is
**backed up** and available across **his own devices** — but only once import and *all* capture
paths are trustworthy, and only against a **clean store**, so the iCloud private zone is never
polluted with throwaway re-imports or duplicate captures. **No server, no auth** — the iCloud
account is the identity (ADR-0002). Moving recipes *between people* is a separate transfer/sharing
feature (ADR-0003), explicitly **out of scope** here.

## Why this is last, and why it's a one-way door

- **First sync uploads everything.** The moment `SyncEngine` starts against a non-empty store, it
  pushes every existing local row into the CloudKit zone. Dev junk, half-migrated cruft, and
  duplicate imports would all land in production. → **cut over against an empty store.**
- **CloudKit production schema is append-only.** Once you deploy record types/fields to the
  Production environment you **cannot delete a field**. → the synced-record column shape must be
  settled *before* the prod deploy.
- **The pipeline is the asset; the data is disposable.** "Feel good about import" means the
  *pipeline* reliably reproduces good recipes — not that a hand-curated library must survive. Local
  data is throwaway (`eraseDatabaseOnSchemaChange` already treats it so); we re-import into the
  clean synced store. Until sync ships there is **no backup** — a lost device is total loss, which
  is the urgency behind closing this gate rather than adding more features.

## What's already verified sync-ready (planning session, 2026-06-30)

The solo-built schema was audited this session against the CloudKit laws — it conforms, so this
milestone is **enablement + hygiene + cutover, not remodeling**:

- **UUID text primary keys everywhere** (`… PRIMARY KEY NOT NULL … DEFAULT (uuid())`) — the single
  most important irreversible law, already satisfied. No autoincrement rowids to migrate.
- **No unique indexes** beyond primary keys; **no compound primary keys** (both unsupported by
  `SyncEngine`). Only non-unique `CREATE INDEX`.
- **No reserved-keyword column collisions** — uses `dateCreated`/`dateModified`, not CloudKit's
  forbidden `creationDate`/`modificationDate`/`recordID`/`recordType`/etc.
- **BLOBs auto-promote to `CKAsset` unconditionally** (verified in SQLiteData 1.6.6 `setBytes`) —
  the ~1 MB per-record limit applies only to a record's own fields, **not** assets, so hero/photo
  bytes and `originalSnapshot` sync correctly **with no schema change** (verified in the SQLiteData
  1.6.6 source this session; captured in [ADR-0010](../decisions/ADR-0010-cloudkit-sync-enablement.md)).

## The CloudKit laws (ADR-0002 — bind every synced table)

- **Private DB, `SyncEngine`, no server, no auth.** iCloud account = identity; no login/Keychain.
- **UUID PKs; no unique indexes.** Logical uniqueness is enforced by **code-level upsert + dedup-on-
  read** (pick one row per key deterministically; a cleanup pass deletes the losers). Even one
  person's two devices editing offline can each insert a duplicate — **plan and test for it**
  (Slice 3).
- **Sharing is later.** Family Cookbook (ADR-0003) is the only piece that uses CloudKit *sharing* (a
  shared zone + `acceptShare` flow) — Phase F+, not this milestone. `CKSharingSupported` /
  `privateTables` are deferred with it.

## House rules (bake into every slice)

- **Verify the current SQLiteData API/version at milestone start.** `1.6.6` as of planning; consult
  the `pfw-sqlite-data` skill (`references/icloud.md`) for the live `SyncEngine` API before building
  on it — this house rule exists because the API has moved between versions.
- **CloudKit needs a real device + iCloud account to truly verify.** Simulator iCloud is flaky and
  logs out ~every 24h (`BadContainer`, `Not Authenticated`, `AccountTemporarilyUnavailable` — see
  `references/icloud.md`). Sim is fine for wiring/build; **device-verify the actual sync**.
- **CI is disabled (billing).** Verify locally every slice: `swift test --package-path
  YesChefPackage`, `bash scripts/check-drift.sh`, `xcodegen generate`, and an `xcodebuild` for an
  **iOS-27 iPad** simulator. `swiftlint --strict` is pre-existing-red on `main` from oversize files
  — don't let *new* files regress it.
- **The `SyncEngine` table list is code.** Every synced `@Table` is listed explicitly; a table left
  off stays local-only. There is **no column-level** exclusion — to keep data local, split it into
  its own table not handed to the engine.
- **Never store credentials.** iCloud is the identity; the app has no auth surface.

---

## Slice 1 — Lean original-provenance (sync prep)

Full spec: [`../efforts/lean-original-provenance.md`](../efforts/lean-original-provenance.md).
**Do this first** — it's independent, already scoped, and it's the one data change that **must**
land before the clean re-import (Slice 4) so the synced store is lean from day one.

- Strip embedded photo JPEG bytes (`displayData`/`thumbnailData`) from the **snapshot** encoder
  (`RecipeBundleCoding.snapshotData`, `RecipeCore.swift:871`) — keep photo metadata; do **not**
  touch the transfer `RecipeBundle` (import/export legitimately carries bytes).
- Stop persisting raw import HTML (`originalImportText`) in release builds (option-gated, default
  off; `#if DEBUG` acceptable fallback). It is read only by a DEBUG DOM-export tool.
- **No DDL** — both columns stay; only what we write changes. This closes the "should
  `originalSnapshot` ride the synced recipe record?" question: yes — once lean it's a few KB.
- The **compare-to-original drift view** in that effort is a separable, sync-irrelevant follow-on —
  split it out; it does not gate the flip.
- Opportunistic fold-in if convenient: the `expectedContentLength` hero-download guard (current
  Ready Effort #1). Not required for this slice.

**Verify:** unit assertion that a decoded snapshot has nil photo bytes but retained metadata and is
low-KB; release-config import yields `originalImportText == nil`; transfer `RecipeBundle` still
carries bytes. `swift test` + `check-drift.sh`.

---

## Slice 2 — CloudKit project setup + `SyncEngine` wiring (started OFF)

Wire sync end-to-end against the CloudKit **dev** environment, but keep it **opt-in / off for real
data** until the cutover (Slice 4).

1. **Xcode project (additive):** add the **iCloud** entitlement with **CloudKit** and container
   `iCloud.<bundle id>`; add `aps-environment`; add `UIBackgroundModes = remote-notification` to
   Info.plist. Defer `CKSharingSupported` (that's Family Cookbook). **XcodeGen `project.yml` is the
   source of truth** — declare entitlements there and `xcodegen generate`.
2. **Bootstrap wiring** in `bootstrapDatabase` (`Schema.swift`):
   - `attachMetadatabase()` in `prepareDatabase` (so `SyncMetadata` is queryable; without it,
     `no such table: sqlitedata_icloud_metadata`).
   - After `defaultDatabase = database`, set
     `defaultSyncEngine = try SyncEngine(for: database, tables: <every synced @Table>, startImmediately: false)`.
   - **Enumerate the synced table list explicitly** — all current `@Table` types
     (`Recipe`, `RecipeSource`, `IngredientSection`, `IngredientLine`, `InstructionSection`,
     `InstructionStep`, `RecipeNote`, `RecipePhoto`, `Tag`, `Category`, `Equipment`, `RecipeTag`,
     `RecipeCategory`, `RecipeEquipment`, `RecipeImportRef`, `MealPlanItem`, `Menu`, `MenuItem`,
     `MenuPlacement`, `GroceryList`, `GroceryItem`, `GroceryItemSource`, `PantryItem`). Confirm the
     list against `Models.swift` at build time — a missed table silently stays local.
   - `startImmediately: false` + a launch gate so the app runs **local-only** when there's no
     iCloud account (graceful degradation — no crash, no login prompt).
   - Guard debug query-tracing against `SyncEngine.isSynchronizing` so sync SQL doesn't spew.
3. **Share extension is a second writer — install triggers, don't network.** `YesChefShareExtension`
   writes to the **App Group shared store**. It may construct a
   `SyncEngine(startImmediately: false)` only to install SQLiteData's sync triggers and write
   `SyncMetadata`; it must never start the engine or perform CloudKit network work. The main app's
   engine owns sync upload/download and picks up extension-written metadata on next launch/foreground.
4. **Verify (dev env, throwaway store, device):** on a device signed into iCloud, with sync manually
   enabled, create a recipe → confirm it appears in the CloudKit **dev** dashboard; relaunch →
   confirms it round-trips. Do **not** point at Production yet. Build the iOS-27 iPad sim; `swift
   test` + `check-drift.sh`.

---

## Slice 3 — Logical-uniqueness hardening (upsert + dedup-on-read)

The ADR-0002 requirement: with no unique indexes, offline two-device inserts can create duplicate
rows for the same logical key. Make reads deterministic and self-healing.

1. **Import identity** (`recipeImportRef`, composed normalized `sourceURL` + `title`): ensure the
   import path is an **upsert**, and add a **dedup-on-read**: when more than one row shares a key,
   pick one deterministically (e.g. lowest `id` / earliest `dateCreated`) and a cleanup pass deletes
   the losers, re-pointing any `recipeID` references. Reuse M1's composed-identity logic.
2. **Other logically-unique data:** audit for the same hazard — e.g. default `GroceryList`
   (`isDefault`), `Tag`/`Category` by name, `PantryItem` by title. Decide per-entity whether dedup
   matters (a duplicate default list is a real bug; two same-named tags may be tolerable) and record
   the decision.
3. **Tests:** seed duplicates (simulating two offline inserts), assert dedup converges to one row
   deterministically and references survive. This is the "test with seeded duplicates" step from the
   plan.

Implementation audit decisions:

- Source-backed `recipeImportRef` duplicates are a bug: keep the earliest ref, delete duplicate
  imported recipes, and repoint meal-plan/menu/grocery `recipeID` references to the survivor.
  Title-only import collisions remain data-preserving: they are still allowed to import as separate
  recipes because normalized title alone is too weak to prove identity.
- Duplicate default grocery lists are a bug: keep every list, but converge to one `isDefault` row.
- Duplicate pantry titles are a bug: keep the canonical title row, merge missing notes, and delete
  duplicate pantry rows.
- Duplicate tag names and duplicate sibling category names are a bug: merge them into the canonical
  row, repoint recipe join rows, and preserve category children by moving them under the survivor.

**Verify:** unit tests green; `swift test` + `check-drift.sh`.

---

## Slice 4 — Clean cutover + enablement (runbook + flip)

Mostly operational (architect + Jon drive the CloudKit dashboard); the code change is removing the
Slice 2 gate. **Order is load-bearing.**

1. **Exercise in dev, then deploy schema to Production.** With Slices 1–3 in, run sync in the
   CloudKit **dev** environment until the schema is complete, then **Deploy Schema Changes to
   Production** in the CloudKit dashboard. This is **one-way** — no field deletion after. Confirm the
   synced-record shape is final (lean `originalSnapshot`, all intended tables).
2. **Wipe local → empty store.** Fresh install / erase the app so the first Production sync uploads
   a **clean** zone (first sync pushes all existing local rows).
3. **Enable sync** — remove the `startImmediately: false` gate (or flip the opt-in), pointed at
   Production.
4. **Re-import the real library** into the clean synced store. **Asset-heavy** (every photo is a
   separate `CKAsset` upload) — do it on wifi and let it run; it is not instant.
5. **Confirm the zone** holds exactly the intended data (spot-check the dashboard).

**Verify:** device, iCloud account, Production — library populates, relaunch round-trips.

---

## Slice 5 — Multi-device + offline-race verification

The real acceptance test; only meaningful on **two devices** signed into the **same** iCloud
account.

- **Cross-device propagation:** create/edit/delete a recipe (and a grocery item, a meal-plan item)
  on device A → confirms on device B within CloudKit's eventual-consistency window.
- **Asset round-trip:** a hero image captured on A renders on B (proves BLOB→`CKAsset` end-to-end).
- **Offline-edit races:** same recipe edited on both while offline → reconcile on reconnect; two
  offline duplicate imports → Slice 3 dedup converges.
- **Account-absent:** signed out of iCloud → app works local-only, no crash, no data loss; signs
  back in → local data syncs up.

**Verify:** documented device results in the PR (there are no server logs — this is
eventual-consistency-on-real-devices).

---

## Out of scope (do not build now)

- **CloudKit sharing / Family Cookbook** (ADR-0003) — shared zone + `acceptShare` + `privateTables`
  + `CKSharingSupported`. Phase F+. `Recipe` is a clean FK-free root record so recipe sharing stays
  viable later; the six-FK `groceryItemSource` won't participate in record sharing — don't design
  grocery sharing around it.
- **Schema remodeling** — canonical ingredient names, etc. Additive and **sync-safe**; add a column
  / a new synced table **after** the flip and backfill lazily (dialog-free, at grocery-add time).
  Do **not** front-load it into this milestone.
- **Curated collections** cross-device refs (ADR-0008) — post-sync (needs dedup-on-read + soft FK +
  title snapshot).
- **Compare-to-original drift view** — folds out of Slice 1 as a later, local, sync-irrelevant UX
  slice.

## ADR

Ratified by [**ADR-0010 — CloudKit sync enablement**](../decisions/ADR-0010-cloudkit-sync-enablement.md)
(on top of the already-Accepted [ADR-0002](../decisions/ADR-0002-cloudkit-sync-no-server.md)):
confirms BLOB→`CKAsset` behavior, the lean-`originalSnapshot` decision, the upsert + dedup-on-read
strategy, and the clean-cutover runbook (dev→prod one-way deploy, empty-store flip, re-import).

---
*Authored 2026-06-30 from the iCloud sync planning session. Companion docs:
[`../efforts/lean-original-provenance.md`](../efforts/lean-original-provenance.md),
[ADR-0002](../decisions/ADR-0002-cloudkit-sync-no-server.md) (decision),
[ADR-0003](../decisions/ADR-0003-private-libraries-recipe-transfer.md) (sharing, deferred),
[ADR-0010](../decisions/ADR-0010-cloudkit-sync-enablement.md) (enablement specifics).*
