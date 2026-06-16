# Decision Log (ADRs)

Settled architecture choices for Yes Chef. **Check these before proposing
architecture changes; don't re-litigate them.** General "how Jon builds software"
decisions live in `~/code/jon-platform`; these record how those bind to Yes Chef
plus any app-specific calls.

- [ADR-0001](ADR-0001-persistence-sqlitedata.md) — Persistence is SQLiteData (not SwiftData/Core Data)
- [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) — Sync is CloudKit via SQLiteData; no server, no auth
- [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) — Private per-person libraries; recipes move by transfer (copy), not co-editing
- [ADR-0004](ADR-0004-structured-recipe-editor.md) — MVP editor uses text entry with structured, non-destructive persistence
