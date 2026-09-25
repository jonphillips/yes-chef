# Effort — Multi-admit: save every recipe in a multi-recipe Create Recipe session

Status: Implemented 2026-09-25; two-app device pass is owed with Cockpit S-join. Schema-free.
Summary: When extraction finds N recipes, let the cook save any number of them from the one Create Recipe
session instead of losing the rest after the first Save. A Cockpit referral then returns **one** verdict
listing every saved recipe.
Related: [`cockpit-find-handoff-receiver.md`](cockpit-find-handoff-receiver.md) (the receiver this extends;
multi-admit was its named out-of-scope follow-up) ·
[ADR-0058](../decisions/ADR-0058-cockpit-find-referral-transport.md) (transport, D5 process-death) ·
[ADR-0053](../decisions/ADR-0053-create-recipe-destination.md) (Create Recipe destination) · Cockpit's
Gate 5 slice plan (`/Users/jon/code/cockpit/docs/milestones/M6-gate5-find-handoff-slice-plan.md`, I3 +
"Multi-admit … Cockpit already consumes it")

## The problem (Jon, 2026-09-25)

A Cockpit email with two recipes extracts to two candidates. Jon saves one, and the other is gone: there is
no way back to it. That comes from three v1 decisions in #322/#325:

- **The review UI is pick-one-of-N.** `CreateRecipeCandidateSection` (`YesChefApp/CreateRecipeView.swift`) says
  "Choose one recipe to review."
- **Save discards the session.** `RecipeLibraryView.recipeCreated` replaces `createRecipeModel` with a fresh
  `CreateRecipeModel()` and switches to the library. The other candidates and the source text go with it.
- **The referral closes on the first save.** `CreateRecipeCoordinator.saveButtonTapped` → `resolve` emits a
  verdict with one `.admitted` and clears `referralID`.

The workaround (copy the source text before saving, then re-paste and extract again) loses provenance, and
Cockpit never hears about the second recipe.

## The contract does not change

- **The wire format is unchanged.** `FindVerdict.outcomes` is already set-valued, and Cockpit's I3 "consumes
  any N admitted + M declined."
- **The only semantic change:** a complete verdict may now carry **several** `.admitted` outcomes, not one.
  Unsaved candidates are still **not reported** (the same as S-y2). A verdict with ≥1 admitted resolves the
  Find as handed off, exactly as before.
- **⚠️ Exactly one verdict per referral stays load-bearing.** Cockpit's S-c2 drain is idempotent: a second
  verdict for an already-resolved referral is **deleted and ignored**. So you must **not** emit a verdict per
  save. Collect the admitted recipes and emit **once**, when the referral closes (D2).

## Decisions

**D1 — Save keeps the session open while unsaved candidates remain.** This applies to every multi-candidate
session (paste, Shortcuts, or referral), not only referrals. It is a Create Recipe behavior.
- After a successful save:
  - if unsaved candidates remain: stay on Create Recipe, mark the saved candidate, and **auto-select the next
    unsaved candidate in list order**;
  - if none remain, or there was only one candidate: close as today (`onSaved` → library, select the recipe).
- **A saved candidate cannot be selected again.** Show it with a "Saved" label or checkmark and make its row
  inert. Saving it a second time would write a duplicate recipe.
- **The Save gate** (`isSavingDisabled`) also blocks when the selected candidate is already saved.
- **A Done affordance** appears once ≥1 candidate is saved and others remain. Done closes the session the way
  the last save would (library, select the most recently saved recipe). **Clear** keeps its current meaning,
  and neither Done nor Clear un-saves anything.
- **Footer copy:** drop "Choose one recipe to review." Say instead that each recipe can be reviewed and saved in
  turn, and that the original text stays above.

**D2 — The coordinator collects admitted recipes and emits one verdict when the referral closes.**
- Hold `admittedRecipeIDs: [Recipe.ID]` for the live referral. A successful save **appends** to it. It does
  **not** clear `referralID` while unsaved candidates remain.
