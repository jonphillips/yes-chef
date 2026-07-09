# ADR-0024 — Editable proposal preview (the apply-action review becomes a roomy, editable sheet)

> **Vocabulary:** the **review card** is the staging surface (`ChatApplyReviewItem` →
> `ChatApplyReviewCard` in `RecipeChatWorkspace.swift`) that shows an LLM **proposal** before the
> commit tap — for the *string-summary* verbs: **Chef-It-Up**, **Serve-With**, **Make-ahead**,
> **complements**, and the **workbench "Create Working Recipe"** rationale/draft. This ADR replaces that
> cramped inline card with a **roomy, scrollable, editable sheet**, and threads the *edited* text through
> commit so the human is the final author. It does **not** touch the *side-by-side compare* review that
> [ADR-0023](ADR-0023-recipe-edit-proposals.md) D3 owns for canonical ingredient/method edits.

Status: **Accepted** — 2026-07-09 (Jon ratified; proposed 2026-07-08, dogfood pass 2026-07-08, Jon chose
the full "editable sheet" scope). **Extends [ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](ADR-0012-menu-actionable-chat.md)**
(the `(extract → review → commit)` apply-action and "model proposes, the tap writes"). **Coexists with
[ADR-0023](ADR-0023-recipe-edit-proposals.md)** — 0023's structured-delta verbs review via the Compare
diff surface (D3); *this* ADR is the review surface for the prose/list-summary verbs. A new consumer of
the [[chat-verb-commit-shapes]] axis; holds [[llm-curation-not-synthesis]]. Sync-safe by construction
(no schema; [ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

Dogfooding 2026-07-08, Jon hit the review card as a wall: the proposal renders as a **non-scrolling
block of `Text` in a fixed vertical band** wedged between the chat transcript and the input bar
(`ChatApplyReviewCard`, `RecipeChatWorkspace.swift` ~line 745). On a real proposal — e.g. the workbench
"Create Working Recipe" rationale — the content is taller than the band, so it's **unreadable and
uneditable**: you can only Discard or Commit sight-unseen.

Two problems, one root:

- **Readability.** The band is small and doesn't scroll; a longer-than-a-paragraph proposal is clipped.
- **Authorship.** The apply-action contract (ADR-0011/0012) is `(extract → review → commit)` where
  `commit` closes over a **pre-baked payload** (`AnyChatApplyAction` builds the review item from
  `extract`'s payload and `commit` calls `action.commit(payload)`). The human can accept or reject, but
  **cannot edit** before the write. For advisory prose (Chef-It-Up, Make-ahead, a serve-with note) the
  natural gesture is "yes, but tweak this line" — which the contract forbids.

The fix Jon chose: a **slide-up sheet** — roomy, scrollable, and **editable**, "as long as its
dismissability isn't fragile."

### Why this is a different surface from ADR-0023

ADR-0023 deliberately reviews the "Adjust this recipe" verb with a **structured current-vs-proposed
diff** (D3, reusing the Compare engine) because it edits **canonical ingredients and method**, where a
free-text box would be reckless. The verbs *this* ADR covers write **sidecar sections and advisory
lists** (Chef-It-Up / Serve-With / Make-ahead / complements) and the **workbench draft's prose** — where
the content *is* prose/a list and free-text editing is exactly the right affordance. So the app keeps
**two** review surfaces on purpose: the structured diff for canonical edits, the editable-prose sheet
for sidecar/advisory writes. Neither should be forced to serve the other's shape.

## Decisions

### D1 — The review is a presented sheet, not an inline band (ratified)

Replace the inline `ChatApplyReviewCard` with a **presented sheet** (slide-up) that is scrollable and
sized for reading. Dismissability must be **deliberate, not fragile**: explicit Commit / Discard
actions, and if the user drags to dismiss with unsaved edits, confirm before discarding (OQ1). Works in
both the compact (iPhone sheet) and iPad split-chat hosts (OQ3).

### D2 — The proposal is editable; commit writes the edited content (ratified — the authorship line)

The human edits the proposed text in the sheet, and the commit persists the **edited** content, not the
original extraction. This is the point: the model drafts, the human authors, the tap writes. It also
tightens the ADR-0011 "model proposes, the tap writes" invariant — now the tap writes *what the human
approved*, character-for-character.

### D3 — Contract change: thread the edited content through commit (ratified — the real work)

`ChatApplyReviewItem.commit` currently takes no payload — it captures a fixed value. Change the
review/commit contract so the **edited content flows into commit**. Concretely: `commit` (or a new
`commit(editedValue:)`) receives the sheet's current text/payload, and `AnyChatApplyAction`'s
`reviewItems`/`renderedSummary` bridge produces an **editable draft** rather than a frozen summary
string. Keep the extraction step unchanged.

### D4 — Editability is per commit shape, not one universal string (ratified)

Respect [[chat-verb-commit-shapes]]. A **prose blob** (Chef-It-Up, Make-ahead, workbench rationale)
edits as free text. A **list** (Serve-With items, complements) edits as a list — or, as a minimum viable
step, round-trips through an editable prose rendering that re-parses on commit. A **whole-recipe draft**
(workbench "Create Working Recipe") is the richest — at minimum its prose fields edit; structured-field
editing is deferred (S2 / OQ2). **Never** flatten a list or a structured payload into one opaque string
just to make it editable — that violates [[llm-curation-not-synthesis]].

### D5 — Scope is app-wide; the ADR-0023 compare verbs are explicitly out (ratified)

Every apply-action that surfaces a `ChatApplyReviewItem` — recipe chat, menu, meal-planner, workbench —
inherits the sheet, because they share the one `RecipeChatPanel`/apply-action machinery. The 0023
"Adjust this recipe" (overwrite / keep-as-variation) verbs are **out**: they own the Compare-diff review
surface and must not be rerouted here.

## Storage sketch

**None.** This is a review-surface + in-memory commit-contract change. No schema, no new table, no
column, no sync concern — sync-safe by construction.

## Cost, honestly — and the slice plan

The extraction and commit *destinations* already exist; what is new is the **sheet** and the
**contract thread** that lets edits reach the write. The risk is entirely in D3 (touching the shared
apply-action generics), so de-risk it on the simplest shape first.

- **S1 — editable sheet for single-string verbs.** Chef-It-Up, Make-ahead, workbench rationale: present
  the sheet, make the text editable, thread the edited string through commit. Proves the D3 contract
  change on the easy shape. Ships the readability win app-wide immediately (even list verbs get the
  roomy scrollable sheet; their editing lands in S2).
- **S2 — list / structured verbs.** Serve-With and complements get list-aware editing (or prose
  round-trip); the workbench draft gets at least prose-field editing. Keeps each commit shape intact.

## Open questions (surface when the slice is drawn — not decided)

- **OQ1 — dismissability.** Sheet drag-to-dismiss vs. explicit-buttons-only; how to avoid an accidental
  dismiss silently dropping edits. *Lean:* explicit Commit/Discard + confirm-on-dismiss-if-edited; no
  fragile swipe-to-lose-work.
- **OQ2 — structured-verb editing depth (S2).** How much structure to expose for Serve-With and the
  workbench draft. *Lean:* minimum viable — prose round-trip first, dedicated structured editors only if
  dogfooding asks.
- **OQ3 — iPad split-chat host.** Today the review lives *inside* the chat column band. Does the sheet
  present over the whole detail view, or as a panel within the chat column? *Lean:* a real sheet over the
  detail view in both compact and split; confirm it doesn't fight the `ChatWorkspaceDetent` drag.
- **OQ4 — edited-but-not-committed lifetime.** If the user edits, leaves the sheet open, and the context
  changes (navigates recipes), is the edit preserved or dropped? *Lean:* drop with the proposal (it's
  ephemeral, like ADR-0023's preview); do not persist an uncommitted edit.
