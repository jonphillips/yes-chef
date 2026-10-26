# Production Cutover Runbook

**Purpose.** This is the ordered, reversible procedure for taking Yes Chef from a dev-signed build on CloudKit
**Development** to a TestFlight build on CloudKit **Production**, **without re-importing the dogfood library**.
It is the ops companion to [ADR-0056](decisions/ADR-0056-move-to-production-and-data-carry.md), which explains
why each step is shaped the way it is. Rewritten 2026-10-26 as one numbered sequence from here to the end.

**The spine (ADR-0056).** The local SQLite store carries across the update in place, because the bundle id and
container id don't change. The **Production private zone starts empty**, and the sync metadatabase is keyed by
container id, not environment, so the carried store may not upload itself. The known-good re-seed is
**backup → restore**: a restore begins as a fresh sync peer and re-pushes the whole library as authoritative.
Galavant's cutover (2026-10-08) followed this shape and ended with its library in Production. It didn't record
whether the in-place carry did the seeding, so Step 9 records that answer.

**Who does what.**
- **Jon:** the device, console and TestFlight steps.
- **Architect:** the diffs, the dispatches, and the record keeping.
- **Codex:** only Step 1's drop slice and Step 3a's script fix, each as a normal reviewed PR.

**Shared platform guidance.** jon-platform `docs/ios/persistence-and-sync.md` owns the CloudSyncKit pieces this
leans on, and `docs/ios/testflight.md` owns the release script. The data-carry finding is a row in
jon-platform `SEAM-LEDGER.md`, waiting for this run's answer.

---

## Steps at a glance

**Done**
- [x] Dead cook columns and raw import HTML dropped; oversize recipes and calendar links repaired (Phase 1).
- [x] SyncMetadata coverage is clean and is now permanent in the Sync status (Phase 2).
- [x] Development schema exported and diffed; Jon settled every keep/drop verdict (Reference A). 2026-10-26.

**Before the freeze**
1. [ ] Ship the drop slice (Codex), and pass its device check on both devices.
2. [ ] Finish every device pass that needs an Xcode Run.
3. [ ] Set up TestFlight for Yes Chef (script fix, tools, config, App Store Connect).

**The cut**
4. [ ] Freeze edits, then take and verify the authoritative backup.
5. [ ] Clean the Development schema in the console: delete the dead list, create the 9 kept fields.
6. [ ] Re-export, confirm an exact match, and deploy Development → Production.
7. [ ] Upload the first TestFlight build.
8. [ ] iPhone: install TestFlight over the dev build and observe the in-place carry.
9. [ ] iPhone: re-seed by restore, unless Step 8 already filled Production.
10. [ ] Confirm Production holds the library, server-side.
11. [ ] iPad: fresh TestFlight install pulls the whole library. **← The cut is real here.**

**After**
12. [ ] Post-cut device checks: automatic backups, two-way edits.
13. [ ] Post-cut housekeeping: record the answers, archive Development, dispatch Yes Chef Dev.

---

## Rules while the cut is open

- **Identifiers don't change.** Keep the bundle id `com.jonphillips.yeschef` and the container
  `iCloud.com.jonphillips.yeschef`. The local carry depends on both. ADR-0059's Debug-only `.dev` identity
  comes after the cut; don't dispatch it before Step 11 (ADR-0059 D1).
- **Schema.** Codex's schema-free work (chat-access S2) can continue alongside the cut. Until Step 11, merge
  no synced-schema change other than Step 1's drop slice. A schema change after Step 6 would need another
  Development change and another deploy before any TestFlight build can ship.
- **Xcode Run.** After Step 8, nothing gets an Xcode Run onto the iPhone, and after Step 11, nothing onto the
  iPad. A Debug build still carries the production bundle id and app group until ADR-0059 ships, so it would
  install over TestFlight against Development. Use the simulator until then.
- **The freeze.** From Step 4 until Step 11 passes, make no edits on either device. An iPhone edit made after
  the backup is lost when the backup is restored. An iPad edit made before its reinstall goes only to
  Development.
- **Leave slack.** The first Production sync is large and will throttle.

---

## 1 — Ship the drop slice  *(Codex; schema change, escalated to Jon)*

The brief is [`efforts/prod-never-set-drop.md`](efforts/prod-never-set-drop.md). It drops the 7 never-set
columns, the `equipment`/`recipeEquipment` tables and the retired `tags`/`recipeTags` tables (ADR-0049 Amd 5)
in one appended migration, and retires the tag record types through `retiredRecordTypes`.

