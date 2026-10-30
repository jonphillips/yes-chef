# Effort — NYT capture fidelity: ingredient sections, author name, opt-in publisher tags

Status: Dispatched 2026-10-04. Schema-free (no table or column changes; the snapshot blob keeps its shape).
Summary: Importing an NYT Cooking recipe in the in-app browser loses its ingredient groups ("For the cake" /
"For the frosting") and stores the author as a URL. Recover the groups from the rendered DOM (a per-site
extractor, the Milk Street precedent) and resolve a schema.org `Person` to its name. Separately, publisher
tags (`keywords`, which on NYT is roughly one tag per ingredient) become opt-in at capture review for every
site, while the snapshot keeps the full harvested list.
Related: [`parser-hardening-truncated-structured-data.md`](parser-hardening-truncated-structured-data.md) (the
Milk Street DOM fallback this copies) · [`unified-categories.md`](unified-categories.md) (tags commit as loose
categories) · ADR-0051 (see "Not a new parser" below)

## Evidence (live page, 2026-10-04)

`cooking.nytimes.com/recipes/1026813-easy-carrot-cake-with-cream-cheese-frosting`:

- **Sections.** JSON-LD `recipeIngredient` is a flat list of 19 lines with no group markers. The groups exist
  only in the rendered DOM, inside `ingredients_ingredients__…`: `<h3 class="pantry--label
  ingredientgroup_name__xNtpC">FOR THE CAKE</h3><ul><li><p class="pantry--ui
  ingredient_ingredient__rfjvs">…</p></li>…</ul>`, then `FOR THE FROSTING` + its own `<ul>`. A recipe with no
  groups (the white bean soup in `nyt-comments.html`) has no `h3`. The class suffixes are CSS-module hashes,
  so match on prefixes (`[class*=ingredientgroup_name__]`, `[class*=ingredient_ingredient__]`), as
  `RecipeMilkStreetExtractor` does.
- **Author.** `"author": {"@type":"Person","name":"Genevieve Ko","url":"https://cooking.nytimes.com/author/genevieve-ko", …}`.
  `RecipeJSONLDExtractor.flatStrings` resolves any dict as `url ?? @id ?? name`, which is right for images and
  `mainEntityOfPage` but wrong for a person, so `author` (and `publisher`) vote the URL.
- **Tags.** `"keywords": "Carrot, Cream Cheese, Easter, Easy, Make-Ahead, Mother’s Day, Party, Sheet-Pan,
  Sour Cream, Spring, Walnut"` → `RecipeParseBuilder.addTag` → `page.tagNames`, which commits unless Jon
  swipes each one away in the review sheet. The share extension commits them with no review at all.
  `recipeCategory` ("Carrot Cake, Dessert") is useful and **stays as it is** (pre-included, editable).

## Fix 1 — NYT ingredient groups from the DOM

Add `RecipeNYTCookingExtractor`, called from `RecipePageParser` next to `RecipeMilkStreetExtractor` (after
`RecipeJSONLDExtractor`). Gate it on host `cooking.nytimes.com`, or on the template being present
(`[class*=ingredientgroup_name__]`), the same way Milk Street gates.

- Walk the ingredients block in document order. Each group heading starts a named section; the
  `ingredient_ingredient` lines that follow belong to it. Lines before the first heading form an unnamed
  section.
- **Only emit sections when at least one group heading exists.** No headings → emit nothing, and the flat
  JSON-LD list stands as today.
- **Lossless guard.** Adopt the DOM grouping only when its lines, whitespace-normalized, are the same
  sequence as the JSON-LD `recipeIngredient` lines the builder already holds. If they differ (a paywall
  teaser, a page redesign, a partial render), emit nothing and keep the flat list. Losing the grouping is
  acceptable. Gaining, dropping or reordering a line is not. (The builder already prefers
  `explicitIngredientSections` over flat `ingredients`, so emitting sections is all it takes.)
- **Heading text.** NYT ships the heading as literal capitals ("FOR THE CAKE"). When a heading has no
  lowercase letters, sentence-case it ("For the cake"). Otherwise keep it verbatim. Drop a trailing colon to
  match how other sections display.

