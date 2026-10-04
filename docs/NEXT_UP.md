# Next Up — Power Browser responsiveness + reader header wrapping

**Slices:** effort `power-browser-perf-and-reader-header` (Fix 1 + Fix 2, one PR, branch `effort/power-browser-perf-and-reader-header`)
**Briefs:** docs/efforts/power-browser-perf-and-reader-header.md
**Done when:** per the brief (§ Done when)
**Owed:** Jon's device passes and the held prod-schema promotion — `docs/device-passes.md` (not executor work).
**Notes:** Schema-free. Measure before you optimize: the PR carries before/after DEBUG timings for the Power Browser derivations and `visibleRecipeRows`. Option values, counts, and ordering must not change; pin them in tests before the rewrite. The completing PR adds the DONE-LOG entry, adds the device pass to `device-passes.md`, and sets this file back to the canonical empty ticket (`Nothing dispatched.` line + **Owed** pointer).
