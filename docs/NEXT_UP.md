# Next Up — Recipe Lenses (ADR-0050 Amendment 1, L1 + L2)

**Slices:** effort `recipe-lenses`, L1 + L2 in one PR.
**Briefs:** [docs/efforts/recipe-lenses.md](efforts/recipe-lenses.md)
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** The chat-access S2b pass (search rows show categories), the automatic-backups pass on the first
TestFlight build, and the control-conventions pass; see [device-passes.md](device-passes.md).
**Notes:** A synced-schema change (two new tables), the first since the cut. Production gets the new record types
only through a Development → Production deploy, which the brief's held-ops block covers; don't run `testflight`
from this branch. Start from a fresh `main`.
