# Next Up — Drop the dead cook columns before the Production deploy (ADR-0056 Phase 1)

**Slices:** effort `prod-dead-column-drop` (one PR, branch `effort/prod-dead-column-drop`)
**Briefs:** docs/efforts/prod-dead-column-drop.md, docs/decisions/ADR-0056-move-to-production-and-data-carry.md Amendment 1
**Done when:** per the brief's "Done when"; verification per `docs/verification.md`.
**Owed:** Jon's device passes in `docs/device-passes.md` (not executor work).
**Notes:** An appended migration on a synced table. Never edit an existing migration body. No migration
squash. If the dead-column test finds a column the brief doesn't name, stop and escalate. The architect
escalates the PR to Jon.
