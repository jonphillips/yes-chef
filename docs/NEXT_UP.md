# Next Up — Sync activity log: watch the iPhone's first sync from the TestFlight build

**Slices:** effort `sync-activity-log`, one Yes Chef PR.
**Briefs:** [docs/efforts/sync-activity-log.md](efforts/sync-activity-log.md)
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Dispatched during PROD-CUTOVER Step 11, to ship as a TestFlight update while the iPhone is still
downloading. No synced-schema change, no migration, and no edit under `Vendor/`. Start from a fresh `main`. The
PR escalates to Jon for merge.
