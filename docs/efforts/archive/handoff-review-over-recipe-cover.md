# Effort — Show the hand-off review over the recipe cover

Status: Ready
Summary: A return pasted into a recipe opened from the Calendar, a Menu or Power Browser opens no review
until the cover closes. Host the hand-off review sheets with the gated presenters, so they open from the cover;
and an unmatched no-row paste writes its ledger row only when the cook commits.
Related: [archive/dogfood-fixes-batch-1.md](dogfood-fixes-batch-1.md) (the gated presenters, PR #58) ·
[ADR-0038 Amd 8](../../decisions/ADR-0038-external-llm-handoff.md) (ledger row at commit) · Amd 6 / Amd 7 (the
unmatched routing this leaves in place)

App-layer only. No schema, no migration, no change to how a return is routed. Steps 1–3 are view wiring; step 4
changes when one kind of ledger row is written.

## The bug

On 2026-11-01 Jon opened a recipe from the Calendar, pasted a revision brief into its toolbar **Paste**, tapped
**Review Anyway** on the unmatched alert, and nothing appeared. When he closed the recipe, the review sheet popped
up.

A recipe opened from the Calendar, a Menu, Power Browser, or a workbench link shows in the root
`.fullScreenCover(item: $presentedRecipe)` (`RecipeFullScreenCover`). The hand-off review sheets
(`handoffReviewCoordinator.review` and `.adjustmentReview`) are attached only to `RecipeLibraryView`'s root,
beneath that cover. So the coordinator's `review` is set, but the root can't present over its own cover, and
the sheet waits until the cover closes. A matched paste fails the same way; the alert isn't the cause.

From the Library, recipe detail is inline rather than in the cover, which is why paste has worked there. The
gated presenters in `AppDestinationPresentation.swift` (PR #58, 2026-07-02) solved this for the meal editor,
grocery and recipe-detail destinations: attached at the root gated on
`presentedRecipe == nil && presentedCookSession == nil`, and again inside `RecipeFullScreenCover`. The hand-off
review sheets arrived later (ADR-0038 S2, 2026-07-13) and were attached to the root only.

## Shape: one PR

1. **`handoffReviewDestinations(coordinator:isPresentationEnabled:)`** in `AppDestinationPresentation.swift`,
   following the existing modifiers. Move both sheets into it unchanged: the `review` sheet with
   `id: \.handoffID` and its `onDismiss` that calls `presentPendingAdjustmentReviewAfterReviewDismissal()`, and
   the `adjustmentReview` sheet. Use `gatedBinding` for both items.
2. **Attach it** at the root, gated like its neighbours, and inside `RecipeFullScreenCover`, ungated.
3. **Audit the other paste doors that live inside a modal**, and give each one a host. Exactly one host is
   enabled at a time, and it's the topmost modal that holds the door. Check at least these:
   - the root `.sheet(item: $recipeModel.destination.workbench)`, which hosts `WorkbenchDetailView` and its
     Hand off / Paste menu;
   - the recipe's **Manage Variations** sheet, whose variation context menu has a Paste
     (`RecipeVariationPromotionPresentation`);
   - `CookSessionFullScreenCover`, which has no paste door today; confirm it has none.

   Report the list in the PR, with each door's host.
4. **Ledger row at commit (ADR-0038 Amd 8).** This applies when *Review Anyway* is tapped on a paste with no
   token, or a token with no stored row (`reviewUnmatchedResult`'s `storedHandoff == nil` branch).
   - **Stage read-only.** Add a `HandoffAppOperations` entry beside `stageReviewForKnownSource`. It builds the
     same unsaved `AIHandoff` from `source.metadata(handoffID:)`, including `dayOffset`, `variationID` and
     `regenerates`. It strips the contract marker and the token, and stages in a `database.read` through
     `AIHandoffIntentImport.stageOnboardReview(handoff:result:in:)` or an equivalent. It does no insert and no
     `markImported`, and returns the unsaved handoff with the review. Retire `stageReviewForKnownSource` if
     nothing else calls it.
   - **Write the row at commit.** `HandoffReviewCoordinator.present` takes an optional pending `AIHandoff`. Every
     write that commits content from a review inserts that row, marked imported at commit time, **inside that same
     `database.write`**, then clears it. That covers every `commit*` path, `overwriteAdjustmentButtonTapped`,
     `keepAdjustmentAsVariationButtonTapped`, `saveScopedVariationButtonTapped` and the learnings commits. Use one
     private helper, and make it idempotent, since one review can commit more than once (a plan, then its
     learnings).
   - **Keep the pending row across the adjustment hop** (brief review → draft → adjustment review):
     `finishDraftingRecipeAdjustment` setting `review = nil` must not clear it. `present` (a new review),
     `discard` and `discardAll` clear it.
   - **Leave the other paths alone.** The matched path and the cross-item path pass `nil`. Reader feedback keeps
     its current path.
5. **No other behavior change.** Routing, the unmatched alert and its copy, and the matched and cross-item ledger
   writes stay as they are. A new-recipe JSON return pasted inside the cover still goes to Create Recipe, which
   switches the section underneath the cover. Leave that alone, and say in the PR whether its toast shows over the
   cover.

## Done when

- Both review sheets present from the gated modifier, and nothing else in `RecipeLibraryView` presents them.
- App tests (`YesChefAppTests/`, beside `HandoffSectionRoutingTests` and `AIHandoffRecipePasteRoutingTests`):
  - Review Anyway on a no-token paste, and on a token-with-no-row paste, each opens a review and leaves **no
    `aiHandoffs` row**;
  - committing that review writes exactly one row, imported, with the door's `sourceType` / `sourceID` /
    `taskType` / `variationID` / `dayOffset`; a second commit from the same review still leaves one row;
  - a recipe-adjustment review keeps its pending row through drafting and writes it on overwrite;
  - discarding the review writes no row;
  - matched, cross-item and reader-feedback pastes behave exactly as before, and existing tests pass, updated
    only where they asserted a row at stage time.
- The completing PR appends this gate to `device-passes.md`:
  > **Hand-off review over the recipe cover** ([effort brief](efforts/archive/handoff-review-over-recipe-cover.md),
  > schema-free). On the iPad, open a recipe from the Calendar and paste a return for it into the toolbar Paste:
  > the review opens over the recipe, matched and unmatched (Review Anyway) alike. Draft a revision through to
  > the adjustment review, and commit it. Repeat from a Menu, from the workbench sheet, and from a variation's
  > Paste in Manage Variations. From the Library, paste still works as before. Paste a return with its
  > `YC-HANDOFF:` line deleted, tap Review Anyway, back out, and paste it again: it still opens.
- Closeout per ADR-0005 D16 (`jon-platform/scripts/closeout`), advancing `NEXT_UP.md` per ADR-0005 D12.

## Verification

Per `docs/verification.md`: `scripts/check-drift.sh`, the generic iOS build, and **`YesChefTests`** (this changes
app model code). Run every build and test elevated from the first attempt; a
sandbox-shaped failure gets one elevated rerun; fail fast on an elevated failure. No simulator installs or
screenshots: presentation is checked on Jon's device pass.
