# Effort: variation anchors are unrepairable, and the adjust surface fails silently (2026-08-01)

**Type:** A standing data-loss defect (Dispatch 0 + 1), a repair affordance (Dispatch 2), and two
silent-failure fixes in the same surface (Dispatch 3). **No schema. No new tables, no columns, nothing added
to the promotion list.** One backfill pass over an existing BLOB column.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Designed. Dispatch 0 should ship on its own, immediately** — every base edit Jon makes before it
lands is another chance to lose a variation. Dispatch 3 is trivial and can ride with 0.
**Summary:** A variation's anchors come from **model output** and are never normalized to base row IDs, so
correcting a typo in a base instruction step orphans the variation permanently; `resolved(applying:)` throws
rather than degrades, so one dead anchor takes out the editor, the reader fold and the grocery list; and two
paths in the adjust surface report failure into the void.
**Related:** [ADR-0021](../decisions/ADR-0021-recipe-variations.md) Amd1-D4/D6/D7 ·
[ADR-0042](../decisions/ADR-0042-workbench-handoff-and-the-return-block.md) D2 ·
[ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless-or-loud) ·
[ADR-0021 Amd 4](../decisions/ADR-0021-recipe-variations.md) V4c is **gated behind Dispatch 1**.

**Read before starting:** ADR-0021 Amendment 1 in full (particularly **Amd1-D4 — the ID-preserving
structured editor** and **Amd1-D6 — base edits after the fact are unchanged**), then ADR-0042 **D2**, then
`CURRENT_HANDOFF.md` Verification Pattern.

---

## The reproduction

Jon, on device, 2026-08-01. Opening a variation of *411 West's Rosemary Chicken* produced an alert titled
**"Could Not Save Variation"** reading:

> The adjustment references an instruction step that could not be matched: Garlic **Crean** Sauce Heat oil in
> small saucepan and sautee garlic briefly. […]

He had corrected the spelling of *Crean* → *Cream* in the base recipe at some earlier point. That single
character ended the variation.

---

## The findings

### Finding 1 — this fires on **load**, and the editor is left unrecoverable

`RecipeVariationEditorModel.baseDetailChanged` ([`RecipeVariationEditor.swift`](../../YesChefApp/RecipeVariationEditor.swift))
calls `resolved(applying:)` inside a `do`/`catch`, and the throw happens **before** `name = variation.name`
and before `hasLoaded = true`:

```swift
do {
  resolvedDetail = try detail.resolved(applying: variation)   // throws here
  name = variation.name                                       // never runs
  note = variation.note ?? ""
  hasLoaded = true
} catch { … }
```

So the sheet presents with an empty `Name`, `resolvedDetail == nil`, and `isSaveDisabled == true` (it keys on
`name.isEmpty`). **There is no action available but Cancel**, and the alert title says *Save* about an
operation that never happened. Do not fix the title and stop — the title is the least of it.

### Finding 2 — the root cause: **identity is taken from the model and never normalized**

