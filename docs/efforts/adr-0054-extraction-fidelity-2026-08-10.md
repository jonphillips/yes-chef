# Effort: extraction preserves recipe structure and identity (ADR-0054, 2026-08-10)

**Type:** [ADR-0054](../decisions/ADR-0054-extraction-preserves-structure-and-identity.md) — four
lossless-or-loud fixes at the `RecipeParseBuilder`/canonical-model boundary. **One dispatch** (D1–D4 are
independent and small; batch them — [[batch-slices-and-lean-handoff]]). **No schema** — every change lives in
the extractor, the workbench-draft intermediate, and the warning enum; the canonical model is untouched, so
**nothing is owed the prod-schema promotion list.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Scoped, ready.** Package-layer (`YesChefCore`) only — no `YesChefApp/` change, so `swift build` +
Core tests carry it. Independent of any in-flight branch.
**Source:** [ADR-0054](../decisions/ADR-0054-extraction-preserves-structure-and-identity.md), drafted from the
**Codex Semantic Fidelity Audit, Aug 2026** (baseline `42ad5b6`) findings P1/P1/P2. The same audit's **P0**
(destructive duplicate-import convergence) already shipped (PR #304); its other P1 (`originalImportText`
retention) is a **provenance** matter deferred to an ADR-0053 amendment, **not in this effort**.
**Summary:** Four real inputs are flattened **silently** today — named instruction sections on the
workbench-return path, multiple complete JSON-LD recipes on one page, nested `HowToSection`s, and intentionally
repeated ingredients across groups. Each is the same failure class ADR-0053 exists to prevent, applied to
structure rather than correctness: *preserve structure up to the canonical model's own ceiling; where an input
exceeds that ceiling, surface the loss loudly at the review surface rather than dropping it.*

**Required invariant:**

> Extraction preserves recipe structure and candidate identity up to the canonical model's one-level ceiling.
> Where an input exceeds that ceiling — a second complete recipe on the page, a nested instruction section — the
> loss is **surfaced as a `WebRecipeCaptureWarning` at the review surface**, never a silent blend or drop. No
> canonical schema grows; no LLM enters any of these decisions (all four are deterministic, fixture-testable).

---

## Read before starting

- **[ADR-0054](../decisions/ADR-0054-extraction-preserves-structure-and-identity.md)** — the four decisions and
  the "assert structure, not success" verification bar. D2 (candidate identity) is the largest and the one with
  a shape decision below.
- **[`RecipeJSONLDExtractor.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeJSONLDExtractor.swift)**
  — `recipeNodes(in:)` (line 51) walks the whole tree and returns **every** Recipe node; both `extract` entry
  points then `for node in recipeNodes(…) { mineIfComplete(node, into: &builder) }` (lines 8–13, 15–35), mining
  them all into one shared `inout` builder. `mineInstructions` (line 115) handles a **top-level** `HowToSection`
  but a **nested** one falls through `instructionStrings` and loses the child grouping (D3).
- **[`RecipeParseBuilder.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/RecipeParseBuilder.swift)**
  — `addIngredient` (line 54) dedups **globally** (`where !ingredients.contains(line)`) across the flat
  `ingredients` array (D4). `markTruncatedStructuredData()` (line 89) + the `warnings` array (line 102) are the
  **precedent to copy** for new warnings — a `mark…()` mutator that appends a `WebRecipeCaptureWarning` in the
  finalizer.
- **[`ParsedRecipePage.swift`](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/ParsedRecipePage.swift)**
  — `WebRecipeCaptureWarning` (line 45) is **`String`-raw** (`case truncatedStructuredData` …). Adding cases
  with **associated values** breaks the `String` raw representation — see the D2 shape note.
  `ParsedRecipeInstructionSection(name?, steps:)` (line 13) is the section-aware source shape that already
  carries names.
- **[`AIHandoffWorkbenchDraftReturn.swift`](../../YesChefPackage/Sources/YesChefCore/AIHandoffWorkbenchDraftReturn.swift)**
  — `fromJSONLD` at line 122; the flatten is line 131 (`let instructionLines = page.instructionSections.flatMap(\.steps)`);
  the **ingredient** path right beside it (`flattenedIngredients`, line 160) already refuses this loss — that
  asymmetry is what D1 removes.
