# Effort: ADR-0026 review-collection sheet — the universal LLM-evaluation surface

**Type:** A review-surface refactor. Hoist the whole multi-item LLM-review **collection** into the
slide-up sheet (ADR-0024's `.medium/.large` detent surface) and delete the cramped inline
`ChatApplyReviewList` band. No new verb, no schema — a presentation refactor over the existing in-memory
`ChatApplyReviewItem` collection.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Ready to dispatch — Dispatch 2 of the 2026-07-09 menu-planner pass.** Implements
[ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) (Accepted 2026-07-10), which extends
[ADR-0024](../decisions/ADR-0024-editable-proposal-preview.md) (the per-item editable sheet — the layer
below) and the [ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](../decisions/ADR-0012-menu-actionable-chat.md)
apply-action contract. Serves [ADR-0025](../decisions/ADR-0025-reader-comment-ingestion.md) (the other
multi-item consumer). **Separate dispatch on purpose** — it re-touches the shared apply-action
presentation state that Dispatch 1 (#136) also lightly touched, so it was held apart from that low-risk
fix bundle. **Do S1 first and confirm it subsumes S2 before building S2.**

**Read before starting:** [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md) in full (the
vocabulary banner + D1–D4 + the D4 adjust-verb resolution are load-bearing), then
[ADR-0024](../decisions/ADR-0024-editable-proposal-preview.md) (the per-item editable sheet this reuses
unchanged). Then, for the current shape:
- `YesChefApp/RecipeChatWorkspace.swift` — `RecipeChatPanel` holds the state to hoist:
  `stagedReviewItems` / `presentedReviewItem` / `committingReviewItemID` (~:233), `run(_:)` staging +
  auto-drill (~:404), `commit`/`discard` (~:426), the inline band to remove (`ChatApplyReviewList` ~:287
  / ~:824), the per-item review to **reuse** (`ChatApplyReviewSheet` ~:891, already renders editable text
  + `supportingEvidenceRows` + discard-confirm), the `.inline` card (`ChatApplyReviewCard` ~:1024), the
  `.sheet` row (`ChatApplyReviewRow` ~:855), the green confirmation (`ChatActionSummary` ~:1062).
- `YesChefPackage/Sources/YesChefCore/RecipeChat.swift` — `ChatApplyReviewItem` (~:594),
  `ChatApplyReviewPresentation { inline, sheet }` (~:665), the `AnyChatApplyAction` inits (~:682).
- `YesChefApp/RecipeDetailModel+Enrichment.swift` — the **adjust verb** (~:13, `.inline` at ~:78): its
  commit calls `presentAdjustmentReview()` (a launcher, not a write) → this is the D4 launch-only row.
- `YesChefApp/RecipeCaptureView.swift` — the **S2 target**: reader-feedback curation as a hand-rolled twin
  (`Section("Reader Feedback")` ~:272, `readerFeedbackReviewItem` ~:167, `readerFeedbackSheet` enum,
  `ChatApplyReviewSheet` reuse ~:148). **Not** in a chat panel — this is why S1's component must be
  host-agnostic.

**Build/verify (house constraint, [[lean-verification-default]]):** package logic via `swift build`; app
via `scripts/xcodebuild-summary.sh` with `-skipMacroValidation`, built once; `xcodegen generate` after
adding files; then `scripts/check-drift.sh`. **No simulator install** — Jon does the device pass (primary
on `iPad Pro 13-inch (M5)`, both orientations; also `iPhone 17 Pro` for the compact sheet). This is a
UI-presentation change with **real device-feel risk** the compiler can't catch (detent behavior, N→1
transitions, dismiss semantics) — call that out in the PR so Jon knows where to look.

---

## The invariant this preserves

**The model proposes; the human triages the whole set, then a tap writes** (ADR-0011/0012, ADR-0024). The
commit/discard contract on each `ChatApplyReviewItem` is **unchanged** — this effort only changes *where*
the collection and its per-item review are presented, never *what* commit does. Nothing is auto-committed;
the collection sheet just makes the triage loop roomy instead of cramped.

## Sync posture (ADR-0002)

**None.** No schema, no table, no column — a refactor over the in-memory `ChatApplyReviewItem` collection.
Sync-safe by construction.

## Slice plan

### S1 — collection sheet (prove on complements)

- Build a **host-agnostic** `RecipeCollectionReviewSheet` (name TBD) parameterized by
  `[ChatApplyReviewItem]` + `commit(_:approvedText:)` / `discard(_:)` / `discardAll` closures — **not**
  baked into `RecipeChatPanel`'s private `@State`. (S2's consumer has no chat panel; see below. This is
  the single most important S1 shape decision — get it wrong and S2 balloons.)
