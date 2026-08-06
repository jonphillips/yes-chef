# Dispatch — ADR-0021 V4c (two step ops) + variation Delete affordance

**Status:** Done — architect-reviewed 2026-08-06, write-up in [`../DONE-LOG.md`](../DONE-LOG.md). Both parts
shipped; review changed the insert op to carry its own `sectionID` (see Part B below).
**Owner:** Codex · **Architect:** Jon
**ADR:** [ADR-0021 Amendment 4](../decisions/ADR-0021-recipe-variations.md) (D4 / V4c) + a gap-fill not in the ADR (Delete).
**Gate:** cleared — anchor-repair Dispatch 1 shipped + device-passed (2026-08-05). Both parts are **schema-free** (the `deltas` BLOB / an existing synced row); **no prod-schema promotion entry**.

Two cohesive parts, sequenced so the small one lands fast. **Part A** is app + thin Core and gives immediate dogfood relief; **Part B** is the meaty Core slice. Land A first even if B needs review iterations.

---

## Part A — Delete a variation (the fast one)

**Motivation (Jon, dogfooding):** after editing the base, a variation sometimes needs repair; rather than repair, the cook wants to just delete it and recreate. Amd2-D4 already sanctions "a variation can be deleted" — but no standalone affordance was ever built. The Choices `Menu` today offers Hand Off / Paste / Rename / Edit / Split Off / Promote and **no Delete** ([`RecipeVariationPromotionPresentation.swift:99`](../../YesChefApp/RecipeVariationPromotionPresentation.swift)).

### Core — `RecipeAdjustment.swift`
Add `public static func deleteVariation(_ variationID:in:now:uuid:)` (exposed via `RecipeRepository`, mirroring `renameVariation` at [`RecipeAdjustment.swift:838`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)):

1. Fetch the variation (throw `.missingVariation` if absent, per existing convention).
2. `try RecipeVariation.find(variationID).delete().execute(db)`.
3. **Clear the active selection only if the deleted variation was the active one.** Do **not** blindly `setActiveVariation(nil, …)` — that wipes the recipe's active highlight even when a *different* variation is active. Read the current active for `variation.recipeID`; if it equals `variationID`, `setActiveVariation(nil, …)`; otherwise leave it. (The split-off tail at [`:922`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift) clears unconditionally, which is correct *there* because split-off already made its variation active — do not copy that shortcut here.)

### ⚠️ Cross-device correctness — tolerate a dangling active selection
`recipeActiveVariations` is **persisted-but-not-synced** (Amd4-D5), but the `RecipeVariation` row **is** synced. So: device A deletes a variation → the delete syncs to device B, where that variation may still be B's locally-selected active. **Confirm the resolve/read path returns the base recipe (not a crash / not a stale fold) when the active `variationID` no longer exists.** Dispatch 1 made `resolved(applying:)` read-lenient for *orphaned anchors*, but a **wholly-missing** active variation is a different case — verify `fetchDetailApplyingActiveVariation` degrades to base and add a test for it. This is the one non-obvious defect in an otherwise trivial slice.

### Model — `RecipeDetailModel+Adjustment.swift`
Add `func deleteVariation(_ variationID:)` mirroring `renameVariation` at [`RecipeDetailModel+Adjustment.swift:109`](../../YesChefApp/RecipeDetailModel+Adjustment.swift) (Task → `database.write` → `RecipeRepository.deleteVariation` → error surface).

### UI — `RecipeVariationChoices`
Add a **destructive** `Button("Delete", role: .destructive)` to the row `Menu`, below Promote, behind a `.confirmationDialog` ("Delete this variation?" / "This can't be undone."). Delete is irreversible, so the confirm is required — but keep it one extra tap, not a paragraph. Follow the existing `renamingVariation`/`splittingOffVariation` `@State` + binding-driven-dialog pattern already in the file.

### Tests
- Core: delete removes the row; active cleared **iff** it was active; deleting a non-active variation leaves the active selection intact; resolve returns base when the active variation is missing.

---

## Part B — V4c: `stepInsert` / `stepRemove` (Amd4-D4)