**Not a new parser.** This is per-site hardening inside the existing web/schema.org front-end, the same kind
of thing as the Milk Street DOM fallback. It adds no front-end, model call, draft type or save path, so the
ADR-0051 guard in `standing-guards.md` doesn't apply.

## Fix 2 — author is a name, never a URL

- In `RecipeJSONLDExtractor`, resolve `author` and `publisher` through a person/organization reader. A dict
  yields its `name`, and nothing if it has none: no `url` or `@id` fallback for these two. A string is used
  as-is. An array yields its distinct names joined as a list ("A and B", "A, B, and C").
- Wherever an `.author` vote is cast (JSON-LD, microdata, meta `author`/`article:author`), drop a value that
  is an http(s) URL. Plenty of sites put a profile URL in `article:author`. Today JSON-LD outranks it on NYT,
  but a page without JSON-LD would surface it.
- Don't change `flatStrings` itself. Images and other properties rely on its URL-first order.

## Fix 3 — publisher tags are opt-in

For **every** site, not just NYT:

- **Capture review (`RecipeCaptureView`, the "Categories & Tags" section).** Harvested tags show as
  **unselected** toggle chips (the `SuggestedCategoryChip` look). Tap one to include it. Categories keep their
  current editable, pre-included rows. Remove the tag `TextField` rows and the "Remove All Tags" button; rename
  happens in the editor after save. Change the footer copy to match ("Tap a tag to add it").
- **Commit.** Only the selected tags reach `reconcileCategories(looseNames:)`. The **original snapshot keeps
  the full harvested `tagNames`** (data-preservation rule 1). The page→bundle path splits "harvested"
  (snapshot) from "adopted" (library joins). Today they're the same array. Model it as an explicit adopted
  set on the draft or the import call, defaulting to **empty**. Don't mutate `page.tagNames`. Selection is
  pure state until commit, like `acceptedSuggestedLabelIDs`.
- **Share extension.** With no tag review there, it adopts **no** tags. The snapshot still holds them.
- `filteringHarvestedLabels` keeps excluding model suggestions that match a harvested tag. The harvested chip
  is right there to tap, so one name never shows twice.

## Tests

- **Fixture.** Add a sanitized `nyt-cooking-ingredient-groups.html`: the Recipe JSON-LD (flat
  `recipeIngredient`, `Person` author with `url`, `keywords`, `recipeCategory`) plus the ingredients DOM block
  with two `ingredientgroup_name` headings. Trim it to those parts. The live page is 670 KB.
- Groups → two sections, "For the cake" (15 lines) and "For the frosting" (4 lines), in order.
- No-heading NYT page → one unnamed section, unchanged from today.
- DOM lines that don't match the JSON-LD (drop one `<li>`) → flat list, no sections.
- Author: a `Person` with `name` + `url` → the name. Two persons → "A and B". A `Person` without `name` → no
  author from JSON-LD. Meta `article:author` = URL → ignored.
- Tags: the parsed page still carries every keyword. Committing with no selection writes no tag categories
  and the snapshot's `tagNames` holds them all. Selecting two writes exactly those two. The share-extension
  import path adopts none.
- The `RecipeCaptureModel` selection logic is App-layer model code, so `YesChefTests` runs
  (`docs/verification.md`).

## Out of scope

- Repairing recipes already imported with a URL author. Release builds don't keep the raw HTML, so there is
  nothing to re-parse, and making a name up from the slug would invent data. Jon fixes those by hand or
  re-imports.
- NYT instruction groups (the steps are a flat JSON-LD list, and grouped steps are rare on NYT).
- Making `recipeCategory` opt-in.
- Any change to the model label-suggestion flow.

## Done when

All three fixes land with the tests above, `check-drift.sh` is green, the generic device build compiles, and
`YesChefTests` passes. Owed device pass: capture the carrot cake in the in-app browser. It should show two
ingredient sections and author "Genevieve Ko", and save with no tags unless one was tapped. Then capture a
second NYT recipe through the share sheet: it should save with no tags.
