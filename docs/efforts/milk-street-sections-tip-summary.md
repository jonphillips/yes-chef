# Effort: Milk Street capture — ingredient subsections, Tip callout, real summary

**Type:** Follow-on hardening (Milk Street DOM fallback, post-PR #50 dogfooding)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Drafting — two of three gaps root-caused with real markup; ingredient
subsection heading needs an authenticated fixture from Jon.

## Context

PR #50 (`docs/efforts/parser-hardening-truncated-structured-data.md`) shipped exactly
its scoped effort — meta-tag JSON-LD teaser detection, the `RecipePrintTemplate_*` /
`RecipeBodyContent_*` DOM fallback, `truncatedStructuredData` warning, fixtures — and
it's correct against the gochujang reference capture. Merged as-is.

Jon's next real capture (`chicken-peanut-red-chili-sauce-pollo-encacahuatado`) has shape
the gochujang fixture didn't exercise: ingredient subsections and a "Tip" callout, plus a
useless meta-description summary. All three are new findings, not regressions.

## 1. Ingredient subsections not captured

The chicken recipe's ingredient list has headings like `FOR THE CHICKEN AND BROTH:` and
`FOR THE SAUCE:` grouping the rows. `RecipeMilkStreetExtractor.extractIngredients`
(`RecipeMilkStreetExtractor.swift:49-66`) only walks amount/description element pairs —
it has no notion of a heading row between groups, so the heading text is dropped
entirely (it isn't an amount+description pair, so it's just skipped).

The good news: no new plumbing is needed downstream. `RecipeParseBuilder.addIngredient`
already funnels into `IngredientSectionHeading.sections(in:)`
(`RecipeParseBuilder.swift:163-166`, `IngredientSectionHeading.swift`), which promotes a
colon-terminated line to a section heading automatically. If the extractor emits the
heading text as its own `builder.addIngredient("FOR THE CHICKEN AND BROTH:")` line, in
document order relative to the rows it precedes, sectioning falls out for free — same
mechanism Paprika import already relies on.

**Blocked on a fixture.** I confirmed via an unauthenticated fetch of the live chicken
recipe that Milk Street server-gates the entire ingredients DOM (both
`RecipePrintTemplate_*` and `RecipeBodyContent_*` blocks render empty/absent without a
logged-in session — the print template shell was present but childless). I can't recover
the real heading element/class from outside Jon's session, so this needs the same
treatment as the original effort: **Jon supplies a sanitized authenticated capture** (View
Source or the existing "View Original" capture path) showing the heading markup, so the
selector can be pinned to a real class-prefix rather than guessed.

## 2. Tip callout not captured

Root-caused from a live unauthenticated fetch — this content is **not** gated (ships in
the base HTML even signed out), so the markup below is real, not a guess:

```html
<div class="Tip_Tip__fTDmm RecipeSummaryContent_tip__AwXvd" role="note" aria-label="Tip">
  <div class="Tip_headerRow__1uMwS">
    <span class="Tip_title__luihG">Tip</span>
  </div>
  <div class="Tip_description__PgD23">
    <p data-p="true">Don't worry about salted versus unsalted peanuts...</p>
  </div>
</div>
```

The hashed suffixes (`__fTDmm`, `__luihG`, `__PgD23`) will churn like the other
Milk Street selectors — match on `[class*=Tip_Tip__]` (or `[role=note][aria-label=Tip]`,
which is even more stable since it's an accessibility attribute, not a CSS module hash).

This is the same shape as `RecipeEditorialProseExtractor` (`addEditorialBlock(label:
text:)`), just keyed on class/role instead of heading text. Add a small pass — either a
new case inside `RecipeMilkStreetExtractor.extract` or a sibling extractor — that selects
`[class*=Tip_Tip__]`, reads `Tip_description__PgD23` (fall back to the container's own
text if the description class also churns), and calls
`builder.addEditorialBlock(label: "Tip", text: ...)`. A recipe can have more than one Tip
box (e.g., one per prep stage); `addEditorialBlock` already dedupes identical blocks and
the review UI already renders multiple editorial blocks, so no new UI is needed.

## 3. Summary is generic site boilerplate

Confirmed live: `<meta name="description">`, `og:description`, and
`twitter:description` all carry the exact same static sentence —
*"Christopher Kimball's Milk Street offers a TV show, podcast, cookbooks and school that
will change the way you cook with easy recipes from around the world."* — identical
across recipe pages (it's Milk Street's site-wide fallback description, not per-recipe
copy). `RecipeMetaExtractor` feeds all three into `.summary` at chrome priority
(`RecipeMetaExtractor.swift:8,18,21`), and since the JSON-LD node is truncated on this
page (`RecipeJSONLDExtractor.mineIfComplete` bails at `isTruncated`,
`RecipeJSONLDExtractor.swift:61-64`), nothing else votes for `.summary` — the boilerplate
wins by default.

The real per-recipe summary **is** in the unauthenticated DOM (not gated):

```html
<div class="RecipeSummaryContent_body__YJ8_l">
  <p data-p="true">According to Jorge Fritz and Beto Estúa of Casa Jacaranda cooking
  school in Mexico City, there is disagreement about whether encacahuatado is a true
  mole...</p>
</div>
```

Fix: have the Milk Street extractor read `[class*=RecipeSummaryContent_body__]`
paragraph text and vote it into `.summary` at a priority above chrome/meta (e.g.
`RecipeAttributeVotes.jsonLDPriority`, or a new tier if conflating with real JSON-LD feels
wrong) so it outranks the generic meta description. Do **not** special-case-string-match
the boilerplate sentence to suppress it — voting in real content at higher priority is
the general fix and doesn't rot if Milk Street tweaks the boilerplate wording.

## Scope decisions

- **In scope:** Tip callout → editorial block (root-caused, ready to implement); real
  `RecipeSummaryContent_body` summary vote (root-caused, ready to implement); ingredient
  subsection heading passthrough via `addIngredient` (mechanism ready, selector blocked on
  a Jon-supplied authenticated fixture).
- **Out of scope:** a general subsection/aside DOM engine for other sites — same
  per-site-playbook posture as the parent effort.
- **Verification:** extend the existing gochujang/chicken-style fixtures (or add a new
  sanitized `milk-street-chicken-peanut.html` once Jon supplies the authenticated
  ingredients markup) covering all three: sectioned ingredients with a named heading, a
  captured Tip editorial block, and `summary` resolving to the real intro paragraph
  instead of the site tagline.

## Next step

Ask Jon for a sanitized authenticated capture of the chicken-peanut recipe (same
"View Original" / view-source path used for the gochujang fixture) so the ingredient
subsection heading selector can be pinned to real markup before dispatch.

---
*Follow-on to `docs/efforts/parser-hardening-truncated-structured-data.md` (PR #50,
merged). Tip and summary markup verified via a live unauthenticated fetch of
`177milkstreet.com/recipes/chicken-peanut-red-chili-sauce-pollo-encacahuatado`; the
ingredients DOM is confirmed server-gated and unavailable from that same fetch.*
