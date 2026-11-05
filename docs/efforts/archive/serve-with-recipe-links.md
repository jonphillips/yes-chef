# Effort — Serve With recipe links

Status: Ready
Summary: Let a Serve With row link to a recipe, with free text unchanged. Adds one nullable synced column, the link
editor and picker, and a chip that opens the linked recipe.

Implements: [ADR-0062](../../decisions/ADR-0062-serve-with-recipe-links.md). Its decisions are the spec; D-numbers below
refer to it. Related: [ADR-0048](../../decisions/ADR-0048-playbook-edit-grain.md).

**Persistent model change (AGENTS.md).**
- **What:** a nullable `linkedRecipeID TEXT` on `recipeServeWith`, as `linkedRecipeID: Recipe.ID?` on the model, with no
  foreign key.
- **Why:** rows have no connection to the library.
- **Existing data:** untouched; every row starts unlinked.
- **Migration:** one appended `ALTER TABLE … ADD COLUMN`, and `declaredSchemaVersion` goes up by one.
- **Sync:** the table is synced. Regenerate `cloudkit-expected-fields.txt`; its diff must be exactly
  `recipeServeWith linkedRecipeID` and `recipeServeWith sqlitedata_icloud_userModificationTime_linkedRecipeID`. Jon does
  the CloudKit deploy (D8); it isn't part of this PR.
- **Simpler alternative:** none that keeps free text and gives a real link (see the ADR's Rejected section).

## Build

**Core (`YesChefCore`).**
1. Add the migration, model field and init default. Keep `ServeWithItem`, `ServeWithSuggestion`, `ServeWithPlan` and the
   return contract unchanged (D5).
2. In `RecipeServeWithRepository` (`RecipeEnrichment.swift`):
   - Add a dedicated link setter, so a title edit can't clobber a link. `update(id:title:note:…)` doesn't touch the
     field. Touch the recipe as the other writers do.
   - Let a hand-authored row be created with a link.
   - In `replaceModelSuggestions`, don't delete a linked row. Keep linked rows in the matching pool, so a returned
     suggestion with the same title retains the row rather than duplicating it (D4).
3. `cloneServeWith` (`RecipeAdjustment.swift`) rebuilds each row field by field, so it must carry the link (D4).
4. `permanentlyDelete` (`RecipeCore.swift`) clears `linkedRecipeID` on rows pointing at the recipe (D3).
5. `recipeIsContentEmpty` (`RecipeRepository+Import.swift`) returns false for a recipe a Serve With row links to (D3).
6. `fetchDetail` adds the set of this recipe's linked ids that exist and aren't archived, and `RecipeDetail` carries it.
   Read it scoped to those ids (D3).

**App.**
7. Extract `RelatedRecipePicker` (`RecipeRelatedRecipeChoices.swift`) into a shared view that takes the rows, the
   recipes to exclude, and the action. Related Recipes behaves as before. Load rows with
   `relatedRecipePickerRows`, on demand, never from an always-on `@Fetch`.
8. `ServeWithItemEditorSheet` (`RecipePlaybookView.swift`) gets the Recipe section (D6). The link is part of the draft
   until Save. Picking fills a blank title only (D2).
9. `RecipeServeWithStrip` takes `onRecipeSelected`. A resolved link shows the glyph and opens the recipe; Edit moves to a
   `.contextMenu` and a named accessibility action, with a matching accessibility hint. Unresolved rows keep today's
   behavior (D3, D6). Show the glyph in the row list too.

Model logic stays in `RecipeDetailModel+Enrichment.swift`; views bind and delegate.

## Tests

In `YesChefCoreTests`:
- Setting and clearing a link; a title or note update leaves the link alone.
- `replaceModelSuggestions`: an unmatched linked `.model` row stays with its provenance unchanged, an unmatched unlinked
  one is deleted, and a matching suggestion doesn't duplicate a linked row.
- Clear Serve With still removes linked rows.
- Cloning a recipe carries links.
- `permanentlyDelete` clears the link and keeps the row's title and note.
- `fetchDetail` resolves an active target, and leaves out an archived target and a missing one. Restoring the archived
  target brings the link back.
- `recipeIsContentEmpty` is false for a link target.
- Rows encoded without the field still decode.
- The expected-fields test passes with exactly the two new lines.

**Verification:** `scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator, because this
touches app model code ([`verification.md`](../../verification.md)).

**Done when:** the build items are in, the tests pass, and closeout runs (ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

After the CloudKit deploy, on TestFlight or a Dev build as the held steps allow: link a Serve With row on the iPad. The
chip shows the glyph and opens the recipe, the context menu still edits it, and the link reaches the iPhone. Regenerate
Serve With and confirm the linked row stays. Archive the target and the chip goes plain; restore it and the link returns.

## Merge

This changes a synced table, adds a migration and owes a gate, so Jon merges it (ADR-0005 D9).
