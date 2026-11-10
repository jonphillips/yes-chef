# Next Up — One glyph per concept: AppSymbol

**Slices:** app-symbol-vocabulary · S1 + S2 (one PR)
**Briefs:** [One glyph per concept](efforts/app-symbol-vocabulary.md)
**Done when:** Per the brief: `AppSymbol` holds ADR-0065 D2's vocabulary; every concept use in the app goes through it (recipe is `richtext.page` everywhere, `book` only for sources, `.edit` vs `.editRow`); `MealPlanItemKind` and `GroceryItemOrigin` drop their Core glyphs for app-side `symbol`; a SwiftLint rule rejects concept glyph literals and is shown firing; every changed glyph is listed in the PR; tests, required builds, closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Decisions are ADR-0065 D1–D5 (Jon, 2026-11-10). Starts after #468 merges (it uses #468's custom symbol sets). No schema change. Non-concept glyphs stay literals (D3); don't convert them. UI acceptance is a Jon device gate.
