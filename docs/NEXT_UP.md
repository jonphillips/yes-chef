# Next Up — Yes Chef Dev: Debug builds get their own app identity (ADR-0059)

**Slices:** effort `yes-chef-dev-variant`: a jon-platform PR, then the completing Yes Chef PR.
**Briefs:** [docs/efforts/yes-chef-dev-variant.md](efforts/yes-chef-dev-variant.md)
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** The chat-access S2b pass (search rows show categories), the automatic-backups pass on the first
TestFlight build, and the control-conventions pass; see [device-passes.md](device-passes.md).
**Notes:** Dispatched ahead of PROD-CUTOVER Step 11 (ADR-0059 Amendment 1). Release identifiers must not change
by a byte. Start from a fresh `main`. PR 403 (Recipe Lenses) stays open and unmerged until this lands; don't
touch it in this effort. Both PRs escalate to Jon for merge.
