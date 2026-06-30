# Effort: Capture editorial prose blocks ("Why This Recipe Works", "Before You Begin")

**Type:** Feature gap (M3 — Authenticated Browser Capture; follow-on from Slice 5)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Ready to scope into Next Up after the Share-Extension refresh effort merges

## Symptom

A captured ATK recipe drops its editorial context — the **"Why This Recipe Works"** and
**"Before You Begin"** blocks — even though they are prominent on the page. Ingredients and
instructions come through fine.

## Root cause (verified)

This is **by design** in the current schema-first parser, not a bug.

- The parser is JSON-LD-first: `RecipeJSONLDExtractor` reads
  `script[type=application/ld+json]` and maps `schema.org/Recipe` fields
  (`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeJSONLDExtractor.swift:6`);
  `description` flows to `ParsedRecipePage.summary`
  (`ParsedRecipePage.swift:34`, `:142`).
- **The editorial blocks are not part of `schema.org/Recipe`.** Confirmed against the Slice 5
  fixture (`atk-rendered.html`): "Why This Recipe Works" / "Before You Begin" appear **only
  in the page body DOM**, never in either JSON-LD block. So a schema-first parser correctly
  has nothing to map, and they are dropped.

To capture them we need a **scoped DOM scrape**, not a JSON-LD field — a deliberate feature
decision, narrow by nature.

## Reuse / precedent

`RecipeBodyImageExtractor` is the exact pattern to copy: a SwiftSoup extractor over the
`Document` that feeds the shared `RecipeParseBuilder`, plugged into the parse flow
(`YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeBodyImageExtractor.swift:13`,
`extract(from:into:)`). The prose extractor is the same shape, keyed on section headings
instead of `<img>`.

Target field: `Recipe` already has `summary` (`Models.swift:9`) and `notes`
(`Models.swift:165`). These blocks are editorial *context*, distinct from the one-line
recipe summary — so map them to **notes**, leaving the JSON-LD `description → summary`
mapping untouched.

## Goal

When a captured page carries recognized editorial prose blocks, preserve them as recipe
notes (clearly labeled), without disturbing schema-first extraction of the core recipe.

## Design

1. **New `RecipeEditorialProseExtractor`** (SwiftSoup, same integration shape as
   `RecipeBodyImageExtractor`): select sections whose heading text matches a small, explicit
   allow-list ("Why This Recipe Works", "Before You Begin"), capture the following prose, and
   add it to the builder as labeled note text. Keep the heading list a named constant — this
   is intentionally ATK-shaped to start.
2. **Plumb prose through `ParsedRecipePage` → bundle → `Recipe.notes`.** Add a field carrying
   the captured editorial blocks (label + text), mapped into the recipe's notes in
   `makeRecipeBundle`. Confirm the exact builder/voting plumbing against `RecipeParseBuilder`
   and `RecipeAttributeVotes` so it composes cleanly with existing notes.
3. **Schema-first stays authoritative.** Prose is additive context, never a substitute for or
   override of JSON-LD recipe fields. Append, don't replace.

## Scope decisions

- **In scope:** an ATK-shaped, heading-keyed editorial-prose scrape mapped to notes, behind
  the schema-first parser; tested against `atk-rendered.html`.
- **Out of scope / explicitly flagged brittleness:** generalizing to arbitrary sites. This is
  the **same brittleness class as the comment-ingestion idea** (`docs/open-questions.md`) —
  site-specific DOM keyed on display text that the publisher can change. Keep it a small,
  named, per-shape scrape; do **not** build a general "editorial section" heuristic engine.
- **Sync-safety (forward note):** writes only to `Recipe.notes` (an existing field) at import
  time; no schema change, no identity impact, nothing for the later `SyncEngine` path.

## Verification

- Unit: parse `atk-rendered.html`; assert the resulting bundle's notes contain the
  "Why This Recipe Works" and "Before You Begin" text (labeled), and that `summary` still
  reflects the JSON-LD `description` (no clobber). Assert a page **without** these blocks
  yields unchanged notes (no spurious capture).
- `swift test --package-path YesChefPackage` green; `scripts/check-drift.sh` clean.
- Jon UI pass: captured ATK recipe shows the editorial notes in detail.

## Open questions for the implementer to confirm

- Exact note shape: one merged note vs. one note per labeled block. Prefer whatever reads
  cleanly in recipe detail and survives a round-trip through `originalSnapshot`.
- Whether to anchor on heading **text** (allow-list above) or a more structural selector;
  text-keyed is simpler and acceptable for the ATK-first scope, but note the brittleness in
  code so the next site doesn't silently inherit a wrong assumption.
- Confirm `summary` is not already being fed from these blocks anywhere via the meta/microdata
  extractors before adding the notes path.

---
*Derived from the M3 Slice 5 follow-on notes
(`docs/milestones/M3-authenticated-browser-capture.md`) and the sanitized fixture
`YesChefPackage/Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/atk-rendered.html`.*
