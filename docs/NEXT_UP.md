# Next Up — Automatic daily backups (S1: CloudSyncKit + Yes Chef)

**Slices:** effort `automatic-backups`, S1. Two PRs: jon-platform `CloudSyncKit` (additive) first, then Yes Chef.
**Briefs:** docs/efforts/automatic-backups.md
**Done when:** per the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's iPad leftover-check pass (sync-failure-surfacing Slice 5), see `docs/device-passes.md`. This
dispatch adds the automatic-backups pass there.
**Notes:** Read jon-platform `docs/adr/0008-automatic-scheduled-backups.md` first; the brief implements its S1.
Reuse `DatabaseBackup.snapshot` unchanged. Pruning only ever deletes files matching the automatic filename
pattern. Publish the container through `project.yml`, never by hand in `Info.plist`. The architect escalates
the Yes Chef PR to Jon (device gates owed). Yes Chef loads `CloudSyncKit` by local path, so build against a
fresh jon-platform `main`. Start from a fresh `main` in both repos.
