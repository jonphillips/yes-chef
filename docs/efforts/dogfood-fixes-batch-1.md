# Effort: Dogfood fixes — batch 1 (bugs + near-term UX)

**Type:** Bug fixes + small self-contained UX wins (no new architecture)
**Owner:** Codex (implement, per slice) · Jon (architect/review)
**Status:** Designed, **queued**. Becomes the next dispatch batch **when Reader Feedback Slice 4
(`docs/efforts/reader-feedback-comment-ingestion.md`) is architect-approved** — not before.
Promote into `CURRENT_HANDOFF.md` § Next Up at that point, one slice at a time.

## Motivation

First real dogfooding pass (Jon, 2026-07-02) surfaced a batch of concrete defects and small
missing affordances. Two are genuine bugs (verified against current code); the rest are
self-contained UX wins that need no new architecture. Grouped here so they ship as a tight
batch after the current LLM-client slice lands.

Explicitly **not** in this batch (filed elsewhere — see § Out of scope):
- Canonical-ingredient work ("salt to taste"), grocery store-section grouping, and aisle
  dropdowns → Phase E grocery milestone (`docs/milestones/grocery-consolidation-and-pantry.md`).
- Ingredient formatting / Markdown / paste-preserve; menu dates & guests; multi-add groceries
  from a calendar day → `docs/open-questions.md`.
- Apple Watch grocery app → `docs/REQUIREMENTS_MVP_ROADMAP.md` §9.

---

## Bug fixes (jump the queue)

### Slice 1 — Add-to-Grocery / add sheets don't present over a full-screen recipe

**Symptom (Jon):** open a recipe full-screen from the Meal Calendar, tap "Add to Grocery" —
nothing happens; dismiss the full-screen recipe and the Add-to-Grocery sheet then slides up.

**Confirmed cause:** recipes open via `.fullScreenCover` at
[`RecipeLibraryView.swift:40`](../../YesChefApp/RecipeLibraryView.swift) (`presentedRecipeID`),
while the ingredient-selection sheet is attached at
[`RecipeLibraryView.swift:289`](../../YesChefApp/RecipeLibraryView.swift)
(`groceryModel.destination.selectIngredients`) on the view *underneath* the cover. UIKit/SwiftUI
queues a sheet requested from a view already covered by a `fullScreenCover` until the cover
dismisses — so the tap "does nothing" until you back out.

**Fix direction:** present the grocery/add sheet from within (or above) the full-screen recipe
presentation, so it appears in-context. Audit every affordance reachable from the full-screen
recipe for the same trap.

