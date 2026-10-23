# Next Up — Sync status false positive (Slice 4: count a row only if its content differs)

**Slices:** effort `sync-failure-surfacing`, Slice 4
**Briefs:** docs/efforts/sync-failure-surfacing.md § Slice 4 ("Why the date leg can't work" is the reason)
**Done when:** per § Slice 4 "Done when"; verification per § Slice 4 and `docs/verification.md`.
**Owed:** Jon's Chat access S1 pass, the Slice 4 readout and the sync failure status pass, and the raw-HTML repair
pass, all in `docs/device-passes.md`.
**Notes:** Two PRs: `CloudSyncKit` in jon-platform first, then Yes Chef. A row that fails the date leg counts
only if its content differs from the cached all-fields record (`unsentEdit`); a match is `stampOnly` and doesn't
count. Compare through SQLiteData's own column encoding (rebuild each `QueryBinding` from the table type), never
raw SQLite values. When unsure, count the row. The report, diagnosis, and `requeue` share one predicate. Decode
all-fields only for date-leg failures, one at a time, and keep verdicts in a caller-owned memory cache. Nothing
writes to SQLiteData's metadata. The 189 tagless rows stay counted and are out of scope. Touches sync, so the
architect escalates both PRs to Jon. Start from a fresh `main` in both repos.
