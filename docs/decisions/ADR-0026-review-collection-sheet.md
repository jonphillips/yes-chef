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

Status: **Accepted** — 2026-07-10 (Proposed 2026-07-09). Dogfood pass 2026-07-09, menu-planner; Jon flagged
"the review area is too small" and asked that the NYT-comment-style slide-up sheet become the *universal*
LLM-evaluation surface. Accepted after the 2026-07-10 architect pass reconciled the D1/D4 adjust-verb
collision (→ launch-only row) and resolved OQ1/OQ3/OQ4 against current code; build brief:
[`efforts/adr-0026-review-collection-sheet.md`](../efforts/adr-0026-review-collection-sheet.md). **Extends [ADR-0024](ADR-0024-editable-proposal-preview.md)** (which made the per-item review a
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
written" surface.

The **"Adjust this recipe"** verb (ADR-0023) is the sole `.inline`-presentation consumer, and its
per-item review still belongs to the structured **Compare-diff** surface (`RecipeAdjustmentReviewView`),
**not** to this sheet's editable-text review — per ADR-0024 D5. But that verb currently renders as a
*launch card* wedged into the very `ChatApplyReviewList` band D1 removes (its commit doesn't write; it
calls `presentAdjustmentReview()` to open the Compare-diff view). Removing the band without a home for it
would strand it.

**Resolution (decided 2026-07-10):** the adjust verb appears in the collection sheet as a **launch-only
row** — no editable-text review; its primary action ("Review Side by Side") opens the Compare-diff
`RecipeAdjustmentReviewView` exactly as today. So the collection sheet lists *everything the LLM proposed*
(honoring the "one place to see it all" goal), while the Compare-diff still **owns** the adjust review
(honoring D4's intent). The sheet therefore supports two per-item modes: **editable review** (default,
`.sheet` items) and **launch-only** (`.inline` items — a row whose action delegates to the item's commit,
which itself presents another surface). No apply-action's commit contract changes; the router just picks
the row's per-item affordance from `presentation`.

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
  remainder and a discard-all. Remove the inline `ChatApplyReviewList` band (both its `.sheet`
  **and** `.inline` cases — the `.inline` case becomes the D4 launch-only row inside the sheet). Prove it
  on the **complements** verb (the multi-item case Jon hit).
  **Build it as a reusable component** (`RecipeCollectionReviewSheet` or similar) parameterized by
  `[ChatApplyReviewItem]` + commit/discard/discard-all closures — **not** baked into `RecipeChatPanel`'s
  private `@State` — because S2's consumer does not host a chat panel (see next).
- **S2 — reader-feedback curation adopts it.** Point the ADR-0025 curation review at the same collection
  sheet. **Note:** that curation lives in `RecipeCaptureView`'s `Form` (a hand-rolled twin: a
  `Section("Reader Feedback")` of proposal rows, each opening a `ChatApplyReviewSheet` via the
  `readerFeedbackSheet` enum), **not** in `RecipeChatPanel`. So S2 hosts the S1 component directly in the
  capture view — which is only cheap if S1 delivered a genuinely host-agnostic component (hence the S1
  requirement above). Do S2 only if S1's shape doesn't already subsume it — confirm during S1.

## Open questions

Resolved against current `main` (`aaabc17`) during the 2026-07-10 architect pass — kept here as
confirm-don't-re-litigate notes for the build, except OQ2 which stays a lean-but-open call:

- **OQ1 — list vs. auto-drill for N=1. → Resolved (preserve current behavior).** Today `run(_:)` sets
  `presentedReviewItem = items.first { $0.presentation == .sheet }`, so a single `.sheet` result already
  auto-opens its editable review with no list. Keep that: N=1 skips the list; the list appears only for
  N>1. Confirm the N→1 transition (committing/discarding down to the last item) reads cleanly.
- **OQ2 — iPad split-chat host.** ADR-0024 OQ3 already asked whether the sheet presents over the whole
  detail view or within the chat column; the collection sheet inherits that answer. *Lean:* a real sheet
  over the detail view in both compact and split; must not fight the `ChatWorkspaceDetent` drag. (Still
  the one genuinely open call.)
- **OQ3 — provenance rows. → Resolved (already rendered).** `ChatApplyReviewSheet` already renders the
  per-item `supportingEvidenceRows` disclosure (`RecipeChatWorkspace.swift`). Reuse that per-item review
  view unchanged and the disclosure survives the hoist for free.
- **OQ4 — committed-summary feedback. → Resolved (per-item in the sheet).** Today the panel shows a green
  `ChatActionSummary` after a commit. Keep a lightweight per-item confirmation in the sheet; the panel
  summary is redundant once the collection sheet owns the loop.

## Related

- ADR-0024 (per-item editable sheet — the layer below this), ADR-0011/0012 (the apply-action contract),
  ADR-0025 (reader-feedback curation — the other multi-item consumer), ADR-0020 (chat UI harvest),
  ADR-0023 (the *separate* Compare-diff review surface, explicitly out of scope).
- Memory: [[chat-verb-commit-shapes]], [[llm-curation-not-synthesis]].
