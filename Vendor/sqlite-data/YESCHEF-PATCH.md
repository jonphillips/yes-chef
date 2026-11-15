# Yes Chef patch: SQLiteData 1.13.0

Vendored from upstream tag `1.13.0`, commit `e72164ceb92a10b62407624c98e5bc2c47d8c0e1`.
The vendor contains upstream `Package.swift`, all `Package@swift-*.swift` manifests,
`LICENSE`, `Sources/`, and `Tests/`; it excludes `Examples/`.

One Yes Chef carry-forward remains:

1. `SyncEngine.handleSentRecordZoneChanges` carries forward Yes Chef's [#389 patch](https://github.com/jonphillips/yes-chef/pull/389),
   re-applied unchanged. When a child save fails with `referenceViolation`, the parent row exists locally, and the
   parent's last known server record has no change tag, it keeps the child and re-queues the child and parent,
   instead of applying the foreign key's delete action. Tracking:
   [issue #547](https://github.com/pointfreeco/sqlite-data/issues/547).

   1.13.0 covers part of this. #571 sorts parents ahead of children in a batch, and #335 with #576 re-queues a
   parent held back by `quotaExceeded`. A parent whose save fails with an error that neither CKSyncEngine nor the
   handler retries is never re-queued, for example `serverRejectedRequest` or `limitExceeded`. Without this patch,
   upstream then deletes that parent's children locally and queues the deletes.
   `ReferenceViolationTests.addReminderAfterListSaveWasRejected` reproduces that case through the CloudKit mock
   alone. It fails on pristine 1.13.0 and passes with the patch.

`MockCloudDatabase` adds a one-shot `rejectedSaves` map for that test.

The former patches 2 and 3 (#414: retry parked records from saved server copies, and refresh a parked record's saved
copy) were dropped in this rebase. 1.13.0 caches each parked record and its assets when it parks it, retries the
cache locally on every fetched batch, and keeps the newest version (#567, #569; closes
[#565](https://github.com/pointfreeco/sqlite-data/issues/565)).
`ForeignKeyConstraintTests.newerParkedRecordIsAppliedAfterItsParentArrives` stays as the regression for that
behavior.

The Yes Chef-only stored-value regression lives in
`Tests/SQLiteDataTests/StoredValuesCompatibilityTests.swift`; keep it when re-vendoring, along
with the CloudKit mock and regression tests.

The package uses upstream's iOS 16 / macOS 13 / tvOS 16 / watchOS 9 platform floors. Yes Chef's
`StructuredQueries` requirement starts at 0.39.1, the floor required by this base.

1.13.0 adds two metadatabase migrations (`unsyncedRecordIDs.record` and `.assets`, and
`pendingRecordZoneChanges.databaseScope`). A device that has run this build can't go back to an older vendor in
a Debug build: the metadatabase's `hasSchemaChanges` assert fires on launch. Release builds tolerate it.

Exit condition: remove this vendor and return to the remote SQLiteData package when an upstream release fixes
[#547](https://github.com/pointfreeco/sqlite-data/issues/547).
