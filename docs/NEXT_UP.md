# Next Up — Retry parked sync records from their saved copy (vendored SQLiteData patch)

**Slices:** effort `sqlite-data-parked-retry`, one Yes Chef PR.
**Briefs:** [docs/efforts/sqlite-data-parked-retry.md](efforts/sqlite-data-parked-retry.md)
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Unblocks PROD-CUTOVER Step 11: the iPhone's first sync is stuck behind this. Patch commit on its own.
Changes sync behavior, so the PR escalates to Jon for merge. Start from a fresh `main`.
