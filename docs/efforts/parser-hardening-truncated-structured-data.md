# Effort: Parser hardening — mis-tagged & truncated structured data (Milk Street, NYT)

**Type:** Robustness gap (M2/M3 web capture — follow-on hardening)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Drafting — Milk Street root cause verified; NYT section pending Jon's pass

## Symptom

A captured **Milk Street** recipe (`https://www.177milkstreet.com/recipes/gochujang-stir-fried-pork-celery`)
"comes up pretty empty." The page is a full, legible recipe in the browser — 12 ingredients,
3 steps — but the parser produces nothing usable.

Milk Street is the reason for this note; NYT Cooking is the sibling case (already partly
handled — see below). Jon ranks these two as the #2/#3 capture sources after ATK, so they
justify named, per-site hardening.

## Root cause (verified against the captured HTML)

Two independent publisher tricks stack here. Neither is a hard paywall — **the full recipe is
in the delivered HTML**, we just aren't reading it.

### 1. JSON-LD is in a `<meta>` tag, not a `<script>` — so we never see it

`RecipeJSONLDExtractor` selects only `script[type=application/ld+json]`
(`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeJSONLDExtractor.swift:6`).
Milk Street ships its JSON-LD entity-encoded inside a **meta attribute**:

```html
<meta name="application/ld+json" content="{ &quot;@type&quot;:&quot;Recipe&quot;, ... }">
```

We find zero JSON-LD blocks. There is no microdata either (Milk Street uses CSS-module
`<div>`s, no `itemprop`), so `RecipeMicrodataExtractor` also finds nothing. Net result today:
empty parse → all four warnings fire → `isUsable == false`. Honest, but useless.

### 2. Even that JSON-LD is a deliberately truncated teaser — this is the trap

The meta-tag JSON-LD is **not** the full recipe. It carries the first 3 ingredients, then a
sentinel string, and only Step 1:

```json
"recipeIngredient": [
  "1 pound boneless country-style pork spareribs, sliced crosswise ¼ inch thick",
  "3 tablespoons soy sauce, divided",
  "2 tablespoons neutral oil, divided",
  "... and more. Sign up for full access to all ingredients and instructions."
],
"recipeInstructions": [ { "@type": "HowToStep", "name": "Step 1", "text": "..." } ]
```

**Why this matters — do not "just also read the meta tag."** The current usability net
(`browserCaptureTeaserPageIsNotUsable`, `WebRecipeBrowserCaptureTests.swift:53`) relies on an
empty parse producing `.noStructuredRecipeData / .noIngredients / .noInstructions`
(`RecipeParseBuilder.swift:66-76`). Milk Street's node defeats that net: it **is** a
`schema.org/Recipe`, it **has** ingredients, it **has** an instruction — so if we start reading
the meta tag naively, `hasStructuredRecipe` becomes true, no warning fires, and the user gets a
confidently-wrong 4-line recipe (one "ingredient" being the *"… Sign up for full access"*
sentinel). That is strictly worse than today's honest-empty. Meta-tag reading and teaser
detection must land **together**, never in that order.

### 3. The full recipe is sitting in the rendered DOM

Both the on-page body and a print template carry the complete recipe. Verified counts from the
capture: **12 ingredient rows, 3 steps.**

- Body: `RecipeBodyContent_ingredientItemBlock__amount` + `…__description`, steps under
  `#step-1/2/3` in `RecipeBodyContent_instructionContent`.
- Print template (cleaner, flat): `RecipePrintTemplate_ingredientAmount`,
  `RecipePrintTemplate_stepNumber`, `RecipePrintTemplate_instructionContent`.

Two DOM gotchas the extractor must handle:

- **Amount and description are separate sibling nodes.** `<div…amount>1</div>` +
  `<div…description>pound boneless country-style pork spareribs…</div>`. Grabbing the
  description alone loses the `1`; the extractor must **join amount + description** per row.
- **The amount is plain text, not an image** (Jon's guess — checked: zero `<img>/<svg>` in
  amount blocks). It can be **empty** (e.g. "Kosher salt and ground black pepper", garnishes) —
  tolerate empty amounts, don't drop the row.
- **The unit lives in the description, not the amount.** The amount div is bare magnitude
  (`1`, `2`, `1-2`); "pound"/"tablespoons" is in the description. Don't treat the amount div as
  a quantity+unit field.

> Brittleness flag: the class suffixes are CSS-module content hashes (`__od5ej`, `__a9B4I`,
> `__gkIv1`) that change on every Milk Street build. Selectors **must** match the stable prefix
> (`[class*=ingredientItemBlock__amount]`, `[class*=RecipePrintTemplate_ingredientAmount]`),
> never the full hashed class.

## Reuse / precedent

- **DOM fallback extractor:** copy the shape of `RecipeBodyImageExtractor` /
  `RecipeEditorialProseExtractor` — a SwiftSoup pass over the `Document` feeding the shared
  `RecipeParseBuilder` via `addIngredient` / `addInstructionSection`
  (`RecipeParseBuilder.swift:36,48`), plugged into `WebRecipePageParser.parse`
  (`RecipePageParser.swift:17-21`). Same additive, schema-first-stays-authoritative contract as
  the editorial-prose effort (`docs/efforts/editorial-prose.md`).
- **Teaser handling precedent:** `browserCaptureTeaserPageIsNotUsable` +
  `nyt-cooking-teaser.html` already encode "teaser → not usable." Extend that contract to the
  *partial-but-present* case rather than inventing a new one.

## Design

