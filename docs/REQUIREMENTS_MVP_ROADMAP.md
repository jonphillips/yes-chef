# Requirements and MVP Roadmap

## 1. Overview

This document defines the initial functional requirements for a personal recipe management and cooking-planning app.

The app should begin as a reliable local-first recipe library with import, editing, search, and cooking-mode capabilities. It should later grow into a grocery, meal-planning, pantry, and event-cooking system.

## 2. Guiding Assumptions

- The initial user has an existing Paprika recipe library.
- Importing existing recipes is strategically important.
- The app should be Apple-first.
- Each person keeps their **own private library** (synced across their own devices via
  the CloudKit private database). Recipes move between family members by **transfer**
  (you send a recipe; the recipient gets an independent copy) — NOT co-editing. See
  ADR-0003.
- The app should not depend on a custom backend (CloudKit via SQLiteData is the only
  sync — ADR-0002).
- The data model should be designed for future sync and migration.
- AI features should be deferred until the core recipe model is reliable.
- Original imported data should always be preserved.

## 3. Core Entities

Yes Chef is a **single owner's private library** (ADR-0003) — there is no shared
household graph, no `Household`/`Cook` entities, no per-person opinion rows. `favorite`,
`rating`, tags, and notes are plain fields/tables on the owner's own recipes. Recipes
move between people by transfer (a copy), modeled as an import/export payload, not as
shared rows. The authoritative definitions are in DATA_MODEL.md §2.6 — read it before
building the schema.

### Recipe

Represents a cookable item.

Required fields:

- id
- title
- subtitle
- summary
- source (a RecipeSource — name/url/author/book/page live there, not flattened here)
- servings
- yieldText
- prepTimeMinutes
- cookTimeMinutes
- totalTimeMinutes
- activeTimeMinutes
- ingredientSections
- instructionSections
- notes
- categories
- tags
- cuisine
- course
- equipment
- difficulty
- rating
- favorite
- archived
- libraryPlacement (future; main vs reference/source material)
- dateCreated
- dateModified
- lastCookedAt
- timesCooked
- photoIDs
- originalImportText
- originalSnapshot (immutable, write-once copy of the recipe as first saved/imported — see DATA_MODEL.md §2.4)

Note: rating and favorite are plain columns — this is the owner's own private copy of
the recipe, so there is exactly one of each (theirs). See DATA_MODEL.md §2.6.
Source, author, cuisine, course, library placement, and future recipe-family role are
typed concepts, not category/tag conventions. See ADR-0006.

### IngredientSection

Represents a named group of ingredients.

Examples:

- Main
- Marinade
- Sauce
- Dressing
- Garnish
- For serving

Fields:

- id
- recipeID
- name
- sortOrder
- ingredientLines

### IngredientLine

Represents one ingredient line.

Fields:

- id
- recipeID
- sectionID
- originalText
- quantity
- unit
- item
- preparation
- isOptional
- shoppingCategory
- sortOrder

Important rule:

The app must preserve `originalText` even when parsed fields are present.

### InstructionSection

Represents a named group of instruction steps.

Examples:

- Main
- Sauce
- Chicken
- Assembly
- Make ahead

Fields:

- id
- recipeID
- name
- sortOrder
- steps

### InstructionStep

Represents one instruction step.

Fields:

- id
- recipeID
- sectionID
- text
- sortOrder
- isOptional

Deferred future fields, not persisted in MVP 1 until defined:

- timerHints
- temperatureHints
- equipmentHints
- ingredientReferences

### RecipeNote

Represents a user note about a recipe.

Fields:

- id
- recipeID
- text
- noteType
- dateCreated
- dateModified
- cookingSessionID
- pinned

Possible note types:

- general
- adaptation
- makeAhead
- freezing
- thawing
- shopping
- serving
- equipment
- scaling
- substitution
- wine
- retrospective
- warning

### Tag

Represents flexible metadata, owned by the library's single owner. When a recipe is
transferred, its tag names travel in the payload and the recipient reconciles them
against their own tags (see DATA_MODEL.md §2.6).

Examples:

- beach
- make-ahead
- grill
- sous-vide
- dinner-party
- chicken
- Korean
- weeknight
- freezer-friendly

Fields:

