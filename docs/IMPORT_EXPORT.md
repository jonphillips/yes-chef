Import and Export Notes

1. Purpose

This document records observed external import/export formats and the rules Yes Chef
uses when converting them into the internal recipe model.

2. Paprika HTML Export

2.1 Source

Paprika's macOS help describes HTML export as a folder containing `index.html`, one
HTML file per recipe, and hrecipe/schema metadata in each recipe page. The observed
fixture matches that broad shape.

Reference:

https://www.paprikaapp.com/help/mac/

2.2 Observed Folder Structure

The current private fixture is a ZIP with this shape after expansion:

```text
PaprikaExport/
  index.html
  Recipes/
    <Recipe Title>.html
    Images/
      <image-folder-id>/
        <image-file-id>.jpg
```

macOS ZIP sidecar entries such as `__MACOSX/` and `.DS_Store` may be present and must
be ignored.

2.3 Index Behavior

`index.html` contains an HTML list of links to recipe pages:

```html
<a href="Recipes/Recipe Title.html">Recipe Title</a>
```

Do not treat the index count as authoritative for import success. A user may provide a
partial fixture where the index references many recipes but only some recipe pages are
present. The importer should parse the recipe pages that exist and report a summary
warning for missing index links.

2.4 Recipe Page Metadata

Observed recipe pages use schema.org-style item properties:

* `itemprop="name"` for title.
* `itemprop="recipeCategory"` for a comma-separated category string.
* `itemprop="prepTime"`, `cookTime`, `totalTime`, and `recipeYield` for timing and
  servings metadata when present.
* `itemprop="url"` around a source link.
* `itemprop="author"` inside the source link.
* `itemprop="description"` for recipe summary/description when present.
* `itemprop="recipeIngredient"` on ingredient line paragraphs.
* `itemprop="recipeInstructions"` around instruction paragraphs.
* `itemprop="comment"` around notes.
* `itemprop="image"` on the primary recipe image.

Not every recipe has every field. Import must preserve raw HTML in
`Recipe.originalImportText` so later parser improvements can recover fields we miss in
the first pass.

2.5 Ingredients and Instructions

Paprika exports each ingredient as a paragraph, often with quantity wrapped in
`<strong>`.

Section headings are not consistently structured. They may be plain ingredient lines,
bold text, uppercase words, or phrases such as `For the sauce:`. The first importer
should preserve these lines as ingredient text rather than over-interpreting them.
Later cleanup can promote headings into `IngredientSection` names.

Instructions are exported as line paragraphs inside a `recipeInstructions` container.
The importer maps each paragraph to an `InstructionStep` while preserving the original
HTML in the recipe.

2.6 Categories, Tags, and Favorite

Paprika category data is currently observed as one comma-separated string. The first
import spike maps those names to Yes Chef category names.

Do not infer `Recipe.favorite` from a category named `Favorite` yet. It may be a real
Paprika category rather than the app's favorite flag, and preserving the source
category is safer.

2.7 Photos

Paprika can export more than one image per recipe.

Observed image behavior:

* The primary image is an `<img itemprop="image">` reference.
* Additional exported images can appear in a PhotoSwipe JavaScript `items` gallery.
* In observed exports, the `itemprop="image"` file may be only a small square cover
  thumbnail (for example 280x280), while PhotoSwipe `src` files may be the
  higher-resolution originals.
* Images are stored under `Recipes/Images/<folder-id>/<file-id>.jpg`.
* Recipe pages may reference image files that are not present in a partial fixture.

Yes Chef should model imported photos as separate `RecipePhoto` rows. The import spike
keeps available photo references and reports warnings for missing files. Missing photos
must not fail the whole recipe import. Production image import must follow
ADR-0005: copy available source bytes into app-owned display/thumbnail storage and
preserve provenance rather than depending on private Paprika export paths.

2.8 Current Import Spike Scope

Implemented now:

* Parse a Paprika HTML export folder.
* Import present recipe pages, independent of `index.html` completeness.
* Parse common metadata into `PaprikaHTMLRecipe`.
* Convert parsed recipes into `RecipeBundleCoding.RecipeBundle`.
* Write a bundle into the library through `RecipeRepository.importBundle`.
* Preserve raw HTML as `Recipe.originalImportText`.
* Preserve Paprika HTML source labels as source/publication identity, not as a
  confidently inferred human author.
* Normalize known source domains into publication names when the imported source label
  is only a URL/domain, for example `www.cooksillustrated.com` to `Cook's Illustrated`.
* Prefer the first PhotoSwipe gallery image as the imported hero when a gallery is
  present, rather than promoting Paprika's small cover thumbnail.
* Copy available photo bytes into app-owned `RecipePhoto` display/thumbnail payloads.
* Preserve Paprika image paths as provenance in `RecipePhoto.originalSourcePath`.
* Report missing recipe-page and missing-photo warnings.
* Read Paprika `.paprikarecipes` backups as a supplement source for original
  `Recipe.dateCreated` values.
* Test against a synthetic, committed Paprika-shaped fixture.

Not implemented yet:

* Full replacement import from Paprika `.paprikarecipes` backups.
* Full-resolution/original image asset storage.
* Quality tuning for text-heavy reference photos.
* Consistent recipe-detail image presentation across low-resolution and
  high-resolution imports.
* Source refresh/image recovery from recipe source pages.
* Conservative source/author/book cleanup from Paprika categories/tags.
* Authenticated source capture for login-only recipe sites. This must use
  user-controlled authentication and sanitized fixtures; raw credentials must not be
  stored in source, docs, logs, commits, or prompts.
* Promoting ingredient headings into real sections.
* Full import review/rollback flow.
* Importing all private fixture data into committed tests.

2.9 Paprika `.paprikarecipes` Backup

The observed `.paprikarecipes` file is a ZIP archive containing one
`.paprikarecipe` entry per recipe. Each entry is gzip-compressed JSON. It is not
currently treated as the primary import format, because the HTML importer already
preserves raw recipe pages, imported images, and enough structured recipe data for the
current app.

The backup format is valuable as a metadata supplement. Observed records include a
`created` timestamp in `yyyy-MM-dd HH:mm:ss` format, and this data is not present in
the HTML export. Yes Chef can read a selected `.paprikarecipes` file and backfill
`Recipe.dateCreated` for existing recipes when matching is confident.

Current supplement rules:

* Match by normalized recipe title.
* If multiple existing recipes have the same normalized title, require a matching
  source URL to disambiguate.
* Skip unmatched, ambiguous, duplicate, or unreadable records and report counts in the
  completion summary.
* Update only `Recipe.dateCreated`; do not touch `Recipe.dateModified` or recipe
  content.
* Preserve the HTML importer as the primary import path until a full backup importer
  provides clear additional value beyond created dates.

2.10 Source and Author Inference

Source and author enrichment has multiple inputs with different confidence levels:

* Explicit Paprika source fields are source identity evidence.
* If an explicit Paprika source field is just a URL/domain, Yes Chef may apply a small
  deterministic publication map for known domains.
* Paprika category/tag labels may contain cookbook or author clues, including patterns
  such as `[Cookbook Name] by [Author]`, but these should be treated as cleanup
  candidates unless the pattern is clear.
* Future web scraping can recover structured author/publisher metadata from source
  pages.
* Once web scraping exists, Yes Chef can revisit recipes with source URLs to enrich
  missing source metadata.

Do not silently convert ambiguous imported categories/tags into author/source fields.
Preserve ambiguous labels and let later cleanup workflows make reviewable suggestions.
