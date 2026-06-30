# ADR-0008 — Curated collections (editorial recipe indexes)

Status: Proposed - 2026-06-30

## Context

Users want a hand-authored, birds-eye view of part of their library: e.g. a
"Mexican" index with an ordered list of taco recipes, then an ordered list of salsa
recipes, with the cook's own grouping and ordering. The motivating artifact is a
Paprika hack — a single recipe whose **description field** was filled with grouped,
ordered links to other recipes. It is brittle for two reasons: Paprika links recipes
by **title match**, and the structure is just prose in a freeform field, so grouping
and ordering cannot be edited as data.

Yes Chef already has most of the primitives this needs, which is why this ADR exists —
to decide *which* primitive owns the concept rather than re-deriving it later:

- **Stable identity is already solved.** `recipes.id` is a UUID primary key and several
  tables already reference it as a real foreign key with `ON DELETE SET NULL`
  (`menuItems.recipeID`, `mealPlanItems.recipeID`, `groceryItemSources.recipeID`). The
  title-matching fragility that exists in this codebase is fenced off in
  `recipeImportRef` and used **only** for import dedupe, never for linking.

- **Categories are the designated org tree (ADR-0006).** `categories` is hierarchical
  (`parentCategoryID`), and parent selection includes descendant recipes in list
  filters. "Mexican → Tacos / Salsas" as a *browsable taxonomy* is already the intended
  path. But the `recipeCategories` join has **no `sortOrder`**, membership is **global**
  (a recipe is "a Taco" everywhere — you cannot curate a hand-picked, hand-ordered
  subset for one view), and a category cannot carry editorial prose between groups.
  Categories give the **birds-eye browse**, not the **curated index**.

- **Menus are the structural twin.** A `Menu` is title + notes + ordered `menuItems`,
  where each item either references a recipe by stable ID (`kind = recipe`) or is a
  freeform note (`kind = note`), all with `sortOrder`. That is almost exactly the
  target shape. The only mismatch is the **grouping axis**: `menuItems` carry
  `dayOffset` + `mealSlot` and menus get placed on a calendar. The curated index is a
  Menu whose axis is **editorial sections** (Tacos, Salsas) instead of days and meals.

- **Tags stay flat (ADR-0006).** Useful as a membership *seed*, not as the hierarchy.

## Decision

Model the curated index as a **new first-class entity, `Collection`**, a sibling of
`Menu` — not an overload of `Menu` and not a reinterpretation of `Category`.

1. **New entity, three levels.** `Collection` → `CollectionSection` → `CollectionItem`,
   mirroring the proven `menus` / `menuItems` shape with an added section layer:

   - `Collection` — `id`, `title`, optional `subtitle`/`notes`, `sortOrder`,
     `dateCreated`, `dateModified`. (User-facing name for this surface — "Index",
     "Guide", "Collection" — is a UI-copy call, not a schema call.)
   - `CollectionSection` — `id`, `collectionID` (FK `ON DELETE CASCADE`), optional
     `name` (the "Tacos" / "Salsas" heading), `sortOrder`. Optionally a **membership
     rule** (see point 4).
   - `CollectionItem` — `id`, `collectionID` and `sectionID` (FK `ON DELETE CASCADE`),
     `kind` (`recipe | note`), `recipeID` (FK `ON DELETE SET NULL`),
     `recipeTitleSnapshot`, `text` (for `note` items), `sortOrder`, `dateCreated`.

2. **Do not overload `Menu`.** A menu is a meal-planning object with a temporal axis
   (`dayOffset`, `mealSlot`) and calendar placement (`menuPlacements`). Reusing it for
   editorial indexes would leave those fields dead and force every planning code path
   to special-case "editorial menus." The shapes are twins; the domains are not.

3. **Compose with categories; do not duplicate the hierarchy.** Collections are an
   *editorial presentation* layer; categories remain the *organizational taxonomy* of
   ADR-0006. A collection may draw its recipes from any categories, tags, cuisines, or
   none — it does not define or replace category membership.

4. **Membership is curated, with an optional smart seed.** v1 membership is **manual**:
   the user adds recipes to a section and orders them. A `CollectionSection` may
   optionally carry a **rule** (`ruleKind`: `category | tag`, plus the referenced id)
   that auto-seeds matching recipes, with manual pins / ordering / supplements layered
   on top. The rule fields are reserved in the schema from the first migration so the
   hybrid does not require a later table change; the seeding *behavior* can ship after
   the manual core.

5. **References are sync-safe by construction.** Per ADR-0002:
   - UUID primary keys on every table; **no unique indexes** beyond the primary key.
   - `CollectionItem.recipeID` is a **soft** FK (`ON DELETE SET NULL`), exactly like
     `menuItems.recipeID` — which the main-conformance audit already flagged as a
     CloudKit "second hard FK / dedup-on-read" concern. A collection entry must
     tolerate a **dangling or not-yet-synced** recipe.
   - `CollectionItem.recipeTitleSnapshot` is **denormalized** (like `menuItems.title`)
     so an entry still renders when its recipe is missing, unsynced, or deduped away.
     This is also precisely what makes the index more robust than the Paprika
     description hack it replaces.
   - Resolve duplicate-recipe references (two offline devices inserting the same
     logical recipe) at **read time**, not via a DB constraint.

6. **This is a post-sync milestone.** Because every guarantee in point 5 is about
   tolerating dangling/duplicate cross-record references under CloudKit, the schema
   shape is **reserved now** but the feature is sequenced **after** private-DB sync, for
   the same reason the audit parks `menuItems.recipeID`: retrofitting reference
   tolerance after sync is live is the expensive path.

## Consequences

- Adds three tables (`collections`, `collectionSections`, `collectionItems`) plus their
  `@Table` models, mirroring the existing menu stack.
- The Paprika description-hack pattern is replaced by structured, reorderable data with
  stable recipe references; no title-match linking is introduced anywhere new.
- A `recipeCategories.sortOrder` gap is documented but **not** required by this ADR —
  ordered *browse within a category* is a separate concern from curated collections. If
  that becomes desired, it is its own small migration.
- Importers do **not** synthesize collections from Paprika data in v1; the hacked
  "index" recipes import as ordinary recipes and the user re-creates the index natively.
- The smart-seed rule deliberately leans on categories/tags as the source of truth for
  membership, keeping ADR-0006 the single home for taxonomy.

## Relationship To Current Implementation

Nothing is built yet. The reference shape this ADR reserves already has a working
precedent in the codebase: `Menu` / `MenuItem` (`Models.swift`, `Schema.swift` "Create
menu schema" migration) demonstrate the title + ordered-items + `recipe | note` item
kind + soft `recipeID` FK + denormalized item `title` pattern that `Collection` will
follow, with a `CollectionSection` layer added between the parent and its items.

Future work, when the milestone opens (post-sync):

- Add the `collections` / `collectionSections` / `collectionItems` migration and models.
- Build the curated editor (add/reorder sections and items, freeform `note` items).
- Render the read view (the "Mexican Index" surface).
- Implement optional section membership rules (the category/tag smart seed) on top of
  the manual core.