- id
- name
- color
- sortOrder

### Category

Represents higher-level organization.

Examples:

- Appetizers
- Chicken
- Beef
- Fish
- Pasta
- Salads
- Desserts
- Cocktails

Fields:

- id
- name
- parentID (future)
- sortOrder

### ShoppingList

Represents a grocery list.

Fields:

- id
- name
- dateCreated
- dateModified
- items

### ShoppingListItem

Represents a shopping item.

Fields:

- id
- shoppingListID
- originalText
- quantity
- unit
- item
- category
- sourceRecipeIDs
- checked
- manuallyAdded
- sortOrder

### MealPlanEntry

Represents a planned meal or dish.

Fields:

- id
- date
- mealType
- recipeID
- titleOverride
- notes
- servings
- sortOrder

Meal types:

- breakfast
- lunch
- dinner
- snack
- prep
- event

### CookingPlan

Represents a larger event or multi-day cooking plan.

Fields:

- id
- title
- startDate
- endDate
- guests
- recipes
- mealPlanEntries
- shoppingLists
- prepTasks
- thawingTasks
- makeAheadTasks
- equipmentSchedule
- servingTimeline
- notes

This is a future differentiating feature and not required in MVP 1.

## 4. MVP 1: Recipe Library

### Goal

Build a reliable, pleasant, Apple-native personal recipe library.

### Required Features

#### 4.1 Recipe List

The user can view all recipes in a list.

Requirements:

- Show recipe title.
- Show optional subtitle/source/category.
- Support search by title, ingredient text, instruction text, note text, source,
  author, category, and tag.
- Support filtering by source and author using `RecipeSource` fields, not category or
  tag strings.
- Default browsing should eventually show main-library recipes; reference/source
  material should be opt-in or reachable from related recipe/family surfaces.
- Support basic sorting:
  - title
  - date added
  - date modified
  - last cooked
  - favorite

#### 4.2 Recipe Detail

The user can view a recipe.

Requirements:

- Show title.
- Show source and URL if present.
- Show servings/yield.
- Show timing metadata.
- Show ingredient sections.
- Show instruction sections.
- Show notes.
- Show tags/categories.
- View the original version (read-only) when an originalSnapshot is present.
- Support readable kitchen typography.
- Keep screen awake during cooking mode.

#### 4.3 Recipe Editing

The user can create and edit a recipe.

Requirements:

- Edit title.
- Edit source.
- Edit URL.
- Edit servings/yield.
- Edit time fields.
- Edit ingredients as structured sections.
- Edit instructions as structured sections.
- Edit notes.
- Edit tags/categories.
- Delete/archive a recipe with confirmation; use `Recipe.archived` as a soft delete.
- Add/remove/reorder ingredient lines.
- Add/remove/reorder instruction steps.

#### 4.4 Recipe Scaling

The user can scale a recipe.

Requirements:

- Display original servings.
- Allow user to choose new serving count or scale factor.
- Scale parsed quantities when possible.
- Defer "change units" until unit normalization exists. When added, conversion must
  be dimension-safe (for example teaspoons/tablespoons/cups within volume, grams/
  ounces within weight) and must not imply volume-to-weight conversions without
  ingredient density data.
- Leave unparsed ingredient text unchanged or visibly marked.
- Do not overwrite the canonical recipe unless user explicitly saves the scaled version.

#### 4.5 Cooking Mode

The user can cook from a recipe comfortably.

Requirements:

- Large readable text.
- Ingredient checklist.
- Step focus mode.
- Optional checked-off instruction steps.
- Keep screen awake.
- Easy access to notes.
- Timer detection can be deferred.

#### 4.6 Tags and Categories

The user can organize recipes.

Requirements:

- Add/remove tags.
- Add/remove categories.
- Filter recipe list by tag/category.
- Allow recipes to have multiple tags and categories.

#### 4.7 Sample Data

The app should include sample recipes for development.

Requirements:

- At least 5 sample recipes.
- Include simple and complex recipes.
- Include multiple ingredient sections.
- Include multiple instruction sections.
- Include notes.
- Include tags.

## 5. MVP 1 Technical Requirements

### Persistence

Requirements:

- Use a local persistent store.
- Design models with migration in mind.
- Use stable IDs.
- Avoid data loss during model changes.