- **The referral closes on** (each emits exactly once, then clears the referral state):
  - the last candidate saved, or a single-candidate save (today's path);
  - Done;
  - Clear, or discarding an incoming offer (today's `declineReferral` call sites);
  - leaving Create Recipe (`abandonOutstandingReferral`);
  - a superseding intake (`stage(text:)` / `stage(referral:)`);
  - relaunch reconcile (D3).
- **What the closing verdict contains:**
  - ≥1 admitted → `FindVerdict(referralID:, outcomes: admitted.map { .admitted(FindRecipeRef($0)) })`;
  - 0 admitted → today's behavior, unchanged (`.dismissed`, or `noRecipeFound` / `extractionFailed` from
    extraction).
- **Rework `declineReferral` into this close step instead of adding a parallel path.** Every existing call
  site ("the cook walked away") becomes "close with whatever was admitted": dismissal with 0 saved, admission
  with ≥1.
- **Keep the in-flight-save handling** (`savingReferralID` / `savingReferralWasAbandoned`) in the new shape.
  If the referral is abandoned while a save is in flight, the save finishes:
  - success → it is included in the closing verdict;
  - failure → close with the admitted-so-far (dismissed if none).

**D3 — Process-death durability covers the admitted set (ADR-0058 D5).**
- **Why:** today relaunch reconcile emits `.dismissed` for any outstanding id. After a partial multi-save, that
  would tell Cockpit "not admitted" for recipes that *are* in the library. The Find turns re-sendable, and a
  re-send comes back `duplicate`, a false strike against the hint (Cockpit I2/I3). This is a correctness bug in
  the naive version, not polish.
- **Persist admitted ids next to the outstanding referral id** in `UserDefaults`: device-local, ids only, and
  written on each successful save.
- **Clear both together** when the closing verdict is written. Keep today's rule: a write failure leaves them
  in place.
- **Relaunch reconcile:**
  - persisted admitted ids non-empty → emit the admitted verdict;
  - otherwise → `.dismissed`, as today.
- **The stale-id path** in `stage(referral:)` (a prior process died, then a different referral arrives)
  follows the same rule.

## Deltas (one dispatch, one PR)

1. **`CreateRecipeModel`:**
   - saved-candidate tracking (`savedExtractionIDs` or a per-candidate saved state);
   - `selectExtraction` refuses a saved candidate;
   - an "advance to next unsaved" step after save;
   - a `hasUnsavedCandidates` / "session complete" read for the view and the coordinator;
   - the `isSavingDisabled` extension.
   - `saveButtonTapped` keeps its single-recipe write, with no batching. Each candidate is still one
     reviewed `save(draft:)` (ADR-0051 Amd 1: the app-authored identity class).
2. **`CreateRecipeCoordinator`:**
   - D2 (the admitted collection and the unified close step);
   - D3 (persist and reconcile the admitted ids);
   - `saveButtonTapped(for:)` returns a result the view can branch on: "saved, session continues" vs.
     "saved, session complete".
3. **`CreateRecipeView`:**
   - the candidate section shows saved state, inert saved rows, and the new footer;
   - the Done toolbar item;
   - call `onSaved` only when the session is complete.
4. **`RecipeLibraryView.recipeCreated`:** unchanged in shape. It still resets the model and navigates, but it
   now only runs at session end.
5. **Docs, in this PR:**
   - `cockpit-find-handoff-receiver.md`: replace "one admitted outcome is a complete verdict" and the S-y2
     "admits one selected candidate per referral" paragraph with the multi-admit rule. Point its out-of-scope
     multi-admit bullet at this effort.
   - The CURRENT_HANDOFF Cockpit device-pass checklist: change "Save one candidate …" to save **two** of a
     multi-recipe email, and add a line to kill Yes Chef between the two saves.
   - Move this effort to DONE-LOG per the usual rule.

## Tests (`YesChefAppTests/CreateRecipeModelTests.swift`, where the coordinator tests already live)

- Two candidates, save both → **exactly one** verdict with **two** `.admitted` outcomes, emitted after the
  second save and not after the first.
- Save one of two, then Done → one verdict, one admitted. Same outcome with Clear, with leaving the section
  (`abandonOutstandingReferral`), and with a superseding `stage(referral:)`.
- Save one of two, then relaunch (a new coordinator on the same `defaults`) → the admitted verdict, **not**
  `.dismissed`. Both keys are cleared after the emit.
- Save none, then close → `.dismissed`, exactly as today (a regression guard on the existing tests).
- A saved candidate cannot be selected or saved again (`isSavingDisabled`, and `selectExtraction` is a no-op).
- After saving candidate 1 of 3, candidate 2 is selected and its extraction is applied to the editor.
- A single-candidate session and a non-referral paste session behave as before: save closes the session.
- An abandonment during an in-flight save followed by a failed save → closes with the admitted-so-far.

## Verification (house style)

- `swift test`, `swiftlint lint --strict`, and the generic device build.
- **Run the `YesChefTests` app target:** this changes `YesChefApp/` model and coordinator code.
- No simulator installs ([[lean-verification-default]]). The device pass rides on the Cockpit S-join
  checklist (Delta 5).

## Guardrails

- **No new parser, no second extraction call, no new save path** (ADR-0051 guard). Multi-save is repeated
  `save(draft:)` over candidates that are already extracted.
- **No wire-format change** and no Cockpit change. If you find yourself touching the `Codable`, the fixtures,
  or the mailbox layout, stop: that is a joint contract.
- **Do not emit a verdict per save** (see "Exactly one verdict" above).
- **Do not report unsaved candidates as declines.** That stays out of the set, as in S-y2.
- **Staging still never clobbers unsaved work** (ADR-0053 Amd2-D4). The incoming-offer path is unchanged
  except that closing the old referral now carries its admitted set.

## Sequencing

- **Land it before Jon's S-join device pass if you can.** Then one two-app pass covers both, and S-join
  exercises the multi-recipe email that motivated Gate 5.
- **It does not gate S-join.** Cockpit already consumes N admitted.

## Explicitly out of scope

- **Keeping per-candidate edits when switching candidates.** `selectExtraction` re-applies the extraction and
  overwrites unsaved edits to the current candidate. This is pre-existing and more visible now. Note it in the
  PR; don't fix it here.
- **Saves after the referral closed** (e.g. the cook left the tab, came back, and saved another candidate).
  They land in the library but are not reported to Cockpit. That is acceptable: the verdict is already final.
- **The Return-to-Confirmed vs. consume race** (claim-by-rename in `receiveReferral`, from Cockpit's S-c2
  review). It is decided at S-join, not here. It touches the same coordinator, so if Jon takes it, it bundles
  into this dispatch cleanly.
- **A "Back to Cockpit" hop**, "Open in Yes Chef" via `recipeRef`, and batch "Save all" without review.
