# Next Up — Clear out the rows of retired synced tables (Slice 6)

**Slices:** effort `sync-failure-surfacing`, Slice 6. Two PRs: jon-platform `CloudSyncKit` (additive) first,
then Yes Chef.
**Briefs:** docs/efforts/sync-failure-surfacing.md § Slice 6
**Done when:** per Slice 6's "Done when"; verification per `docs/verification.md`.
**Owed:** See [device-passes.md](device-passes.md) for the automatic-backups pass and the Slice 5 iPad
leftover-check pass. The Yes Chef PR adds Slice 6's pass.
**Notes:** Touches sync and deletes from iCloud without confirmation. That's allowed only for the retired types
`categorySeedStates` and `categorySeedTombstones`, and the purge must throw on any type `makeSyncEngine`
registers. The metadata `DELETE` is the one write to SQLiteData's metadata this effort permits; the brief gives
the reasons. Reuse Slice 5's `CloudSyncLeftoverClient` delete path. Build against a fresh jon-platform `main`, and
start from a fresh `main` in both repos.
