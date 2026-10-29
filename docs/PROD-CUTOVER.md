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
1. [x] Ship the drop slice (Codex), and pass its device check on both devices.
2. [x] Finish every device pass that needs an Xcode Run.
3. [x] Set up TestFlight for Yes Chef (script fix, tools, config, App Store Connect).

**The cut**
4. [x] Freeze edits, then take and verify the authoritative backup.
5. [x] Clean the Development schema in the console: delete the dead list, create the 9 kept fields.
6. [x] Re-export, confirm an exact match, and deploy Development → Production.
7. [x] Upload the first TestFlight build.
8. [x] iPad: install TestFlight over its current build and observe the in-place carry.
9. [ ] iPad: re-seed by restore. **The first attempt lost data on the iPad** (see Step 9); the retry waits on a
   SQLiteData patch.
10. [ ] Confirm Production holds the library, server-side, and the iPad's library matches Step 4's backup.
11. [ ] iPhone: fresh TestFlight install pulls the whole library. **← The cut is real here.**

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
- **Xcode Run.** After Step 8, nothing gets an Xcode Run onto the iPad, and after Step 11, nothing onto the
  iPhone. A Debug build still carries the production bundle id and app group until ADR-0059 ships, so it would
  install over TestFlight against Development. Use the simulator until then.
- **The freeze.** From Step 4 until Step 11 passes, make no edits on either device. An iPad edit made after
  the backup is lost when the backup is restored. An iPhone edit made before its reinstall goes only to
  Development.
- **Leave slack.** The first Production sync is large and will throttle.

---

## 1 — Ship the drop slice  *(Codex; schema change, escalated to Jon)*

The brief is [`efforts/prod-never-set-drop.md`](efforts/prod-never-set-drop.md). It drops the 7 never-set
columns, the `equipment`/`recipeEquipment` tables and the retired `tags`/`recipeTags` tables (ADR-0049 Amd 5)
in one appended migration, and retires the tag record types through `retiredRecordTypes`.