### Testing

Required tests:

- Recipe model creation.
- Ingredient line creation.
- Recipe search.
- Recipe scaling for simple quantities.
- Import fixture parsing once import begins.

### Architecture

Requirements:

- Keep model, persistence, and UI concerns reasonably separated.
- Avoid giant view files.
- Use preview/sample data.
- Avoid premature abstraction.
- Prefer clear, idiomatic Swift.

## 6. MVP 2: Import

### Goal

Import existing user-owned recipes from Paprika or other export formats.

### Requirements

- Import from sample file fixtures.
- Preserve original recipe text.
- Preserve source URL.
- Preserve title.
- Preserve ingredients.
- Preserve instructions.
- Preserve notes.
- Preserve categories/tags where possible.
- Preserve flat Paprika category names; do not assume Paprika parent/child category
  hierarchy survives export unless a future fixture proves it.
- Preserve or backfill original creation dates when the selected export format exposes
  them. The HTML export does not; observed `.paprikarecipes` backups do.
- Preserve photos if practical.
- Preserve the best available image quality from the source export, and record when
  the available image appears to be low-resolution.
- Provide import summary:
  - imported count
  - skipped count
  - warnings
  - errors
- Allow review of imported recipes.

### Technical Spike

Before implementing production import:

1. Obtain a small Paprika export sample.
2. Inspect file format.
3. Document format in `/docs/IMPORT_EXPORT.md`.
4. Write a parser for a small fixture.
5. Convert parsed data to internal recipe model.
6. Add tests.

## 7. MVP 3: Grocery List

### Goal

Generate a usable shopping list from recipes.

### Requirements

- Add all ingredients from a recipe to a shopping list.
- Add selected ingredients from a recipe.
- Manually add shopping items.
- Check off items.
- Group items by category.
- Preserve source recipe references.
- Combine obvious like items where possible.
- Allow user to edit combined items manually.
- Do not over-normalize if uncertain.

### Examples

If two recipes include:

- 1 onion
- 2 onions

The shopping list may combine into:

- 3 onions

If two recipes include:

- 1 bunch cilantro
- cilantro, for garnish

The app should preserve ambiguity or ask user rather than confidently combining.

## 8. MVP 4: Meal Planning

### Goal

Assign recipes to meals and generate shopping lists from a plan.

### Requirements

- Calendar view.
- Add recipe to date.
- Add recipe to meal type.
- Add non-recipe meal entry.
- Adjust servings for planned recipe.
- Add meal notes.
- Generate grocery list from date range.
- Support weekly planning.

## 9. Future Differentiators

### Family Cookbook (Phase 2 recipe transfer)

A browsable shared space where family members publish recipes for others to discover
and copy into their own library (copy-on-adopt: an independent copy, edits never
propagate). This is the "living cookbook the kids grow into" surface. It is the only
part of the app that uses CloudKit *sharing* (one shared zone the family joins once),
and because published recipes are read-then-copy, it avoids co-editing conflicts. Build
after the private library and Phase-1 "Send a Recipe" are solid. See ADR-0003 and
DATA_MODEL.md §2.6.

### Cooking Plans

A Cooking Plan is an event or multi-day plan with recipes, grocery lists, prep tasks, thawing tasks, equipment schedule, and serving timeline.

Examples:

- Dinner party
- Beach week
- Holiday meal
- Family weekend
- Multi-night travel cooking plan

### Make-Ahead Intelligence

The app should eventually identify and track:

- What can be chopped ahead.
- What can be frozen.
- What should not be frozen.
- What can be cooked and reheated.
- What must be done day-of.
- What should be packed separately.
- What needs cooler space.
- What needs to thaw 12/24/48 hours ahead.

Future LLM-assisted workflow: generate an on-demand make-ahead strategy for a saved
recipe, let the user review/edit it, and persist the accepted strategy with the
recipe, likely as a dedicated make-ahead section rather than a generic note. This
should remain user-approved recipe content, not an invisible model inference that
changes automatically.

### Source Refresh and Image Recovery

For recipes with source URLs, the app should eventually be able to revisit the source
page and attempt to recover fresher structured data or a higher-resolution image than
the original import provided. This depends on a source-page scraper/importer and must
preserve the user's current recipe as the canonical editable copy unless the user
explicitly accepts updates.

