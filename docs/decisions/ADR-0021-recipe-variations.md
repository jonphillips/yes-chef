# ADR-0021 — Recipe variations (named deltas on a base recipe, selected in the reader)

> **Vocabulary:** the feature is **recipe variations**. A **variation** is a *named delta* applied on
> top of a **base recipe** — never a separate Recipe row, never a comment. The user **selects** a
> variation in the ordinary recipe interface; the selected delta **folds** into the reader (highlighted
> in place) and into the **grocery list**. A variation is *not* an ADR-0019 **experiment** (a hypothesis
> in a workbench) — though an experiment is its natural *source* (see D6). Do not call a variation a
> "version," a "fork" (that word is reserved for a workbench-log entry kind, ADR-0006/0019), or a "study."

Status: **Proposed** — 2026-07-06 (architect + Jon, during Recipe Workbench S1 dogfooding; body
decisions D1–D6 ratified in that conversation, schema is a recommendation). Extends
**[ADR-0019](ADR-0019-recipe-design-studies.md)** — closes the promote-target gap its D1(c) left open.
Binds **[ADR-0016](ADR-0016-multi-recipe-cook-session.md)** (whole-picture cooking, *not* step-by-step)
and **[ADR-0015](ADR-0015-chat-persistence.md)** (the local-only, sync-excluded store precedent). A new
consumer of the ADR-0011/0012 actionable-chat commit-shape axis ([[chat-verb-commit-shapes]]).
Sync-safe by construction (ADR-0002).

## Context

Dogfooding Workbench S1, Jon casually asked the chat for a **variation** on a recipe. The word is doing
more work than "comment": a real variation carries **its own ingredients and its own method changes**
("the smoky version adds chipotle and drops the paprika"). Jon's requirements, stated in the design
conversation:

- **Not separate recipes.** One recipe should hold several variations; he does not want the library to
  sprout a row per variation (this is exactly the flood ADR-0019 D1(c) rejected).
- **A real model with a UI component *inside the recipe*.** Look at each variation, **select the one you
  are cooking this time**, and have that selection **fold smartly into the method display and the grocery
  list**.
- **Without leaning on step-by-step cooking**, a surface Jon is on record as not wanting (ADR-0016).

The whole question is: *which primitive owns "variation"* — before we re-derive it as either an alternate
Recipe (drift + flood) or a smear of prose on the base.

### The insight that keeps this out of the black hole

A variation modeled as an **alternate Recipe** inherits the entire recipe pipeline a second time
(editing, images, scaling, provenance, sync) *plus* drift — edit the base and every variation rots. The
escape is to model a variation as a **thin overlay**: a name plus a small, structured set of changes,
composed by the *existing* reader and grocery pipeline over the unchanged base.

