# Next Up — Production baseline squash (ADR-0056 Phase 1)

**Slices:** effort `prod-baseline-squash` (one PR, branch `effort/prod-baseline-squash`)
**Briefs:** docs/efforts/prod-baseline-squash.md, docs/decisions/ADR-0056-move-to-production-and-data-carry.md D2
**Done when:** per the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's device passes in `docs/device-passes.md` (not executor work).
**Notes:** Schema change on every device's live store. **Step 0 (freeze the legacy schema fixture) comes
before any edit to `Schema.swift`.** Use GRDB's `registerMigration(_:merging:)`; don't hand-roll identifier
bookkeeping. If you find a dead column the brief doesn't name, stop and escalate. The architect escalates
the PR to Jon and holds the merge until the real-store check passes on a copy of each device's database.