Initial goals:

- Detect recipes whose imported image is low-resolution or visibly inconsistent with
  the detail display target.
- Offer a "refresh from source" or "find better image" workflow when a source URL is
  available.
- Preserve provenance: source URL, fetched image URL, dimensions, checksum, date
  fetched, and any warnings.
- Never overwrite user edits silently; recovered data should be reviewable.
- Respect source site terms and only fetch content the user is allowed to access.
- At the end of the scraping milestone, evaluate whether the scraper can recover
  selected recipe comments, especially "most helpful" comments from NYTimes recipes.
  Possible workflows include live user review to mark a few keepers, or asking an
  LLM to integrate and synthesize useful comment-derived adjustments into a
  reviewable proposal. Treat this as a separate, site-specific research task because
  it may require DOM interaction, authentication, and stricter source-site terms
  review.

### Hierarchical Recipe Categories

Yes Chef should support a curated category tree for stable personal organization.
This should be modeled as categories with an optional parent category, not as
parent/child tags.

Initial goals:

- Keep tags flat for cross-cutting labels such as `make-ahead`, `grill`, and
  `dinner-party`.
- Let categories form a tree for stable user organization such as meal type, protein,
  occasion, or personal collection.
- Do not make source, author, cuisine, course, or library placement depend on category
  strings when the app has typed fields for those concepts.
- In list filtering, selecting a parent category should include recipes in descendant
  categories unless the user explicitly asks for exact matching.
- Current foundation: the editor accepts category paths such as
  `Meal Type > Dinner Party`; the repository creates parent/child category rows and
  list filters include parent paths for descendant recipes. The recipe filter sheet
  supports multi-select category filtering through a hierarchical picker rather than
  a flat path list.
- In the iPad layout, consider a category tree in the recipe navigation surface once
  the library grows beyond simple filters.
- Use recovered flat Paprika category names as raw material, but expect manual
  hierarchy reconstruction because the observed `.paprikarecipes` archive does not
  expose the old parent/child category tree.
- Do not require category descriptions in the first implementation. LLM workflows
  should usually infer category meaning from the title, children, and assigned
  recipes. Consider an optional description or LLM hint field later for ambiguous
  parent categories.
- Outstanding iOS 27 beta 1 issue: drag/drop category re-parenting is deferred. The
  SDK 27 drag/drop container APIs compile, but in current simulator testing category
  rows became draggable without reliable drop behavior and interfered with navigation
  activation. Revisit after later iOS 27 betas or after isolating a stable minimal
  reproduction.

### Source and Author Facets

Source and author should be first-class browse/filter facets.

Initial goals:

- Expose `RecipeSource.name`, `author`, `publicationName`, and `bookTitle` in the
  editor when the user wants detailed source metadata. Current foundation: the recipe
  editor shows a compact source summary row that drills into a dedicated source editor.
- Preserve source and author data during import where it is available.
- Filter recipe lists by source and author independently. Current foundation: source
  and author filters are searchable multi-select facets with the top ten most-used
  values grouped above the remaining alphabetical list.
- Treat cookbook names and publications as source metadata, not categories.
- Allow category/tag import evidence to help populate source fields, but keep uncertain
  labels as imported categories until the user or a parser can confidently clean them.

### Library Placement and Recipe Families

Yes Chef should support two browsing tiers:

- Main library: recipes the user normally wants to browse, cook, plan, or improve.
- Reference/source material: recipes kept for comparison, inspiration, or source
  evidence but hidden from default browsing.

Initial goals:

- Add a `libraryPlacement` concept with main as the default and reference/source
  material as an alternate placement. Implemented foundation: recipes persist this
  field, the editor can change it, and recipe browsing defaults to the main library
  with controls for Reference and All.
- Keep archived/deleted recipes separate from reference recipes. Reference means
  intentionally retained; archived means hidden because the user no longer wants it
  active.
- Add a future `RecipeFamily` concept for related recipes such as multiple chocolate
  chip cookie or Kung Pao chicken versions.
- Let a family identify one preferred/canonical recipe while keeping related versions
  available from the detail/family surface.
