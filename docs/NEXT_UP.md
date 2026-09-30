# Next Up — Scale ingredient ranges + label a blocked compare fallback

**Slices:** effort `ingredient-range-scaling` (Fix 1 + Fix 2, one PR, branch `effort/ingredient-range-scaling`)
**Briefs:** docs/efforts/ingredient-range-scaling.md
**Done when:** per the brief (§ Done when)
**Owed:** Jon's device passes and the held prod-schema promotion — `docs/device-passes.md` (not executor work).
**Notes:** `YesChefCore` only, schema-free. Fix it at display time: don't change `IngredientParser.parse` or the stored quantity columns (grocery reads them). The completing PR adds the DONE-LOG entry, adds the reader scaling pass to `device-passes.md`, and sets this file back to `Nothing dispatched.` with its **Owed** line.
