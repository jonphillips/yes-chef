# Next Up — Recover the 241 instruction steps from the Step 4 backup

**Slices:** effort `recover-lost-instruction-steps`, one PR (PROD-CUTOVER Step 10a).
**Briefs:** docs/efforts/recover-lost-instruction-steps.md
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** The chat-access S2b pass (search rows show categories), and the automatic-backups pass on the first
TestFlight build; see [device-passes.md](device-passes.md).
**Notes:** Schema-free, so it's allowed during the cut. It writes to the live library from a backup, so the
architect reviews it at slice resolution before Jon merges. Start from a fresh `main`. Touch no sync code, and
nothing in `Vendor/` or jon-platform.