**What "add instructions" means in the model.** Today a variation's payload carries `ingredientOps` + `methodStepReplacements` (substitutions only) — [`RecipeVariationPayload`, `RecipeAdjustment.swift:180`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift). There is **no way to add or remove a step**, so "add an instruction" forces a whole separate recipe. Amd4-D4 widens the vocabulary by **exactly two** ops.

### The two ops (and only these two)
- `stepInsert(after: RecipeStepReference, sectionID: InstructionSection.ID?, text: String)` — anchored to a base step, plus a head position for "before everything."
- `stepRemove(RecipeStepReference)`.

**`sectionID` was added in review (2026-08-06).** As first built the op carried only the anchor, so resolve gave
the new step its *anchor's* section — and a step added at the head of a section anchors to the last step of the
section *above*, so it silently moved there. The ingredient `add` op always carried its section for the same
reason. The section is a **placement hint, not a second anchor**: if it no longer resolves the insert falls back
to the anchor's section rather than reporting an unresolved anchor.

`RecipeStepReference` **reuses `RecipeMethodStepReplacement`'s anchoring** ([`:469`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)) — the same base-step-ID anchor the anchor-repair effort just made repairable. Do **not** invent a parallel anchoring scheme.

### Still unrepresentable, deliberately — route to split-off
`instructionStepMoved` and **every** instruction- and ingredient-**section** op stay out. The D4 test governs any future widening: *does this require deciding where something goes relative to things it was not anchored to?* If yes, it stays out and the derivation returns it as unrepresentable → Amd1-D7 offers the split-off. **Reordering is explicitly this case** — it is not a variation, and V4b will make its split-off *link* rather than orphan.

### Changes
1. **Payload** ([`:180`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)): carry the two new structural ops (new anchored-op type; keep `methodStepReplacements` as-is for substitutions). Extend `encodedData`/`decode` round-trip.
2. **Anchor normalize + backfill** ([`normalizingAnchors` :212, `backfillingAnchors` :238](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)): the new anchored ops must normalize to base-step IDs and backfill/report unresolved anchors exactly like `methodStepReplacements` do — this is *why* V4c was gated behind Dispatch 1; adding anchored ops without this multiplies the anchor defect.
3. **`RecipeVariationUnrepresentableEdit`** ([`:340`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)): **remove** `instructionStepAdded` (:349) and `instructionStepRemoved` (:350) and their description arms (:363–364).
4. **Derivation** (`derivingVariation`, emits at [`:1386` / `:1400`](../../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift)): instead of appending those unrepresentable cases, emit `stepRemove` / `stepInsert(after:)` with **minimality** (smallest anchored op set that reproduces the resolved detail). A move still decomposes to remove+insert only if the derivation naturally lands there — do **not** special-case moves into representability; if minimality can't express it, it stays unrepresentable.
5. **Resolution** (`resolved(applying:)`): fold an inserted step into the resolved instruction list at its anchor; drop a removed step.
6. **Reader rendering:** an inserted step renders as an **addition in the same visual grammar as an added ingredient** (D3) — base legible underneath, no merged-procedure resolver.

### Tests
- Extend `RecipeVariationTests` / `RecipeVariationResolutionTests` / `RecipeVariationAnchorRepairTests`: round-trip both ops; derive → resolve identity for an added and a removed step; a base-step-text edit followed by resolve still folds (anchor normalized, not orphaned); `instructionStepMoved` and a section add still come back unrepresentable and reach the split-off offer.

---

## Verification (per lean-verification default)
Build once (generic iOS app build) + `swift test` for Core + check-drift. **No simulator installs** — Jon does the device pass. Part A's cross-device tolerance and Part B's derive↔resolve identity are the two things the tests must actually pin.

## Handoff bookkeeping
On approval: DONE-LOG entries, remove the V4c + Delete items from CURRENT_HANDOFF's Next Up (the bump rides in this slice's own PR, read from main). **V4b (related-recipe edges) remains separately queued** — it is the schema slice with the owed two-device sync pass (back up first, ADR-0030) and is deliberately **not** in this dispatch.