- Do not require a `canonical` tag or category filter to keep the normal recipe list
  useful.

### Authenticated Source Capture

Some high-value recipe sources require login, such as America's Test Kitchen and Milk
Street. The app should investigate a private, user-controlled authentication approach
before building site-specific importers.

Guardrails:

- Do not store raw passwords in source code, docs, fixtures, logs, commits, or agent
  prompts.
- Prefer interactive user login through an app-controlled browser/auth surface, with
  any reusable credentials or session material stored only in the user's Keychain.
- Treat private distribution as reducing product exposure, not as permission to embed
  credentials or bypass access controls.
- Design site connectors so authenticated fetch, parsing, and storage are separable and
  testable with sanitized HTML fixtures.
- Provide a manual fallback where the user can import saved HTML or copied recipe text
  from a logged-in browser session without sharing credentials with development tools.

### Equipment-Aware Planning

The app should eventually know whether a plan requires:

- Oven
- Grill
- Stovetop
- Wok burner
- Sous vide
- Blender
- Food processor
- Mixer
- Vacuum sealer
- Rice cooker

It should flag conflicts.

Example:

Three dishes all requiring the oven at different temperatures within the same 30-minute serving window.

### Personal Preference Memory

The app should support user-controlled preference notes.

Examples:

- Dislikes aggressive seafood.
- Avoids octopus/cuttlefish/anchovy-forward dishes for spouse.
- Likes make-ahead recipes that preserve 90%+ quality.
- Prefers high-quality food over convenience.
- Likes sous-vide and grill workflows.
- Wants serious hosting logistics.
- Avoids bland grocery-list meal planning.

### Recipe Versioning

The app should eventually distinguish:

- Original imported recipe.
- Cleaned version.
- User-adapted version.
- Event-specific version.
- Scaled version.
- Notes from each time cooked.

## 10. Out of Scope for Early Development

Do not implement early unless explicitly requested:

- User accounts
- Server backend
- Public sharing
- Social features
- Subscription payments
- Nutrition database
- Calorie tracking
- Restaurant inventory
- Voice assistant
- Complex OCR
- Android
- Web app
- AI-generated recipes as a primary feature

## 11. Development Milestones

### Milestone 0: Project Setup (house-stack bootstrap)

Goal: a buildable skeleton that already embodies the house stack, so every later
milestone pattern-matches a known-good seed instead of inventing structure. Read
`~/code/jon-platform/docs/ios/` (swift-style, persistence-and-sync, ui-and-platforms,
toolchain) and the ADRs in `docs/decisions/` before starting.

- Create the Xcode project, SwiftUI multiplatform (iPhone/iPad/Mac). Plain product
  name everywhere — **no version suffix** in project, targets, modules, bundle ID,
  app group, or CloudKit container (rewrites get a fresh bundle ID, not a suffix).
- Add a **local SPM package** for app-agnostic logic (parsing, scaling, list
  combining) with its own test target. Don't pre-split into many packages.
- Add **SQLiteData** as a dependency (verify the current API/version first — it moves
  fast). Stand up the local SQLite store in the app group container (a share
  extension is on the roadmap and must write to the same DB).
- Define the schema from §2.6 as plain value-type structs with UUID primary keys:
  `Recipe`, the ingredient/instruction entities, `RecipeNote`, `RecipePhoto`, `Tag`,
  `Category`, `Equipment`, and the `RecipeTag`/`RecipeCategory`/`RecipeEquipment`
  joins. Ordinary foreign keys — this is a single owner's private library, no shared
  graph, no `Household`/`Cook`. `favorite`/`rating` are plain columns on `Recipe`.
- Capture `Recipe.originalSnapshot` (a write-once frozen copy) on first save/import,
  reusing the recipe-bundle serializer (DATA_MODEL.md §2.4). The read-only viewer can
  follow in Milestone 1.
- Add `@Dependency` for clock/date/uuid/database — no singletons.
- Build one screen as the pattern seed: a recipe list screen backed by an
  `@Observable` feature model with a single `Destination` enum (no `isShowingX`
  booleans), reading via `@FetchAll`. Thin view; any save/load logic in the model.
- Add sample data for previews and a first `pfw-testing`-style test of a pure
  function (e.g. a trivial scaling helper) to prove the test setup.
