# ADR-0021 — Recipe variations (named deltas on a base recipe, selected in the reader)

> **Vocabulary:** the feature is **recipe variations**. A **variation** is a *named delta* applied on
> top of a **base recipe** — never a separate Recipe row, never a comment. The user **selects** a
> variation in the ordinary recipe interface; the selected delta **folds** into the reader (highlighted
> in place) and into the **grocery list**. A variation is *not* an ADR-0019 **experiment** (a hypothesis
> in a workbench) — though an experiment is its natural *source* (see D6). Do not call a variation a
> "version," a "fork" (that word is reserved for a workbench-log entry kind, ADR-0006/0019), or a "study."

Status: **Shipped** — the model, the reader fold and the grocery fold were built as
**[ADR-0023](ADR-0023-recipe-edit-proposals.md) S2** (the `recipeVariations` table + the local-only active
selection store); ADR-0023 D1/S2 supersedes this ADR's standalone framing, and variations are reached
through the adjust proposal/review surface.
**[Amendment 1](#amendment-1--a-variation-is-hand-edited-through-the-resolved-view-the-ops-are-derived-never-authored-2026-07-21)
(hand-editing via the resolved view — ops are derived, never authored) and
[Amendment 2](#amendment-2--promotion-is-the-release-valve-a-variation-can-become-the-base-or-its-own-recipe-2026-07-21)
(promotion to base / to its own recipe) are Proposed — 2026-07-21, both schema-free**; **Amd1-D7** (an
inexpressible edit reports at save and offers the split-off) and **Amd2-D4** (no probation machinery) were
ratified in that conversation, and **Amendment 1 now carries no open questions.** Originally **Proposed** — 2026-07-06 (architect +
Jon, during Recipe Workbench S1 dogfooding; body decisions D1–D6 ratified in that conversation, schema was
a recommendation). Extends
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

## Amendment 1 — a variation is hand-edited through the **resolved view**; the ops are **derived, never authored** (2026-07-21)

**The want, parked twice and never answerable as posed:** looking at a variation, Jon wants to edit *the
variation* — fix a line, define a section header, tune a step. Variations are LLM-created and then
read-only (`docs/open-questions.md`, 2026-07-09 and reaffirmed 2026-07-11), so this has had no home, and the
obvious framing made it look like a trade: **either** the variation becomes hand-editable **or** we keep the
overlay, the in-place highlighting, and base-follow-through. Jon named the trade exactly (2026-07-21): *"It
seems crazy that I can't edit it. But I love the overlay, color comparison and wouldn't want to lose it."*

**There is no trade. The framing hid an assumption — that a human editing a variation edits its *ops*.**

### Amd1-D1 — Edit the resolved recipe; recompute the delta on save

The human edits the variation the way they edit anything else — the **resolved** recipe, in the ordinary
structured editor. On save, the app **diffs the edited result against the base and recomputes the op set**.
The overlay is not lost; it is *re-derived*. Reader fold, in-place highlighting, and grocery fold all
continue to work because the delta still exists — nobody hand-wrote it.

**The ops are a derived artifact, not content.** Today they are derived from an LLM proposal; after this
amendment they are equally derivable from a human edit. Nothing about the model changes — only who supplies
the input to the derivation.

**Two consequences worth stating, because they read as bugs and are features:**

- Editing a variation's line **back to the base text** silently drops the op, and the highlight disappears.
  That is correct: the variation no longer differs there.
- Editing the same variation twice never accumulates cruft. The op set is recomputed whole each time, so it
  is always minimal by construction.

### Amd1-D2 — This is OQ1's **edit-born** path, promoted from a creation lean to the editing mechanism

[OQ1](#oq1--the-creation-verb-who-writes-the-diff-raised-2026-07-06-jon) already sorted diff-writing into
*description-born* (LLM extracts structure from prose) and **edit-born** (mechanical set-math, no LLM), and
leaned toward the mechanical path "wherever the content is already structured." **The lean was right and
scoped too narrowly** — it was only ever applied to *creating* a variation. Applied to *editing* one, the
same engine closes the parked want. **Ratified here for the edit path; the creation paths are unchanged.**

[OQ2](#oq2--the-fold-is-the-staging-surface) also strengthens: for a hand edit there is nothing to stage.
The human was editing the resolved view, so the recomputed highlight **is** the confirmation — no proposal
card, no review sheet, no "model proposes / tap writes" gate, because no model proposed anything.

### Amd1-D3 — The `deltas` BLOB **stays**, and ADR-0040 is satisfied rather than violated

**On the record, because the architect argued the opposite earlier the same day and was wrong:** the
`deltas` BLOB (`Schema.swift:758`) looked like the ADR-0040 defect — content that can only be regenerated,
never repaired, exactly like `Menu.prepPlan`. **It is not, and the reason is the principle's own wording:
ADR-0040 keys on the grain *the human edits*.** Once the human edits the resolved recipe, **no human ever
touches an op** — the BLOB is a derived cache of a mechanical diff, which is the one thing a blob is
legitimately for.

The earlier reasoning failed by assuming *"hand-editable variation"* meant *"hand-editable ops."* It does
not, and the fix is cheaper than the fix for the misdiagnosis: **no new table, no new column, no migration,
and nothing added to the standing prod-schema promotion list.** The CloudKit promotion window is therefore
**not** a constraint on this work.

*(The [[editable-at-the-grain-stored]] test, stated so it does not have to be re-derived: ask what a human
would repair by hand. If the answer is a field, it is a column. If the answer is "the thing this was
computed from," the computed form may be a blob.)*

### Amd1-D4 — The editor must be the **ID-preserving structured** editor, not a text round-trip

This is the correctness gate, and it has a known failure in this repo. If the edit path round-trips through
joined text and re-parses (minting fresh line IDs), a one-word change diffs as **remove + add** and the
variation lights up as if the whole recipe changed. That is precisely the defect the ADR-0023 S1 revision
fixed for adjust — *stop round-tripping through `ingredientText`; mutate the `[IngredientLine]` /
`[InstructionStep]` arrays in place, preserving `id` / `sectionID` / `sortOrder`.*

**The enabling fact is already shipped:** `resolved(applying:)` applies the delta through that same
ID-preserving path with a **deterministic** UUID sequence seeded by the variation's ID
(`RecipeAdjustment.swift:684`), so every row in the resolved view has a stable identity across resolutions —
base rows keep base IDs, added rows get reproducible ones. `variationIngredientHighlights`
(`RecipeAdjustment.swift:711`) already compares those identities in one direction. **The diff-back is the
mirror of code that exists**, not new machinery.

**Diff minimality is the acceptance criterion, not an optimization** — a correct-but-noisy diff destroys the
color comparison, which is the feature being protected.

### Amd1-D5 — The **op vocabulary bounds the editable surface**, and it extends on demand for free

An edit is expressible only if the vocabulary can carry it: today `add` / `remove` / `substitute` / `scale`,
plus the method note (D2) and ADR-0023's whole-step replacement. **Section headers, line reordering, and new
sections are not expressible** — which is the real reason "add a header to a variation" has no home. It is
not a missing button; it is unrepresentable.

**Because ops are derived, extending the vocabulary migrates no human data** — the ops are simply
recomputed under the wider vocabulary on next save. So this is incremental: add a new op when a real edit
demands one, one at a time, each with a consumer.

**The first candidate is step *insertion*, and the evidence is a real run, not a guess.** The 2026-07-21
[ADR-0042 Amd1](ADR-0042-workbench-handoff-and-the-return-block.md#amd1-d7--learnings-stay-with-a-re-aimed-ask-resolves-amd1-oq1-hand-run-2026-07-21)
hand-run produced a six-change revision brief for a real recipe; four changes mapped cleanly onto existing
ops (three whole-step replacements, one `scale`), and **two wanted the same thing the vocabulary cannot
express — appending a *finishing step*** ("finish with lemon juice before serving"; "add chopped rosemary at
the end"). Method ops today are whole-step **replacement** only.

**This reorders the queue away from where the parked open questions pointed.** Section headers were the
named want; **step insertion is what real use produced first.** Note it is not a blocker — both changes are
expressible by rewriting the *last* step's text — which makes it a **quality** defect rather than a
correctness one, and a quietly bad one: the finishing action gets smuggled into the tail of an unrelated
step, so the highlight blames the wrong step and the base's step boundaries silently rot. That is what the
extension buys. **v1 constrains
the editor to what is expressible and says so plainly** rather than silently discarding an inexpressible
edit (lossless-or-loud, ADR-0040). Two constraints stay:

- **Section headers need [ADR-0014](ADR-0014-recipe-text-editing-model.md)** (the header/text-editing model)
  before they are added to the vocabulary; that dependency is unchanged by this amendment.
- **Nothing here reopens ADR-0016.** Reordering, if it is ever added, is a different *order*, never a merged
  executable procedure. D3's refusal of a resolver stands.

Edits that genuinely exceed the vocabulary have a defined answer, and it is not a richer delta model — it is
[Amendment 2](#amendment-2--promotion-is-the-release-valve-a-variation-can-become-the-base-or-its-own-recipe-2026-07-21). D2 predicted this: *"If a variation's method genuinely diverges beyond a note's worth, that is the signal
it wants to become its own recipe."*

### Amd1-D6 — Base edits after the fact are unchanged

Re-derived ops still anchor to base identity, so editing the *base* while variations exist remains the open
ADR-0023 OQ3 question (`validateVariationsCanRebase` currently guards it). This amendment neither worsens
nor solves it. Do not let it ride along silently.

### Slice — V1, schema-free

- **Core:** derive-on-save — resolved-detail-in → `RecipeVariationPayload`-out, the mirror of
  `resolved(applying:)`; write it beside that function so the pair stays honest. **The derivation returns
  the ops *and* an explicit list of edits it could not represent** (Amd1-D7) — a typed result, not a
  thrown error and never a silent drop, so the app can name the specific edit.
- **App:** open the structured editor on a variation's resolved detail (base stays untouched); save routes
  to the derivation, not to the base writers. **Guard hard:** editing while a variation is active must never
  fall through to `overwriteRecipe*`.
- **Tests (Core, the real signal):** edit a substituted line → one `substitute` op, base row identity
  preserved; edit a line back to base text → op disappears; edit a variation-added line → the `add` op's
  text changes and no new op appears; edit across two sections → per-section correctness; round-trip
  (derive → `resolved(applying:)`) reproduces the edited text exactly; **a minimality test** — a one-word
  change produces exactly one op; **and an inexpressible edit** (a new section header) returns it in the
  unrepresentable list with nothing saved (Amd1-D7).
- **Verify** per the house pattern; Jon device-passes that the highlight after a hand edit marks only what
  actually changed.

### Amd1-D7 — An inexpressible edit **reports at save and offers the split-off** (ratified: Jon, 2026-07-21)

*(Resolves Amd1-OQ1.)* The editor does **not** pre-emptively refuse — no disabled header button, no rule
explained before the user has hit it. The edit is accepted, and **at save** the app says what cannot be kept
and offers [Amendment 2](#amendment-2--promotion-is-the-release-valve-a-variation-can-become-the-base-or-its-own-recipe-2026-07-21)'s
**split off as its own recipe** as the way to keep it.

Three constraints on that moment, because a save-time report is exactly where content gets silently eaten:

- **Never save a partial derivation.** The choice is *keep the whole edit by splitting off* or *go back and
  change it* — never "saved, minus the parts we couldn't represent." That is lossless-or-loud (ADR-0040) at
  the one point where this design could violate it.
- **Name the specific edit**, not the category — *"a new section header (`For the sauce`) can't be kept in a
  variation,"* not *"unsupported edit."* The user needs to know which of their changes is the problem.
- **The split-off carries the edit through**, including the inexpressible part. That is the entire reason
  it is the offer: the new recipe is ordinary recipe data with no vocabulary to exceed.

**Sequencing consequence:** the *report* is the requirement, the *offer* is the affordance. If V1 ships
before V2, V1 reports and asks the user to change the edit — it must not promise a button that does not
exist yet. Bundling V1 + V2 in one dispatch avoids that awkward interim, and both are schema-free
([[batch-slices-and-lean-handoff]]).

## Amendment 2 — promotion is the release valve: a variation can become the **base** or its **own recipe** (2026-07-21)

**The taxonomy this rests on is Jon's, from the 2026-07-21 design conversation, and it is the thing that
was missing:**

- **(A) True variations.** They coexist with the base forever — the half batch, the vegetarian one, the
  smoky one. The base stays canonical, the variation is a lens. **This is what ADR-0021 was written for**,
  and Amendment 1 makes it editable.
- **(B1) A new dish wearing a variation's clothes.** The adjust exercise went far enough that it is not a
  lens anymore. It is filed as a variation only because that is the only destination the commit sheet
  offers.
- **(B2) A candidate on probation.** *"Make this once or twice and see whether it's the real recipe that
  subsumes the base."* Jon: *"It's almost workbench light."*

### Amd2-D1 — The commit sheet asks a **storage** question; the human's answer is an **intent**

Today the adjust commit offers *overwrite* or *keep as a variation* — two storage locations. The user's
actual answer is one of four intents: *this replaces it* · *this lives alongside it* · **this is its own
dish now** · **this might replace it, once I've cooked it.** One destination absorbing three intents is why
B1 and B2 end up mis-filed as variations, and why the variation table looked like it needed to grow
capabilities that only B-kind items ever wanted.

**The fix is destinations, not capabilities.** Both new ones are *promotions*, and both are reachable from
an existing variation as well as at commit time — because the mis-filing has already happened in the
library.

### Amd2-D2 — B1: **split off as its own recipe**

Materialize the variation's resolved detail into a new `Recipe` with its own children, and drop the
variation. Nothing overlays anything afterward: it is an ordinary recipe, fully editable, with no anchors to
drift. This is the manual promote D2 already gestured at, and it is the escape hatch for every edit
Amendment 1's vocabulary cannot express.

**No provenance column in v1.** A `derivedFromRecipeID` link is tempting and cheap, but it has **no
consumer** — nothing would read it — and a synced column with no consumer is exactly the
[[withdraw-not-defer-orphaned-schema]] trap, with a prod-schema promotion cost attached. If a consumer
appears (a "derived from" affordance, a compare), it designs its own storage then. The variation's `name`
carries into the new recipe's title, which is the provenance a human actually uses.

### Amd2-D3 — B2: **promote to base**, and the old base becomes a variation for free

The variation's resolved detail becomes the base recipe (through the existing `replaceEditableChildren`
writer, in one transaction), and **the previous base is preserved as an auto-derived variation** — the same
derivation engine as Amendment 1, run once in the other direction. It costs almost nothing, and it makes
subsume **reversible** instead of destructive: the old recipe is still right there in the picker, one tap
away.

Existing variations on that recipe re-anchor to the new base, which is the ADR-0023 OQ3 rebase question
arriving by another door — **this slice is where it must actually be answered**, not deferred again.

### Amd2-D4 — **No probation machinery.** Ratified: Jon, 2026-07-21

B2 sounds like it wants a lifecycle — a `candidate` status, a cook count, "you've made this twice, ready to
decide?" **It does not.** Jon, asked directly: *"I don't need counts or anything. I just need to be able to
promote when ready."*

Take that as the decision **and** the principle: the app tracking whether you have cooked something twice
and then prompting you about it is choreography, and choreography decays near the stove
([[automation-decays-near-the-stove]]). **The human knows when they are ready; the app's whole job is to
have the button there when they are.** Consequences, all of them subtractive: no `status` column, no cook
counter, no verdict prompt, no notification, nothing to sync, nothing to go stale. A B2 candidate is
**stored exactly like a true variation** — the difference lives in the cook's head until the day they press
promote, which is the correct place for it.

### Slice — V2, schema-free

Both promotions reuse shipped writers (`replaceEditableChildren`, the recipe-create path, the derivation
from Amendment 1). **No new tables, no new columns, nothing added to the promotion list.** Sequence after
Amendment 1, since promote-to-base wants the derivation engine. Answer ADR-0023 OQ3 (rebase existing
variations onto a new base) as part of it — with a warn-and-confirm if a re-anchor cannot be validated,
never a silent drop.

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

**Update (2026-07-21):** the edit-born half is ratified for the **edit** path by
[Amendment 1](#amendment-1--a-variation-is-hand-edited-through-the-resolved-view-the-ops-are-derived-never-authored-2026-07-21)
— the mechanical diff is how a hand-edited variation writes its delta. The creation paths above are
unchanged.

### OQ2 — The fold *is* the staging surface

However the diff is written, it is reviewed by the **D3 reader-fold** — re-render the base with the delta
highlighted in place — which is already the Workbench S2 "model proposes, the tap writes" pattern. So no
separate preview card is built; the fold is the preview. The failure mode this catches is **identity
anchoring** ("swap the paprika" when the base lists smoked paprika twice — which row?); the human tap after
the fold is the guard.

**Update (2026-07-21):** still true for LLM-written deltas. For a **hand-edited** variation there is nothing
to stage at all — see
[Amd1-D2](#amd1-d2--this-is-oq1s-edit-born-path-promoted-from-a-creation-lean-to-the-editing-mechanism).