**Implementation status (PR #58, in review):** the first pass (commit `5772ed8`) extracted the
meal-editor and grocery presenters into `YesChefApp/AppDestinationPresentation.swift`, attached
them to `RecipeFullScreenCover`, and gated the root copies on `presentedRecipeID == nil`. The
gating pattern is correct (exactly one presenter live per destination — no double-present
window). But it only covered 2 of the ~6 toolbar affordances on
[`RecipeDetailView.swift`](../../YesChefApp/RecipeDetailView.swift).

**Extend the slice (architect, 2026-07-02):** four more `RecipeDetailView` toolbar actions set
**`recipeModel.destination`**, whose presenters live *only* on the root `AppContainer` and are
still trapped under the cover. Recipes open full-screen whenever tapped from the **Meal Calendar**
or a **Menu** (`onRecipeSelected` → `presentedRecipeID`), so these are live dead buttons there:

  | Affordance | Trigger (`RecipeDetailView.swift`) | Root-only presenter (`RecipeLibraryView.swift`) |
  |---|---|---|
  | Edit | `libraryModel.editButtonTapped` (:68) | `.editRecipe` sheet (:92) |
  | Start Cooking | `libraryModel.cookButtonTapped` (:172) | `.cookingMode` sheet (:97) |
  | View Original | `libraryModel.originalSnapshotButtonTapped` (:140) | `.originalSnapshot` sheet (:102) |
  | Delete | `libraryModel.deleteButtonTapped` (:74) | `.deleteRecipe` confirmationDialog (:107) |

  Apply the same pattern already used in this PR: add a `recipeDetailDestinations`-style modifier
  (covering `editRecipe`, `cookingMode`, `originalSnapshot`, `deleteRecipe`) in
  `AppDestinationPresentation.swift`, attach it to `RecipeFullScreenCover`, and gate the root
  copies on `presentedRecipeID == nil`. The `RecipeDetailModel` scaling sheet
  (`RecipeDetailView.swift:194`) is already inside the cover — leave it. Push to the same PR #58
  branch.

**Done when:** every toolbar affordance on a recipe opened full-screen — Add-to-Grocery,
Add-to-Plan, Edit, Start Cooking, View Original, Delete — presents immediately, in-context over
the recipe, from the Meal Calendar, a Menu, *and* the library.

### Slice 2 — Add-to-Meal / Add-to-Grocery act on the viewed recipe, with confirmation

**Symptom (Jon):** from a recipe, the "add to meal" affordance is confusing — no confirmation
that *this* recipe was added, and if the target recipe isn't at the top of a list it's unclear
what got added.

**Fix direction:** when invoked from a recipe you're viewing, the action targets **that**
recipe and shows an explicit confirmation (the recipe that was added + where). Don't make the
user re-pick from a list the recipe they're already looking at. Coordinate with Slice 1 so the
confirmation surface itself presents correctly over the recipe. **Done when:** adding to
meal/grocery from an open recipe confirms the specific recipe added, unambiguously.

### Slice 3 — Archived recipes are invisible with no restore/purge

**Symptom (Jon):** deleting a recipe silently *archives* it — it's not really gone, and there's
no way to see, restore, or truly delete it.

**Confirmed cause:** delete = soft-archive. `Recipe.archived: Bool`
([`Models.swift:23`](../../YesChefPackage/Sources/YesChefCore/Models.swift)),
`RecipeRepository.archive`
([`RecipeCore.swift:399`](../../YesChefPackage/Sources/YesChefCore/RecipeCore.swift)), called
from the delete path at
[`RecipeModels.swift:171`](../../YesChefApp/RecipeModels.swift); the library only ever shows
`unarchivedRecipeRows`
([`RecipeLibraryListState.swift:320`](../../YesChefApp/RecipeLibraryListState.swift)). There is
no view that lists archived rows and no hard-delete path.

**Extra weight now that sync is on:** archived rows replicate to every device invisibly and ride
into the private CloudKit zone forever. This is worth closing sooner rather than later.

**Fix direction:** an "Archived" view (e.g. from library overflow / settings) that lists
archived recipes with **Restore** (`archived = false`) and **Delete permanently** (real
`Recipe.delete`, FK-cascading its children). Keep it low-prominence. **Done when:** Jon can find,
restore, and permanently delete archived recipes; permanent delete removes the row (and its
child rows) so it stops syncing.

**Dangling references — archive means GONE (Jon, 2026-07-02).** Surfaced from the PR #58 review:
`archived` is honored inconsistently. The recipe list and the calendar/menu *add-pickers* filter
it ([`RecipeLibraryListState.swift:321`](../../YesChefApp/RecipeLibraryListState.swift),
[`MealCalendarModels.swift:114`](../../YesChefApp/MealCalendarModels.swift),
[`MenuModels.swift:41`](../../YesChefApp/MenuModels.swift)), but *already-scheduled* meal-plan
items and menu dishes resolve the recipe by ID with **no** archived check, so an archived recipe
keeps rendering on its scheduled date / in its menu and stays tappable into a live, fully
interactive archived detail.

Decision: **archiving cascades — remove the recipe's meal-plan placements *and* menu-dish
placements at archive time.** The meal calendar is forward-planning (not a log), and although
menus lean historical, Jon's intent on archive is unambiguously "gone everywhere"; restore brings
back the recipe, not its placements (cheap to re-add). Enforce this so no future view has to
remember to filter:
- On archive, delete the recipe's meal-plan item rows and menu-dish rows (same transaction as the
  archive flip; must be sync-safe — deletes replicate).
