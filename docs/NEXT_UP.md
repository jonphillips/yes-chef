# Next Up — Menu brings in calendar days (Dispatch 1 of 2)

**Slices:** menu-absorbs-calendar-days · S1 + S2 (one PR)
**Briefs:** [A menu brings in its calendar days](efforts/menu-absorbs-calendar-days.md)
**Done when:** Per the brief: cooking history counts recipes on past placed menus through one shared day-arithmetic helper; placing a menu with one placement offers Bring In, which moves loose calendar items and copies wholly-contained placed menus (items, prep steps, grocery sources re-pointed) in one transaction; Menu detail offers it on demand; regression coverage, required builds/tests, closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Decisions are ADR-0063 D1–D4 (Jon, 2026-11-08). No schema, sync or migration change in this dispatch. S3–S5 (the `workDayOffset` column) are Dispatch 2 — do not start them here. UI acceptance remains a Jon device gate.
