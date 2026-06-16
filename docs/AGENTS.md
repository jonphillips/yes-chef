# AGENTS.md

## Project Identity

This project is an Apple-first personal recipe management and cooking-planning app.

It is inspired by Paprika-style recipe management but is not intended to be a direct clone. The goal is to build a modern, private, local-first app for serious home cooks who collect, adapt, plan, shop, cook, and remember what worked.

## House Style and Guidelines
Shared style and architectural guidelines are available in ~/code/jon-platform directory. Start with AGENTS.md there. Nothing in this document should override those guidelines unless we discuss. If you cannot access this directory and information, you must alert me.

## Development Priorities

Follow these priorities in order:

1. Preserve user data.
2. Keep the data model clear and migration-friendly.
3. Build the core recipe library before clever features.
4. Prefer simple, idiomatic Swift and SwiftUI.
5. Avoid premature server/backend complexity.
6. Avoid premature AI features.
7. Add tests for parsing, import, scaling, and data transformations.
8. Keep UI code readable and decomposed.
9. Preserve original imported recipe text.
10. Ask before making persistent model changes that imply migration complexity.

## Current Product Scope

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

## Architecture Guidance

Use the house Apple-native stack defined in `~/code/jon-platform` (read
`docs/ios/swift-style.md`, `persistence-and-sync.md`, and `ui-and-platforms.md`
before proposing architecture). In short:

- SwiftUI multiplatform for UI
- `@Observable` feature models + swift-navigation enum `Destination` for
  navigation/sheets (no `isShowingX` boolean soup)
- SQLiteData (Point-Free) for persistence — local SQLite is the source of truth.
  **Not SwiftData, not Core Data.**
- swift-dependencies (`@Dependency`) for clock/date/UUID/database — no singletons
- Value-type domain models; make impossible states unrepresentable with enums
- Functional core (pure functions), thin views; non-trivial save/load logic lives
  in a model, never in a View
- Sample data for previews
- Separation between model, persistence, parsing/import, and UI
- swift-testing + CustomDump for tests of non-trivial logic
- Use the installed `pfw-*` skills (sqlite-data, dependencies, swift-navigation,
  modern-swiftui, testing) for library mechanics

Avoid:

- Massive SwiftUI view files
- Hidden global state
- Unnecessary abstractions
- Unexplained dependencies
- Networking unless required
- Backend assumptions
- Destructive data transformations

## Implementation Guardrails Learned From Pass 1

These are now project rules, not preferences:

1. Composite detail reads must use SQLiteData observation (`@Fetch` with a
   `FetchKeyRequest`) in a feature model. Do not do one-shot async
   `database.read` calls from `.task` just to populate view `@State`; that can
   surface normal task cancellation as user-facing errors and leaves detail
   screens stale after edits.
2. Non-trivial feature behavior belongs in `@Observable @MainActor` models.
   Views bind to model state and delegate actions; repository functions remain
   pure database operations that accept an explicit `Database`.
3. Editor text blobs are an MVP input surface, not permission to flatten the
   stored model. Until the editor has section-aware UI, it owns only the first
   editable/default ingredient section, the first editable/default instruction
   section, and general notes. It must leave extra sections and typed notes
   untouched.
4. Saves must preserve stable child IDs whenever content is unchanged. Do not
   delete-all/reinsert ingredient lines, instruction steps, notes, or join rows
   as a routine edit strategy; this creates avoidable sync churn and future
   conflict risk.
5. Finite persisted domains must be real Swift enums (`RawRepresentable`,
   `Codable`, `QueryBindable`) rather than strings or static string namespaces.
6. `Recipe.originalSnapshot` must use the canonical recipe-transfer bundle
   shape: full Recipe row plus structured children and tag/category names. Do
   not introduce a separate lossy display-only snapshot format.
7. Add regression tests when a review identifies a data-preservation bug. At a
   minimum, test stable IDs and preservation of out-of-scope structured data.

## Data Preservation Rules

Recipe import and editing must preserve source fidelity.

Rules:

1. Never discard original imported text.
2. Ingredient parsing should preserve the original ingredient line.
3. Instruction cleanup should preserve original instruction text or source.
4. Imported source URLs should be retained.
5. Import warnings and errors should be visible.
6. If data cannot be parsed confidently, store it as text rather than inventing structure.

## Persistent Model Change Rule

Before changing persistent model types, explain:

- What model is changing.
- Why it needs to change.
- Whether existing data could be affected.
- Whether a migration is required.
- Whether there is a simpler alternative.

Do not casually rename or remove persisted fields.

## Testing Expectations

Add tests for:

- Recipe model creation.
- Ingredient parsing.
- Recipe scaling.
- Search behavior.
- Import parsing.
- Shopping-list aggregation when implemented.

For import tests, use fixtures in a dedicated test fixture directory.

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

## First Implementation Target

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
   - Lightweight cooking memory: mark cooked, update `lastCookedAt`/`timesCooked`,
     and optionally create a retrospective note

Do not implement CloudKit sync, recipe transfer (send/Family Cookbook), production
import UI, grocery list, meal planning, pantry, or AI in the first coding pass unless
specifically requested. A Paprika fixture spike may happen early to validate the schema,
but it is not a shipped import flow.

There is no `Household`/`Cook`/sharing schema to build — the core is a single owner's
private library (ADR-0003).
