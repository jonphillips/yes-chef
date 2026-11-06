# Effort — Create Recipe actions, Calendar review edits, and Source navigation

Status: Ready
Summary: Fix three reported defects in one schema-free dispatch: From Chat Open sometimes discards, Calendar complement edits made during proposal review disappear after adding, and Source navigation repeatedly reopens after Back.

Jon requested architect planning on 2026-11-06 and confirmed the Calendar edits were made in proposal review before adding.
This is one dispatch with three acceptance tracks; it is not a redesign of chat or the recipe editor.

Related: [Chat access](archive/chat-access-mcp.md), [previous complement-body fix](archive/polish-batch-2026-11.md#2-calendar-complements-keep-their-reason), [ADR-0024](../decisions/ADR-0024-editable-proposal-preview.md), [ADR-0026](../decisions/ADR-0026-review-collection-sheet.md), [standing guards](../standing-guards.md).

## S1 — From Chat Open must never invoke Discard

**Evidence.** `ChatAccessInboxView.swift` puts Open and Discard together in a Form row, without explicit button styles;
return rows repeat this with Open, Copy, and Discard. The host is `CreateRecipeView`. This is a strong suspect for shared
row activation, not a reproduced diagnosis. `ChatAccessInboxModel.workingIDs` prevents concurrent operations but cannot
correct a wrong action that wins the race. Successful Open intentionally consumes the staged inbox item, so disappearance
alone is not proof of deletion: the content must appear in the draft or appropriate review.

**Build.** Give each action independent button activation and clear hit targets, scoped to both inbox row variants.
Use explicit system button styles; do not add gesture delays, arbitrary spacing, or a global Form style as a workaround.
Retain download/busy disabling, inaccessible-return restrictions, staging-before-claim behavior, and error recovery.
Opening must stage the selected content; Copy must not claim it; only an explicit Discard action may discard it.

**Acceptance.** Open, Copy, Discard, and whitespace between controls do not activate another action. Repeated Open taps
cannot discard content. Retain `ChatAccessInboxModelTests` coverage for staging, claiming, and failure preservation;
add behavior tests only where behavior changes. Model tests do not prove hit-testing: Jon's device gate is required.

## S2 — Preserve Calendar complement edits from review through Edit

**Evidence.** The earlier complement-body fix is already present. `HandoffComplementReview.mealPlanComplementReviewItems`
and `MealCalendarModel.makeApplyActions` both pass approved text into `applyingEditableReviewText`; the repository writes
`suggestion.body` to `MealPlanItem.notes`, and Calendar Edit seeds its Details from those notes. Therefore, merely adding
body support or changing row truncation would repeat completed work and would not diagnose this report.

The remaining boundaries are `RecipeCollectionReviewSheet` → `ChatApplyReviewSheet` → the real commit closure →
`MealPlanComplementSuggestion.applyingEditableReviewText` → `MealCalendarRepository.addComplementItem` → fresh Calendar
rows and `editButtonTapped`. The parser currently trims/removes empty lines and unconditionally consumes the first two
nonempty lines as title/placement, even when the placement line is invalid. That is a concrete fidelity risk, but it is
not yet established as the cause of Jon's missing additions.

**Build.** First reproduce with a distinctive addition in the proposal's note body, then identify the first boundary
where it disappears. Cover both external handoff review and Ask now, which share the review surface but have different
commit wiring. Exercise a single proposal and a collection, a previously empty and nonempty body, appended paragraphs,
and saving immediately while the keyboard remains up. Check returning to the collection and accepting after editing
if that sequence exposes the loss. Fix the demonstrated boundary; do not assume an old captured suggestion, parser,
or observation bug without evidence.

Approved body text must survive commit and a fresh database read, and appear when Calendar Edit reopens. Preserve
paragraph breaks and intentional body clearing. If title/placement are editable, malformed metadata must not silently
eat body lines: retain the text for correction and surface a validation issue, or keep metadata separately structured
from the body. Keep the handoff's original date authoritative. Scope any parser adjustment to the confirmed loss and
retain old two-line handoff compatibility; no new external return format or contract version.

**Regression tests.** Drive the actual app review-item builders and their commit closures into an isolated database,
then reload Calendar and inspect the Edit draft. Assert the added text, title, date, slot, and unrelated rows are intact.
Add focused Core cases if parsing/storage changes. Existing Core tests that construct their own review closures do not
certify app wiring. If reproduction remains elusive, retain the evidence and ask the architect in the implementation
PR for the missing sequence; do not mark S2 fixed on a passing synthetic round trip alone.

## S3 — Source Back returns once and stays back

**Evidence.** `RecipeEditorFields` uses an implicit destination `NavigationLink` in its lazy Form content. Source edits
mutate the same draft that renders the link summary. Create Recipe uses the existing stack in `AppMainLayout`.
No code explicitly requests a repush; the root cause remains unconfirmed.

**Build.** Trace the push/pop lifecycle before selecting the fix. Preferred narrow direction: one explicit Source case
in the editor model's destination state, with destination registration on a stable enclosing view outside lazy Form
content. Back clears that state, and ordinary draft changes cannot present Source. Keep the existing stack and shared
draft, using the same presentation contract in Create Recipe and existing-recipe editing. No nested NavigationStack,
UIKit navigation-controller workaround, timing delay, or model recreation. Ensure reset/replacement of a create draft
cannot leave an active Source route. If evidence supports a smaller fix, explain it in the PR.

**Acceptance.** Enter/edit Source, Back, and remain at the recipe editor. Reopen with edits intact. Repeat with back
button and swipe-back, keyboard dismissal, inbox updates, and both new/existing recipes. Save/reopen preserves source
fields; cancelling an existing-recipe edit does not persist them. Add app model regression coverage for any new route
state, dismissal, reset, and draft preservation; actual navigation still requires Jon's device pass.

## Verification and completion

No schema, migration, sync-engine, extraction-strategy, or persistent-model changes are authorized by this brief.
Do not attempt recovery of previously lost text without a surviving source and a separate decision.

- Run the focused regression tests, then `scripts/check-drift.sh`, the generic device build, and the `YesChefTests`
  app target per [verification.md](../verification.md), elevated from the first attempt.
- Explain each demonstrated cause and correction in the PR, distinguishing model evidence from UI evidence.
- Closeout (ADR-0005 D16), with one owed device gate covering all three acceptance tracks on iPad and iPhone:
  independent From Chat actions; edited complement text visible after adding and reopening Calendar Edit; and Source
  Back remaining at the editor with draft changes preserved. Jon owns device interaction; no agent screenshot work.
- The implementation PR escalates to Jon for merge while that device gate remains owed.

## Dispatch ledger

- [ ] Dispatch 1 — S1 + S2 + S3, one implementation PR.
