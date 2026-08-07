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

**[Amendment 1](#amendment-1--d1-was-wrong-about-capture-there-are-two-save-paths-and-the-review-surface-is-source-specific-2026-08-07)
— Proposed 2026-08-07.** Corrects a factual error in D1: web capture — the largest and most mature front-end —
does **not** terminate in `RecipeEditorDraft`. It reviews on `ParsedRecipePage` and commits through a **second
canonical save path** (`importCapturedRecipe` → `importBundle`), which Paprika import shares. Restates the rule
in a form a review can actually enforce: **one sink type; one save path per identity class; review surfaces may
be source-specific but must edit the sink.** Names capture as a grandfathered exception with its reason. Found
while drafting [ADR-0053](ADR-0053-create-recipe-destination.md), which answers OQ1.

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

## Amendment 1 — D1 was wrong about capture: there are two save paths, and the review surface is source-specific (2026-08-07)

**D1 asserted a convergence that does not exist.** It says every text→recipe path terminates in
`RecipeEditorDraft` → the review sheet → `save(draft:)`, and that "this is already true." It is not true of the
web-capture path — the largest, oldest and most exercised front-end in the table:

- **Review edits `ParsedRecipePage`, not the sink.** `RecipeCaptureView`'s editable fields — `reviewTitle`,
  `reviewSummary`, `reviewServingsText`, `editorialBlocks`, `readerFeedbackBlocks`, `reviewCategoryNames`,
  `reviewTagNames` — are computed get/set pairs straight onto `draft.page`
  ([RecipeModels.swift:459](../../YesChefApp/RecipeModels.swift)).
- **Commit runs a second canonical save path.** `RecipeRepository.importCapturedRecipe`
  ([WebRecipeCaptureClient.swift:319](../../YesChefPackage/Sources/YesChefCore/WebRecipeCapture/WebRecipeCaptureClient.swift))
  calls `page.makeRecipeBundle(...)` → `importBundle`
  ([RecipeRepository+Import.swift:207](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift)).
  Paprika import uses the same path. `save(draft:)`'s callers are the editor, menu-note promotion, workbench
  `createDraftRecipe`, and `SampleData` — capture is not among them.

**Left uncorrected this is worse than a documentation error: it makes D7 unenforceable.** A reviewer told "no new
terminal draft type, the sink is already one thing" cannot reconcile that with the capture code in front of them,
and the natural resolutions are both wrong — either wave the guardrail through as aspirational, or open a
convergence refactor nobody asked for.

### Amd1-D1 — The split is real and mostly correct: **import identity is what separates the two paths**

`importBundle` carries what `RecipeEditorDraft` does not model, and the extras are not incidental: dedupe against
`RecipeImportRef` by normalized source URL + title, `RecipeImportWarning` (title-only collision, ambiguous
identity), batch preview, batch import and rollback, plus photo / editorial / reader-feedback payloads.

**Those exist because the source has a stable external identity.** A URL or a Paprika record can be imported
twice and must not become two recipes. **Typed and pasted text have no such identity** — there is nothing to
dedupe against, and inventing one would be fabricating provenance. So the rule is not "one save path"; it is:

> **One save path per identity class.** A source with a stable external identity commits through `importBundle`.
> A source authored in the app commits through `save(draft:)`.

Paste-text and everything else in [ADR-0053](ADR-0053-create-recipe-destination.md) is therefore correctly on
`save(draft:)`, and **converging the two paths is not work this ADR owes.** It would be a real decision with a
real trigger (a source that is both authored and externally identified), not a tidy-up.

### Amd1-D2 — D1 restated: one **sink type**, plural **review surfaces** — the same logic as D2, one layer later

D2 already establishes that front-ends stay plural because sources genuinely differ. **The review layer inherits
that argument**: capture's review surface exists because the review must show what *that source* contributed —
harvested categories and tags, editorial prose blocks, reader-feedback candidates — none of which a paste has.
Forcing capture through the editor's review would delete affordances, not unify anything.

D1 is therefore restated as three clauses, each independently checkable:

1. **One terminal draft *type*: `RecipeEditorDraft`.** A new source may not introduce a new terminal draft type.
2. **One save path per identity class** (Amd1-D1). A new source may not introduce a *third*.
3. **A review surface may be source-specific, but it edits the sink.** New surfaces justify themselves by
   source-specific content to show, not by convenience.

**Capture is a named, grandfathered exception to clause 3** — it predates the strategy, it edits `ParsedRecipePage`
rather than the sink, and its extras are exactly the justification clause 3 asks for. It is recorded here as an
exception with a reason rather than left as a silent contradiction. **It is not a precedent**: a new source
citing capture to skip the sink is the review block D7 describes.

### Amd1-D3 — D7's guardrail, restated to match

A change that turns a new source into a recipe must: route LLM extraction through `RecipeExtractionClient`;
reuse an existing deterministic extractor where the source is structured; **terminate in `RecipeEditorDraft`**;
and **commit through the save path its identity class dictates**. A PR adding a fifth bespoke parser, a second
"text→recipe" model call, a new terminal draft type, or a third save path is a review block. Unchanged in spirit;
now stated in terms the code actually supports.

## Open questions

- **OQ1 — one entry point for paste + workbench-return + menu-note, or per-source?** All three are "free text
  → recipe." Decide when paste-text is scoped; until then each keeps its own thin entry and shares the engine.
  **Answered 2026-08-07 by [ADR-0053](ADR-0053-create-recipe-destination.md):** paste and typed text get **one
  first-class destination** (Create Recipe, reached from the library `+`), and the workbench-return and menu-note
  entries **stay where they are** — each belongs to a subject (a workbench, a menu) and arriving via the library
  would be the wrong door. See ADR-0053 OQ5 for the residue.
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
