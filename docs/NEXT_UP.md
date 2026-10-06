# Next Up — Lift backup & restore into CloudSyncKit

**Slices:** effort `cloudsynckit-backup-lift` (two PRs, both on branch `effort/cloudsynckit-backup-lift`: jon-platform first, then yes-chef)
**Briefs:** docs/efforts/cloudsynckit-backup-lift.md, jon-platform docs/adr/0006-lift-backup-restore-into-cloud-sync-kit.md
**Done when:** per the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's device passes in `docs/device-passes.md` (not executor work).
**Notes:** A move, not a copy: Yes Chef's behavior, copy, and backup files are unchanged. The jon-platform
PR is additive, and Galavant `main` must still build against it. Keep both defaults-key strings exact.
Touches sync, so the architect escalates both PRs to Jon. Start from a fresh `main` in both repos.
