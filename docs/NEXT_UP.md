# Next Up — Vendored SQLiteData patch: keep children whose parent never reached CloudKit

**Slices:** effort `sqlite-data-reference-violation-patch`, one PR (PROD-CUTOVER Step 9a).
**Briefs:** docs/efforts/sqlite-data-reference-violation-patch.md
**Done when:** per the brief's "Done when"; verification per the brief and `docs/verification.md`.
**Owed:** The chat-access S2b pass (search rows show categories), and the automatic-backups pass on the first
TestFlight build; see [device-passes.md](device-passes.md).
**Notes:** Schema-free, so it's allowed during the cut. It changes sync behavior inside a vendored dependency, so
the architect reviews it at slice resolution before Jon merges. Start from a fresh `main`. Don't touch
`YesChefPackage/Package.swift` or anything in jon-platform.
