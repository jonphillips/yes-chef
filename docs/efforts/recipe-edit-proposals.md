# Effort: Recipe edit proposals — the "Adjust this recipe" verb

**Type:** A new actionable-chat verb (`.adjustRecipe`) on the recipe reader + a non-destructive
**proposal/preview** primitive + a **side-by-side review** surface. Reuses the `(extract → review →
commit)` apply-action, the `WorkbenchDraftRecipeClient` LLM shape, and the `WorkbenchCompareCore` diff
engine. **Not** a variation model (that's the S2 destination, ADR-0021) and **not** a sidecar section.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Proposed — not yet dispatched.** Implements [ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md)
(the verb + proposal primitive + overwrite destination), which extends
[ADR-0021](../decisions/ADR-0021-recipe-variations.md) (the variation destination). Milestone-sized across
all three slices; **S1 is schema-free and shippable on its own.** Do **not** bundle S2/S3 into S1.

**Read before starting:** [ADR-0023](../decisions/ADR-0023-recipe-edit-proposals.md) in full (the vocabulary
banner + D1–D6 are load-bearing), then [ADR-0021](../decisions/ADR-0021-recipe-variations.md) (the S2
destination and its delta vocabulary D2). Then, for reuse patterns:
`RecipeDetailModel+Enrichment.swift` (the existing `applyActionCatalog` on `RecipeDetailModel` — the verb
slots in here), `WorkbenchDraftRecipe.swift` (the LLM-client + JSON-parse shape the delta extractor
mirrors), `WorkbenchCompareCore.swift` + `WorkbenchCompareView.swift` (the canonical-name alignment + the
two-column view the side-by-side review reuses), `RecipeChatWorkspace.swift` (`ChatApplyAction` /
`AnyChatApplyAction`, the staging card, the `requiresSubject` flag), and the `originalSnapshot` /
`RecipeBundleCoding` snapshot codec + viewer (`RecipeModels.swift`, `RecipeCore.swift`) for the D5 undo
restore-point. ADR-0017 for per-feature `ReasoningEffort` (the adjust verb is `high`).

**Build/verify (house constraint, [[lean-verification-default]]):** package logic via `swift build`; app
via `-skipMacroValidation`, built once; `xcodegen generate` after adding files; then the `CURRENT_HANDOFF.md`
Verification Pattern — **no simulator install**, Jon does the device pass. Verb + review are **reader-hosted**
(primary pass on `iPad Pro 13-inch (M5)`, both orientations) and must also work on `iPhone 17 Pro` (the
review as a sheet).

---

## The invariant this preserves

**The model proposes; the tap writes** (ADR-0011/0012), extended: **the model writes only to a transient
preview** (ADR-0023 D2). No chat turn mutates a stored recipe, creates a variation, or overwrites anything
on its own — every write routes through the side-by-side review card and a human tap, and overwrite is
guarded by a one-level undo (D5).

## Sync posture (ADR-0002 / ADR-0015)

**S1 touches no schema.** The proposal and the undo restore-point are **local-only, SyncEngine-excluded**
(ADR-0015 precedent; guarded by the live-schema audit test that already excludes chat and the ADR-0021
active-selection store). The overwrite reuses the existing structured-editor update (ADR-0004) — no new
column, no CKAsset. The **variation** destination's durable table is **ADR-0021's** and arrives only in S2.

## Slice plan

- **S1 — the proposal primitive + preview + overwrite-only (schema-free; de-risks the effort).**
  - `.adjustRecipe` apply-action on `RecipeDetailModel.applyActionCatalog` (sibling of the make-ahead /
    chef-it-up / serve-with actions), available whenever the reader has a recipe — so it lands on **every
    recipe and the workbench working recipe** at once.
  - **Delta extractor** — an LLM client mirroring `WorkbenchDraftRecipeClient` (system prompt + strict-JSON
    parse), emitting a **structured delta** in ADR-0021 D2's op vocabulary (`add`/`remove`/`substitute`/
    `scale` + method note / whole-step replacement), **not** a whole-recipe blob (ADR-0023 D4). `high`
    effort, generous `maxTokens` (budget reasoning + output, throw on truncation — [[reasoning-budget-starves-output]]).
  - **Ephemeral proposal store** — transient, device-local, sync-excluded (ADR-0023 D2). Discarded on
    dismiss.
  - **Side-by-side review view** — reuse `WorkbenchCompareCore` alignment + the two-column `WorkbenchCompareView`,
    pointed at *(current recipe, proposed recipe)*. Ingredients diff structurally (aligned rows + blanks);
    method as prose before/after (ADR-0023 D3). Full-screen cover on iPad (`.detailOnly` focus pattern),
    sheet on iPhone.
  - **Commit = overwrite-in-place** through the ADR-0004 structured editor update, after stashing a
    **pre-edit restore point** (reuse `RecipeBundleCoding` codec + snapshot viewer; a *distinct* store from
    the pristine `originalSnapshot` column, which must not be clobbered — ADR-0023 D5). Undo restores the
    stash.
  - **Dogfood before S2.** Watch whether "adjust" mostly wants overwrite or mostly wants "keep both" — that
    tells us how urgent the variation destination is.

- **S2 — the variation destination (this is ADR-0021's build).**
  - Add **"keep as a variation"** as the second commit path on the *same* proposal: the structured delta
    the S1 extractor already produces *is* the ADR-0021 variation payload. Introduces the `recipeVariations`
    table + BLOB + migration, the reader fold (highlighted-in-place), and the grocery fold — per ADR-0021.
  - Resolves ADR-0021 **OQ1** (no separate extraction — S1's delta is reused) and **OQ2** (the S1
    side-by-side is the staging surface). Resolve ADR-0023 **OQ3** here: overwrite of a recipe that already
    carries variations must re-validate/rebase or warn (delta anchors on base-ingredient identity).

- **S3 — iterative refine loop + workbench-log deposit.**
  - Keep chatting to **revise a live proposal** before committing (re-extract with the current proposal as
    context, not from scratch). This is the conversational editing loop Jon originally asked for.
  - On the workbench, a committed adjustment can drop a `rationale`/`experiment` entry into the workbench
    log (ADR-0019) — closing the "why did I change this" memory loop.

## Out of scope / parked

- **Structural, per-step mergeable method model** — declined (ADR-0016 / ADR-0021 D2 / ADR-0023 OQ1).
  Method edits are whole-step text replacement or a prose note, never a step-sequence resolver.
- **Multi-level undo stack** — one-level restore point in v1 (ADR-0023 OQ2); a stack is a fast-follow only
  if dogfooding asks.
- **The variation reader/grocery fold** — owned by ADR-0021, built in S2; not part of the S1 primitive.