`RecipeMethodStepReplacement.index(in:)`
([`RecipeAdjustment.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)) resolves in
three stages: `id`, then `stepNumber`, then exact trimmed-string equality on `originalText`. Jon's payload
fell all the way to string equality, which means **`id` and `stepNumber` were both nil.**

They were nil because nothing in the app ever fills them. `RecipeAdjustmentProposal.methodStepReplacements`
parses `baseStepID` / `stepNumber` / `originalText` straight out of the model's JSON, and
`keepAdjustmentProposalAsVariation` encodes that proposal into the `deltas` BLOB **as it arrived**:

```swift
deltas: try RecipeVariationPayload(proposal: proposal).encodedData(),
…
_ = try detail.resolved(applying: variation)   // validated, then discarded
```

Line 565 already resolves every anchor against the live base **and throws the result away.** The information
needed to write a durable anchor is computed and discarded one line before the insert.

**This is ADR-0042 D2 arriving from the direction it was not defended.** That decision reads: *"a wrong
ingredient identity silently corrupts a recipe and orphans ADR-0021 variation anchors"* — and it kept
`adjustRecipe` unwired on the **hand-off** path for exactly this reason. The in-app extractor path was never
given the same treatment, and it is the one that shipped. The principle is *structured writes stay in-app*;
copying the model's identity claim verbatim into a durable BLOB is the model doing a structured write with
extra steps.

**The same defect exists on `RecipeIngredientReference`** (`id` + `originalText`, parsed from
`baseIngredientID`). It has not bitten yet because ingredient text is edited less often than instruction
prose. Fix both.

### Finding 3 — `resolved(applying:)` **throws**, so one dead anchor is a total loss

It is not only the editor's read path. `RecipeRepository.fetchDetailApplyingActiveVariation` is what
[`GroceryCore.swift:368`](../../YesChefPackage/Sources/YesChefCore/GroceryCore.swift) and
[`GroceryIngredientChoice.swift:36`](../../YesChefPackage/Sources/YesChefCore/GroceryIngredientChoice.swift)
call, and `variationIngredientHighlights` calls `resolved(applying:)` directly. **An orphaned anchor on an
active variation can take out the reader fold and that recipe's grocery contribution**, not just the editor.

That is a lossless-or-loud inversion: the loud part is right, the *scope* is wrong. Ten good ops and one dead
anchor should not read as zero ops.

### Finding 4 — the `stepNumber` fallback is a **silent-corruption hazard**, not a safety net

Had `stepNumber` been populated, Jon would have seen no error — `index(in:)` would have returned
`steps[stepNumber - 1]` and rewritten whatever step now occupies that position. After any base reordering
that is **the wrong step, silently**. Do not respond to this effort by populating `stepNumber` or by adding
fuzzy text matching. **The answer is a stable ID; the fallbacks are for reading legacy payloads only, and one
of them should be narrowed** (Dispatch 0, Pass C).

### Finding 5 — two silent failures in the same surface (adjacent, and free to fix)

Both in [`HandoffReviewCoordinator.swift`](../../YesChefApp/HandoffReviewCoordinator.swift):

- **`RecipeAdjustmentBriefReviewSheet` has no `.alert` modifier.** `standardReviewSheet` has one (~line 679)
  and `WorkbenchExperimentsReviewSheet` has one (~line 842); the brief sheet does not. Its `draftRevision()`
  catch sets `errorTitle` / `errorMessage` / `isShowingError = true` and **nothing renders it** — so a
  failing *"Draft the Revision"* is indistinguishable from a dead button. The likely throw is
  `resolveTier(…, requirement: .frontierRequired)` when frontier is off or the selected provider's key is
  gone, which is a very reachable state when a hand-off return arrives.
- **`isShowingError` then latches `true` on the shared coordinator**, so the next sheet that *does* carry the
  alert may fire a stale one.
- **No progress indication.** The button only disables; a 30-second frontier call looks identical to a
  no-op. The experiments sheet already shows the house pattern (`ProgressView` in the button label).
- **Latent, on the success path:** `discard(originalReview)` → `dismiss()` → `await Task.yield()` →
  `presentAdjustmentReview(…)`. Both sheets hang off the same `RecipeLibraryView` (lines ~141 and ~144), and
  one cooperative hop is not a dismissal transition, so the second sheet is likely swallowed. Fix the alert
  first — this may be sitting behind it, and it may also be why Jon reported the button doing nothing.

---

## Dispatches

Four. **0 and 3 are one PR and should land now.** 1 and 2 follow in order.

### Dispatch 0 — normalize anchors at the write boundary, and backfill *(the fix that matters)*

**Pass A — normalize on write.** In `keepAdjustmentProposalAsVariation`, stop discarding the resolution.
Resolve every `RecipeIngredientReference` and `RecipeMethodStepReplacement` against the live base, and
**rewrite the payload with the resolved `IngredientLine.ID` / `InstructionStep.ID`** before encoding. Keep
`originalText` as a human-readable label for the repair UI (Dispatch 2) and for diagnostics — it stops being
load-bearing. The same normalization applies wherever else a payload is minted from a proposal; find them by
type, not by memory.

**Pass B — backfill, idempotent, non-synced-schema.** One pass over existing `recipeVariations.deltas`:
resolve each anchor by today's rules and write back the ID where it still matches. **Report, do not guess:**
anchors that no longer match are left exactly as they are and listed. The report is a deliverable Jon reads
— it is the inventory of what Dispatch 2 will have to repair by hand, and Jon's *Crean* case will be in it.

> This is a **data pass over a synced column**. Back up first
> ([ADR-0030](../decisions/ADR-0030-local-backup-and-restore.md)) and it owes a two-device pass — but note
> that it is *convergent by construction*: both devices resolve the same anchors from the same base rows to
> the same IDs, so it must not produce a conflict. Verify that rather than assuming it.

**Pass C — narrow the fallbacks.** `index(in:)` keeps `id` first and `originalText` last. **Remove the
`stepNumber` positional fallback** (Finding 4), or gate it behind "no `originalText` present," which is
legacy-only after Pass B. A wrong-step rewrite is worse than an unmatched anchor, and after Pass A there is
no path that produces a payload needing it.

**Tests (Core, the real signal):** a proposal whose model output carries no `baseStepID` still persists with
a resolved id; editing the base step's text afterwards leaves the variation resolving correctly; the backfill
is a no-op on second run; the backfill never rewrites an anchor it cannot match; a payload with only
`originalText` still resolves (legacy read); a reordered base no longer causes a positional mis-rewrite.

### Dispatch 1 — degrade, don't throw

`resolved(applying:)` returns the fold **plus the unresolved anchors**, rather than throwing on the first
one. Use the same shape `RecipeVariationDerivation` already returns for unrepresentable edits — a typed
result, not an error, and never a silent drop ([ADR-0040](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md)).

- **Apply every op that resolves.** A variation with one dead anchor renders its other ops.
- **The editor loads**, populates `name`/`note`, and shows a repair banner naming the unresolved anchor by
  its `originalText`.
- **Reader and grocery degrade quietly and visibly** — the fold applies what it can and the recipe shows that
  something needs attention. Grocery must not silently drop or silently include; decide which, and test it.
- **`keepAdjustmentProposalAsVariation`'s validation call still throws** — refusing to *write* an unresolvable
  anchor is correct and stays. This dispatch changes the *read* path only.

**Do not** let this become a licence to save partial derivations on the write side. Amd1-D7's
lossless-or-loud rule at save is untouched.

### Dispatch 2 — the repair affordance

When an anchor is unresolved, show the stored `originalText` beside the recipe's current steps (or ingredient
lines) and let the cook tap the one it meant. Re-anchor by ID; the repair is permanent. Offer **discard this
op** as the other choice, explicitly, rather than leaving a dead anchor as the default state.

Jon's *Crean* case is a five-second fix once the UI lets him see it. Reuse the row-selection idiom rather
than inventing one; [ADR-0048](../decisions/ADR-0048-playbook-edit-grain.md) D2's shared row component is the
likely host.

### Dispatch 3 — the silent-failure fixes *(rides with Dispatch 0)*

- Add the missing `.alert` to `RecipeAdjustmentBriefReviewSheet`.
- Reset `isShowingError` when its sheet dismisses, so it cannot latch.
- Add the `ProgressView`-in-button treatment during `draftRevision()`, matching the experiments sheet.
- Correct the editor's alert title — it is a **load** failure, not a save failure.
- Fix the sheet-to-sheet handoff (`Task.yield()` → present the adjustment review from the coordinator after
  the first sheet's dismissal actually completes, not one cooperative hop later). **Verify on device**; this
  one is a diagnosis from reading, not from a reproduction.

---

## Guardrails a dispatch must not undo

- **Do not widen anchor matching.** No fuzzy text match, no normalized-whitespace-and-punctuation compare, no
  "closest step." Every one of those trades a loud failure for a silent wrong-step rewrite, which is the
  Finding 4 hazard with better manners.
- **Do not add schema.** The BLOB is correct here (Amd1-D3): a delta op has no independent consumer and
  nothing anchors to it. This effort is a normalization and a read-path change.
- **Do not relax Amd1-D7.** Partial saves stay forbidden. Degrading applies to *reading* an already-stored
  variation, not to accepting an edit that cannot be represented.
- **Do not populate `stepNumber` to make matching more robust.** See Finding 4.
- **Do not begin ADR-0021 Amd 4 V4c** (`stepInsert` / `stepRemove`) until Dispatch 1 has landed. Two more
  anchored op kinds over unrepairable anchors multiplies the defect.

## Verification

- `swift build` the package; the **generic app build is required evidence** (`CURRENT_HANDOFF.md`
  Verification Pattern); `scripts/check-drift.sh`; SwiftLint clean.
- **Core tests carry the correctness** — Dispatch 0's list above, plus a Dispatch 1 test that a variation
  with one unresolved anchor still resolves its remaining ops and reports exactly one unresolved.
- **The backfill report is read by Jon** before the second device converges.
- **Device pass:** Jon opens the *411 West's Rosemary Chicken* variation. After Dispatch 1 it must open and
  show the problem; after Dispatch 2 it must be repairable in one tap. Then: edit a base instruction step's
  wording on a recipe with an active variation and confirm the fold survives — that is the whole point of
  Dispatch 0 and the thing Amd1-D6 always claimed was true.