1. **Milk Street DOM fallback extractor.** New `Recipe…` extractor keyed on the
   `RecipePrintTemplate_*` block (prefix selectors), joining amount + description per ingredient
   row and reading `stepNumber` + `instructionContent` for steps. Feed the builder additively.
   Keep the selector prefixes a named constant; this is intentionally Milk-Street-shaped, like
   the ATK editorial scrape.
2. **Read `<meta name=application/ld+json>` JSON-LD — but only with teaser detection wired.**
   In `RecipeJSONLDExtractor`, also collect `meta[name=application/ld+json]` and parse its
   (SwiftSoup-decoded) `content`. Before feeding a Recipe node to the builder, **detect the
   teaser**: drop any ingredient/step matching the sentinel (`"… Sign up for full access"` /
   `"… and more."`), and if a node is detected as truncated, treat it as **non-authoritative** —
   it must not by itself satisfy `hasStructuredRecipe` or suppress warnings when the DOM fallback
   is what actually carries the recipe. Prefer: skip the partial meta node's ingredients/steps
   entirely and let the DOM fallback own them (avoids the exact-match dedup fight in
   `addIngredient`, since teaser lines are a subset of the full DOM lines but not guaranteed
   byte-identical).
3. **New warning for partial structured data.** Add `WebRecipeCaptureWarning.truncatedStructuredData`
   (`ParsedRecipePage.swift:37`) raised when a teaser sentinel is seen, so the usability gate and
   UI can distinguish "silently partial" from "cleanly empty." A page that recovers via DOM
   fallback should clear it; one that can't should surface as not-usable, matching NYT.
4. **Schema-first stays authoritative for well-formed pages.** None of this changes the happy
   path (ATK, Serious Eats, etc.): a real `<script>` JSON-LD Recipe still wins. This is fallback
   and guard-rail only.

## Per-site status

| Source | Trick | Today | After this effort |
|---|---|---|---|
| Milk Street | meta-tag JSON-LD **+** truncated teaser **+** full recipe in DOM | empty → not usable | DOM fallback recovers full recipe; teaser guarded |
| NYT Cooking | hard teaser (`#recipe-paywall`), no recipe in teaser DOM | teaser → not usable ✅ (`nyt-cooking-teaser.html`) | unchanged; confirm the new sentinel path doesn't regress it — **Jon investigating next** |

NYT's teaser is the *clean* case (nothing to recover, correctly rejected). Milk Street is the
*dirty* case (recoverable, currently dropped). The shared lesson: **partial structured data is
more dangerous than absent structured data** — the guard in step 2/3 is the point of the effort,
the DOM scrape in step 1 is the payoff.

## Scope decisions

- **In scope:** meta-tag JSON-LD reading with teaser/sentinel detection; a Milk-Street-shaped
  print-template DOM fallback (amount+description join, empty-amount tolerant, prefix selectors);
  a `truncatedStructuredData` warning; fixtures + tests for both.
- **Out of scope:** a general "read any DOM recipe" engine. This is the same site-specific-DOM
  brittleness class as the editorial-prose and comment-ingestion ideas
  (`docs/open-questions.md`) — keep it small, named, and per-shape.
- **Sync-safety (forward note):** import-time parsing only; writes go through the existing
  `Recipe` ingredient/instruction fields. No schema change, no identity impact, nothing for the
  `SyncEngine` path (consistent with `[[sqlitedata-blob-cloudkit-asset]]`).
- **Forward note — this is per-site "playbook #1".** The Milk Street DOM fallback is the first
  concrete instance of the per-site capture-behavior registry sketched in
  `docs/open-questions.md` ("In-app capture — per-site behavior playbooks"). Build the extractor
  so it reads as a *named, host-keyed, fixture-tested* behavior that degrades to schema-first —
  the seam the NYT comment-loading playbook will later slot into — not a one-off. Keep it
  parser-side for now; the interactive playbooks (sort/Load-More) live in the in-app `WebPage`
  browser and are post-sync.

## Verification

- Add a sanitized fixture `milk-street-gochujang.html` (mirror the sanitize step used for the
  existing `SanitizedSites/*`). Assert the parsed bundle has **all 12 ingredients** (each with
  its amount joined, salt/garnish rows amount-less but present) and **all 3 steps**, and that the
  *"… Sign up for full access"* sentinel never appears as an ingredient.
- Add a "truncated only, no DOM fallback available" fixture (or strip the print template) and
  assert `truncatedStructuredData` + not-usable — i.e. the trap in step 2 can't silently pass.
- Regression: `browserCaptureTeaserPageIsNotUsable` (NYT) stays green and its warning set is
  unchanged.
- `swift test --package-path YesChefPackage` green; `scripts/check-drift.sh` clean; Jon UI pass
  on the live Milk Street recipe.

## Open questions for the implementer to confirm

- Whether to source the DOM fallback from `RecipePrintTemplate_*` (flat, print-oriented) or
  `RecipeBodyContent_*` (on-page). Print template looks cleaner; confirm both are present on a
  non-print capture before committing.
- Exact teaser sentinel matching — anchor on `"Sign up for full access"` vs the broader
  `"… and more."`? Prefer the most specific string that still catches the ingredient **and**
  instruction truncation markers; keep it a named constant.
- Confirm SwiftSoup `.attr("content")` returns the entity-decoded JSON (expected) so the existing
  `jsonObject(from:)` / smart-quote salvage path in `RecipeJSONLDExtractor` applies unchanged.

---
*Derived from a real Milk Street capture Jon supplied (gochujang stir-fried pork & celery).
Companion to `docs/efforts/editorial-prose.md` (same DOM-scrape-behind-schema-first pattern) and
the NYT teaser handling in `WebRecipeBrowserCaptureTests.swift` /
`Fixtures/.../SanitizedSites/nyt-cooking-teaser.html`.*