- The sheet presents the **collection** for N>1: a scrollable list of staged items (title + summary +
  per-item Discard), each drilling into its per-item review. **Reuse `ChatApplyReviewSheet` unchanged**
  for the per-item editable review — that already renders editable text, the "Full proposal" disclosure,
  and the `supportingEvidenceRows` provenance disclosure (OQ3 survives for free).
- **N=1 auto-drills** (OQ1): keep today's `run(_:)` behavior (`items.first { $0.presentation == .sheet }`
  auto-opens the per-item review, no list). The list appears only for N>1. Confirm the N→1 transition as
  the set is worked down to the last item reads cleanly.
- **Per-item commit/discard keeps the sheet open on the remainder** (D3); the sheet dismisses when the set
  is empty or on a deliberate dismiss. Dismissability stays non-fragile per ADR-0024 (confirm-on-dismiss
  if an item has unsaved edits — already in `ChatApplyReviewSheet`). Add a **discard-all** gesture.
- **Committed confirmation is per-item in the sheet** (OQ4): a lightweight per-item confirmation; the
  panel's green `ChatActionSummary` is redundant once the sheet owns the loop (decide whether to keep it
  for the last-item-resolved case or drop it).
- **Remove the inline `ChatApplyReviewList` band** — both cases. The `.sheet` case becomes the collection
  list; the `.inline` case (adjust verb, the **only** one) becomes a **D4 launch-only row** inside the
  sheet: a row whose action button ("Review Side by Side") delegates to the item's existing commit, which
  presents `RecipeAdjustmentReviewView`. **No editable-text review for `.inline` items** — the Compare-diff
  surface still owns the adjust review. The router picks the per-item affordance from `item.presentation`.
- After removal, the panel band's only jobs are: error banner, action-subject chip, Apply menu, input
  (see `RecipeChatPanel.body` ~:282–354).
- **Prove on the complements verb** (`MenuModels.swift:501` / `MealCalendarModels.swift:404` — the
  multi-item case Jon hit in the dogfood pass). Regression-check the single-item verbs (make-ahead,
  chef-it-up, serve-with) still auto-drill.
- OQ2 (iPad split-chat host) is the one still-open call: *lean* is a real sheet over the detail view in
  both compact and split, not fighting the `ChatWorkspaceDetent` drag. Flag in the PR for Jon's device
  pass.

### S2 — reader-feedback curation adopts the same sheet

- Point the `RecipeCaptureView` reader-feedback curation (the `Section("Reader Feedback")` twin) at the S1
  `RecipeCollectionReviewSheet`, replacing the hand-rolled row-list + `readerFeedbackSheet` enum. The
  curation items already carry provenance (`ReaderFeedbackTip.provenanceSummary` → the item's
  `supportingEvidenceRows`), so the shared per-item review renders them unchanged.
- **Only build S2 if S1's shape doesn't already subsume it** — confirm during S1 whether the host-agnostic
  component drops into the capture Form directly. If S1 delivered a genuinely reusable component, S2 is a
  small adoption; if not, stop and re-scope rather than forcing it.

## Out of scope

- The ADR-0023 "Adjust this recipe" *review* surface stays the structured Compare-diff
  `RecipeAdjustmentReviewView` (D4). Only its **launch card** moves into the sheet as a launch-only row —
  do **not** reroute the Compare-diff review itself here.
- No changes to any verb's extract/commit contract, no new `ChatApplyReviewItem` fields unless a launch-only
  row genuinely needs one (prefer deriving launch-only from `presentation == .inline` + the existing
  `commit`/`commitTitle`).
