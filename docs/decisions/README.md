# Decision Log (ADRs)

Settled architecture choices for Yes Chef. **Check these before proposing
architecture changes; don't re-litigate them.** General "how Jon builds software"
decisions live in `~/code/jon-platform`; these record how those bind to Yes Chef
plus any app-specific calls.

- [ADR-0001](ADR-0001-persistence-sqlitedata.md) — Persistence is SQLiteData (not SwiftData/Core Data)
- [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) — Sync is CloudKit via SQLiteData; no server, no auth
- [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) — Private per-person libraries; recipes move by transfer (copy), not co-editing
- [ADR-0004](ADR-0004-structured-recipe-editor.md) — MVP editor uses text entry with structured, non-destructive persistence
- [ADR-0005](ADR-0005-image-storage-and-processing.md) — Recipe images use a pure processing pipeline and recipe-owned storage rows
- [ADR-0006](ADR-0006-taxonomy-source-and-library-placement.md) — Categories stay flexible; source, author, placement, and recipe families are typed concepts
- [ADR-0007](ADR-0007-web-recipe-capture-engine.md) — Web recipe capture harvests Galavant's parser now and converges on a shared package later
- [ADR-0008](ADR-0008-curated-collections.md) — Curated collections are a new sibling of Menu (editorial indexes); reserved now, built post-sync (Proposed)
- [ADR-0009](ADR-0009-in-app-authenticated-browser-capture.md) — In-app authenticated browser capture (rendered logged-in DOM) via WebExtractorKit; never store credentials
- [ADR-0010](ADR-0010-cloudkit-sync-enablement.md) — CloudKit sync enablement specifics: BLOB→CKAsset, lean original-provenance, upsert + dedup-on-read, clean cutover
