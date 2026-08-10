# ADR-0054 — Extraction preserves recipe structure and identity: losses at the builder boundary are surfaced, never silent

Status: **Proposed** — 2026-08-10. Drafted by Claude (architect) from the **Codex Semantic Fidelity Audit,
Aug 2026** (baseline `42ad5b6`), findings P1 (workbench instruction sections), P1 (multiple JSON-LD Recipe
nodes), and P2 (nested `HowToSection`). Governed by
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless-or-loud) and the
[[llm-vs-determinism-surface-boundary]] line; builds on
[ADR-0051](ADR-0051-text-to-recipe-extraction-strategy.md) (one sink, plural front-ends, one extraction
engine), [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd2 (the workbench-return extractor),
and [ADR-0047](ADR-0047-llm-capture-fallback.md) (the deterministic-first ladder). Related principle memories:
[[editable-at-the-grain-stored]], [[decompose-notes-into-typed-homes]], [[workbench-draft-extraction-seam]].

**This ADR decides how much structure the deterministic extractor must preserve, and what it must do when an
input exceeds the shape it and the canonical model can hold. It does not redesign the parser, the LLM
fallback, or any UI.**

> **Out of scope, on purpose.** The audit's P0 (destructive duplicate-import convergence) is a data-loss bug,
> handled in [its own effort](../efforts/import-duplicate-destructive-convergence-2026-08-09.md), not here.
> The audit's other P1 — **Create Recipe retaining `originalImportText`** — is *provenance retention*, a
> different mechanism from structural fidelity, and belongs in an **ADR-0053 amendment**, not this ADR. I
> earlier floated bundling it here; on reading the code they share nothing but an audit heading. Kept apart.

## Context

**One shape underlies all three findings.** `RecipeParseBuilder`
([`RecipeParseBuilder.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeParseBuilder.swift))
is **single-recipe and exactly one level deep**: it accumulates the attributes of *one* recipe, and its
instruction model is a flat list of `ParsedRecipeInstructionSection(name?, steps: [String])` — named groups,
one level, no nesting. The canonical model matches it exactly:
`InstructionSection(name?, sortOrder)` → `InstructionStep(sectionID, …)`
([`Models.swift`](../../YesChefPackage/Sources/YesChefCore/Models.swift)), with **no parent pointer**. Sections
one level deep is not an accident of the builder; it is the grain the whole app stores and edits.

Three real inputs exceed that shape, and today each is flattened **silently**:

1. **Named instruction sections vanish on the workbench-return path.**
   [`WorkbenchDraftRecipe.fromJSONLD`](../../YesChefPackage/Sources/YesChefCore/AIHandoffWorkbenchDraftReturn.swift:122)
   does `let instructionLines = page.instructionSections.flatMap(\.steps)` — collapsing "Make the sauce" /
   "Bake" into one anonymous list. The current comment rationalizes it: *"the draft's instruction field is
   single-section by construction, and the cook re-sections after promoting."* That rationale is wrong on its
   own terms, because **both ends of this pipe are already section-aware**: the source
   `ParsedRecipePage.instructionSections` carries the names, and the sink `RecipeEditorDraft.instructionSections`
   ([`RecipeEditorDraft.swift:27`](../../YesChefPackage/Sources/YesChefCore/RecipeEditorDraft.swift)) is a
   first-class list of `RecipeEditorInstructionSectionDraft`. The loss happens **only** at the intermediate
   `WorkbenchDraftRecipe`, whose `instructionLines` is flat. And the *ingredient* path through the very same
   function already refuses this loss — multiple named ingredient groups are re-inlined as `Name:` heading
   lines the editor reconstructs on promote (`flattenedIngredients`, and the comment there:
   *"rather than the cook silently losing them"*). Instructions are the asymmetric exception, not a principled
   design.

2. **Multiple complete recipes on one page blend into one Frankenstein.**
   [`RecipeJSONLDExtractor`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeJSONLDExtractor.swift)'s
   `recipeNodes` walks the whole JSON-LD tree and returns **every** Recipe-typed node (including nested and
   `@graph` members), then `extract` does `for node in recipeNodes(…) { mineIfComplete(node, into: &builder) }`
   — mining them all into **one shared builder**. A page with a main recipe plus a "related recipe," a
   round-up of three recipes, or a base-plus-variant pair produces one apparently-successful synthetic recipe
   assembled from more than one source node: ingredients concatenated, instruction sections interleaved,
   images pooled, scalar fields decided by vote. There is no notion of *candidate recipe identity* anywhere in
   the pipeline.

3. **Nested `HowToSection` names are lost.** `mineInstructions` handles a top-level `HowToSection`, but its
   steps come from `instructionStrings(dict["itemListElement"])`, which on a *nested* `HowToSection` returns
   that child's `name` as if it were a step string (or drops its steps) — the child section's grouping is
   gone, and what survives is misleading. The builder has nowhere to put a second level regardless.

**The line this ADR draws** is the [[llm-vs-determinism-surface-boundary]] one and ADR-0040's lossless-or-loud
rule, applied to extraction: *preserve structure up to the canonical model's own ceiling; where an input
exceeds that ceiling, surface the loss loudly at the review surface rather than dropping it silently.* Silent
structural loss is the same failure class as a silently-wrong extraction admitted to canonical data
(ADR-0053's whole motivation) — it just loses grouping instead of correctness.

## Decision

### D1 — Instruction section names survive end-to-end; carry section drafts, don't flatten

`WorkbenchDraftRecipe` stops flattening instructions. Carry the parsed instruction sections through the
workbench-return draft as **(name?, steps)** groups — structurally symmetric with how it already preserves
ingredient group names, and mapping straight into `RecipeEditorDraft.instructionSections`, which already exists
and already round-trips through the editor and the canonical `InstructionSection` rows. Both ends are
section-aware; remove the flat narrow point between them.

- Prefer carrying **structured section drafts** over the ingredient path's in-band `Name:` heading-line trick.
  The heading-line convention exists for ingredients because the ingredient draft field is a single text blob;
  the instruction sink is *already a list of section drafts*, so structured carry is both cleaner and lossless
  by construction. (If an implementation constraint forces the in-band route, the `Name:` heading convention
  is the acceptable fallback — but it must reconstruct on promote, i.e. there must be an instruction-side
  reader analogous to `IngredientSectionHeading`; do not emit heading lines nothing parses back.)
- Delete the "cook re-sections after promoting" rationale from the code comment; it described a silent loss,
  not a design.

### D2 — Candidate recipe identity survives extraction; multiple complete recipes never blend

`RecipeJSONLDExtractor` stops mining every Recipe node into one builder. Instead:

- **One builder per candidate node.** Extraction yields a list of candidate `ParsedRecipePage`s (or the
  moral equivalent), one per materially-complete Recipe node — never a page-level blend.
- **Deterministic primary selection is the floor.** When exactly one candidate is materially complete, use it.
  When two or more are, pick a primary by a **deterministic, documented rule** (proposed: the node with the
  most complete required content — has both ingredients and instructions — breaking ties by JSON-LD document
  order / `@graph` position; a Recipe that is the page's `mainEntity`/top-level node outranks one nested inside
  another node's field). The rule must be stable and testable, not "first seen."
- **The loss is visible.** When more than one materially-complete candidate exists, emit a new
  `WebRecipeCaptureWarning` case (e.g. `.multipleRecipeCandidates(count:)`) carrying the count, so the capture
  and Create Recipe review surfaces show *"this page contained N recipes; showing 1"* rather than presenting a
  silent blend as success. **User selection among candidates is the eventual affordance** and the right
  long-term answer; a deterministic primary + a loud warning is the shippable floor and satisfies the
  invariant now.

> **Invariant (Codex's wording, adopted):** *Candidate Recipe identity must survive extraction. Multiple
> materially-complete candidates must be deterministically selected with visible evidence, or require user
> selection/review.*

"Materially complete" is defined narrowly and deterministically: a Recipe node with **both** at least one
ingredient and at least one instruction. A node with only a name/image (a "related recipe" teaser) is not a
candidate and is ignored, not blended.

### D3 — Nested `HowToSection` is a declared-lossy input shape: flatten, and say so

The canonical model is one level deep and **stays that way** — no parent pointer, no recursive section table,
for an input shape this rare. When a `HowToSection` contains child `HowToSection`s:

- **Flatten into the parent's one level, preserving the child name as grouping, not discarding it.** Compose
  the child's name into the flattened output (proposed: the child section's steps are emitted under the parent
  section with the child name carried as a composed section name — e.g. `Parent — Child` — or as a leading
  labeled step; pick one and test it). The child name is *content*, so it is preserved somewhere visible, per
  [[decompose-notes-into-typed-homes]] — never dropped and never mistaken for a step.
- **Record the flattening.** Emit a warning (reuse/extend the truncation-style `WebRecipeCaptureWarning`
  surface) so review shows that a nested structure was flattened. Nested sections are **unsupported by
  decision**, made explicit at review — not silently supported and not silently lost.

### D4 — Ingredient dedup is section-scoped, not global

`RecipeParseBuilder.addIngredient` drops any line already present anywhere in the recipe. That silently loses
**intentionally repeated** ingredients — "1 cup sugar, divided" appearing in two groups, salt in both a rub
and a sauce, "reserved marinade" reused. Exact-string dedup is scoped **within a section** (or dropped for
sectioned ingredients entirely); identical lines in *different* sections are both kept. Cross-section
deduplication is not a fidelity feature; it is silent removal of the cook's structure.

## Consequences

- **Fidelity becomes testable as structure, not decode.** The verification bar (below) asserts section names,
  candidate counts, and nested labels — the audit's explicit ask that fixes add *semantic-fidelity* tests, not
  parser-success tests.
- **The capture/Create review surface gains two new signals** (multiple candidates, nested flattening) on the
  existing `WebRecipeCaptureWarning` channel — consistent with ADR-0053's "uncertainty is computed and shown,"
  no new UI framework.
- **No schema change.** The canonical model is untouched; every decision lives in the extractor, the workbench
  draft intermediate, and the warning enum.
- **D2 changes an extractor return shape** (page → candidates). Confined to the three
  `RecipeJSONLDExtractor.extract` callers
  ([`RecipePageParser`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipePageParser.swift),
  [`CreateRecipeSource`](../../YesChefPackage/Sources/YesChefCore/CreateRecipeSource.swift),
  [`AIHandoffWorkbenchDraftReturn`](../../YesChefPackage/Sources/YesChefCore/AIHandoffWorkbenchDraftReturn.swift));
  each takes the primary candidate and reads the new warning. Deterministic-first; no LLM enters the selection.

## Alternatives considered

- **Add a nested/recursive instruction-section schema (reject).** A parent pointer on `InstructionSection` to
  represent a genuinely rare input shape is schema and sync surface for almost no recipes, and it would make
  *every* editor and reader account for depth forever. Flatten-and-surface is proportionate. ([[squash-migrations-at-prod-baseline]] instinct: don't grow synced schema for a corner.)
- **Keep blending and de-duplicate/repair with the LLM later (reject).** Selecting among candidate recipes is
  a reproducible, evidence-bearing decision — exactly the deterministic side of the
  [[llm-vs-determinism-surface-boundary]] line. An LLM picking which recipe you captured is unreviewable
  guesswork over a decision the source markup already answers.
- **Preserve instruction sections via the ingredient `Name:` heading trick (accept only as fallback).** It
  works, but the instruction sink is already structured; using an in-band string convention where a typed one
  exists re-introduces a parse boundary for no reason. Structured carry (D1) is primary.

## Verification (assert structure, not success)

Core tests in `YesChefCoreTests`, each asserting semantic structure — not decode success, non-nil, counts, or
saves alone:

- **D1:** a workbench-return JSON-LD block with `HowToSection`s "Make the sauce" / "Bake" produces a draft
  whose `instructionSections` carry **those names** and the right steps under each — read the names, not just
  the step count.
- **D2:** a page with two materially-complete Recipe nodes yields **two candidates**, a deterministic primary
  by the documented rule, and the `.multipleRecipeCandidates` warning; assert the primary's ingredients are
  *only* its own (no lines from the other node). A page with one complete recipe + one name-only teaser yields
  **one** candidate and no warning.
- **D3:** a nested `HowToSection` produces flattened output in which the child section **name is present**
  (as composed name or labeled group, per the chosen form) and a flattening warning is raised — assert the
  label survives and is not emitted as a bare step.
- **D4:** a recipe repeating an ingredient across two sections keeps **both** occurrences.

Standard gate: `swift build` the package; generic app build is required evidence (`CURRENT_HANDOFF.md`
Verification Pattern); `scripts/check-drift.sh`; SwiftLint clean.

## Open questions

- **OQ1 — candidate *selection UI*.** D2 ships a deterministic primary + warning. When does user selection
  among candidates become worth the surface — is the round-up page (N full recipes) common enough in Jon's
  real capture sources to justify it, or is the warning sufficient indefinitely? Defer until dogfooding shows
  a real multi-recipe page.
- **OQ2 — nested flattening form.** Composed section name (`Parent — Child`) vs. labeled leading step. D3
  picks the composed-name form provisionally; confirm against a real nested source (some print-style recipe
  sites) at implementation, since the choice is only visible on that rare input.
