# Effort — Keep children whose parent never reached CloudKit (vendored SQLiteData patch, PROD-CUTOVER Step 9 retry)

Status: **Dispatched** — 2026-10-28. Schema-free. Blocks the Step 9 re-seed.
Summary: SQLiteData deletes a single-parent child row on the device whenever CloudKit rejects it with
`referenceViolation`. It assumes another device deleted the parent, but during a first upload the parent may simply
not be on the server yet. Step 9's re-seed hit this and deleted 669 rows on the iPad. Vendor SQLiteData 1.8.2 into
the repo with a patch that keeps the child, and re-queues it and its parent, when the server never confirmed the
parent. Override the remote package with it in the app build.
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Steps 9–10 ·
[ADR-0056 Amd 2](../decisions/ADR-0056-move-to-production-and-data-carry.md) · upstream
[pointfreeco/sqlite-data#547](https://github.com/pointfreeco/sqlite-data/issues/547) (open) and
[#548](https://github.com/pointfreeco/sqlite-data/pull/548) (unmerged fix, written against 1.12)

## Why

Step 9 (2026-10-27): the iPad restored the Step 4 backup, and sync re-pushed the library into the empty Production
zone. A backup taken on 2026-10-28, compared with Step 4's, had lost every row of a table with exactly one parent
foreign key whose parent wasn't on the server when the row was sent:

- all 289 `recipeNotes`, all 9 `recipeVariations`, all 13 `groceryItemSources`;
- 41 `instructionSections` (and their 244 `instructionSteps`, by local cascade);
- 41 `recipePhotos`, 30 `recipeServeWith`, and 2 `recipeDeliberationLog` rows.

Tables with two parents (`ingredientLines`, `recipeCategories`) lost nothing, because SQLiteData gives them no CloudKit
parent reference. Neither did `recipes`. Production's log for the window showed bursts of `BAD_REQUEST` saves
between child-type saves, while recipes uploaded three per request because of their snapshot assets.

The handler is `SyncEngine.swift`'s `.referenceViolation` case in `handleSentRecordZoneChanges` (1.8.2, around
line 1705). It is unchanged through 1.12.1. Its `.cascade` branch deletes the child with `_isSynchronizingChanges`
false, so the delete is also queued to CloudKit. Upstream's own tests
(`ReferenceViolationTests.moveReminderToList_RemoteDeletesList`) depend on that delete when the parent still exists
locally, because the remote delete hasn't been fetched yet. **So "the parent exists locally" can't tell the two cases
apart.** What separates them is whether the server ever confirmed the parent.

## The patch (vendored `SyncEngine.swift` only)

In the `.referenceViolation` case for failed **saves**, after the existing single-foreign-key guard and before
`foreignKey.onDelete` is applied:

1. Read the child's `foreignKey.from` value for `recordPrimaryKey`. If the child row is gone or the value is NULL,
   keep today's behavior.
2. Look up the parent: its row in `foreignKey.table`, and its `SyncMetadata` (`recordType` = parent table, primary
   key = that value, normalized the way SQLiteData normalizes `recordPrimaryKey`).
3. **The parent never reached the server** when its row exists locally **and** its metadata has no server-confirmed
   record: `lastKnownServerRecord` is nil, or its `recordChangeTag` is nil. A nil-tag record is what
   `nextRecordZoneChangeBatch` stores before a send (`refreshLastKnownServerRecord(record)`, around line 1231), so
   the record's presence alone proves nothing. In that case:
   - don't apply `onDelete`;
   - clear `lastKnownServerRecord` on the parent's and the child's metadata (as `clearServerRecord()` does);
   - append `.saveRecord` for the parent and then the child to `newPendingRecordZoneChanges`. Build the parent's
     record ID the way `nextRecordZoneChangeBatch` builds its parent reference, not by hand;
   - log one line through the engine's `logger`, naming the child and the parent.
4. **Otherwise** (the parent is gone locally, or the server confirmed it once): today's behavior, unchanged.

If the parent's own save keeps failing, this loops (the child is re-sent, rejected, and re-queued) without losing
anything. The Sync screen keeps both rows listed as not uploaded, which is the honest outcome ([[no-dead-data]]).
Don't port #548's `quotaExceeded` retry, and change no other error case.

## Wiring — vendor, then override

- Copy `pointfreeco/sqlite-data` at tag **1.8.2** (`26471412f457f2c640bf5759a63870353a19f9e1`, the version in
  `Package.resolved`) into `Vendor/sqlite-data/`: `Package.swift`, `Package@swift-6.0.swift`, `LICENSE`, `Sources/`,
  `Tests/`. Leave out `Examples/`. **Commit the untouched copy first and the patch second**, so the PR's second commit
  is the whole behavior change. Take the copy from the tag, not from `~/code/sqlite-data`: that's Jon's fork
  (`jonphillips/sqlite-data`), checked out on an unrelated branch.
- Add `Vendor/sqlite-data/YESCHEF-PATCH.md`. It names the upstream commit, the one changed function, the two upstream
  links, and the exit condition: delete the vendor directory and return to the remote package once a SQLiteData
  release fixes #547.
- `project.yml`: change the `SQLiteData` package from `url:`/`from:` to `path: Vendor/sqlite-data`. Keep the directory
  name `sqlite-data`, because that is the package identity. Xcode then uses the local package in place of the
  remote one for every package that depends on it (`YesChefPackage`, `CloudSyncKit`). **Don't edit**
  `YesChefPackage/Package.swift` or jon-platform's `CloudSyncKit/Package.swift`; CloudSyncKit is Galavant's too. If
  Xcode reports an identity conflict instead of overriding, stop and report it rather than changing either manifest.
- Confirm the override took effect: after `xcodegen` and package resolution,
  `YesChef.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` has no `sqlite-data` pin. Its
  other pins don't move.
- `YesChefPackage`'s own `swift test` still resolves upstream 1.8.2. That's fine: its tests never exercise a send.

## Tests (in the vendored package)

In `Vendor/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/ReferenceViolationTests.swift`, next to the existing
cases, using `MockCloudDatabase`:

- **The parent never reached the server.** Insert a parent and a cascade child locally. Keep the parent off the
  server (for example, remove its pending save before the first send, or have the mock fail it with a dropped
  error). Send the child, and get `referenceViolation`. Assert that the child row still exists, both saves are
  pending, and that after the next send cycle both records are on the mock server.
- **The same for a `SET NULL` child.** The foreign key stays set.
- **The four existing tests pass unchanged.** They are the remote-delete path, where the parent was confirmed on the
  server.

## Out of scope

Upgrading SQLiteData. The "Up to date" blind spots and the launch-time repair passes on the main thread (both in
[`open-questions.md`](../open-questions.md)). A Retry All button. Galavant (a seam-ledger row covers it).

## Verification

- `swift test --package-path Vendor/sqlite-data --filter ReferenceViolationTests`, then the package's whole suite
  once. If the CloudKit tests can't run on macOS, run them with `xcodebuild test` on an iOS simulator instead and
  say so.
- `scripts/check-drift.sh`, plus the generic device build from `docs/AGENTS.md` (elevated from the start).
- The `Package.resolved` check above.

## Done when

- One Yes Chef PR: the pristine vendor commit, the patch commit, `project.yml`, and `YESCHEF-PATCH.md`, with every
  verification above green.
- It sets `NEXT_UP.md` to `Nothing dispatched.`, adds a `DONE-LOG.md` entry, and ticks PROD-CUTOVER **9a**.
- Then Jon uploads the build (Step 9b) and re-seeds (Step 9c). The architect audits the result (Step 10).
