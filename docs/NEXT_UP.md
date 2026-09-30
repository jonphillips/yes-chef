# Next Up — Scale ingredient ranges (reader + grocery upper bound) + label a blocked compare fallback

**Slices:** effort `ingredient-range-scaling` (Fixes 1–3, one PR, branch `effort/ingredient-range-scaling`)
**Briefs:** docs/efforts/ingredient-range-scaling.md
**Done when:** per the brief (§ Done when)
**Owed:** Jon's device passes and the held prod-schema promotion — `docs/device-passes.md` (not executor work).
**Notes:** `YesChefCore` only, schema-free. One range helper shared by the reader (Fix 1) and the parser (Fix 3). The repair of existing lines is a **post-engine** data pass beside `backfillVariationAnchors`, never a migration, and it touches range lines only. The completing PR adds the DONE-LOG entry, adds the device pass to `device-passes.md`, and sets this file back to `Nothing dispatched.` with its **Owed** line.
