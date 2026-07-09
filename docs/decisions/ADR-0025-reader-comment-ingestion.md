# ADR-0025 — Reader Feedback: NYT comment harvest → LLM curation → distinct recipe notes

> **Vocabulary:** **reader comments** = the community thread on a source recipe page (NYT Cooking,
> sortable to "Most Helpful," full of genuine technique/result tips buried in noise). This ADR
> **interactively harvests** them in the in-app authenticated browser, has an LLM **curate** them
> (select + lightly trim *distinct* tips — never merge), and writes each accepted tip as its **own
> reviewable `RecipeNote` of a new `readerFeedback` type**, displayed on the recipe as a **Reader
> Feedback** section and available to the recipe chat. It **wires the already-written but unreferenced
> `RecipeReaderCommentExtractor`**. The detailed build lives in the companion effort
> [`efforts/reader-feedback-comment-ingestion.md`](../efforts/reader-feedback-comment-ingestion.md);
> this ADR records the *decisions*.

Status: **Accepted** — 2026-07-09 (Jon ratified; proposed 2026-07-08, dogfood pass 2026-07-08). Ratifies the design in
`efforts/reader-feedback-comment-ingestion.md` (2026-07-01), with two updates for what shipped since:
the LLM client and key storage now exist (`LLMClientKit` + Keychain `apiKeyStore`), and the curation
prompt is a DB-backed AI **preference**, not `AppStorage`. **Extends [ADR-0007](ADR-0007-web-recipe-capture-engine.md)**
(capture parser) and **[ADR-0009](ADR-0009-in-app-authenticated-browser-capture.md)** (in-app
authenticated browser; comments are *interactively loaded* from the logged-in DOM — impossible in the
passive share extension). **Feeds [ADR-0011](ADR-0011-actionable-chat-make-ahead.md)** recipe chat.
**Binds [ADR-0018](ADR-0018-prompt-customization-taste-profile.md)** (the curation prompt is a per-task
preference). Holds **[[llm-curation-not-synthesis]]** and **[[llm-vs-determinism-surface-boundary]]**
(advisory, review-before-commit — the right place for an LLM). Additive enum case only — **no schema
change**, sync-safe ([ADR-0002](ADR-0002-cloudkit-sync-no-server.md)). Shares the review-sheet
dismiss-fragility hardening with **[ADR-0024](ADR-0024-editable-proposal-preview.md)** (OQ1 there = Slice 1
here).

## Amendment — 2026-07-09 (dogfood revision of D3–D5, post-[#129](https://github.com/jonphillips/yes-chef/pull/129))

