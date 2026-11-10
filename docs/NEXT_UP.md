# Next Up — The menu row's note shows on the recipe screen

**Slices:** menu-row-note-on-recipe (one PR)
**Briefs:** [The menu row's note shows on the recipe screen](efforts/menu-row-note-on-recipe.md)
**Done when:** Per the brief: `RecipeRowNoteRequest` returns the opening row's trimmed note and its menu title (or day and slot) only when the row still points at the recipe shown; `RecipeDetailModel` observes it beside `persistedScale`; a read-only card labeled "For <menu>" shows above Ingredients/Method in compact and at the top of the directions column in wide; nothing writes the recipe; tests, required builds (including `YesChefTests`), closeout.

**Owed:** see [device-passes.md](device-passes.md)
**Notes:** No schema change. Editing stays in the menu's Edit Dish sheet. UI acceptance is a Jon device gate.
