# ADR-0026 — The LLM-review collection is a sheet (the universal "evaluate content from the LLM" surface)

> **Vocabulary:** an apply-action's `extract` step can return **one or many**
> `ChatApplyReviewItem`s — one for the single-string verbs (Chef-It-Up, Make-ahead, prep plan), *many*
> for the list verbs (**complements** returns one item per suggested dish; reader-feedback curation
> returns one per curated tip). [ADR-0024](ADR-0024-editable-proposal-preview.md) made the **per-item**
> review a roomy, editable **sheet**. This ADR fixes the layer above it: the **collection** of staged
> items — the triage list itself — still lives in the cramped bottom band of the chat panel
> (`ChatApplyReviewList` in `RecipeChatWorkspace.swift`), and the sheet only ever presents **one** item
> at a time. This ADR moves the **whole review collection** into the slide-up surface, making it the
> single, universal "evaluate content from the LLM" interface across every consumer.

Status: **Proposed** — 2026-07-09 (dogfood pass 2026-07-09, menu-planner; Jon flagged "the review area is
too small" and asked that the NYT-comment-style slide-up sheet become the *universal* LLM-evaluation
surface). **Extends [ADR-0024](ADR-0024-editable-proposal-preview.md)** (which made the per-item review a
sheet) and **[ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](ADR-0012-menu-actionable-chat.md)**
(the `(extract → review → commit)` apply-action). **Serves [ADR-0025](ADR-0025-reader-comment-ingestion.md)**
— reader-feedback curation is the other multi-item review and inherits this surface. A consumer of the
[[chat-verb-commit-shapes]] axis; holds [[llm-curation-not-synthesis]] (the collection triages **distinct**
items, never a flattened merge). Sync-safe by construction (no schema; [ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

ADR-0024 solved the **single proposal**: tap a one-string verb, get a scrollable editable sheet. But the
multi-item verbs still triage in a wall. Today (`RecipeChatWorkspace.swift`):

- `run(_:)` stages the returned items into `stagedReviewItems` and auto-presents **only the first**
  `.sheet`-presentation item (`presentedReviewItem = items.first { $0.presentation == .sheet }`).
- The **rest** render as `ChatApplyReviewList` — a `VStack` wedged into the ~120pt band between the chat
  transcript and the input bar. For "What complements this?" that band holds a stack of `Note: …` rows,
  each with a tiny two-line summary and Discard / Review buttons (Jon's dogfood screenshot #3).
- So a multi-suggestion result is triaged in a cramped strip, one roomy sheet reachable per row, with no
  single place that shows "here is everything the model proposed, work through it."

The complaint is precise: **the review *area* is too small**, and the fix Jon named is the one that
already worked for NYT "Most Helpful" comment curation — a **slide-up sheet** — promoted to be the
**universal** surface for evaluating anything the LLM returns for commit.

### Why "collection sheet", not just "present the first item"

The unit of review for a list verb is the **set**, not each item in isolation. Complements arrive as a
handful of candidate dishes; reader-feedback curation as a handful of tips. The human wants to see them
together, keep some, drop some, edit one, and commit — a triage loop. A per-item sheet that you must
re-open row by row from a cramped list is the wrong shape. The collection **is** the review.

## Decisions

### D1 — The review collection is presented as a sheet, not an inline band

When an apply-action stages **one or more** review items, present them in a **slide-up sheet** (the same
`.medium/.large` detent surface ADR-0024 established), not in the chat panel's bottom band. Remove the
inline `ChatApplyReviewList` from the panel; the band's only job becomes the error banner + the
action-subject chip + the Apply menu + the input.

### D2 — The sheet lists the collection and hosts per-item review in one place

The sheet shows the **collection**: a scrollable list of staged items (title + summary + per-item
Discard), and drilling into an item gives the **ADR-0024 editable review** (roomy, scrollable, the edited
text threads through commit). A single item skips straight to its editable review (no pointless
one-row list). The human works the whole set from this one surface — keep, edit, discard, commit —
without returning to the cramped panel.

### D3 — Commit / discard semantics are per item; the sheet survives until the set is resolved

Committing or discarding one item removes it from the collection and leaves the sheet open on the
remainder (so a 4-suggestion complement result is worked to zero without re-invoking the verb). The sheet
dismisses when the set is empty or the human dismisses it deliberately; **dismissability stays
non-fragile** per ADR-0024 OQ1 (explicit actions; confirm-on-dismiss if an item has unsaved edits).
Discarding the whole set is one gesture.

### D4 — Scope is every apply-action consumer; this is the one LLM-evaluation surface

Recipe chat, menu, meal-planner, workbench, **and** the ADR-0025 reader-feedback curation review all
surface `ChatApplyReviewItem`s through the shared `RecipeChatPanel`/apply-action machinery, so they all
inherit the collection sheet. There is **one** universal "evaluate content from the LLM before it's
written" surface. (The ADR-0023 "Adjust this recipe" verbs remain **out** — they own the structured
Compare-diff review, per ADR-0024 D5, and must not be rerouted here.)

## Storage sketch

**None.** A review-surface refactor over the existing in-memory `ChatApplyReviewItem` collection. No
schema, no table, no column, no sync concern — sync-safe by construction.

## Cost, honestly — and the slice plan

The per-item editable review already exists (ADR-0024). What is new is **hoisting the collection into the
sheet** and moving the staging/commit/discard loop out of the panel band. The risk is in the shared
presentation state (`stagedReviewItems` / `presentedReviewItem` in `RecipeChatWorkspace.swift`), so this
is **one focused dispatch**, not bundled with the low-risk dogfood fixes.

- **S1 — collection sheet.** Present staged items in the slide-up sheet: a list-of-items mode plus the
  ADR-0024 per-item editable review, with per-item commit/discard that keeps the sheet open on the
  remainder and a discard-all. Remove the inline `ChatApplyReviewList` band. Prove it on the
  **complements** verb (the multi-item case Jon hit).
- **S2 — reader-feedback curation adopts it.** Point the ADR-0025 curation review at the same collection
  sheet so the two multi-item reviews share one surface (only if S1's shape doesn't already subsume it —
  confirm during S1).

## Open questions (surface when the slice is drawn — not decided)

- **OQ1 — list vs. auto-drill for N=1.** A single-item result should skip the list and open its editable
  review directly (today's `items.first { … }` behavior). Confirm the transition reads cleanly for the
  N→1 case as items are committed/discarded down to the last one.
- **OQ2 — iPad split-chat host.** ADR-0024 OQ3 already asked whether the sheet presents over the whole
  detail view or within the chat column; the collection sheet inherits that answer. *Lean:* a real sheet
  over the detail view in both compact and split; must not fight the `ChatWorkspaceDetent` drag.
- **OQ3 — provenance rows.** Reader-feedback curation items carry supporting-evidence / provenance
  (ADR-0025); the collection sheet must preserve the per-item `supportingEvidenceRows` disclosure the
  ADR-0024 sheet already renders. Confirm it survives the hoist.
- **OQ4 — committed-summary feedback.** Today the panel shows a green `ChatActionSummary` after a commit.
  Decide whether that confirmation lives in the sheet (per item) or still in the panel after the set
  resolves. *Lean:* keep a lightweight per-item confirmation in the sheet; the panel summary is
  redundant once the collection sheet owns the loop.

## Related

- ADR-0024 (per-item editable sheet — the layer below this), ADR-0011/0012 (the apply-action contract),
  ADR-0025 (reader-feedback curation — the other multi-item consumer), ADR-0020 (chat UI harvest),
  ADR-0023 (the *separate* Compare-diff review surface, explicitly out of scope).
- Memory: [[chat-verb-commit-shapes]], [[llm-curation-not-synthesis]].