- Adopt **"Archive"** as the user-facing term for the destructive recipe action (button +
  confirmation copy), replacing "Delete Recipe" / "Delete X from your recipe library?", so the
  label matches the recoverable-but-gone behavior.
- Belt-and-suspenders: guard the item/dish *resolution* path against archived recipes too, so a
  stale or mid-sync reference can never re-open a live archived detail.

**Done when:** archiving a recipe removes it from the library, its calendar dates, and any menus in
one step; nothing left tappable resolves an archived recipe; the action reads as "Archive"; and the
Archived view can restore (recipe only) or permanently purge.

---

## Near-term UX wins (small, self-contained)

### Slice 4 — Browser: clear-URL (X) button

Add a trailing clear button to the browser URL field that empties the current URL/address.
Small. **Done when:** one tap clears the field.

### Slice 5 — Recipe list: keep search reachable / scroll-to-top

Search currently scrolls away with the list. Either pin the search field so it stays reachable,
or add a fast scroll-to-top affordance (tap status bar already does some of this on iOS — verify;
if insufficient, add an explicit control). **Done when:** Jon can get back to search/top of a
long recipe list without manually scrolling all the way up.

### Slice 6 — Share the grocery list as text

Add a Share action to a grocery list that produces a plain-text rendering (respecting current
order/grouping) into the system share sheet. **Done when:** the grocery list can be shared as
readable text to Messages/Notes/etc. *(When Phase E store-section grouping lands, the text export
should reflect the sections — note the dependency, don't block on it.)*

### Slice 7 — Edit a grocery item (name + amount)

Grocery rows can't be edited today. Add an edit affordance for a grocery item's **name** and
**amount/quantity**. Keep it compatible with the source-provenance model (a manual edit to a
generated row shouldn't silently corrupt its `GroceryItemSource` breakdown — decide and test the
interaction: e.g. an edited row detaches to a custom/edited state, or the edit is preserved
distinctly). **Flag the provenance interaction in the PR.** **Done when:** name and amount are
editable and the change persists without breaking the source breakdown.

### Slice 8 — Scale a recipe by a multiplier (double/triple), show resulting servings

Today scaling is driven through the servings concept. Add a direct multiplier (×2, ×3, …, and/or
free multiplier) that scales ingredient quantities, and **display the resulting servings count**
after scaling so the servings still read correctly. Do not remove servings-based scaling; add
the multiplier as a parallel, more direct control. **Done when:** Jon can double/triple a recipe
directly and see the resulting servings.

### Slice 9 — Add an image to a manually-entered recipe

The manual recipe editor has no way to attach a photo. Add a photo picker (reuse the existing
image storage/processing path — ADR-0005; hero images already sync as CKAssets, so no schema
change). **Done when:** a manually-created recipe can have a hero image added, and it displays
and syncs like a captured one.

---

## Out of scope — with destinations

| Deferred | Goes to |
|---|---|
| "Salt to taste" / canonical ingredient pickup | `docs/milestones/grocery-consolidation-and-pantry.md` (Phase E) |
| Grocery list split by store section | Phase E grocery — "later grocery polish" (aisle/section) |
| Define "Aisles" as a dropdown | Phase E grocery — same |
| Ingredient formatting / Markdown / paste-preserve | `docs/open-questions.md` § Recipe ingredient authoring |
| Menu date + upcoming/previous + on planner | `docs/open-questions.md` § Menus / planning model |
| Menu guests (searchable field) | `docs/open-questions.md` § Menus / planning model |
| Multi-add groceries by tapping a calendar day | `docs/open-questions.md` § Menus / planning model |
| Apple Watch grocery app | `docs/REQUIREMENTS_MVP_ROADMAP.md` §9 Future Differentiators |

## Working agreement

- Each slice: branch → PR → merge (`main` protected; self-merge). Commit trailer + PR trailer as
  usual. Verify locally (`swift test --package-path YesChefPackage`, `bash scripts/check-drift.sh`,
  iPad + iPhone sim install) — CI doesn't run on this repo.
- Slices 1–3 (bugs) ship first; 4–9 are independent and can be reordered by whatever Jon finds
  most annoying next.
