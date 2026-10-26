# Production Cutover Runbook

**Purpose.** The ordered, reversible procedure for taking Yes Chef from a dev-signed build on CloudKit
**Development** to a TestFlight/App Store build on CloudKit **Production** — **without re-importing the
dogfood library.** This is the ops companion to
[ADR-0056](decisions/ADR-0056-move-to-production-and-data-carry.md); read the ADR first for *why* each step
is shaped this way. It absorbs and sequences the **Prod-schema promotion list** in
[`CURRENT_HANDOFF.md`](CURRENT_HANDOFF.md).

**Shared platform guidance lives up in jon-platform** — `jon-platform/docs/ios/persistence-and-sync.md`
owns the CloudSyncKit-level pieces this runbook leans on (the metadatabase coverage diagnostic, the
migration-behind-the-engine trap, the one-way Dev→Prod schema deploy, dashboard verification). This runbook
is the yes-chef-specific execution on top of it; the shared *data-carry* finding is tracked in
`jon-platform/SEAM-LEDGER.md` and lifts into that house doc once the dry run (Phase 4) proves it.

**Not a dispatch.** These are ops steps Jon runs (with the architect), each gated on the one before. The
build/schema/CloudKit actions are not Codex work; the dead-column drop's *code* (D2, as amended) is the one part that ships as a
normal reviewed slice.

**The spine (ADR-0056):** the local SQLite store carries across the update in place (same bundle id), but
the **Production private zone starts empty and may not auto-seed** (the sync metadatabase is keyed by
container id, not environment). So the **known-good re-seed is backup→restore** — restore begins as a fresh
sync peer and re-pushes the whole library as authoritative. In-place auto-seed is an optimization the dry
run may bless, never the plan's assumption.

---

## Preconditions (before anything below)

- [ ] `main` is green: package build + `check-drift` + `YesChefTests`/`YesChefCoreTests`.
- [ ] Calendar-derived cooking history has landed; `Recipe` no longer persists
      `lastCookedAt` / `timesCooked`.
- [ ] **Do not change** the bundle id (`com.jonphillips.yeschef`) or container id
      (`iCloud.com.jonphillips.yeschef`). Local-container carry depends on both being stable.
      ADR-0059's Debug-only `.dev` identity comes **after** the cut and leaves these Release identifiers
      alone. Don't dispatch it before Phase 4e (ADR-0059 D1).
- [ ] Schedule a window with slack — the first Production sync is large and will throttle (see Phase 4).

**Sequencing while the cut is open (2026-10-26).** Codex's schema-free work (chat-access S2) can continue
alongside the cut. Merge **no synced-schema change** other than 4a's keep/drop drops until the cut is done.
S2's two-device pass must finish before Phase 4c or wait for TestFlight: after 4c nothing gets an Xcode Run
onto a device until ADR-0059 (Yes Chef Dev) ships post-cut.

---

## Phase 1 — Drop the dead cook columns  *(ships as a reviewed slice; ADR-0056 D2 as amended by Amd 1)*

Brief: [`efforts/prod-dead-column-drop.md`](efforts/prod-dead-column-drop.md). **No migration squash.**
Production locks the CloudKit schema, not the local migration list, so the squash is deferred cleanup that
can happen any time after the cut (ADR-0056 Amd 1).

- [x] One appended migration drops `recipes.lastCookedAt` and `recipes.timesCooked`. The fields and
      CodingKeys come out of `Recipe`. Old backup JSON still decodes, since unknown keys are ignored.
- [x] A test proves every table's on-disk columns match its model, so no other dead column reaches
      Production unnoticed.
- [x] Before installing the build, export a backup from each device. Afterwards, confirm the library is
      intact and that an edit syncs to the other device.
- [x] **Raw import HTML dropped, and its fallout repaired** ([`efforts/raw-import-html-drop.md`](efforts/raw-import-html-drop.md),
      ADR-0010 Amd 1). This is the second reviewed slice. An appended migration drops `recipes.originalImportText`.
      A post-engine pass deletes the 1,527 photo rows that have no image bytes. It then re-uploads the nine
      recipes over CloudKit's 1 MB record limit, plus their children, and re-links the three calendar rows that
      sync blanked. Capture stops saving photos it never downloads. **It must land before Phase 3.** Otherwise the re-seed
      backup carries records that can't upload and calendar links that are NULL.

**Gate:** the drop has shipped and Jon's device pass is clean. **Cleared 2026-10-26.**

---

## Phase 2 — SyncMetadata coverage check  *(ADR-0056 D4)*

Every row that should sync must be *uploadable*; a row with no sync metadata seeds neither zone.

- [x] For each synced table, compare row count to the count the engine will push; investigate any gap.
      **2026-10-26:** both devices read "Up to date" with nothing unsynced, which is this check made permanent.
      Migration-inserted or pre-engine rows are the usual orphans ([[migration-writes-bypass-sync-triggers]]).
- [x] Remediate orphans **deterministically** (deterministic-UUID, post-engine), never with a fresh-UUID
      migration write.