Reviewing the first curation build ([#129](https://github.com/jonphillips/yes-chef/pull/129)), Jon flagged
the auto-curate-then-review flow as **too magical/opaque** and pinned down what the output should actually
look like: a human editor's numbered list of atomic recipe changes — *"use less honey (some said none, but
that's a different recipe IMO); 2 garlic cloves instead of 1; salt and drain the cukes if not serving
right away; don't add the splash of water — dressing goes watery; …"* — where **some lines distill what
many commenters converged on** and **some preserve one commenter's specific detailed contribution.** This
amendment revises **D3–D5** to hit that target. #129's scaffolding stands (the `readerFeedback` enum case,
the `RecipeReaderCommentExtractor` bridge, the Reader Feedback display section, the ADR-0024 review-sheet
reuse, and per-accepted-tip `RecipeNote` storage); what changes is the **curation prompt, the review UI,
and the token budget.**

- **A1 — the rule refines to "synthesize *within* a point, never *across* points" (revises D3).** The
  original D3 read as "never synthesize." That was too blunt: the hazard was never *"collapse the six
  people who all said less honey into one line"* — it was *"blend seven distinct changes into one soupy
  paragraph."* So the LLM **may** collapse a change many commenters mention into **one atomic point**, and
  **must** keep distinct changes as **separate entries** ("less honey" and "more garlic" are always two).
  The output shape stays the [[llm-curation-not-synthesis]] guardrail — a **JSON array of atomic points,
  never a prose blob** — which is exactly what keeps within-point consensus from becoming across-point
  mush. Two provenance kinds are both first-class: **consensus-distilled** (many comments → one point, with
  a support count) and **singular-preserved** (one rich, specific comment kept largely intact). D3's
  quality bar is otherwise unchanged: precision over recall, cut the blabber, **empty list is a valid
  answer.**

- **A2 — provenance-in-review is the answer to "too magical" (revises D4/D5).** Each proposed point
  carries its **provenance** — a support count and the **backing anonymized comments**, expandable at
  review time (*"Use less honey ← 6 comments"* / *"Salt and drain the cukes ← 1 detailed comment"*). The
  model **shows its evidence**; it is not a black box. Jon reviews the list in the ADR-0024 editable sheet
  — accept / **edit** / reject **each point** — injecting his own editorial cut (the *"…but that's a
  different recipe IMO"* voice is his, added at review, not the model's). A **"promote a comment the model
  missed"** escape hatch keeps the manual-triage instinct alive as a fallback without making him wade
  through the raw thread as the primary flow. **Storage is unchanged from #129:** each accepted point is
  one `RecipeNote(readerFeedback)`. Provenance is **transient/advisory** — shown at review; *optionally*
  persist a light *"(from 6 comments)"* tag in the note text (OQ6, Jon's call), no schema impact either way.

- **A3 — no deterministic near-duplicate pre-filter; redundancy IS the signal.** An earlier review idea —
  a cheap deterministic dedup/consensus-collapse pass before the frontier — is **rejected here.** Consensus
  detection *needs* the redundancy intact to count "6 people said less honey"; collapsing near-duplicates
  first would destroy the exact signal A1 depends on. Strip only **truly empty/garbage** comments before
  the call. (The on-device first-pass-model idea is likewise deferred — same risk of dropping the signal,
  and no cost case at today's volumes.)

- **A4 — raise the token budget and check truncation.** Because A1 requires the **whole thread** to reach
  the frontier for the tally, `maxTokens: 2048` at `.high` reasoning over ~80 comments is too tight
  ([[reasoning-budget-starves-output]]). Raise the ceiling (billing is per token *used*, not the cap, so a
  generous ceiling only removes truncation) **and** check `ModelResponse.wasTruncated` — a cut-off tally
  silently **under-counts** consensus, which is a wrong answer, not just a short one. Surface a distinct
  "couldn't finish — try again" state rather than swallowing it as an empty curation.

**New open question — OQ6:** persist a lightweight support-count tag in the accepted note text, or keep the
count review-only? *Lean:* review-only unless Jon wants the provenance durable on the recipe.

## Context

Dogfooding NYT capture 2026-07-08, Jon asked whether the app captures the comment thread the in-app
browser renders so nicely — the stated goal being to let the AI **scour comments for tips**. It does not:
`RecipeReaderCommentExtractor` (NYT-only; `[RawComment { text, helpfulCount }]`) exists but has **zero
callers**, nothing persists comments, and the chat context omits them.

We already designed this in `efforts/reader-feedback-comment-ingestion.md` (2026-07-01): harvest the
ranked thread, LLM-**curate** it into distinct tips, surface them as a reviewed **Reader Feedback** note
section. Jon reconfirmed that design over a leaner "raw comments → chat only" alternative (2026-07-08):
the value is in *distinct, specific, human-approved tips* ("I used cardamom instead and it was great"),
which a raw-blob-to-chat path would neither preserve as durable recipe content nor let him review. The
curated notes also satisfy the original "feed the AI" ask for free — they are `RecipeNote` rows the chat
context can read (D7).

### Why an LLM here is the right call (not a determinism violation)

Per [[llm-vs-determinism-surface-boundary]], an LLM is appropriate on an **advisory, reviewed** surface
and wrong on a reproducible data-merge (grocery). Comment triage is judgment-heavy noise-filtering,
**reviewed before anything is saved**, and never touches canonical ingredients/method — squarely the
advisory side. The hazard is **synthesis** (flattening distinct tips into mush); D3 designs against it at
the *output-shape* level, not just prompt wording ([[llm-curation-not-synthesis]]).

## Decisions

### D1 — Interactive harvest, in-app browser only, as a named per-site playbook (ratified)

NYT comments are **not** in the passively-captured DOM — they sit behind a "Most Helpful" sort control
and a "Load More" button and must be **interactively loaded via JS injection**. Therefore:

- A **named "Load Comments" action** in `BrowserViews.swift`, separate from the "Capture" recipe action,
  injects JS to sort to Most Helpful and click Load More, **bounded to a fixed cap** (start ~20–30
  comments / 3–5 clicks; tune from a real fixture — OQ1).
- This is **in-app-browser only.** The share extension is passive/one-shot (no WebKit) and structurally
  cannot drive a sort+load — state this as a hard constraint, not a limitation to work around.
- Structure it as the **first interactive entry in a registry of named, fixture-tested per-site
  playbooks** (Milk Street's DOM fallback is the parser-only playbook #1), so ATK/Milk Street comment
  playbooks slot in later without a rewrite. Comments ride a **separate pipeline** from
  `RecipeJSONLDExtractor`/`RecipeParseBuilder` — they are not `schema.org/Recipe`.

### D2 — Anonymize at DOM extraction; only `{text, helpfulCount}` survive (ratified — PII/ToS line)

Comments are third-party content. Commenter **display name and avatar are stripped at extraction time** —
never built into the in-memory struct, never sent to the LLM, never stored. The extractor is a pure,
host-keyed, fixture-tested function over the loaded `Document` (same shape as
`RecipeEditorialProseExtractor`, no WebKit dependency) producing `[RawComment { text, helpfulCount }]`.

### D3 — Curate ruthlessly: cut the noise, keep only distinct, non-obvious, genuinely useful tips (ratified)

> **Amended 2026-07-09 (A1 above):** "never synthesize" refines to **synthesize *within* a point, never
> *across* points** — consensus-distilling many comments into one atomic line is now explicitly allowed;
> only across-point merging into a prose blob is forbidden. The JSON-array-of-atomic-points output shape is
> unchanged.

Two jobs — and the **first is the whole point of the feature**, so it must be the loudest instruction in
the prompt, not a trailing clause:

1. **Selectivity — the quality bar (primary).** Most of a comment thread is blabber: "made this for my
   family, they loved it," restaurant nostalgia, location gripes, five-star raves, obvious swaps. The
   LLM's *primary* job is to **discard all of it** and surface only the **handful** of comments carrying a
   **genuinely useful, non-obvious tip** — a technique correction, a timing/temperature fix, a
   result-changing ratio tweak, a "do X or it breaks" warning, a real improvement the recipe author
   missed. **Bias hard toward precision over recall:** returning three real tips and dropping a marginal
   one is correct; padding the list to look thorough is the failure mode. If nothing clears the bar,
   **return an empty list** — never stretch to fill it. This bar is the reason the feature exists (raw
   comments would just be noise to the reader and the chat); state it first and forcefully.
2. **Distinctness — curate, don't synthesize (secondary).** Keep the survivors **distinct**: select and
   lightly trim individual comments; never paraphrase or merge them into a consensus. The **output shape
   enforces this** — a structured list of snippets, one per accepted tip, *not* a free-text paragraph (a
   model can ignore an instruction; it can't easily ignore "return a JSON array of `{text}` items, one per
   accepted tip"). This is the **curation commit shape** ([[chat-verb-commit-shapes]],
   [[llm-curation-not-synthesis]]).

### D4 — Each accepted tip is its own reviewable `RecipeNote(readerFeedback)` (ratified)

> **Amended 2026-07-09 (A2 above):** each proposed point now carries **visible provenance** (support count
> + expandable backing comments) at review time, plus a "promote a comment the model missed" escape hatch —
> the answer to the "too magical" worry. Per-point storage as a `RecipeNote(readerFeedback)` is unchanged.


Add an additive `RecipeNoteType.readerFeedback` enum case (no table/schema change; same sync-safe pattern
as the existing note types). Each selected snippet becomes its **own draft `RecipeNote` row**, so in the
**review-before-commit** flow (`RecipeCaptureView`) Jon can accept three tips and reject a fourth
**individually** — never editing a merged blob — mirroring the editorial-prose accept/edit/delete
pattern already built. Nothing is saved without approval.

### D5 — Displayed as a "Reader Feedback" section (ratified)

The recipe reader renders the `readerFeedback` notes as a labeled **Reader Feedback** section of distinct
quoted tips. The detail view currently labels sections via `note.noteType.rawValue.capitalized`, which
won't split camelCase — add an explicit display-string map so `readerFeedback` → "Reader Feedback."

### D6 — The curation *preference* is user-editable in Settings; the *guardrails* stay in code (ratified — updates the effort doc)

Yes, the prompt is tweakable — but as a layered **preference**, not a raw prompt, per ADR-0018's "never
expose raw task prompts" law. Two layers, deliberately split:

- **Non-editable scaffolding (code, at the task boundary).** D3's quality bar (cut the noise; distinct,
  non-obvious, genuinely-useful tips only; precision over recall; empty list if nothing qualifies) **and**
  the structured JSON-array output contract are the feature's guardrails. If a user could delete "return
  distinct tips, not a summary" or "only genuinely useful non-obvious tips," they'd break the feature —
  so these are not user-facing. This is exactly why ADR-0018 keeps raw task prompts out of the UI.
- **Editable preference (Settings, the taste layer).** What *Jon* counts as useful is a new
  **`readerFeedback` case on `AIPromptPreferenceKind`**, exposed alongside Chef-It-Up / Serve-With /
  Make-ahead / Complements (ADR-0018) — DB-backed (synced, consistent) and injected at the `LLMClientKit`
  boundary like every other task preference. Ship a sensible default the user can refine, e.g. *prize
  technique / timing / temperature / ratio fixes and failure-warnings; ignore dietary swaps, sourcing
  gripes, and taste-only raves.*

So the answer to "should the prompt live in Settings?" is: **the preference yes, the scaffolding no** —
the same two-layer split every other task preference already uses.

### D7 — The curated notes feed the recipe chat (ratified — preserves the original "scour" ask)

Because accepted tips are `RecipeNote` rows, extend `RecipeChatRecipeContext` to include the
`readerFeedback` notes (today it serializes only `noteType == .general`) — as a distinctly-labeled bucket
so the assistant can draw on reader tips when answering. This is the low-cost payoff of the notes model:
the AI "scours" the *curated* feedback, not raw noise.

## Storage sketch (sync-safe by construction)

**Additive enum case only** — `RecipeNoteType.readerFeedback`. Writes go through the existing `RecipeNote`
table at review/commit time. No new table, no new column, no identity impact, nothing new for
`SyncEngine`. (The raw `[RawComment]` harvest is transient/device-local — only the *curated, approved*
tips persist, as notes.) **Note:** this **drops** the `recipes.readerCommentsData` column proposed in the
first draft of this ADR — the notes model replaces it.

## Relationship to the prior effort (what's carried, superseded, shared)

- **Carried verbatim:** the interactive NYT harvest (D1), anonymization (D2), curation-not-synthesis
  (D3), the `readerFeedback` note type + per-tip review (D4/D5), the fixture-first grounding step, the
  named-playbook-registry framing.
- **Superseded (what shipped since 2026-07-01):** the effort doc's Slice 4 ("build a Claude client + key
  storage — first LLM integration") is **done** — reuse `LLMClientKit` + the Keychain `apiKeyStore`; do
  not build a new client. The `AppStorage` curation prompt becomes a DB-backed preference (D6).
- **Shared hardening:** the effort doc's Slice 1 (review-sheet dismiss fragility —
  `RecipeCaptureView`/`ShareViewController` lack `interactiveDismissDisabled`/`isModalInPresentation`) is
  the **same** fragility [ADR-0024](ADR-0024-editable-proposal-preview.md) OQ1 raises. Do it once,
  standalone, and let both efforts depend on it.

## Cost, honestly — and the slice plan

Mirrors the effort doc, minus the now-existing LLM client:

- **S1 — review-sheet dismiss hardening.** `interactiveDismissDisabled`/`isModalInPresentation` while
  edits are unsaved + Cancel-with-confirm, on `RecipeCaptureView` and `ShareViewController`. Shared with
  ADR-0024; lands any time.
- **S2 — harvest a real "Most Helpful, fully loaded" NYT DOM fixture** (Claude-in-Chrome MCP against an
  authenticated recipe). Precondition — selectors are unknowable until a real page is in hand.
- **S3 — NYT comment playbook + anonymizing extractor** (D1/D2): the named Load-Comments action + JS
  sort/Load-More, and the pure fixture-tested `[RawComment]` extractor.
- **S4 — curation in the review flow + `readerFeedback` note type + display + prompt preference**
  (D3–D6): the `LLMClientKit` curation call inside `RecipeCaptureView`, distinct draft notes, the Reader
  Feedback section, and the `AIPromptPreferenceKind.readerFeedback` setting.
- **S5 — feed the chat** (D7): include `readerFeedback` notes in `RecipeChatRecipeContext`.
- **S6 — Jon device-tests end to end** on a real NYT recipe: Load Comments → distinct proposed tips →
  accept/reject individually → Reader Feedback section shows distinct tips (not one blended paragraph) →
  the chat can cite them.

## Open questions (surface when the slice is drawn — not decided)

- **OQ1 — cap + Load-More bound.** Exact comment cap and how aggressively to bound Load-More clicks
  (runaway scrape vs. missing good tips). *Lean:* start ~20–30 / 3–5 clicks, tune from S2's real volume.
- **OQ2 — NYT selectors.** Sort control / Load More / comment nodes — unknowable until S2's fixture.
- **OQ3 — extractor home.** `YesChefCore` (host-testable, no network in tests) vs. app-layer — given the
  extractor is pure over a `Document`, *lean* Core (like the editorial-prose extractor); the interactive
  JS-injection playbook stays app-layer in `BrowserViews.swift`.
- **OQ4 — chat bucket (D7).** Feed `readerFeedback` notes as a distinct labeled bucket vs. folded into
  general notes. *Lean:* distinct bucket, so the assistant frames them as community tips, not recipe facts.
- **OQ5 — per-source prompt overrides.** Only NYT has comments today; keep the curation prompt global for
  now, revisit per-source once real-world performance is known (effort doc's out-of-scope call).