- [x] The architect sets `NEXT_UP.md` to the drop slice when chat-access S2 merges.
- [ ] Review: the architect escalates the PR to Jon (synced schema). Jon merges.
- [ ] Device check, per the brief:
  - export a backup from each device first;
  - install on both devices, and confirm the library and the category browser are intact;
  - delete the empty loose **beach** and **cocktail** categories, relaunch, and confirm they stay gone;
  - Sync reads "Up to date" on both devices once the purge has run;
  - an edit syncs.

**Gate:** the slice has merged, the device check is clean, and both devices read "Up to date".

## 2 — Finish the Xcode-Run device passes

Anything that needs a dev build on a device has to happen now, before the freeze.

- [ ] **Chat access S2's two-device pass** (`efforts/chat-access-mcp.md` § S2, once it ships). If S2 isn't done
      by the time everything else is ready, don't hold the cut for it: run its pass on a later TestFlight build.
- [ ] **The drop slice's pass** (Step 1).
- [ ] Nothing else in [`device-passes.md`](device-passes.md) under **Owed** needs a dev build. The automatic-backups
      pass needs a TestFlight build, so it moves to Step 12.

**Gate:** no owed pass needs a dev build on a device.

## 3 — Set up TestFlight for Yes Chef  *(one time)*

Verified 2026-10-26: Yes Chef has no `testflight.conf`, and neither `asc` nor `testflight` is installed on this
Mac. The guide is jon-platform `docs/ios/testflight.md` § One-time setup.

- [ ] **3a — Fix the script's app-group check (jon-platform, Codex).** `scripts/testflight` fails any bundle with
      a second app group (`… app group or CloudKit container mismatch`). Yes Chef's app is entitled to two:
      `group.com.jonphillips.yeschef` and ADR-0058's `group.com.jonphillips.cockpit-yeschef`. Add an optional
      `EXTRA_APP_GROUPS` config key (space-separated) that the verifier also accepts. Every other group still
      fails, and the share extension keeps the single-group rule. Update the conf reference in `testflight.md`.
      The architect writes the dispatch.
- [ ] **3b — Tools (Jon).**
  - Install and pin `asc` at Galavant's pin (`brew install asc && brew pin asc`; `asc --version` = `5.14.0`).
  - Log in with the shared Team API key (`asc auth login …`, then `asc auth status --validate`).
  - Link the command: `ln -s ~/code/jon-platform/scripts/testflight ~/code/bin/testflight`.
  - The CloudKit management token is already saved (Reference A).
- [ ] **3c — `testflight.conf` at the repo root.** It rides in Step 3a's yes-chef companion PR, or Jon adds it:

      SCHEME=YesChef
      PROJECT=YesChef.xcodeproj
      XCODEGEN=1
      TEAM_ID=7MQEE539G9
      APP_BUNDLE_ID=com.jonphillips.yeschef
      EXTENSION_BUNDLE_IDS="com.jonphillips.yeschef.share-extension"
      APP_GROUP=group.com.jonphillips.yeschef
      EXTRA_APP_GROUPS="group.com.jonphillips.cockpit-yeschef"
      CLOUDKIT_CONTAINER=iCloud.com.jonphillips.yeschef
      SCHEMA_GATE=1
      ASC_VERSION=5.14.0
      TEST_NOTES_LOCALE=en-US
      DONE_LOG=docs/DONE-LOG.md
      DEVICE_PASSES=docs/device-passes.md

- [ ] **3d — App Store Connect (Jon).** A Yes Chef app record exists for `com.jonphillips.yeschef`, and Jon is in an
      internal testing group with automatic distribution.
- [ ] **3e — Dry run.** From a clean `main`, run `testflight --dry-run`. Preflight and setup must pass. The schema
      gate is **expected to fail** ("Deploy Schema Changes…") until Step 6. Any other stop gets fixed now.

**Gate:** the dry run fails only on the schema gate.

## 4 — Freeze, then take the authoritative backup  *(ADR-0056 D3)*

- [ ] Both devices read "Up to date". **Start the freeze**: no edits on either device until Step 11 passes.
- [ ] iPhone: Settings → Import & Export → **Export a Backup**. This is the re-seed source and the rollback.
- [ ] iPad: export a backup too. It's insurance for Step 11, which deletes the app there.
- [ ] Verify the iPhone file: run Reference B's audit on a scratch copy. It opens read-only, and the recipe count
      matches Settings → Sync → Local record counts.
- [ ] Keep it in **two places**: iCloud Drive and the Mac.

**Gate:** a verified backup exists in two places.

## 5 — Clean the Development schema  *(CloudKit Console, Development)*

**Never use "Reset Development Environment".** It deletes the Development data, and that data is the fallback.