- [x] Verify the **promotion list against `makeSyncEngine` in `CloudSync.swift`, in both directions** — a
      synced-table column is on the list; a column on an unregistered (local) table belongs nowhere near it.
      **2026-10-26:** every entry is on one of the 36 registered tables. But the list is not what a deploy
      copies: a deploy copies the whole Development schema, so the check that decides the cut is 4a's parity
      check. The 2026-10-26 backup also shows two listed items that have never held a value
      (`pantryItems.thresholdQuantity`/`thresholdUnit` and `categories.color`), so they may not be in
      Development at all.

- [x] **Make the check permanent in the sync status** ([`efforts/sync-failure-surfacing.md`](efforts/sync-failure-surfacing.md)).
      "Up to date" requires zero rows that never reached the server and zero inbound rows that couldn't be
      applied. The detail names them. Phase 4d then reads the same signal against Production.

**Gate:** coverage is clean, or the remaining gaps are understood and intentional.

---

## Phase 3 — Take the authoritative backup  *(ADR-0056 D3)*

- [ ] From the current dev-signed build, export a full backup (`VACUUM INTO` snapshot — images ride along as
      in-DB BLOBs).
- [ ] Verify the file opens and is complete (not a truncated/partial write).
- [ ] Store it off-device (Files / iCloud Drive) **and** a second location. **This file is the re-seed
      source and the rollback.** Nothing after this point is trusted until this exists.

**Gate:** a verified pre-cut backup exists in two places.

---

## Phase 4 — Deploy the Production schema, then dry-run the cut on ONE device  *(ADR-0056 D5)*

Do these in order on a **single** device. The Development environment stays live and untouched as a
fallback throughout.

**4a — Make the Development schema match the app, then deploy it.** A deploy copies the **whole**
Development schema into Production. Development's schema is whatever past uploads created, not what
`makeSyncEngine` registers, so it can be wrong in two ways:

- **Dead types and fields (permanent once deployed).** Development keeps every record type and field that was
  ever uploaded, and Production can't remove them later. Candidates, taken from the migrations that dropped them:
  - record types `categorySeedStates` and `categorySeedTombstones` (emptied by sync-failure Slice 6);
  - fields `recipes.lastCookedAt`, `recipes.timesCooked`, and `recipes.originalImportText`;
  - fields `ingredientLines.substitution` and `menus.prepPlan`;
  - fields `workbenchReferences.kind` and `workbenchReferences.provenance`, if an early device uploaded them.

  SQLiteData also writes companion fields per column: a modification-time field for every column, and a
  `_hash` field for assets. A dead column's companions are dead too.
- **Missing types and fields (recoverable, but uploads fail until fixed).** Development creates a record type
  only when its first record uploads, and a field only when some record carries a non-nil value. Production
  never creates either one, so a missing one makes that record's upload fail until a later additive deploy.
  The sync status will show it as not synced. From the 2026-10-26 backup:
  - `equipment` and `recipeEquipment` have no rows, so their record types may not exist;
  - 23 columns have never held a value: `recipes.activeTimeMinutes`/`restTimeMinutes`,
    `recipeSources.pageNumber`, `ingredientLines.shoppingCategory`, `recipeNotes.cookingSessionID`,
    `tags.color`, `categories.color`, `mealPlanItems.notes`/`startTime`/`endTime`, `menus.notes`,
    `workbenchLog.outcome`/`relatedRecipeID`, `groceryLists.remindersListName`,
    `groceryItemSources.mealPlanItemID`/`menuID`/`menuItemID`/`menuPlacementID`/`scheduledDate`/`mealSlot`/`sourceSubtitle`,
    and `pantryItems.thresholdQuantity`/`thresholdUnit`, plus the 8 columns of the two empty tables.

  A field may already exist if an earlier value was later cleared. The schema export decides. Whether each
  never-set column is kept (create it) or dropped (an appended migration before the cut) is decided per column
  in [`open-questions.md`](open-questions.md) § "production cutover: keep-or-drop the never-set synced columns".

**How to run the backup audit (repeatable).**
1. Audit a **fresh in-app backup**, never a simulator store. Jon exports it to iCloud Drive → Documents →
   App Backups → `YesChef-Backup-<date>.sqlite`; it may need to sync down to the Mac first.
2. Copy it into its own scratch directory and open the copy read-only:
   `sqlite3 "file:<path>?immutable=1"`.
3. For each of the 36 tables in `YesChefCloudSync.syncedTables`, count the rows, and for each column count the
   non-NULL rows. Zero rows means the record type may be missing; zero non-NULL means the field may be missing.

Steps:
- [ ] Create a CloudKit management token (CloudKit Console → Settings → Tokens) and store it with
      `xcrun cktool save-token --type management`. Then export Development:
      `xcrun cktool export-schema --team-id 7MQEE539G9 --container-id iCloud.com.jonphillips.yeschef --environment development --output-file yeschef-dev.ckdb`
- [ ] The architect diffs the export against the registered tables and their columns, and writes the exact dead
      list and missing list here.
- [ ] Delete the dead record types and fields in the console. Once Phase 1 has shipped to every device, nothing
      writes them. **Never use "Reset Development Environment"**: it deletes the Development data, and that data is
      the fallback.
