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

### S1 dispatch — section-aware revision (the current build, ADR-0023 S1 option B)

The first S1 pass (branch `codex/adjust-recipe-s1`) builds and passes but only edits the **first** ingredient/
instruction section, because `proposedDetail` round-trips through a single `ingredientText`
(`editorDraft` → join → `IngredientParser.lines` back into section 0), which also mints new line IDs. But
Paprika and web imports create **real multi-section recipes** (`PaprikaHTMLImport.swift` `makeRecipeBundle`;
`RecipeParseBuilder.sectionedIngredients`), so a "For the chicken / For the sauce" recipe would only get its
top group edited. This revision makes adjust span all sections. **Still schema-free** — no new tables; only
*how* existing children are written changes. Sync posture unchanged (in-memory restore point, no synced row).

**The pivot:** stop round-tripping through text. Mutate the detail's `[IngredientLine]` / `[InstructionStep]`
arrays **in place**, preserving each line's `id`, `sectionID`, `sortOrder`. This gives section-awareness *and*
ID preservation (which S2 variation anchoring wants) in one move.

1. **Section-aware, ID-preserving delta application** (`RecipeAdjustment.swift`).
   - `substitute`/`scale`: replace the matched line's `originalText` (re-run `IngredientParser.parse` for the
     structured fields) **in place** — keep `id`/`sectionID`/`sortOrder`.
   - `remove`: drop the matched line from whatever section it lives in.
   - `add`: mint a new line; target section = an optional `sectionName` on the op matched case-insensitively
     to an existing section name, else the **first** section; append with next `sortOrder`.
   - Instruction replacements: same in-place mutation, keyed `id` → `stepNumber` → exact text.
   - Resolver (`RecipeIngredientReference.index` / `RecipeMethodStepReplacement.index`) spans **all** sections
     (`id` first, then exact text; prefer `id` on duplicate text). Keep the fail-safe throw for a genuinely
     unmatched reference.
   - Delete `editorDraft(applyingTo:)`, `existingIngredientLineID`, and the `editable*` single-section helpers
     once unused — no dead code. Fold in the `methodNote == nil ? notes : notes` dead-ternary cleanup;
     `methodNote` still lands exactly once as a general note.
2. **Multi-section overwrite + restore writers** (`RecipeAdjustment.swift` / `RecipeCore.swift`).
   - Private `replaceEditableChildren(recipeID:ingredientSections:ingredientLines:instructionSections:instructionSteps:generalNotes:in:)`
     — delete the recipe's existing ingredient sections+lines, instruction sections+steps, and **general** notes,
     then insert the provided ones (direct SQLiteData `.delete()`/insert primitives, inside the existing write
     transaction, atomic).
   - `overwriteRecipeWithAdjustmentProposal`: compute proposed detail, stash the `RecipeBundleCoding` restore
     point (unchanged), then `replaceEditableChildren` with the proposed multi-section children. Leave
     **untouched**: recipe-row provenance (`originalSnapshot`, `dateCreated`, `coverPhotoID`,
     `makeAhead`/`chefItUp`/`serveWith`), source, photos, tags, categories, equipment, non-general notes. Bump
     `dateModified`.
   - `restoreRecipeAdjustment`: **latent-bug fix** — rewrite to decode the bundle and `replaceEditableChildren`
     with the snapshot's **full multi-section** children, **not** via single-section `RecipeEditorDraft` (today
     undo would itself collapse a multi-section recipe to one section).
3. **Extractor contract** (`RecipeAdjustment.swift`). Add optional `"sectionName"` to the `add` op (schema +
   parse). Prompt: may edit ingredients in **any** section; reference existing rows by exact `id`/text; name the
   target section on adds when relevant. Keep truncation/empty handling.
4. **Tests** (`RecipeAdjustmentTests.swift`, core-only — no simulator). Apply-to-preview across **two** ingredient
   sections (substitute in section 2, add to a named section, remove from section 2 → per-section changes correct,
   other section intact, `id`s preserved on in-place edits); overwrite a two-section recipe (both sections
   persisted; `originalSnapshot`/photos/tags/categories/source untouched); **undo/restore a two-section recipe**
   (all sections restored exactly — the case that breaks today); keep the existing parse/single-section/
   snapshot/truncation tests.

**App layer:** expected to be untouched — `RecipeModels.swift` calls the same repo signatures, and the review
(`IngredientMatrixView` via `WorkbenchCompare`, which flattens by canonical name) handles multi-section. Confirm
the review renders a two-section proposed detail sensibly; adjust only if it doesn't.

**Verify — fail fast, no simulator:** `swift build` + `swift test` (the new tests are the signal); `xcodegen
generate` only if files were added; **one** app build for `iPad Pro 13-inch (M5) (16GB)` with
`-skipMacroValidation`; `scripts/check-drift.sh`. **Do not boot, install, or `simctl` a simulator, and do not
try to repair the toolchain** — if the app build fails, paste the compiler error and **stop**; Jon does the
device pass.

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
