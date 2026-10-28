# Yes Chef patch: SQLiteData reference violations

Vendored from upstream commit `26471412f457f2c640bf5759a63870353a19f9e1` (tag 1.8.2).

The only changed upstream function is `SyncEngine.handleSentRecordZoneChanges` in
`Sources/SQLiteData/CloudKit/SyncEngine.swift`. The patch preserves and re-queues a child
and its parent when CloudKit rejects the child with `referenceViolation` and the parent
has no server-confirmed record.

Upstream tracking: [issue #547](https://github.com/pointfreeco/sqlite-data/issues/547) and
[PR #548](https://github.com/pointfreeco/sqlite-data/pull/548).

Exit condition: delete this vendor directory and return to the remote SQLiteData package
when an upstream release fixes #547.
