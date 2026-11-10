# Next Up — Chat-started recipe returns and stage_menu

**Slices:** chat-started-returns-and-menus · S4 + S5 (one PR)
**Briefs:** [Chat-started recipe returns and `stage_menu`](efforts/chat-started-returns-and-menus.md)
**Done when:** Per the brief: `stage_recipe_return` resolves a recipe ref in the helper, stages a `.ycrecipereturn` envelope, and opens in the app as a `.recipe` review through a freshly created local `AIHandoff`; `stage_menu` validates and stages a `.ycmenu` envelope that opens a review sheet whose Create Menu writes one transaction and never a recipe row without an id; `get_recipe` returns Make-ahead and Chef It Up; the instructions open per Amd 2-D6 and the label block is one Core constant; no ids in tool output; tests, required builds (including `YesChefTests`), closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Decisions are ADR-0060 Amd 2 D1–D6 (accepted 2026-11-10, #471). No schema change. Tool descriptions carry the routing (ChatGPT doesn't show the model server instructions). The PR body gives Jon the install order: app on both devices first, then the helper. UI acceptance is a Jon device gate.