- Add `AGENTS.md` and the `docs/` (decisions, this roadmap, product brief, data
  model).

Use the installed `pfw-*` skills (sqlite-data, dependencies, swift-navigation,
modern-swiftui, sharing, testing) for the mechanics of each step.

### Milestone 1: First Vertical Slice

Goal: prove the app's core shape end-to-end using the real local schema, without
pulling grocery, planning, transfer, production import, CloudKit sync, or AI into the
first build.

- Real local SQLite schema for the MVP 1 entities.
- Sample recipes stored through the same persistence path production data will use.
- Recipe list.
- Recipe detail.
- Recipe edit.
- Delete/archive recipe with confirmation, implemented as a soft delete.
- Search.
- Tags/categories.
- `Recipe.originalSnapshot` captured for manually-created and imported recipes on
  first save, plus a read-only "view original" surface.
- Basic scaling display that never overwrites the canonical recipe unless explicitly
  saved.
- Cooking mode shell: readable typography, ingredient checklist, step focus, keep
  screen awake.
- Meal-planner-ready cooking memory: keep `lastCookedAt`/`timesCooked` in the
  schema, but do not expose a manual "mark cooked" or retrospective-note flow in
  the first slice. The meal calendar will later update/derive last-cooked history
  from planned meals whose dates have passed.
- Explicitly excluded: CloudKit sync, grocery lists, meal planning, recipe transfer,
  family cookbook, pantry, and AI.

### Milestone 2: Paprika Import Spike (schema validation)

- Inspect sample Paprika export.
- Document format.
- Parse fixture.
- Import into model and persist through repository.
- Copy available photo bytes into app-owned recipe photo rows.
- Prefer the best available Paprika photo source, recognizing that `itemprop=image`
  may be only a small cover thumbnail while PhotoSwipe gallery sources may be higher
  resolution.
- Reconcile recipe detail image display so low-resolution and high-resolution imports
  feel intentionally handled rather than visually jumpy.
- Supplement existing HTML-imported recipes from a Paprika `.paprikarecipes` backup to
  recover `Recipe.dateCreated` when title/source matching is confident.
- Preserve unmapped/raw fields.
- Add tests.
- Full import review/rollback flow remains later.

### Milestone 3: Scaling and Cooking Mode Hardening

- Ingredient scaling edge cases.
- Unit normalization and a "change units" scaling control for compatible units only;
  canonical recipe text remains unchanged unless explicitly saved.
- Unparsed/uncertain quantity display.
- Cooking mode polish.
- Ingredient checklist persistence if useful.
- Step focus polish.
- Keep screen awake.
- Add tests.

### Milestone 4: Grocery List

- Add recipe ingredients to list.
- Check off items.
- Group items.
- Basic combining.

### Milestone 5: Meal Planning

- Calendar/date-based planning.
- Add recipe to meal.
- Past dated meal entries update/derive `Recipe.lastCookedAt` and related cooking
  memory, replacing any manual "mark cooked" workflow.
- Generate grocery list from plan.

### Milestone 6: Send a Recipe (Phase 1 transfer)

Builds on the import payload from Milestone 2 — transfer is just another import path
(ADR-0003, DATA_MODEL.md §2.6). No shared CloudKit infrastructure.

- Serialize a recipe + children + tag/category names into a self-contained bundle
  (a `.yeschef` file or universal link).
- "Send recipe" hands the bundle to the system share sheet (Messages, AirDrop, …).
- Receiving imports the bundle as a fresh copy (new UUIDs); reconcile tag/category
  names against the recipient's own (find-or-create).
- Carry sender name as a plain provenance string.
- Tests: round-trip a recipe (export → import) and assert an independent copy.

### Milestone 7: Family Cookbook (Phase 2 transfer — later)

The browsable shared surface. The only part of the app that uses CloudKit *sharing*
(a shared zone the family joins once). Build after the private library + send are
solid — see §9 Future Differentiators.

## 12. Quality Bar

The app should feel:

- Fast
- Calm
- Modern
- Trustworthy
- Personal
- Serious but not fussy
- Better suited to an experienced cook than generic consumer recipe apps

Data correctness matters more than visual flourish in the first version.