- [ ] **Try one deletion first.** Delete `recipes.originalImportText`, which still holds values on existing
      records. If the console refuses, stop and tell the architect before going on.
- [ ] Delete everything on Reference A's dead list:
  - the record types `categorySeedStates`, `tags` and `recipeTags`;
  - the dead fields on `recipes` and `menus`;
  - the `sqlitedata_icloud_userModificationTime_<column>` companion of each column Step 1 dropped.
- [ ] Create the 9 kept fields in Reference A's table, each **encrypted**, with the type the table gives. A wrong
      type or a missing encryption makes those uploads fail.

## 6 — Verify, then deploy to Production

- [ ] Re-export Development:
      `xcrun cktool export-schema --team-id 7MQEE539G9 --container-id iCloud.com.jonphillips.yeschef --environment development --output-file yeschef-dev.ckdb`
- [ ] The architect diffs it against `syncedTables` (32 tables after Step 1) and their columns, with Reference A's
      method. **It must match exactly**: every live column, its modification-time companion, a `_hash` for each
      asset, and nothing else.
- [ ] CloudKit Console → **Deploy Schema Changes** → Production. This is permanent: Production can never remove a
      deployed type or field.

**Gate:** Production's schema equals Development's, which equals the app.

## 7 — Upload the first TestFlight build

- [ ] From a clean, green `main`: `testflight`. Its schema gate now passes. The export verifier checks each
      bundle's id, version, app groups and container, and that the app's `aps-environment` is `production`.
- [ ] Wait for processing to reach `VALID` (up to 45 minutes; `testflight --resume` if it times out).

**Gate:** the build is installable from TestFlight.

## 8 — iPhone: install over the dev build, and observe the in-place carry  *(ADR-0056 OQ1)*

> ⚠️ From here on, no Xcode Run onto the iPhone (Rules).

- [ ] Install the TestFlight build over the dev build. Confirm the **local library is intact**: recipes, photos,
      calendar, menus.
- [ ] **Sync is already on after the update.** The enable key lives in the app's defaults, which carry over, so the
      engine starts against the empty Production zone on first launch, holding Development's sync metadata. That
      is the in-place carry test. Galavant's identical start lost nothing.
- [ ] Leave it about 10 minutes. Then, in the CloudKit Console, query the **Production** private database, zone
      `co.pointfree.SQLiteData.defaultZone`, and compare counts for a few big types (`recipes`, `ingredientLines`,
      `recipePhotos`) against Settings → Sync → Local record counts.
  - **Production has everything:** in-place carry works, so skip Step 9. Record OQ1 = yes.
  - **Empty or partial** (the expected case): do Step 9. Record OQ1 = no.

## 9 — iPhone: re-seed by restore

- [ ] Settings → Import & Export → **Restore from a Backup**, choosing the Step 4 file. The restore holds sync off.
- [ ] Settings → Sync → **Turn on iCloud sync**, and confirm at **Turn On iCloud Sync?**. The whole library
      re-pushes into Production as authoritative.
- [ ] **Expect throttling.** The first push hits CloudKit 429s and takes a while. Don't intervene, reinstall or
      wipe. Let it drain until Sync reads "Up to date".

## 10 — Confirm Production holds the library  *(server-side, ADR-0056 OQ3)*

- [ ] In the console, Production private database, zone `co.pointfree.SQLiteData.defaultZone`: per-type counts
      match the iPhone's Local record counts. "Up to date" in the app has been wrong before, so this check is
      the server's word.

## 11 — iPad: a fresh install pulls everything

> ⚠️ From here on, no Xcode Run onto the iPad (Rules).

- [ ] Delete Yes Chef from the iPad. Its copy stays in Development and in its Step 4 backup.
- [ ] Install the TestFlight build. **Before turning sync on, confirm the library is empty.** That proves deleting
      the app cleared its app-group container, the check the ADR-0030 restore procedure rests on. If the old
      library is still there, stop and tell the architect.
- [ ] Settings → Sync → **Turn on iCloud sync**. The whole library arrives, photos included, and Sync reads
      "Up to date".

**Gate (the real one):** Steps 10 and 11 both pass. **Only now is the cut real**, and the freeze ends.

## 12 — Post-cut device checks

- [ ] **Automatic backups**, on the first TestFlight build: the full pass in [`device-passes.md`](device-passes.md),
      on both devices.
- [ ] Make an edit on each device, and confirm it arrives on the other.
- [ ] If S2's pass was deferred in Step 2, run it now.

## 13 — Post-cut housekeeping  *(architect, with Jon)*

