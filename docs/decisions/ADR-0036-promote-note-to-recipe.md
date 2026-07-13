# ADR-0036 — Promote a recipe-shaped note into a real recipe

> **Vocabulary:** a *note* here is user-authored prose with **no structured recipe body** — most often a
> menu/meal **note-item** (`MealPlanItemKind.note`, no `recipeID`, per [[menu-item-recipe-id-invariant]]),
> and secondarily a `RecipeNote` deposited on a recipe (ADR-0027). A *recipe* is the structured
> `Recipe` + `IngredientLine`s + `InstructionStep`s that the whole app is built around (grocery, scaling,
> cook mode, compare, menus). **Promotion** = turning recipe-shaped note prose into a real structured
> recipe, so everything downstream works on it.

Status: **Accepted** — 2026-07-12 (Proposed 2026-07-12). Origin: Jon's 2026-07-12 dogfood conversation ("I have a note that has
a recipe shape… what is *easier* — adding note items to a grocery list, or speccing the promotion of a
note to a recipe?"). **Formalizes [ADR-0027](ADR-0027-harvest-chat-into-notes.md) D5 / A6**, previously
parked "out of scope — a separate downstream step." Touches
[ADR-0021](ADR-0021-recipe-variations.md)/[ADR-0023](ADR-0023-recipe-edit-proposals.md) (draft/review/commit
surface) and [[reference-placement-and-original-provenance]] (where the new recipe lands + what it
remembers). Reuses the existing extract→review→commit machinery ([ADR-0024](ADR-0024-editable-proposal-preview.md))
and the text→structured-recipe parser (`WebRecipeCapture/RecipeParseBuilder.swift`,
`IngredientParser.swift`).

## Context

Jon has a note whose body is really a recipe (ingredients + method as prose). He wants those ingredients
on a grocery list and framed the choice as two build options:

- **Option A — let note-items feed the grocery list directly.**
- **Option B — promote the note to a real recipe.**

**A is a trap, and not because it's more work — because it secretly *contains* B's hard part with none of
the payoff.** Grocery generation reads **structured** `IngredientLine`s off a recipe
(`GroceryRepository+Generation`). A note is prose with no structured ingredients. To feed a note into the
grocery pipeline you must first parse its prose into ingredient lines — which is exactly the difficult
half of promoting it to a recipe. Build A and stop, and you own a one-off prose→ingredients parser that
serves *only* groceries. Build B, and the same parse lands a recipe that grocery **plus** scaling, cook
mode, compare, and menu-placement all consume for free. **We choose B.**

Promotion is also cheaper than a from-scratch feature because the parsing and the review/commit surface
already exist:

- **Text → structured recipe** is what web capture already does (`RecipeParseBuilder`, `IngredientParser`)
  — point it at the note's text instead of page HTML.
- **`WorkbenchDraftRecipe`** is already a structured draft (`ingredientLines`, `instructionLines`, title,
  servings, …) with a review render, an editable-prose round-trip
  (`editableProseReviewText`/`applyingEditableProseReviewText`), and `editorDraft(libraryPlacement:)` that
  produces a committable `RecipeEditorDraft`. This is the natural intermediate for a promoted note.
- **The editable-proposal preview** (ADR-0024) is the human-in-the-loop review surface — the parse is a
  *proposal*, never a silent create.

## Decision

Add a **"Make a recipe from this note"** action that parses the note's prose into a `WorkbenchDraftRecipe`
(on-device tier by default per [[yeschef-onbard-model-tier]], since it's cheap/private; frontier-preferred
if the user has a key), presents it in the **existing editable-proposal review surface** (ADR-0024) for
correction, and on commit creates a real `Recipe` with structured ingredients + method. Parsing is
**advisory input to a review**, not an autonomous write — consistent with the whole apply-action family
and the "preserve original text" priority.

**Provenance.** The source note is preserved, not consumed. The original prose rides into the new recipe
as an editable general note (see OQ2 — resolved to a `RecipeNote`, not a `RecipeSource` snapshot or FK);
the note itself is left intact until the user opts into S2 replacement. No destructive delete of user prose.

**Placement.** The new recipe lands in the main library by default. If the source was a *menu* note-item,
the promotion additionally offers to **replace the note-item in place with a recipe-kind menu item**
pointing at the new recipe (restoring the `recipeID` invariant), so the dish becomes a first-class menu
entry that flows into the menu's grocery generation and prep plan.

## Build slices (proposed — confirm scope with Jon before dispatch)

**S1 — parse + review + commit to library.** Wire the note text through the `RecipeParseBuilder`-style
extraction into a `WorkbenchDraftRecipe`, surface it in the ADR-0024 review preview, commit to a new
`Recipe`. Provenance link recorded. No menu re-placement yet. Reuses existing parse + review + commit;
the net-new is the entry point (a note action) and the note→draft adapter. Schema-free if provenance can
ride an existing column/snapshot; otherwise one additive nullable column (call it out — it would join the
standing prod-schema follow-up list).

**S2 — menu re-placement.** When the source is a menu note-item, offer to swap it for a recipe-kind item
referencing the new recipe (satisfies [[menu-item-recipe-id-invariant]]). App-layer, small, gated on S1.

## Consequences

- Solves the grocery ask *correctly*: once promoted, the note's ingredients flow through the normal,
  deterministic grocery pipeline (and inherit ADR-0035 store-area grouping) with zero grocery-specific
  code.
- No new parsing engine — reuses web-capture extraction and the ADR-0024 review surface. The genuinely
  new design work is **placement + provenance**, which is exactly why ADR-0027 parked it as its own step.
- Keeps the "notes are prose, recipes are structured" boundary clean: promotion is an explicit,
  reviewed transformation, not an implicit blurring of the two.

## Open questions

- **OQ1 — which "note" is in scope first? — RESOLVED 2026-07-12.** Jon's first need is **a note *on a
  menu* that is really in a recipe shape** — i.e. a `MealPlanItemKind.note` menu item whose body is
  recipe prose. So **S1 targets the menu note-item**, and S2's menu re-placement (swap the note-item for a
  recipe-kind item pointing at the new recipe) is the natural completion of that exact flow. `RecipeNote`
  promotion is a later, separate slice (S3), not part of this scope.
- **OQ2 — provenance storage. — RESOLVED 2026-07-13 (S1 build).** Neither a snapshot nor an FK. The
  original note prose is written into the new recipe as an **editable general `RecipeNote`** (`From menu
  note "<title>":` + the prose), not a `RecipeSource`. Rationale from device testing: a `RecipeSource`
  renders as a pinned, non-editable "source" card at the top of the recipe (and can't be deleted), which
  crowds the recipe and the menu row for no payoff. A general note is user-trimmable/deletable, survives
  sync as plain text (the lightest thing that survives), and needs no schema column. No machine FK is
  stored: after S2 replacement the live back-link is the menu item's own `recipeID`; for a kept note the
  human-readable attribution line is the provenance. The S2 replacement also clears the note row's
  `notes` so the promoted row collapses to its title.
- **OQ3 — parse quality bar for hand-typed prose.** Web capture parses fairly structured page markup;
  free-hand note prose is messier. The editable review (ADR-0024) is the safety net, but watch whether
  on-device extraction is strong enough or this should default frontier-preferred.
