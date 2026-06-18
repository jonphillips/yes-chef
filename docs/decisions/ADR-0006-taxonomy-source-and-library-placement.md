# ADR-0006 - Taxonomy, source metadata, and library placement

Status: Accepted - 2026-06-17

## Context

Yes Chef needs flexible personal organization, but it also needs to understand recipe
metadata well enough to support filtering, planning, import cleanup, and future
LLM-assisted workflows.

Several concepts look superficially similar:

- User-created categories such as Desserts, Chicken, Cocktails, or Dinner Party.
- Source identity such as America's Test Kitchen, Milk Street, or The French Laundry
  Cookbook.
- Author identity such as Steve Dunn, Christopher Kimball, or Thomas Keller.
- Known facets such as cuisine and course.
- Library placement, where some recipes belong in the main browsing list and others
  are retained as source/reference material.
- Recipe families, where several recipes are variants of the same dish and one may be
  the preferred or canonical version.

Paprika exports can flatten many of these into category names. That is useful import
evidence, but it should not force Yes Chef to flatten its own model.

## Decision

Yes Chef will use both flexible user taxonomy and typed semantic facets.

1. **Categories are user/library organization, not the universal metadata bucket.**
   Categories remain user-editable and may become hierarchical, but they should not be
   the primary storage for source, author, cuisine, course, or library placement when
   the app understands those concepts.

2. **Tags remain flat and cross-cutting.** Tags are for flexible labels such as
   `make-ahead`, `freezer`, `beach`, `grill`, or `dinner-party`. Do not recreate
   source/author/category hierarchy in tags.

3. **Source and author are first-class metadata.** `RecipeSource` owns source identity:
   source name, URL, author, publication, book title, page number, import provenance,
   and notes. Filtering by source or author should read these fields, not category
   strings.

4. **Known facets should be typed when useful.** Cuisine and course are already recipe
   fields. If another domain becomes important and stable enough, model it explicitly
   rather than hiding it in categories.

5. **Library placement is separate from category/tag.** Recipes can belong to the main
   browseable library or to a reference/source-material area. Reference recipes remain
   searchable and linkable, but do not clutter the default recipe list.

6. **Archived is still deletion/retirement, not source material.** A reference recipe
   is kept intentionally. An archived recipe is hidden because the user no longer
   wants it in normal workflows.

7. **Recipe families are separate from placement.** A chocolate chip cookie family or
   Kung Pao chicken family may have one preferred/canonical recipe and several related
   source/reference versions. The preferred recipe can appear in the main library
   while related versions remain discoverable from the family or recipe detail view.

8. **LLM features should prefer typed fields.** Future LLM cleanup, planning, and
   recommendation tools can infer from text, but typed fields such as source, author,
   cuisine, course, placement, and family role give them a cleaner and more reliable
   semantic map.

9. **Metadata inference is staged by confidence and source.** Exposing source/author
   fields is separate from inferring them. Explicit Paprika source fields are the first
   source of truth for source identity. Paprika categories/tags such as
   `[Cookbook Name] by [Author]` or old chef categories are evidence for later cleanup,
   not an excuse to silently rewrite ambiguous taxonomy. Future web scraping can use
   schema.org/page metadata to recover author/publisher data, and a later enrichment
   pass can revisit existing source URLs once that scraper exists.

10. **Known source domains may be normalized deterministically.** When an imported
    source label is only a URL/domain, it is acceptable to map known domains to
    publication names, such as `cooksillustrated.com` to `Cook's Illustrated`. Unknown
    domains should not be aggressively guessed; they can wait for scraping, manual
    cleanup, or LLM-assisted suggestions.

11. **Category descriptions are optional future metadata.** Category names, child
    categories, and assigned recipes should be sufficient context for most LLM-assisted
    workflows. Do not require descriptions in the initial category editor; consider an
    optional description or LLM hint field later for ambiguous parent categories.

## Consequences

- Do not solve "filter by author" by creating author categories.
- Do not solve "show only my normal recipes" by requiring a `canonical` tag filter.
- Importers may use Paprika category strings as evidence, but should map known concepts
  into typed fields when confidence is high and preserve uncertain labels as categories
  or tags.
- Paprika's HTML source label should not automatically become a human author. Treat it
  as source/publication identity unless a parser or cleanup workflow has stronger
  evidence.
- The recipe list should eventually default to main-library recipes, with controls for
  showing reference/source-material recipes.
- Category management can still become powerful, including hierarchy, but it is a user
  organization tool rather than the only knowledge model in the app.

## Relationship To Current Implementation

The current model has `RecipeSource.author`, `publicationName`, `bookTitle`, and
related fields; the editor and filters expose source and author facets. Categories
and tags are app data rather than built-in constants. `Category.parentCategoryID`
supports hierarchy, and the editor accepts path-style category input such as
`Meal Type > Dinner Party`. `Recipe.libraryPlacement` is persisted with `main` as
the default and `reference` as an alternate browsing tier. `Recipe.archived` exists
for soft deletion.

Future work should add:

- Conservative Paprika metadata cleanup for clear cookbook/author patterns.
- Web source scraping for structured author/publisher metadata.
- Source metadata enrichment for existing recipes with source URLs, after scraping
  exists.
- Full category management UI for renaming, merging, deleting, and re-parenting
  categories.
- Optional category descriptions or LLM hints if user-created category names prove
  ambiguous.
- A recipe-family model for related versions and preferred/canonical recipe selection.
