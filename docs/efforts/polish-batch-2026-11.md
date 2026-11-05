# Effort — Polish batch, November 2026

Status: Ready
Summary: Three small fixes in one PR: recipe links inside the full-screen recipe cover, calendar complements that keep the
model's reason, and the Settings Sync sheet that slides back down. No schema or sync change.

Found in the Serve With device pass (ADR-0062), the `handoff-menu` device pass, and Jon's report of 2026-10-29.

## 1. Recipe links inside the full-screen cover

**The bug.** On Menu, tapping a linked Serve With chip closes the recipe cover and reopens it on the parent recipe. The linked
recipe never shows. Related Recipes and "Drafted From" links use the same handler, so they probably fail too.

**Likely cause, not yet tested.** `RecipeLibraryView.swift` ≈ line 91 presents `RecipeFullScreenCover` from `presentedRecipe`,
and `onRecipeSelected` swaps that value. `RecipeDetailView` builds its model once in `@State` (≈ line 45), so a new
`presentation` may not reach it. The split-view path handles the same swap with `.id(recipe.id)` (`AppMainLayout.swift` ≈ line
353), and the cover has no `.id`. If that's the cause, `.id(presentation.id)` on the `RecipeDetailView` in the cover may be the
whole fix. If it isn't, find the real cause and say what it was in the PR body.

**Keep:** the smallest fix. Done still closes the cover, and there's no back stack to the parent recipe in this batch.

## 2. Calendar complements keep their reason

**The bug.** The chat explains why each dish fits the meal, but the staged complement holds only the dish name, because
`MealPlanHandoffContext.complementPrompt` (`AIHandoffContext.swift` ≈ line 300) asks for "exactly two lines each". This is the calendar's copy of the bug [ADR-0012 Amendment 2](../decisions/ADR-0012-menu-actionable-chat.md) fixed
for Menu. Follow what `MenuComplementSuggestion` does.

1. **`MealPlanComplementSuggestion`** gains an optional `body`. `rendered`, `editableReviewText` and
   `applyingEditableReviewText` carry it as everything after the placement line, and deleting those lines in review clears it.
2. **Hand-off parser:** lines after the placement line become the body. Stop reporting them in `unparsedBlocks`
   (`MealPlanComplement.swift` ≈ line 111). A two-line block stays valid, with no body.
3. **`addComplementItem`** (`MealCalendarCore.swift` ≈ line 367) stores the body in `notes` instead of `nil`. The calendar row
   already shows `displayNotes`.
4. **Ask now:** add `body` to the client's JSON format and `parse`.
5. **Wording, in both the calendar and Menu hand-off prompts and in both Ask now instructions:** the third part is a short
   reason the dish fits this meal, plus any useful ingredient or method detail, and it's optional. Remove "exactly two lines".

**No contract bump:** `AIHandoffReturnContract` has no complement stanza, and old two-line replies still parse. Say so in the PR
body if you find otherwise.

**Tests, in `MealPlanComplementTests`:** replace the surplus-lines half of
`handoffParserKeepsUnknownSlotsAndSurplusLinesAsReviewEvidence`; unknown slots stay review evidence. Add a body round trip
through review text, clearing it in review, the Ask now `parse`, and `addComplementItem` writing `notes`.

## 3. Settings Sync sheet

**The bug.** Tapping the Sync row often shows the sheet sliding up and straight back down, so it takes a second tap (long-standing).

**Likely cause.** `SyncStatusSection` hangs `.sheet(isPresented:)` on a `Section` inside the Settings `Form`
(`SyncStatusSection.swift` ≈ line 38). The row re-renders whenever `SyncHealthModel` ticks, which can dismiss the sheet.

**Fix:** move the state and the `.sheet` out to the `Form` in `SettingsViews.swift` (≈ line 51), and leave the row as a plain
button. Keep `SyncStatusDetailView` as it is.

## Out of scope

The calendar day plan (ADR-0034 Amendment 1), sync status accuracy, and the other candidates in `open-questions.md`.

**Verification:** `scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator, because this touches
app code ([`verification.md`](../verification.md)). Threads 1 and 3 have no automated coverage, so the device gate is their
evidence. State that in the PR body.

**Done when:** all three threads are in one PR, the tests pass, and closeout runs (ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

On iPad and iPhone: from a Menu, open a recipe and tap a linked Serve With chip, a Related Recipes link and a "Drafted From"
link; each shows the linked recipe. Hand off a calendar Complement and let it stage or paste it back: the review shows each
dish's reason, and after adding, the reason shows on the calendar row. Do the same from a Menu. Tap the Settings Sync row
several times, including while sync is running: the sheet opens on the first tap and stays up.

## Merge

The PR owes a device gate, so Jon merges (`agent-collaboration.md`, ADR-0005 D9).
