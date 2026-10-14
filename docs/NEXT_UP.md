# Next Up — Sync failure status in Yes Chef

**Slices:** effort `sync-failure-surfacing`, Slices 1–2 — jon-platform `CloudSyncKit`, then Yes Chef (two PRs, in order)
**Briefs:** docs/efforts/sync-failure-surfacing.md
**Done when:** per Slices 1–2 and the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's two-device sync status pass in `docs/device-passes.md`.
**Notes:** jon-platform#70 is docs-only and must merge before Slice 1 starts. Dispatch Slice 1 to jon-platform for the additive `CloudSyncKit` signal and tests; after it merges, bump Yes Chef to that package version and dispatch Slice 2 for the Settings sync row and retry detail. The brief's device pass and completion steps still apply. Do not add an automatic retry loop. Start each slice from a fresh `main`.