- [ ] Record the OQ1 answer from Step 8 in ADR-0056, and in jon-platform `SEAM-LEDGER.md`'s data-carry row (its
      trigger needs it). Then lift the carry guidance into `persistence-and-sync.md`.
- [ ] Keep **Development** as a cold archive through at least one confirmed two-device Production round trip
      (ADR-0056 OQ2). Reset it after that, **before** Yes Chef Dev first turns sync on (ADR-0059 OQ1).
- [ ] Set `NEXT_UP.md` to the Yes Chef Dev dispatch (ADR-0059; the ticket is at the end of
      [`efforts/yes-chef-dev-variant.md`](efforts/yes-chef-dev-variant.md)). Until it merges, Xcode Run goes only to
      the simulator.
- [ ] **From now on, every TestFlight build waits on a schema deploy.** A slice that adds a synced table or column,
      or is the first to write a non-nil value to one, must create it in Development (from a simulator build or
      the console) and deploy before its TestFlight build ships. `testflight` enforces this.
- [ ] Add the cut to `DONE-LOG.md`. Remove the keep-or-drop item from `open-questions.md`. Delete
      `yeschef-dev.ckdb` from the repo root.

---

## Rollback

- **Before Step 8:** nothing has changed on either device's install. Development and its data are untouched.
- **Steps 8–10 (iPhone on TestFlight, iPad still on the dev build):** the iPad still has the full library on
  Development. To back out on the iPhone, delete the app, reinstall the dev build from Xcode, and restore the
  Step 4 backup with sync held. Nothing is lost.
- **After Step 11:** restore the Step 4 backup. Restore is authoritative ([[restore-is-authoritative]]), but quiesce
  the other device first, so a held delete there can't re-delete a restored record (ADR-0030 Amd 3).

---

## Reference A — The Development schema diff  *(2026-10-26)*

A deploy copies the **whole** Development schema into Production. Development's schema is whatever past uploads
created, not what `makeSyncEngine` registers, so it can be wrong in two ways:

- **Dead types and fields (permanent once deployed).** Development keeps every record type and field that was
  ever uploaded, and Production can't remove them later. SQLiteData also writes companion fields per column: a
  modification-time field (`sqlitedata_icloud_userModificationTime_<column>`) for every column, even when the
  value is nil, and a `<column>_hash` field for each asset. A dead column's companions are dead too.
- **Missing types and fields (recoverable, but uploads fail until fixed).** Development creates a record type
  only when its first record uploads, and a field only when some record carries a non-nil value. Production
  never creates either one, so a missing one makes that record's upload fail until a later additive deploy.
  The sync status will show it as not synced.

The old hand-kept "Prod-schema promotion list" (formerly in `device-passes.md`) is superseded by this diff.

**How it was made.**
- Token: CloudKit Console → Settings → Tokens, then `xcrun cktool save-token --type management`.
- Export: `xcrun cktool export-schema --team-id 7MQEE539G9 --container-id iCloud.com.jonphillips.yeschef --environment development --output-file yeschef-dev.ckdb`.
- Diff: for each table in `syncedTables`, the expected fields are each on-disk column, plus
  `sqlitedata_icloud_userModificationTime` and its per-column `_<column>` companion, plus `<column>_hash` for each
  BLOB column. A field in the export that isn't expected is dead, and an expected field the export lacks is
  missing. Ignore CloudKit's `___` system fields and the `Users` type.

**The diff (Development export of 2026-10-26 against the 36 `syncedTables`).** The 2026-10-26 backup found
`equipment` and `recipeEquipment` empty and 23 columns that have never held a value. The export settles which of
them Development actually lacks. Every live column's modification-time companion is already present, including
the companions of the never-set columns.

*Dead — delete in the console (Step 5):*
- record type `categorySeedStates`. `categorySeedTombstones` was never uploaded, so it isn't there.
- `recipes`: `originalImportText`, `timesCooked`, and the companions
  `sqlitedata_icloud_userModificationTime_originalImportText`, `_timesCooked`, and `_lastCookedAt`. The
  `lastCookedAt` field itself was never uploaded.
- `menus`: `prepPlan` (an asset), `prepPlan_hash`, and `sqlitedata_icloud_userModificationTime_prepPlan`.
- Not in Development, so nothing to do: `ingredientLines.substitution`, `workbenchReferences.kind`, and
  `workbenchReferences.provenance`.
