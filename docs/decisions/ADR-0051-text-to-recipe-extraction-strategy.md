# ADR-0051 — Text → recipe: one sink, plural front-ends, one extraction engine

> **Vocabulary:** a **front-end** turns one *source* of text/markup into recipe structure (a web page, a
> menu note, a hand-off return, a paste, a photo). A **waypoint** is a source-specific pre-save draft envelope
> (`ParsedRecipePage`, `WorkbenchDraftRecipe`). The **sink** is the single editor/save intermediate every path
> terminates in (`RecipeEditorDraft`). The **extraction engine** is the one shared LLM step that turns
> unstructured text into the shared recipe *core* (`RecipeExtractionClient` → `RecipeExtraction`).

Status: **Accepted** — 2026-08-05 (Jon ratified, same conversation that ratified ADR-0042 Amd 2). Opened
Proposed the same day (architect + Jon, in the ADR-0042 Amendment 2 conversation: *"I really want to
consolidate our strategy here — force the issue"*). **Consolidates a shape that already has three shipped
consumers plus one ratified** — this is past the single-consumer trap the house avoids, so it earns an ADR
rather than a seam-ledger row ([[seam-ledger-append-on-sight]]). **Extends
[ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amendment 2** (which drew the
extraction-vs-synthesis line and routed the `workbenchDraft` return through the capture seam — the first path
built *to* this strategy). **Holds the [[llm-vs-determinism-surface-boundary]] line** and applies
[[editable-at-the-grain-stored]] (the sink is the human's last edit).

## Context

**"Turn this text into a recipe" happens in four places, and each grew its own front-end.** This is not a
defect — each front-end exists because its *source* genuinely differs — but the paths were never named as one
strategy, so the fifth source (paste text) and the sixth (photo → OCR) are each an invitation to fork a fifth
and sixth parser. **We nearly did exactly that:** ADR-0042 Amendment 2's *first* draft proposed a bespoke
label-cycle parser for the `workbenchDraft` return before recognizing the return was ordinary extraction that
the existing engine already does. That near-miss is why this ADR exists.

What is actually there today:

| Source | Front-end (parse) | Waypoint | Sink |
| --- | --- | --- | --- |
| Web page | deterministic schema.org (JSON-LD/microdata/meta) **+ LLM extraction fallback** | `ParsedRecipePage` | `RecipeEditorDraft` |
| Menu note (the button) | deterministic **heading heuristic**, preserve-on-failure | `WorkbenchDraftRecipe` | `RecipeEditorDraft` |
| Workbench draft (onboard) | **LLM synthesis** (deliberately invents) | `WorkbenchDraftRecipe` | `RecipeEditorDraft` |
| Workbench draft return (ADR-0042 Amd 2) | deterministic **JSON-LD** | (core → `WorkbenchDraftRecipe`) | `RecipeEditorDraft` |
| Paste text · photo→OCR | **the seam** | — | `RecipeEditorDraft` |

Files: web — `WebRecipeCapture/` (`RecipePageParser`, `RecipeJSONLDExtractor`, `RecipeExtractionClient` →
`ParsedRecipePage`); menu note — `MenuNoteRecipePromotion.swift` (`RecipeParseBuilder.draftRecipe(title:prose:)`);
workbench — `WorkbenchDraftRecipe.swift` (`WorkbenchDraftRecipeClient` synthesis; `editorDraft(...)` → the sink).

**Two facts the table makes visible, and this ADR turns into rules:**

1. **The sink is already one thing — `RecipeEditorDraft`.** Every path terminates there before the review
   sheet and the save. That convergence is real and load-bearing; it should be *ratified*, not left implicit.
2. **The waypoints are two (`ParsedRecipePage`, `WorkbenchDraftRecipe`) over a shared core.** Both are
   supersets of the same recipe core — title, times, `ingredientSections[{name, lines}]`,
   `instructionSections[{name, steps}]` (that core is literally `RecipeExtraction`) — differing only in
   *source-specific extras*: web carries author/tags/images/reader-feedback; workbench carries a rationale and
   candidate provenance. They are not redundant; they are different envelopes.

## Decisions

### D1 — The sink is `RecipeEditorDraft`, ratified. No path invents a new one.

Every text→recipe path terminates in `RecipeEditorDraft` → the review sheet → the identity-preserving save
(`RecipeCore` `save(draft:)`). This is already true; ratifying it makes it a rule a review can enforce. **A
new source may not introduce a new save path, a new review surface, or a new terminal draft type** — it maps
its output onto `RecipeEditorDraft` and reuses the existing review + save. The sink is where
[[editable-at-the-grain-stored]] is honored: the human's last edit happens there, on structured fields, before
anything canonical exists.

### D2 — Front-ends stay plural: a strategy keyed by *source*, never a god-parser

**The consolidation is of the sink and the LLM engine (D5), not the parsers.** Collapsing the front-ends into
one universal parser would be the wrong abstraction and would *lose information the source-specific parsers
deliberately encode*:

- The menu-note front-end recognizes **only explicit headings** and leaves everything else in an immutable
  provenance copy, "rather than losing prose to an over-eager extraction" (`MenuNoteRecipePromotion.swift:37`).
  That conservatism is correct *because a menu note is often not a recipe* — a universal LLM parser would
  invent structure a cook never wrote.
- The web front-end runs **deterministic extractors first** and only falls back to the model for the halves
  they miss. That tiering is correct *because a well-marked-up page needs no model at all*.

So adding a source **adds a front-end**; it never adds a sink (D1) or a draft type. The front-end set is a
strategy pattern, chosen by source. This is the disciplined form of "don't repeat yourself": share the sink
and the engine, keep the parsers plural on purpose.

### D3 — Extraction vs. synthesis is the primary axis (carried from ADR-0042 Amd 2)

Every front-end is **extraction** — faithful, *never invent* — **except** the onboard workbench draft, which
is **synthesis**: it deliberately combines and rejects candidates to make an editorial choice. This axis
decides which engine a source may use: a source whose text *is* a recipe (page, note, paste, photo, a
hand-off return) is extraction and must not route through the synthesis client; only the workbench's
"make me a recipe from these candidates" want is synthesis. **A return of already-decided content is always
extraction** — that was the ADR-0042 Amd 2 correction, generalized.

### D4 — Two-tier is the default for an *unstructured* source: deterministic first, LLM fallback

Any front-end over unstructured or semi-structured text uses the capture pattern: **deterministic extractors
first, the LLM extraction engine only for what determinism cannot reach.** A structured source (schema.org
JSON-LD, whether from a page or a hand-off return) is parsed **deterministically and for free**; the model is
the fallback, not the front door. This keeps cost proportional to messiness and keeps the common case
model-free. Menu-note is the deliberate exception (D6).

### D5 — One extraction engine: `RecipeExtractionClient`, lifted out of `WebRecipeCapture` at the second consumer

`RecipeExtractionClient` is the single shared LLM-extraction step. Its `structuredPageText` parameter name is
**already vestigial** — the input is just text, and its instructions are pure faithful transcription (*"never
invent a quantity, ingredient, timing… leave it missing"*). The shared *core* it returns, `RecipeExtraction`,
is the recipe core every waypoint wraps.

- **Rename + relocate out of the `WebRecipeCapture` namespace** to a source-neutral home when the **second
  real extraction consumer lands** — the ADR-0042 Amd 2 workbench return, or paste text, whichever ships
  first. **Not before:** extracting an abstraction against one consumer is the trap the house avoids
  ([[seam-ledger-append-on-sight]]); the return path reuses the engine *in place* until then.
- **The two waypoints are not forced to merge.** `ParsedRecipePage` and `WorkbenchDraftRecipe` stay distinct
  envelopes over the shared `RecipeExtraction` core, because their source-specific extras are real. Revisit
  only if a *third* envelope appears with no new extras to justify it (OQ2).

### D6 — Menu-note keeps its deterministic-only, preserve-on-failure design — for now, and named

The menu-note front-end deliberately omits the D4 LLM-fallback tier: a heading-less note yields a near-empty
draft with its prose preserved in provenance, and the cook rejects rather than trusting an invented structure.
**That stays.** Whether menu-note should *gain* an LLM-extraction fallback (offer, don't impose, when the
deterministic pass finds nothing) is a **named deferred decision, triggered by paste-text** — which is the
same "free prose a human typed" shape and will force the question honestly. **Do not add it on this ADR's
momentum** (OQ3).

### D7 — The forcing guardrail: no new text→recipe path ships a new parser

The rule that makes this ADR a forcing function rather than a description. **A change that turns a new source
into a recipe must:**

1. route its LLM extraction through **`RecipeExtractionClient`** (never a new model call that re-derives
   "text → recipe"), and
2. reuse an existing **deterministic** extractor where the source is structured (schema.org → the JSON-LD
   extractor), and
3. terminate in **`RecipeEditorDraft`** (D1), through the existing review + save.

**A PR that adds a fifth bespoke parser, a second extraction model call, or a new terminal draft type is a
review block** — the author routes through the seam or brings a decision here first. This is a Standing guard
in `CURRENT_HANDOFF`, because the whole risk is a dispatch quietly forking the seam under deadline.

## Open questions

- **OQ1 — one entry point for paste + workbench-return + menu-note, or per-source?** All three are "free text
  → recipe." Decide when paste-text is scoped; until then each keeps its own thin entry and shares the engine.
- **OQ2 — do the two waypoints ever merge into one source-neutral draft envelope?** *Lean: no* — they carry
  genuinely different extras. Revisit only if a third envelope appears that adds nothing new.
- **OQ3 — the menu-note LLM-fallback tier (D6),** triggered by paste-text. Offer-don't-impose if built.
- **OQ4 — cross-app: is the extraction engine a jon-platform / LLMClientKit lift?** Capture was harvested from
  Galavant ([[galavant-capture-engine-reuse]]); if Galavant carries the same faithful text→structure step, the
  engine is a convergence candidate on the ADR-0044 provenance-engine model — its own trigger and its own
  audit, not this ADR's scope.

## Slice — mostly a guardrail; the first path is already ratified

This ADR schedules **no build slice of its own.** Its concrete moves ride existing work:

- **The guardrail (D7) lands now** — a Standing guard in `CURRENT_HANDOFF`. Zero code.
- **The first path built to the strategy is ADR-0042 Amd 2 S3** (`workbenchDraft` return via the deterministic
  JSON-LD extractor) — already ratified, gated on its S3a hand-run.
- **The `RecipeExtractionClient` lift (D5)** rides whichever of {workbench return, paste text} ships second as
  an extraction consumer — recorded here so it happens deliberately, not by reflex.

## Related

- [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd 2 (the trigger; the extraction-vs-synthesis
  axis; the JSON-LD return that is the first path built here),
  [ADR-0032](ADR-0032-workbench-reference-material-fetch.md) (reference-material capture, a sibling text intake),
  [ADR-0044](ADR-0044-provenance-engine-to-llmclientkit.md) (the engine-lift model behind OQ4),
  [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (why the sink edits structured fields).
- Memory: [[workbench-draft-extraction-seam]] (the seam this ADR ratifies),
  [[llm-vs-determinism-surface-boundary]], [[editable-at-the-grain-stored]],
  [[galavant-capture-engine-reuse]], [[seam-ledger-append-on-sight]],
  [[automation-decays-near-the-stove]] (why menu-note stays conservative, D6).
