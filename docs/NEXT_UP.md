# Next Up — Find deletes that never reached iCloud (Slice 5)

**Slices:** effort `sync-failure-surfacing`, Slice 5. Two PRs: jon-platform `CloudSyncKit` (additive) first,
then Yes Chef.
**Briefs:** docs/efforts/sync-failure-surfacing.md § Slice 5
**Done when:** per Slice 5's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's iPad leftover-check pass (Slice 5 § Jon's pass), to be added to `docs/device-passes.md` by the
Yes Chef PR.
**Notes:** Touches sync and deletes from iCloud, so the architect escalates both PRs to Jon. The delete runs only
on records the user confirmed, through `CKDatabase` directly. Never write to SQLiteData's metadata or its
engine state. Don't investigate why the iPad's sends fail; that's out of scope and waits on a device log. Slice 4
(jon-platform #83) is on jon-platform `main`, and Yes Chef loads `CloudSyncKit` by local path, so build against
a fresh jon-platform `main`. Start from a fresh `main` in both repos.
