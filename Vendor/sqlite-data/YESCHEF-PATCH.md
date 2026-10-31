# Yes Chef patch: SQLiteData reference violations

Vendored from upstream commit `26471412f457f2c640bf5759a63870353a19f9e1` (tag 1.8.2).

The only changed upstream function is `SyncEngine.handleSentRecordZoneChanges` in
`Sources/SQLiteData/CloudKit/SyncEngine.swift`. The patch preserves and re-queues a child
and its parent when CloudKit rejects the child with `referenceViolation` and the parent
has no server-confirmed record.

The manifests (`Package.swift`, `Package@swift-6.0.swift`) also raise `platforms` to
iOS 17 / macOS 14 / tvOS 17 / watchOS 10. swift-structured-queries 0.35.0 raised its own
floors to iOS 16 (so upstream 1.8.2's iOS 13 declaration fails to link
`StructuredQueriesSQLite`) and gated `octetLength()` behind iOS 17 (which
`CloudKit/Internal/Triggers.swift` uses). First seen in `jon-platform-workspace`, which
resolves 0.35+. Every consumer targets iOS 27 / macOS 15+, so nothing loses support.

Upstream tracking: [issue #547](https://github.com/pointfreeco/sqlite-data/issues/547) and
[PR #548](https://github.com/pointfreeco/sqlite-data/pull/548).

Exit condition: delete this vendor directory and return to the remote SQLiteData package
when an upstream release fixes #547.