- [ ] Create the missing record types and fields in Development. How depends on the diff: either add them in the
      console with the type and encryption SQLiteData uses, or use a DEBUG-only primer that uploads one throwaway
      record per type with every column set and then deletes it. Deleting the record doesn't remove the schema.
- [ ] Re-export, confirm the schema matches the app exactly, then deploy Development to **Production**. This
      permanently locks the record types.

**4b — Distribution build config  (ADR-0056 D6).**
- [ ] Shipping build has dogfood scaffolding OFF: no seed-sample-data, no erase-on-schema-change, and sync
      enablement goes through the **persistent** path, not a volatile Xcode launch argument.
- [ ] Entitlements intact on **both** the app and the share extension: app-group + iCloud container.

**4c — Install over the dev build; re-seed via restore.**

> ⚠️ **From here on, nothing gets an Xcode Run onto a device that has TestFlight Yes Chef.** A Debug build
> still has the production bundle ID and app group until ADR-0059 lands, and it would install over
> TestFlight against the Development environment. Use the simulator until then (ADR-0059 D1).

- [ ] Install the distribution (TestFlight) build over the dev build on the one device. Confirm the **local
      library is intact** after the update.
- [ ] Restore the Phase 3 backup on this build (restore begins as a new peer; sync stays held by
      `disableForRestore` until you enable it).
- [ ] Enable sync. The whole library re-pushes into the empty Production zone as authoritative.
- [ ] **Expect throttling.** The initial push of the full library will hit CloudKit 429s and take a while
      ([[sqlitedata-single-fk-sync-limit]]). **Do not intervene, do not wipe** — let it drain.

**4d — Confirm the zone is actually seeded (server-side, not the in-app indicator).**
- [ ] Check the **Production private zone** record counts in the CloudKit dashboard — "up to date" in-app has
      lied before, so confirm against the zone (ADR-0056 OQ3).

**4e — Confirm a fresh device pulls the full library.**
- [ ] On a **second, fresh** install of the distribution build, sign into the same iCloud account and
      confirm the entire library (recipes + images) arrives from Production.

**Gate (the real one):** 4d and 4e both pass. Only now is the cut real.

> **Optional — bless in-place carry (ADR-0056 D1 optimization).** Before the restore in 4c, you may first
> enable sync *without* restoring and observe whether the local rows upload to Production on their own
> (watch 4d). If they seed the zone cleanly, in-place carry works on this device and the restore is
> unnecessary going forward. If nothing uploads, fall back to the restore path above. Never skip the backup
> (Phase 3) to try this.

---

## Rollback

- **Before the cut is proven (through 4e):** the Development environment and its data are untouched.
  Reinstall the dev-signed build (or restore the Phase 3 backup on a dev build) to return to the working
  Development library. Nothing is lost.
- **After Production is proven but something is wrong later:** restore the pre-cut backup — restore is
  authoritative and re-establishes the library as the source of truth for iCloud and every peer
  ([[restore-is-authoritative]]). Quiesce other peers first so a held peer delete cannot re-delete a
  restored record (ADR-0030 Amd 3).

---

## Post-cut

- [ ] Keep the **Development** zone as a cold archive through at least one confirmed two-device Production
      round-trip before deciding whether to reset it (ADR-0056 OQ2). Recommended: reset it then, **before**
      Yes Chef Dev first turns sync on, so it starts light and never writes into the archive (ADR-0059 OQ1).
- [ ] The architect sets `NEXT_UP.md` to the Yes Chef Dev dispatch (ADR-0059; the ticket is at the end of
      [`efforts/yes-chef-dev-variant.md`](efforts/yes-chef-dev-variant.md)). Until it merges, Xcode Run goes
      only to the simulator.
- [ ] In `CURRENT_HANDOFF.md`, retire the **Prod-schema promotion list** section once deployed (it is a
      one-time ops step, not standing guidance) and note the cut in `DONE-LOG.md`.

---

## Condensed checklist

1. [ ] Preconditions: green main, cook columns unread, ids unchanged, window with slack.
2. [x] Phase 1 — cook columns and raw import HTML dropped by appended migrations; oversize recipes re-uploaded and
   calendar links repaired; no other dead columns; device pass clean.
3. [x] Phase 2 — SyncMetadata coverage clean; promotion list checked against `CloudSync.swift` (2026-10-26).
4. [ ] Phase 3 — verified pre-cut backup in two places.
5. [ ] Phase 4a — Development schema exported and matched to the app (dead removed, missing created); Production schema deployed.
6. [ ] Phase 4b — distribution build: scaffolding off, entitlements intact.
7. [ ] Phase 4c — install over dev build, library intact, restore + enable sync, let throttling drain.
8. [ ] Phase 4d — Production zone seeded, **confirmed server-side**.
9. [ ] Phase 4e — fresh device pulls the full library. **← cut is real here.**
10. [ ] Post-cut — Development kept as archive; handoff/DONE-LOG updated; Yes Chef Dev (ADR-0059) dispatched.
