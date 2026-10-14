# Next Up — Sync failure status in Yes Chef

**Slices:** effort `sync-failure-surfacing`, Slice 2 — Yes Chef (one PR, after jon-platform#70 merges)
**Briefs:** docs/efforts/sync-failure-surfacing.md
**Done when:** per Slice 2 and the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's two-device sync status pass in `docs/device-passes.md`.
**Notes:** Wait for jon-platform#70 to merge and bump to its new `CloudSyncKit` package version first. The Settings sync row shows the new state; sync detail lists unsynced rows by readable name with a Retry action that calls `requeue`. Do not add an automatic retry loop. Tick `PROD-CUTOVER.md` Phase 2, add the completion to `DONE-LOG.md`, and keep the device pass owed until Jon clears it. Start from a fresh `main`.
