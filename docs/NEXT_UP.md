# Next Up — Sync failure status in Yes Chef (Slice 2)

**Slices:** effort `sync-failure-surfacing`, Slice 2 — Yes Chef only
**Briefs:** docs/efforts/sync-failure-surfacing.md § Slice 2
**Done when:** per Slice 2 and the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's two-device sync status pass in `docs/device-passes.md`.
**Notes:** Nothing in jon-platform blocks this. Slice 1's `CloudSyncKit` signal, `.needsAttention` case and
`CloudSync.requeue` are on jon-platform `main` (jon-platform#72), and Yes Chef loads `CloudSyncKit` by local path, so
there's no package version to bump: build against a jon-platform checkout on fresh `main`. The sync row already
renders `.needsAttention` (#353). This dispatch adds the per-row detail list with **Retry**. Do not add an
automatic retry loop. Start from a fresh `main`.