- [x] The architect sets `NEXT_UP.md` to the drop slice when chat-access S2 merges.
- [x] Review: the architect escalates the PR to Jon (synced schema). Jon merges. (PR #377, 2026-10-26.)
- [x] Device check, per the brief (both devices passed, 2026-10-26):
  - export a backup from each device first;
  - install on both devices, and confirm the library and the category browser are intact;
  - delete the empty loose **beach** and **cocktail** categories, relaunch, and confirm they stay gone;
  - Sync reads "Up to date" on both devices once the purge has run;
  - an edit syncs.

**Gate:** the slice has merged, the device check is clean, and both devices read "Up to date".

## 2 — Finish the Xcode-Run device passes

Anything that needs a dev build on a device has to happen now, before the freeze.

- [x] **Chat access S2's two-device pass** (`efforts/chat-access-mcp.md` § S2). Passed 2026-10-26.
- [x] **The drop slice's pass** (Step 1). Passed 2026-10-26.
- [x] Nothing else in [`device-passes.md`](device-passes.md) under **Owed** needs a dev build. The automatic-backups
      pass needs a TestFlight build, so it moves to Step 12.

**Gate:** no owed pass needs a dev build on a device.

## 3 — Set up TestFlight for Yes Chef  *(one time)*

The guide is jon-platform `docs/ios/testflight.md` § One-time setup. As of 2026-10-27, `asc` 5.17.1 is installed and
pinned on this Mac, `testflight.conf` is on `main` (3c), and the `testflight` link and the API key aren't set up yet.

- [x] **3a — Fix the script's app-group check (jon-platform, Codex).** `scripts/testflight` fails any bundle with
      a second app group (`… app group or CloudKit container mismatch`). Yes Chef's app is entitled to two:
      `group.com.jonphillips.yeschef` and ADR-0058's `group.com.jonphillips.cockpit-yeschef`. Add an optional
      `EXTRA_APP_GROUPS` config key (space-separated) that the verifier also accepts. Every other group still
      fails, and the share extension keeps the single-group rule. Update the conf reference in `testflight.md`.
      Brief: [`efforts/testflight-app-groups.md`](efforts/testflight-app-groups.md), dispatched 2026-10-26.
- [x] **3b — Tools (Jon).** Done 2026-10-27, and preflight verified the pin and the key.
  - Install and pin `asc` (`brew install asc && brew pin asc`); `asc --version` must equal `ASC_VERSION`, now
    `5.17.1` for both apps. That's done. The pin moved up from `5.14.0` on 2026-10-27, because Homebrew installs
    5.17.1 and no release had ever run on 5.14.0. Every `asc` command and flag the script uses exists in 5.17.1.
  - **Create the Team API key.** Nothing has created it yet; Galavant's setup gate is open too. In App Store
    Connect, go to Users and Access → Integrations → App Store Connect API → **Team Keys**. Choose **Request
    Access** if the API was never enabled. Generate a key with the **App Manager** role, then note its Key ID and
    the Issuer ID, and download the `.p8` (it downloads only once). Run `asc auth login --name jon-team --key-id …
    --issuer-id … --private-key <path>`, then `asc auth status --validate`, then delete the `.p8`. The key is
    stored in the Keychain, and one Team key serves Galavant and Yes Chef.
  - Link the command: `ln -s ~/code/jon-platform/scripts/testflight ~/code/bin/testflight`.
  - The CloudKit management token is already saved (Reference A).
- [x] **3c — `testflight.conf` at the repo root.** It rides in Step 3a's yes-chef companion PR:

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
      ASC_VERSION=5.17.1
      TEST_NOTES_LOCALE=en-US
      DONE_LOG=docs/DONE-LOG.md
      DEVICE_PASSES=docs/device-passes.md

- [x] **3d — App Store Connect (Jon).** A Yes Chef app record exists for `com.jonphillips.yeschef`, and Jon is in an
      internal testing group with automatic distribution. Preflight read the record's build numbers on 2026-10-27.
      **Confirm the internal testing group before Step 7**, because no script checks it.
- [x] **3e — Dry run.** Passed 2026-10-27: it stopped only at the schema gate. From a clean `main`, run `testflight --dry-run`. Preflight and setup must pass. The schema
      gate is **expected to fail** ("Deploy Schema Changes…") until Step 6. Any other stop gets fixed now.

**Gate:** the dry run fails only on the schema gate.

## 4 — Freeze, then take the authoritative backup  *(ADR-0056 D3)*

**Roles swapped 2026-10-27 (Jon):** the **iPad** carries the library and re-seeds Production (Steps 8–9), and
the **iPhone** gets the fresh install (Step 11). Jon uses the iPad more and trusts its library, Step 11 discards
the reinstalled device's local-only rows (chat threads and messages, AI hand-offs), and the audit below found the
iPad's library to be the complete one.

- [x] Both devices read "Up to date". **Start the freeze**: no edits on either device until Step 11 passes.
- [x] iPad: Settings → Import & Export → **Export a Backup** (`YesChef-Backup-2026-10-27 ipad.sqlite`). This is the
      re-seed source and the rollback.
- [x] iPhone: export a backup too (`YesChef-Backup-2026-10-27 iphone.sqlite`). It's insurance for Step 11, which
      deletes the app there.
- [x] Verify the iPad file: run Reference B's audit on a scratch copy. **Passed 2026-10-27:** it's byte-identical to
      the source, `integrity_check` is ok, it's stamped schema 54, and every synced table is present.
- [x] Keep both in **two places**: iCloud Drive and the Mac.

**What the audit found** (the two backups compared row by row):
- **The iPhone is missing 199 `ingredientLines` across 19 recipes**, all from the 2026-07-08 import and in one
  alphabetical run, "Bruschetta…" to "Buffalo…". Fifteen of them have no lines at all on the iPhone. The iPad has
  every line, and the iPhone has nothing the iPad lacks. The iPhone still read "Up to date", because that check
  only counts its own unsent or unapplied rows; it can't see inbound records that never arrived. Restoring the
  iPhone backup, as this runbook first planned, would have lost these lines in Production.
- **One `workbenchCandidates` row exists only on the iPhone**: "Broccoli Spoon Salad with Warm Vinaigrette",
  added 2026-07-15. With the iPad as the source it's dropped, so Jon re-adds it after the cut if he wants it.
- **The iPad ran a build with two migrations that aren't on GitHub**: "Create meal plan day order overlay" and
  "Add captureKind to workbench references". They're harmless to the restore. The backup is stamped 54, the same as
  `main`, so the restore accepts it. GRDB leaves unknown applied migrations in place, and erase-on-schema-change
  is opt-in. What's left is an empty `mealPlanDayOrders` table, which `main` never syncs, and a `captureKind`
  column that `main` also has.
- The rest are expected per-device differences: `aiHandoffs`, `chatThreads`, `chatMessages` and
  `recipeActiveVariations` never sync. Every other synced table matches row for row.

**Gate:** a verified backup exists in two places.

## 5 — Clean the Development schema  *(CloudKit Console, Development)*

**Never use "Reset Development Environment".** It deletes the Development data, and that data is the fallback.
**Pick the right container.** The console also lists `iCloud.com.jon.yeschef`, which is empty and unused and shows
only `Users`. Work in **`iCloud.com.jonphillips.yeschef`**.

**Done 2026-10-27.** Before any change, a fresh Development export was diffed against `main`'s 32 `syncedTables`. It
matched Reference A plus Step 1's drops exactly, and the iPad's unpushed build had added nothing.

- [x] **Try one deletion first.** Delete `recipes.originalImportText`, which still holds values on existing
      records. If the console refuses, stop and tell the architect before going on.
- [x] Delete everything on Reference A's dead list (3 record types and 15 fields):
  - the record types `categorySeedStates`, `tags` and `recipeTags`;
  - the dead fields on `recipes` and `menus`;
  - the `sqlitedata_icloud_userModificationTime_<column>` companion of each column Step 1 dropped.
- [x] Create the 9 kept fields in Reference A's table, each **encrypted**, with the type the table gives. A wrong
      type or a missing encryption makes those uploads fail.

## 6 — Verify, then deploy to Production

- [x] Re-export Development:
      `xcrun cktool export-schema --team-id 7MQEE539G9 --container-id iCloud.com.jonphillips.yeschef --environment development --output-file yeschef-dev.ckdb`
- [x] The architect diffs it against `syncedTables` (32 tables after Step 1) and their columns, with Reference A's
      method. **It must match exactly**: every live column, its modification-time companion, a `_hash` for each
      asset, and nothing else.
- [x] CloudKit Console → **Deploy Schema Changes** → Production. This is permanent: Production can never remove a
      deployed type or field.

**Done 2026-10-27.** The post-Step-5 export had 33 record types (the 32 synced plus `Users`), no dead or missing
fields, and every field encrypted except assets. Compared with the pre-Step-5 export, it changed only by the
planned 3 types and 15 fields removed and 9 fields added. Production held only `Users` before the deploy, and the
dialog listed exactly 32 "Create" types. Afterwards a Production export equaled Development's, field for field,
so `testflight`'s schema gate now passes.

**Gate:** Production's schema equals Development's, which equals the app.

## 7 — Upload the first TestFlight build

- [ ] From a clean, green `main`: `testflight`. Its schema gate now passes. The export verifier checks each
      bundle's id, version, app groups and container, and that the app's `aps-environment` is `production`.
- [ ] Wait for processing to reach `VALID` (up to 45 minutes; `testflight --resume` if it times out).

**Gate:** the build is installable from TestFlight.

## 8 — iPad: install over its current build, and observe the in-place carry  *(ADR-0056 OQ1)*

> ⚠️ From here on, no Xcode Run onto the iPad (Rules).

- [ ] Install the TestFlight build over the iPad's current build. Confirm the **local library is intact**: recipes,
      photos, calendar, menus.
- [ ] **Sync is already on after the update.** The enable key lives in the app's defaults, which carry over, so the
      engine starts against the empty Production zone on first launch, holding Development's sync metadata. That
      is the in-place carry test. Galavant's identical start lost nothing.
- [ ] Leave it about 10 minutes. Then, in the CloudKit Console, query the **Production** private database, zone
      `co.pointfree.SQLiteData.defaultZone`, and compare counts for a few big types (`recipes`, `ingredientLines`,
      `recipePhotos`) against Settings → Sync → Local record counts.
  - **Production has everything:** in-place carry works, so skip Step 9. Record OQ1 = yes.
  - **Empty or partial** (the expected case): do Step 9. Record OQ1 = no.

**Done 2026-10-27, build 1.0.0 (1168). OQ1 = no.** The library was intact on the iPad, but the carry only
partly seeded Production: recipes arrived, with no `ingredientLines`. Sync still read "Up to date", because the
Development sync metadata marked every row as already uploaded.

## 9 — iPad: re-seed by restore

**First attempt (2026-10-27/28): data loss on the iPad.** The restore and "Turn on iCloud sync" worked, and the
upload ran for hours. During that upload SQLiteData deleted 669 rows on the iPad: every row whose single parent
wasn't on the server yet when the row was sent (upstream
[pointfreeco/sqlite-data#547](https://github.com/pointfreeco/sqlite-data/issues/547)). Those were all 289 recipe
notes, all 9 variations, all 13 grocery-item sources, 41 instruction sections with their 244 steps, 41 photos,
30 serve-with rows and 2 deliberation-log entries. Recipes and ingredient lines were untouched. The Step 4 iPad
backup still holds every row, so nothing is unrecoverable. The audit file is `YesChef-Backup-2026-10-28 probable
DATA LOSS.sqlite` in Jon's Downloads. The retry:

> ⚠️ Until 9c, **keep Yes Chef closed on the iPad**. Every run can delete more rows and queue those deletes to
> CloudKit. Don't turn off iCloud for Yes Chef in iOS Settings: SQLiteData treats that as a sign-out and erases
> local data.

- [x] **9a — The patch** (Codex): [`efforts/sqlite-data-reference-violation-patch.md`](efforts/sqlite-data-reference-violation-patch.md).
- [x] **9b — Upload the patched build**: `testflight` from a clean `main`, as in Step 7. **Done 2026-10-28,
  build 1.0.0 (1170).**
- [x] **9c — Re-seed:** **Done 2026-10-28/29.** The patch held: no single-parent child was deleted. CloudKit
  throttled the upload overnight, and 384 rows sat as not uploaded until it cleared by itself.
  - Install the 9b build on the iPad from TestFlight, then turn on **Airplane Mode before first launching it**.
    That way the old sync state can't send anything.
  - Open Yes Chef. Settings → Import & Export → **Restore from a Backup**, choosing the Step 4 **iPad** file
    (`YesChef-Backup-2026-10-27 ipad.sqlite`). The restore discards the old sync state and holds sync off.
  - Turn Airplane Mode off. Settings → Sync → **Turn on iCloud sync**.
  - Set Auto-Lock to **Never**, keep the iPad plugged in, and keep Yes Chef **in the foreground**. The engine
    uploads very little in the background. Expect throttling and several hours. Don't intervene, reinstall or
    restore again.
  - **Ignore "Up to date" while it runs.** It can read green mid-upload (see `open-questions.md`). The gate is
    Step 10.

## 10 — Confirm Production holds the library  *(server-side, ADR-0056 OQ3)*

- [ ] **The iPad lost nothing.** Export a backup from the iPad. The architect compares its row counts with the
      Step 4 iPad backup (Reference B). Every synced table must match. The only allowed difference is
      `recipeCategories` rows that the launch-time cuisine/course backfill adds.
      **2026-10-29 audit:** everything matches (`recipeCategories` +2) except **`instructionSteps`, 241 short**.
      All 241 are among the 244 steps the first attempt deleted. Production still held those deletes, and the
      re-seed's download almost certainly applied them again. Every one's recipe and section is on the iPad.
  - [ ] **10a — Put the 241 steps back** from the Step 4 backup, with their IDs:
        [`efforts/recover-lost-instruction-steps.md`](efforts/recover-lost-instruction-steps.md). Codex builds it,
        Jon uploads it and runs it on the iPad, and the architect re-runs this comparison. Until then, don't edit
        instructions in the 41 affected recipes.
- [ ] In the console, Production private database, zone `co.pointfree.SQLiteData.defaultZone`: spot-check the types
      that lost rows (`recipeNotes`, `recipeVariations`, `instructionSections`, `recipePhotos`) plus
      `ingredientLines`. Production → Logs should show no `BAD_REQUEST` bursts after the upload settles.
      "Up to date" in the app has been wrong before, so this check is the server's word. The iPhone's fresh install
      (Step 11) is the full count check.

## 11 — iPhone: a fresh install pulls everything

> ⚠️ From here on, no Xcode Run onto the iPhone (Rules).

- [ ] Delete Yes Chef from the iPhone. Its copy stays in Development and in its Step 4 backup.
- [ ] Install the TestFlight build. **Before turning sync on, confirm the library is empty.** That proves deleting
      the app cleared its app-group container, the check the ADR-0030 restore procedure rests on. If the old
      library is still there, stop and tell the architect.
- [ ] Settings → Sync → **Turn on iCloud sync**. The whole library arrives, photos included, and Sync reads
      "Up to date".
- [ ] **The iPhone's gap is closed.** Local record counts match the iPad's (`ingredientLines` 27,613), and
      **Buffalo Chicken Wings with Blue Cheese** shows its 24 ingredient lines (Step 4 audit).

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
- [ ] Remove the temporary **Recover Missing Instruction Steps** action (Step 10a), marked `TEMPORARY`.
- [ ] Add the cut to `DONE-LOG.md`. Remove the keep-or-drop item from `open-questions.md`. Delete
      `yeschef-dev.ckdb` from the repo root.

---

## Rollback

- **Before Step 8:** nothing has changed on either device's install. Development and its data are untouched.
- **Steps 8–10 (iPad on TestFlight, iPhone still on the dev build):** the iPhone still has its library on
  Development, minus the 199 lines it never received. To back out on the iPad, delete the app, reinstall a dev
  build of `main` from Xcode, and restore the Step 4 iPad backup with sync held. Nothing is lost. The iPad's earlier
  build came from code that isn't on GitHub, so don't try to reinstall that one.
- **Step 9's first attempt:** the iPad's library is short 669 rows. The fix is Step 9c itself, a restore of the Step
  4 backup. Never restore it on the unpatched build 1168, because the next sync would delete the same rows again.
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