- **Once Step 1 ships:**
  - the record types `tags` and `recipeTags` (ADR-0049 Amd 5; Slice 6's purge empties them first);
  - the companion `sqlitedata_icloud_userModificationTime_<column>` of each dropped column below.

*Missing — 2 record types and 17 fields.* The other 6 never-set columns
(`groceryItemSources.mealPlanItemID`/`menuID`/`menuItemID`/`scheduledDate`/`mealSlot`/`sourceSubtitle`) already
exist from earlier values. The keep-or-drop reasoning is in [`open-questions.md`](open-questions.md)
§ "production cutover: keep-or-drop the never-set synced columns". Every field is `ENCRYPTED`.

| Missing | Type | Write path | Verdict (Jon, 2026-10-26) |
|---|---|---|---|
| `recipeSources.pageNumber` | STRING | editor "Page" field | keep → create (Step 5) |
| `mealPlanItems.notes` | STRING | calendar entry editor | keep → create (Step 5) |
| `menus.notes` | STRING | new-menu sheet | keep → create (Step 5) |
| `workbenchLog.outcome` | STRING | log-entry editor | keep → create (Step 5) |
| `workbenchLog.relatedRecipeID` | STRING | Adjust rationale logged to the Workbench | keep → create (Step 5) |
| `groceryLists.remindersListName` | STRING | grocery list "Reminders List" field | keep → create (Step 5) |
| `pantryItems.thresholdQuantity` | DOUBLE | pantry editor | keep → create (Step 5) |
| `pantryItems.thresholdUnit` | STRING | pantry editor | keep → create (Step 5) |
| `groceryItemSources.menuPlacementID` | STRING | grocery generation from placed menu dishes | keep → create (Step 5) |
| `recipes.activeTimeMinutes` | INT64 | none (copied by Adjust, read by the browser) | drop (Step 1) |
| `recipes.restTimeMinutes` | INT64 | none (copied by Adjust) | drop (Step 1) |
| `ingredientLines.shoppingCategory` | STRING | none (parser never sets it; read as a grocery-aisle fallback) | drop (Step 1) |
| `recipeNotes.cookingSessionID` | STRING | none (only ever written nil) | drop (Step 1) |
| `tags.color` | STRING | none | drop, with the `tags` table (ADR-0049 Amd 5) |
| `categories.color` | STRING | only copied from `tags.color`; no UI sets or shows it | drop (Step 1); re-add additively if a color UI is built |
| `mealPlanItems.startTime` | TIMESTAMP | none | drop (Step 1) |
| `mealPlanItems.endTime` | TIMESTAMP | none | drop (Step 1) |
| record types `equipment` and `recipeEquipment` | — | none (no importer fills a bundle's equipment; Adjust only copies it) | drop (Step 1) |

## Reference B — How to run the backup audit  *(repeatable)*

1. Audit a **fresh in-app backup**, never a simulator store. Jon exports it to iCloud Drive → Documents →
   App Backups → `YesChef-Backup-<date>.sqlite`; it may need to sync down to the Mac first.
2. Copy it into its own scratch directory and open the copy read-only:
   `sqlite3 "file:<path>?immutable=1"`.
3. For each table in `YesChefCloudSync.syncedTables` (36 today, 32 after Step 1), count the rows, and for each
   column count the non-NULL rows. Zero rows means the record type may be missing; zero non-NULL means the field
   may be missing.

## History

**Old phase numbers** (cited by shipped briefs): Phase 3 → Step 4 · Phase 4a → Steps 5–6 and Reference A ·
Phase 4b → Steps 3 and 7 · Phase 4c → Steps 8–9 · Phase 4d → Step 10 · Phase 4e → Step 11 · Post-cut → Steps 12–13.


- **Phase 1 (cleared 2026-10-26).**
  - [`efforts/prod-dead-column-drop.md`](efforts/prod-dead-column-drop.md) dropped `recipes.lastCookedAt` and
    `timesCooked`, and added the test that every table's on-disk columns match its model. There was no migration
    squash (ADR-0056 Amd 1).
  - [`efforts/raw-import-html-drop.md`](efforts/raw-import-html-drop.md) dropped `recipes.originalImportText`,
    deleted 1,527 photo rows with no bytes, re-uploaded the nine recipes over the 1 MB limit, and re-linked three
    calendar rows (ADR-0010 Amd 1).
- **Phase 2 (cleared 2026-10-26).**
  - Both devices read "Up to date" with nothing unsynced.
  - [`efforts/sync-failure-surfacing.md`](efforts/sync-failure-surfacing.md) made this check permanent: "Up to
    date" requires zero rows that never reached the server and zero inbound rows that couldn't be applied, and
    Slice 6 purges retired record types.
- **Reference A (2026-10-26).** Development was exported, diffed, and the keep/drop verdicts settled (plan PRs
  #373 and #374).
