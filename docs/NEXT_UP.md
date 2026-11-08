# Next Up — Menu prep plan runs by work day (Dispatch 2 of 2)

**Slices:** menu-absorbs-calendar-days · S3 + S4 + S5 (one PR)
**Briefs:** [A menu brings in its calendar days, and a multi-day prep plan runs by work day](efforts/menu-absorbs-calendar-days.md)
**Done when:** Per the brief: add the nullable `workDayOffset` field and migration; carry work days through prep-plan generation, review text, editing, and day bands; shift copied prep steps on bring-in; regression coverage, required builds/tests, closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** ADR-0063 D5–D8 (Jon, 2026-11-08). The new nullable column is synced: Jon creates it in Development and promotes it to Production before any TestFlight upload. UI acceptance remains a Jon device gate.
