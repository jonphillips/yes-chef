# Next Up — Sync status false positive (Slice 3: explain why a row counts as not uploaded)

**Slices:** effort `sync-failure-surfacing`, Slice 3
**Briefs:** docs/efforts/sync-failure-surfacing.md § Slice 3 ("What happened" explains why)
**Done when:** per § Slice 3 "Done when"; verification per § Slice 3 and `docs/verification.md`.
**Owed:** Jon's Chat access S1 pass, sync failure status pass (blocked on this fix), and raw-HTML repair pass in
`docs/device-passes.md`.
**Notes:** Two PRs: the read-only `CloudSyncKit` diagnosis in jon-platform first, then Yes Chef's DEBUG Diagnose
button with Copy. The report's counting must not change: refactor `isServerConfirmed` to return a reason and keep
the report's behavior identical. No requeue, no fix; Slice 4 is specified from Jon's readout. Touches sync, so the
architect escalates both PRs to Jon. Start from a fresh `main` in both repos.