The feature is a swamp only if you insist on **resolving** the overlay into one coherent, executable
procedure a cooking-mode state machine could walk ("add the chipotle… *where exactly* in the step
sequence?"). **Jon does not want that surface** (ADR-0016), and that refusal is precisely what makes this
tractable. We never need one merged timeline. We need only two resolutions, both forgiving:

- **Grocery = set math.** `base ± variation deltas` over ingredients. Selecting a variation swaps which
  ingredient set feeds the aggregator. Robust and boring.
- **Method = annotation.** Render the base steps and *mark up* the changes in place ("Smoky version: add
  the chipotle with the garlic"). No canonical merge, because nobody is marching the steps blind.

So the aesthetic Jon already holds (whole-picture, meh on step-by-step) and this feature are **aligned,
not in tension.**

## Decisions

### D1 — A variation is a structured delta on the base, stored *on the recipe* (ratified)

Not an alternate `Recipe` row (ADR-0019 D1(c), re-affirmed: flood + drift), not a free-text comment. A
variation is child data of its base recipe: a name, an optional note, and a structured change set. The
base recipe stays the single source of truth; variations are overlays on it.

### D2 — Delta vocabulary: ingredients structured, method as prose (ratified — the scoping line)

The change set is **structured for ingredients** and **prose for method**:

- **Ingredient ops** — `add`, `remove`, `substitute`, `scale`, referencing base ingredient identity where
  applicable. Structured, because this is where the grocery payoff lives *and* where structure is
  tractable.
- **Method note** — free text tied to the variation, surfaced as a callout against the base steps. **Not**
  structured, mergeable, per-step instruction edits. The moment we make method edits structural and
  mergeable, we are back at the step-by-step resolver ADR-0016 declined. Hold this line and the feature
  stays finite.

If a variation's method genuinely diverges beyond a note's worth, that is the signal it wants to become
its own recipe (a manual promote), not that variations need a richer method model.

### D3 — Two resolutions, both forgiving; no merged procedure (ratified)

Selecting a variation drives exactly two things, and nothing that requires a linear executable merge:

1. **Reader fold** — the base recipe re-renders with the delta applied and **highlighted in place**
   (added/removed/substituted ingredients marked; the method note shown as a callout). The base is always
   legible underneath; the overlay is a lens.
2. **Grocery fold** — the selected variation's resolved ingredient set feeds the grocery list via the
   existing Phase E aggregation ([[grocery-pantry-threshold-design]]). No selection ⇒ base ingredients, as
   today.

Explicitly out: any single merged step-by-step procedure, any cooking-mode resolver.

### D4 — Home is the recipe; the workbench is a *producer*, not the owner (ratified — corrected in convo)

Variations live on, display in, and are selected from the **ordinary recipe interface**. The workbench is
**one birth path** for variations (deliberation there may throw off "try it this way"), alongside plain
hand-authoring and one-shot chat. The reader owns the fold, not the workbench — so the feature is **not
gated behind the workbench at all**. (This corrects the architect's first sketch, which over-located
selection in the workbench session.)

### D5 — Active selection is persisted, **not** synced (ratified)

The **variations themselves** are durable, synced data (real deltas a user authored — new rows/BLOB,
sync-safe). The **"which variation is active right now"** highlight is different: it is per-cook and
per-person. It must **persist** — Jon needs to leave the recipe, use other areas of the app, and return
without reselecting — but it must **not sync**, because "which variation I'm cooking tonight" shared
across devices manufactures a conflict for zero benefit ("A on my phone, B on the iPad" is not a
disagreement to resolve).

Therefore active selection is **not** a column on the synced `recipes` table. It lives in a **local-only,
SyncEngine-excluded store**, exactly as ADR-0015 did for chat messages (and guarded by the same
live-schema audit test).

### D6 — Provenance: a variation is the missing promote target for an ADR-0019 experiment (ratified)

ADR-0019 D1(c) rejected turning each **experiment** (`{hypothesis, change, rationale}`) into a Recipe row,
and left experiments as a hypothesis list with **no durable promote target** short of a full new Recipe.
Variations fill that gap: a cook who actually tries an experiment and wants to keep it **promotes it into
a variation on the working recipe** — durable, selectable, grocery-aware, and *without* flooding the
library. Producers of variations, then:

- **Hand-authoring** in the recipe UI.
- **One-shot chat** ("give me a spicier version") — a **new commit shape**: a *structured-delta* apply
  action, richer than the blob/list/per-line/no-commit shapes catalogued in [[chat-verb-commit-shapes]].
  Classify it as such before building; it must emit structured ingredient ops, not prose to smear
  ([[llm-curation-not-synthesis]]).
- **Promote-from-experiment** in the workbench (the loop-closer above).

## Proposed schema (sync-safe by construction, per ADR-0002 — recommendation, not ratified)

Mirrors the `menus`/`menuItems` + Codable-BLOB pattern already in the repo:

- **`recipeVariations`** (synced) — `id` (UUID PK), `recipeID` (**soft FK → `recipes`,
  `ON DELETE CASCADE`** — a variation cannot outlive its base), `name: String`, `note: String?` (the
  method annotation), `sortIndex`, `deltas: Data?` (Codable BLOB `[VariationDelta]`, the serveWith/prepPlan
  BLOB pattern). `VariationDelta` = an enum over `add`/`remove`/`substitute`/`scale` carrying the
  ingredient payload. Provenance (`origin: hand | chat | experiment`) optional but cheap.
- **Active selection — local-only, SyncEngine-excluded** (ADR-0015 precedent): a tiny
  `recipeActiveVariation(recipeID → variationID)` local store. **Never** a column on synced `recipes`
  (that would sync the highlight, violating D5). Guarded by the live-schema audit test that already
  excludes chat.

All additive; UUID PKs; no reserved columns or unique indexes ([[sqlitedata-blob-cloudkit-asset]]). BLOB
carries no image bytes, so no CKAsset concern.

## Cost, honestly — and why this is *not* a dispatch yet

Scoped as above it is tractable, but it is **milestone-sized, not a slice**. It touches the model (new
synced table + BLOB + migration), the grocery aggregation (variation-aware ingredient set), the reader
(the highlighted-fold UI), the recipe UI (author/select surface), a local-only selection store, and chat
(the new structured-delta commit shape). That is real, and it **must not derail Recipe Workbench S2**,
which is the current Next Up.

**Status is Proposed. Not a dispatch target.** It sits in the Ready-Efforts "open design ADRs" bucket.
Recommended next step is *not* code but **more dogfooding**: when the chat offers a variation, notice what
you actually reach for it to do — read it, shop it, or cook it — because that tells us whether the first
slice is grocery-folding or read-only annotation. Ratify slices with Jon before any build.

## Open questions (surface for discussion when the time comes — not decided)

### OQ1 — The creation verb: who writes the diff? (raised 2026-07-06, Jon)

The likely birth gesture is a workbench verb — *highlight text → "this is a Variation called ___."* But a
variation is a **delta against the base**, not the highlighted text itself, so "writing the diff" hides a
fork that turns on **what was highlighted**:

- **Description-born (LLM writes the diff).** The model *described* a version in chat that is applied
  nowhere yet; the only representation is prose. So the verb is **structured extraction**: `prose + base
  recipe → [VariationDelta]`. Note this is *not* a text diff — it is the same bounded, checkable extraction
  class as the existing per-line substitution verb, made safe precisely by D2's closed op vocabulary. It is
  the new **structured-delta commit shape** — a structured *object* out, the newest/most complex shape in
  [[chat-verb-commit-shapes]]; classify it as such and hold [[llm-curation-not-synthesis]] (emit distinct
  ops, never a re-blended recipe).
- **Edit-born (compute the diff, no LLM).** The highlight is content the user actually *changed*, or the
  structured ingredients already differ from the base. Then the diff is **mechanical set-math**
  (`new − base`), deterministic, no trust question — and it is the *same engine* as the deferred
  original-vs-current provenance idea ([[reference-placement-and-original-provenance]]). Two features, one
  diff engine.

**Lean (not ratified):** prefer the mechanical path wherever the content is already structured; reserve the
LLM strictly for the prose→structure bridge, to keep the untrustworthy step as small as possible.

### OQ2 — The fold *is* the staging surface

However the diff is written, it is reviewed by the **D3 reader-fold** — re-render the base with the delta
highlighted in place — which is already the Workbench S2 "model proposes, the tap writes" pattern. So no
separate preview card is built; the fold is the preview. The failure mode this catches is **identity
anchoring** ("swap the paprika" when the base lists smoked paprika twice — which row?); the human tap after
the fold is the guard.
