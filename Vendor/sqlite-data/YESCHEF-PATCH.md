# Yes Chef patches: SQLiteData 1.12.1

Vendored from upstream tag `1.12.1`, commit `aa613accbe882b561f26e37a348a8f42e92cd398`.
The vendor contains upstream `Package.swift`, all `Package@swift-*.swift` manifests,
`LICENSE`, `Sources/`, and `Tests/`; it excludes `Examples/`.

The Yes Chef changes are confined to `Sources/SQLiteData/CloudKit/SyncEngine.swift` and its
CloudKit mock/test support:

1. `SyncEngine.handleSentRecordZoneChanges` preserves and re-queues a child and its parent when
   CloudKit rejects the child with `referenceViolation`, the parent row exists locally, and its
   last known server record has no change tag. This ports only the keep-and-requeue behavior from
   [upstream PR #548](https://github.com/pointfreeco/sqlite-data/pull/548), with the local-row and
   server-confirmation checks needed by Yes Chef. It does not port #548's `quotaExceeded` retry.
   Tracking: [issue #547](https://github.com/pointfreeco/sqlite-data/issues/547).
2. `SyncEngine.handleFetchedRecordZoneChanges` retries parked records from their saved server
   copies when their parent tables change, and retries every parked copy once on startup. It
   refreshes saved copies when newer versions arrive and uses one bounded CloudKit fetch only when
   a saved copy is missing or unusable. `MockCloudDatabase` records request sizes and can simulate
   throttling for these tests. The upstream issue for this behavior is pending the architect.
   Related context: [SQLiteData discussion #334](https://github.com/pointfreeco/sqlite-data/discussions/334).

The package uses upstream's iOS 16 / macOS 13 / tvOS 16 / watchOS 9 platform floors. Yes Chef's
`StructuredQueries` requirement starts at 0.39.1, the floor required by this base.

Exit condition: remove this vendor and return to the remote SQLiteData package only when an
upstream release fixes both [#547](https://github.com/pointfreeco/sqlite-data/issues/547) and the
parked-record re-fetch behavior (the architect will add the tracking issue link here).