- **[`RecipeEditorDraft.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeEditorDraft.swift)** — the sink
  `instructionSections: [RecipeEditorInstructionSectionDraft]` (line 27) is **already a first-class list of
  section drafts**, so D1 carries structure straight through, no in-band string trick.
- The three `RecipeJSONLDExtractor.extract` callers — `RecipePageParser.swift:57` (web capture, **JSON-LD is one
  of six extractors** into the shared builder), `CreateRecipeSource.swift:58` (JSON-LD alone),
  `AIHandoffWorkbenchDraftReturn.swift:127` (JSON-LD alone). The web path's multi-extractor composition is the D2
  scoping wrinkle below.
- `CURRENT_HANDOFF.md` Verification Pattern.

---

## The context (by reading — no device repro needed)

One shape underlies all four findings: `RecipeParseBuilder` is **single-recipe, exactly one level deep**, and
the canonical model (`InstructionSection(name?, sortOrder)` → `InstructionStep`, **no parent pointer**) matches
it exactly. One level deep is the grain the whole app stores and edits — it is not changing. The fixes preserve
structure *up to* that ceiling and make every loss *at or above* it loud, never silent.

Two things about the current code decide the implementation shape and must be understood before touching it:

1. **The web-capture path composes six extractors into one builder.** `RecipePageParser` calls
   `RecipeJSONLDExtractor` **and** `RecipeMetaExtractor`, `RecipeMicrodataExtractor`, `RecipeMilkStreetExtractor`,
   `RecipeBodyImageExtractor`, `RecipeEditorialProseExtractor` — all mining the *same* `inout builder`. Those five
   are **page-level signal augmenters** (meta tags, microdata, body images, prose), not competing recipe
   identities. So D2's "candidate identity" concern is about **multiple JSON-LD Recipe nodes**, not about the
   other extractors — and the fix must not disturb the composition.
2. **Warnings ride a `String`-raw enum via a builder `mark…()` + finalizer append.** New warnings follow
   `markTruncatedStructuredData()` verbatim. A warning that needs to carry a **count** conflicts with the
   `String` raw value (see D2).

---

## The findings

### Finding 1 — instruction section names survive the workbench-return path (D1)

`WorkbenchDraftRecipe.fromJSONLD` stops flattening instructions at line 131. Both ends are already
section-aware: the source `page.instructionSections` carries `(name?, steps)`, and the sink
`RecipeEditorDraft.instructionSections` is a list of `RecipeEditorInstructionSectionDraft`. Carry the sections
**structurally** through the workbench draft into the editor draft — symmetric with how `flattenedIngredients`
already preserves ingredient group names, and lossless by construction.

- **Prefer structured carry** over the ingredient path's in-band `Name:` heading-line trick. The heading-line
  convention exists only because the ingredient draft field is a single text blob; the instruction sink is a
  typed list, so structured carry is cleaner. *(Fallback only if an implementation constraint forces it: the
  `Name:` heading convention is acceptable, but it must reconstruct on promote — there must be an
  instruction-side reader analogous to `IngredientSectionHeading`; do not emit heading lines nothing parses
  back — [[editable-at-the-grain-stored]].)*
- **Delete the "cook re-sections after promoting" rationale** from the code comment; it described a silent loss,
  not a design.
- Trace `WorkbenchDraftRecipe.instructionLines` — if nothing outside `fromJSONLD`/promotion still needs the flat
  field, retire it; if a consumer does, carry sections **alongside** and derive the flat view from them (do not
  keep the flat field as the source of truth).

### Finding 2 — candidate recipe identity survives; multiple complete recipes never blend (D2)

Today both `extract` entry points mine **every** materially-complete Recipe node into the one shared builder — a
round-up page, a base-plus-variant pair, or a "related recipe" full node all blend into one Frankenstein recipe.
Stop that.

**Shape decision (architect call — read this before implementing).** ADR-0054 D2 phrases the change as "the
extractor yields a list of candidates," and for the two JSON-LD-only callers that would be natural. But on the
web path the JSON-LD extractor is one of six mining a shared builder (context #1), so a full candidates-list
return would force `RecipePageParser` to reconcile a list against five other extractors' contributions — a
larger, riskier change than the invariant needs. **Ship the floor as internal primary-selection, keeping the
`inout builder` API:**

- Inside both `extract` entry points, replace `for node in recipeNodes(…) { mineIfComplete(…) }` with:
  gather the **materially-complete** nodes (a node with **both** ≥1 ingredient and ≥1 instruction — a name/image
  teaser is **not** a candidate and is ignored, not blended), **select one primary** by the deterministic rule
  below, `mineIfComplete` **only the primary**, and mark the warning when more than one complete candidate
  existed.
- **Deterministic primary rule (documented, testable — not "first seen"):** among materially-complete nodes,
  prefer the one that is the page's top-level / `mainEntity` node over one nested inside another node's field;
  break ties by JSON-LD document / `@graph` order. State the rule in a code comment and assert it in a test.
- This satisfies the ADR invariant — *candidate identity survives; a blend never ships as success* — because the
  primary is mined **alone**. A full candidates-list return + a user picker is **OQ1, deferred** until dogfooding
  shows a real multi-recipe page ([[llm-vs-determinism-surface-boundary]]: this is the deterministic side; an
  LLM must never pick which recipe you captured).

**The warning — and the enum-count wrinkle.** Add `builder.markMultipleRecipeCandidates()` mirroring
`markTruncatedStructuredData()`, surfaced as a new `WebRecipeCaptureWarning`. ADR-0054 proposed
`.multipleRecipeCandidates(count:)`, **but `WebRecipeCaptureWarning` is `String`-raw** — an associated value
breaks the raw representation and touches every `String(rawValue:)`/logging/display site. **Recommendation: ship
a plain `case multipleRecipeCandidates` (no count).** The count is not load-bearing for the invariant (the
review surface says "this page contained more than one recipe; showing one"), and preserving the `String`-raw
enum is worth more than the number. If Jon wants the count surfaced, converting the enum to associated values is
a separate, wider change — flag it, don't fold it in silently.

### Finding 3 — nested `HowToSection` is declared-lossy: flatten and say so (D3)

The canonical model stays one level deep. When a `HowToSection` in `mineInstructions` contains child
`HowToSection`s:

- **Flatten into the parent's one level, preserving the child name as grouping** — do not discard it and do not
  let it leak out as a bare step (today `instructionStrings` returns the nested child's `name` as if it were a
  step string). Provisional form: emit the child steps under a composed section name (`Parent — Child`);
  confirm the form against a real nested source at implementation (D3/OQ2). The child name is **content**, so it
  is preserved somewhere visible ([[decompose-notes-into-typed-homes]]).
- **Record the flattening** with a warning (a new `WebRecipeCaptureWarning`, e.g.
  `case nestedInstructionSectionsFlattened`, plain — same String-raw reasoning as D2). Nested sections are
  **unsupported by decision, made explicit at review** — not silently supported, not silently lost.

### Finding 4 — ingredient dedup is section-scoped, not global (D4)

`RecipeParseBuilder.addIngredient` drops any line already present **anywhere** in the recipe
(`where !ingredients.contains(line)`), silently losing intentionally repeated ingredients — "1 cup sugar,
divided" in two groups, salt in both a rub and a sauce, reserved marinade reused.

- Scope exact-string dedup **within a section** (the unit added by one `addIngredientSection` call / the
  unsectioned bucket), not across the whole recipe. Identical lines in **different** sections are **both kept**.
- Check **both** accumulation paths: the flat `addIngredient` **and** `addIngredientSection` (Finding 4's fix is
  incomplete if section-add still cross-dedups). Within a single section, exact-duplicate collapse is fine; the
  loss to stop is *cross-section*.
- Cross-section dedup is not a fidelity feature; it is silent removal of the cook's structure.

---

## The dispatch

One PR, package-layer only (`YesChefPackage/Sources/YesChefCore/…`). D1–D4 are independent — implement all four.

1. **D1** — `WorkbenchDraftRecipe.fromJSONLD` carries `(name?, steps)` instruction sections into
   `RecipeEditorDraft.instructionSections`; retire/derive the flat `instructionLines`; delete the stale comment.
2. **D2** — `RecipeJSONLDExtractor` selects a single deterministic **primary** materially-complete node and mines
   only it; `builder.markMultipleRecipeCandidates()` + a new plain `WebRecipeCaptureWarning` case; keep the
   `inout builder` API and the `RecipePageParser` six-extractor composition intact.
3. **D3** — `mineInstructions` flattens nested `HowToSection`s under a composed section name and marks a new
   `nestedInstructionSectionsFlattened` warning; the child name never surfaces as a bare step.
4. **D4** — `RecipeParseBuilder` dedups ingredients **within a section**, not globally; both add paths.

### Tests (`YesChefCoreTests` — assert structure, not decode success)

Per ADR-0054's "assert structure, not success" bar — read the **names and shapes**, not counts/non-nil/saves
alone:

1. **D1:** a workbench-return JSON-LD block with `HowToSection`s "Make the sauce" / "Bake" → a draft whose
   `instructionSections` carry **those names** with the right steps under each. Assert the names, not just the
   step count.
2. **D2 (blend prevented):** a page with two materially-complete Recipe nodes → the primary is chosen by the
   documented rule, `.multipleRecipeCandidates` is raised, and the primary's ingredients are **only its own**
   (assert no line from the other node bled in).
3. **D2 (teaser ignored):** one complete recipe + one name/image-only node → **one** result, **no** warning, no
   blend.
4. **D2 (primary rule):** construct nodes where document order and `mainEntity`/nesting disagree, and assert the
   rule's tiebreak picks the documented winner (proves it is not "first seen").
5. **D3:** a nested `HowToSection` → the child section **name is present** (as composed name / labeled group, per
   the chosen form) and is **not** emitted as a bare step; a flattening warning is raised.
6. **D4:** a recipe repeating an ingredient across two sections keeps **both** occurrences; a within-section
   exact duplicate may still collapse (assert the cross-section pair survives).

Extend the existing capture fixtures (`WebRecipeCaptureTests`, `RecipeExtractionTests`,
`WebRecipeMilkStreetCaptureTests`) rather than starting a new corpus.

---

## Guardrails a dispatch must not undo

- **No schema change.** No parent pointer on `InstructionSection`, no recursive section table — the canonical
  model stays one level deep (ADR-0054 "Alternatives"; [[squash-migrations-at-prod-baseline]]). D3 is
  flatten-and-surface **by decision**.
- **No LLM in any of these decisions.** Candidate selection, section carry, nested flattening, and dedup are all
  deterministic and fixture-testable ([[llm-vs-determinism-surface-boundary]]). An LLM picking which recipe you
  captured is unreviewable guesswork over a decision the markup already answers.
- **Do not fork a parser.** All of this is inside the existing deterministic `RecipeJSONLDExtractor` /
  `RecipeParseBuilder` (ADR-0051's one-strategy guard — the standing handoff block).
- **Keep the `inout builder` API and the six-extractor web composition** (D2 shape decision). Do **not** convert
  the extractor to a candidates-list return on this effort — that is OQ1's user-selection affordance, deferred.
- **Keep `WebRecipeCaptureWarning` `String`-raw** — new cases are plain (no associated values) unless Jon
  explicitly wants the count, which is a separate widening.
- **Losses are loud, never silent.** Every place an input exceeds the one-level ceiling raises a warning on the
  existing channel; nothing is dropped or blended as success (ADR-0040 lossless-or-loud;
  [[editable-at-the-grain-stored]]).

---

## Verification

- `swift build` the package; `scripts/check-drift.sh`; SwiftLint clean. **No `YesChefApp/` change**, so the
  generic app build is not the correctness gate here and `YesChefTests` does not apply — but confirm nothing in
  the app references a retired `instructionLines`/warning shape before claiming green
  ([[app-test-target-in-verification]] applies only if an app-layer type moves).
- Correctness rides the six Core tests above — the structure assertions are the point.
- **No new table** — nothing owed the prod-schema promotion list.
- **Device pass (Jon):** capture a real round-up / multi-recipe page and confirm one clean recipe + the "more
  than one recipe on this page" cue (not a blend); a workbench-return with named instruction groups keeps those
  names on promote; a nested-section print source flattens with the child name visible; a divided/repeated
  ingredient survives in both groups.

## Open questions (carried from the ADR)

- **OQ1 — candidate *selection UI*.** D2 ships a deterministic primary + warning; user selection among
  candidates waits until dogfooding shows a real multi-recipe page is common in Jon's sources.
- **OQ2 — nested flattening form.** Composed section name (`Parent — Child`) vs. labeled leading step; D3 picks
  composed-name provisionally — confirm against a real nested source at implementation.
