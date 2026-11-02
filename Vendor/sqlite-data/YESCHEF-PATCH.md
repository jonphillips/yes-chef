# Yes Chef patches: SQLiteData 1.12.1

Vendored from upstream tag `1.12.1`, commit `aa613accbe882b561f26e37a348a8f42e92cd398`.
The vendor contains upstream `Package.swift`, all `Package@swift-*.swift` manifests,
`LICENSE`, `Sources/`, and `Tests/`; it excludes `Examples/`.

The Yes Chef carry-forwards touch the following upstream surfaces:

1. `SyncEngine.handleSentRecordZoneChanges` carries forward Yes Chef's [#389 patch](https://github.com/jonphillips/yes-chef/pull/389),
   re-applied unchanged. It preserves and re-queues a child and parent when the child save fails
   with `referenceViolation`, the parent row exists locally, and the parent's last known server
   record has no change tag. This is equivalent in effect to the keep-and-requeue half of
   [upstream PR #548](https://github.com/pointfreeco/sqlite-data/pull/548), not its code: this
   patch reads the parent key from the local row, requires the parent row to exist, and clears both
   saved server copies before re-queuing. It does not port #548's `quotaExceeded` retry. Tracking:
   [issue #547](https://github.com/pointfreeco/sqlite-data/issues/547).
2. `SyncEngine.handleFetchedRecordZoneChanges` retries parked records from saved server copies
   when their parent tables change, and retries every parked copy once on startup. It uses one
   bounded CloudKit fetch only when a saved copy is missing or unusable.
3. `SyncEngine.upsertFromServerRecord` refreshes a parked record's saved server copy when a newer
   version arrives. `SyncEngine` also adds `didRetryParkedRecordScopesAfterStart` and
   `fallbackRecordCursorsByScope` state. `MockCloudDatabase` records request sizes and can simulate
   throttling for the parked-retry tests. The upstream issue for this behavior is pending the
   architect. Related context: [SQLiteData discussion #334](https://github.com/pointfreeco/sqlite-data/discussions/334).

The Yes Chef-only stored-value regression lives in
`Tests/SQLiteDataTests/StoredValuesCompatibilityTests.swift`; keep it when re-vendoring, along
with the CloudKit mock and regression tests.

The package uses upstream's iOS 16 / macOS 13 / tvOS 16 / watchOS 9 platform floors. Yes Chef's
`StructuredQueries` requirement starts at 0.39.1, the floor required by this base.

Exit condition: remove this vendor and return to the remote SQLiteData package only when an
upstream release fixes both [#547](https://github.com/pointfreeco/sqlite-data/issues/547) and the
parked-record re-fetch behavior (the architect will add the tracking issue link here).
