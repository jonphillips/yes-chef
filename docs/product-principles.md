# Product principles & history

Background for agents: read the section that matches the work (recipe model, UI, import, AI,
style). Moved verbatim from `docs/AGENTS.md` on 2026-09-29 so the always-read guide stays
lean. Some of it predates shipped features (import, AI, meal planning) — where it conflicts
with an ADR in `docs/decisions/`, the ADR wins.

## Original MVP scope (history)

The initial app should support:

- Recipe list
- Recipe detail
- Recipe creation/editing
- Ingredients
- Instructions
- Notes
- Tags
- Categories
- Search
- Recipe scaling
- Cooking mode
- Sample data
- Future import from Paprika export

Do not build the following unless explicitly requested:

- User accounts
- Server backend
- Social sharing network
- Public recipe feed
- Nutrition tracking
- Subscription/payment infrastructure
- Android app
- Web app
- Complex AI recipe generation
- OCR
- Voice assistant

## Recipe Model Philosophy

Ingredient lines should support both original text and parsed fields.

Example:

Original:

`2 tablespoons finely chopped fresh rosemary`

Parsed:

- quantity: 2
- unit: tablespoon
- item: fresh rosemary
- preparation: finely chopped

But the original text must remain available.

Do not over-normalize early. Recipe data is messy. Prefer a tolerant model.

## UI Philosophy

The app should feel:

- Modern
- Calm
- Fast
- Serious
- Kitchen-friendly
- Private
- Personal

Cooking screens should prioritize readability and low friction.

Useful qualities:

- Large typography
- Clear ingredient sections
- Clear instruction steps
- Easy notes access
- Minimal clutter
- Screen awake during cooking mode

Avoid gimmicky UI.

## Import Strategy

The app should eventually import user-owned Paprika data.

Before implementing full import:

1. Inspect a real sample export.
2. Document the file structure.
3. Build a parser for a small fixture.
4. Preserve all original data.
5. Add tests.
6. Report import warnings.

Do not assume Paprika’s format before inspecting a sample.

## AI Strategy

AI features are future enhancements, not MVP foundation.

Good future AI features:

- Clean imported recipe text.
- Parse ingredients.
- Extract prep tasks.
- Suggest make-ahead plan.
- Generate cooking timeline.
- Identify shopping categories.
- Flag equipment conflicts.
- Suggest substitutions based on explicit user preferences.

Bad early AI features:

- Generic recipe generation.
- Unreviewed automatic rewriting.
- Confident nutrition guessing.
- Destructive normalization.
- Hidden transformations.

## Coding Style

Prefer:

- Clear names
- Small files
- Small views
- Explicit model relationships
- Simple functions
- Tests for logic
- Preview data
- Comments where they clarify non-obvious choices

Avoid:

- Cleverness
- Framework churn
- Unnecessary packages
- Large architectural rewrites
- Silent behavior changes

## First implementation target (history — built)

Build a minimal but real recipe library:

1. Define core models (plain structs, UUID PKs — a single owner's private library, no
   shared graph; see DATA_MODEL.md §2.6):
   - Recipe (plain `favorite`/`rating` columns; a write-once `originalSnapshot` blob
     captured on first save — see DATA_MODEL.md §2.4)
   - RecipeSource (separate table linked by `recipeID`, not flattened onto Recipe)
   - IngredientSection
   - IngredientLine
   - InstructionSection
   - InstructionStep
   - RecipeNote
   - RecipePhoto
   - Tag
   - Category
   - Equipment
   - RecipeTag, RecipeCategory, RecipeEquipment (joins, real FKs both sides)

2. Add sample data.

3. Build screens:
   - Recipe list
   - Recipe detail
   - Recipe editor

4. Add:
   - Search
   - Tag/category display
   - Favorite flag (a plain column on the recipe)
   - Tagging
   - View original version, read-only (from the frozen `originalSnapshot`)
   - Basic scaling display
   - Cooking mode shell
   - Meal-planner-ready cooking memory: derive last-cooked history from past
     planned meals; do not expose a manual "mark cooked" or retrospective-note flow
     in the first slice.

Do not implement CloudKit sync, recipe transfer (send/Family Cookbook), production
import UI, grocery list, meal planning, pantry, or AI in the first coding pass unless
specifically requested. A Paprika fixture spike may happen early to validate the schema,
but it is not a shipped import flow.

There is no `Household`/`Cook`/sharing schema to build — the core is a single owner's
private library (ADR-0003).
