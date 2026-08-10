# Effort: import silently deletes a divergent recipe that shares an import identity (2026-08-09)

**Type:** A standing data-loss defect. **One dispatch.** No schema — no new tables, no columns, nothing
added to the promotion list. A guard on an existing write path plus one activated (currently-dead) warning
branch.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Designed. Ship on its own, now.** Every import Jon runs against a URL he has already captured
and since edited is another chance to lose the edited copy, and the delete **syncs**.
**Source:** Codex Semantic Fidelity Audit, Aug 2026, finding **P0** (baseline `42ad5b6`).
**Summary:** `mergeDuplicateImportedRecipes` repoints meal-plan / menu / grocery references off a duplicate
Recipe and then **hard-deletes it**, with no check that the duplicate is content-empty. Because the canonical
survivor is the **earliest** row, the one deleted is the *newer* copy — the one most likely to carry the
cook's edits, notes, photos, variations and snapshot. The delete propagates through sync as a tombstone.
**Required invariant (Codex's wording, adopted verbatim):**

> Non-identical recipes must never be destructively converged solely because they share import identity.

**Related:** [ADR-0030 local backup and restore](../decisions/ADR-0030-local-backup-and-restore.md) (the delete
syncs; restore is the only recovery for anything already lost) · [ADR-0040 editable at the grain it is
stored](../decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) (lossless-or-loud — a delete is the
loudest possible loss and here it is silent) · the variation-anchor-repair effort (same disease: a synced
data-loss defect that read-path code caused while looking like housekeeping).

**Read before starting:** the whole of
[`RecipeRepository+Import.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift) from
`importBundle` (line ~322) through `mergeDuplicateImportedRecipes` (line ~596), and `CURRENT_HANDOFF.md`
Verification Pattern. This is a **Core** change, so `YesChefCoreTests` is the correctness signal.

---

## The reproduction (by reading — no device repro yet)

The library holds two recipes that share a strong (non-title-only) import identity — same normalized source
URL **and** normalized title:

- **A**, captured first, untouched.
- **B**, captured (or re-captured) later, then edited: the cook fixed the yield, added two notes, a photo, and
  a variation.

The user re-imports that URL a third time, or runs any import path that calls
[`matchingImportRefs`](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift:552) while both A
and B exist.

1. `matchingImportRefs` finds `refs = [A, B]` for the key (count > 1, not title-only).
2. It picks `canonicalRef = refs[0]` — and `areImportRefsInCanonicalOrder` sorts by `dateCreated` ascending,
   so **canonical = A, the older row.**
3. `mergeDuplicateImportedRecipes(canonical: A, duplicates: {B})` repoints every `MealPlanItem`, `MenuItem`
   and `GroceryItemSource` off B onto A, then:

   ```swift
   for recipeID in duplicateRecipeIDs {
     try Recipe.find(recipeID).delete().execute(db)   // B is gone, with its notes/photo/variation
   }
   ```

4. `matchingImportRefs` deletes B's `RecipeImportRef`, returns `[A]` (count 1), so `importBundle` reports
   `.alreadyImported` pointing at A. No warning. **B's edits are unrecoverable except via ADR-0030 restore,**
   and the tombstone syncs to every device.

The current tests do not catch this because they converge **effectively empty** recipes — so deletion looks
harmless. That is the exact gap Codex flagged: parser-success / row-count assertions, never content
preservation.

---

## The findings

### Finding 1 — the destructive branch has no content guard

[`mergeDuplicateImportedRecipes`](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift:596)
deletes **every** duplicate unconditionally. It never asks whether the loser carries content the canonical
does not. That is the whole defect.

### Finding 2 — the survivor is the *oldest*, so the newest edits are what die

`areImportRefsInCanonicalOrder` (line ~621) sorts ascending by `dateCreated`. Re-capture-then-edit is the
common shape, and it puts the edited copy last, i.e. always on the losing side. The policy is precisely
backwards for edit-preservation — but do **not** fix this by flipping the sort. "Keep the newest" would just
delete a *different* non-empty recipe. The fix is to stop deleting non-empty recipes at all, not to pick a
better victim.

### Finding 3 — the non-destructive branch already exists, and is currently dead

`importBundle`'s switch has a `default:` (matchingRefs.count > 1) arm that emits
[`ambiguousImportIdentityWarning`](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift:639)
— "an import identity matched more than one existing recipe." **It is unreachable today**, because
`matchingImportRefs` always collapses non-title-only matches to a single ref before the switch sees them. The
correct, non-destructive resolution of the ambiguous case is already written; the merge step is what steals
the collision before anyone can warn about it. This dispatch turns that dead arm live.

---

## The dispatch

One PR. Two code passes and its tests.

### Pass A — guard the merge so it only converges a *provably content-empty* loser

Split the duplicates in `matchingImportRefs` into **mergeable** (safe to repoint + delete) and **divergent**
(must survive), using an emptiness test, not an identity/equality test.

- **Mergeable** = the duplicate Recipe has **no substantive content of its own**: no child rows scoped to its
  `recipeID` in any content table, and `originalSnapshot == nil`. Enumerate the content tables against the
  live schema — do not trust this list from memory — but it is at least: `ingredientSections`,
  `ingredientLines`, `instructionSections`, `instructionSteps`, `recipeNotes`, `recipePhotos`, `recipeTags`,
  `recipeCategories`, `recipeEquipment`, `recipeSources`, `recipeVariations`, `recipeActiveVariations`, and
  any user-edit/provenance rows keyed by `recipeID` (e.g. `RecipeAdjustment`, `RecipeDeliberationLog` — grep
  for `recipeID` to find the full set). A childless husk with `originalSnapshot == nil` is safe to drop.
- **Divergent** = anything else. **Never deleted.**

Then:

- `mergeDuplicateImportedRecipes` repoints references and deletes **only the mergeable subset**. Its
  `MealPlanItem` / `MenuItem` / `GroceryItemSource` repointing targets the same subset — a divergent
  duplicate keeps its own references untouched.
- Delete the `RecipeImportRef` rows for **only the merged** losers. Divergent losers keep their refs.
- `matchingImportRefs` returns `[canonical] + survivingDivergentRefs`. When any divergent duplicate survives,
  that is count > 1, and the switch's `default:` arm fires.

**Why "empty," not "identical to canonical."** A full structural compare (loser vs canonical across every
child table) is the deferred conflict-aware-merge work, not this fix. "Empty" is conservative in the only
direction that matters: it errs toward *keeping*. If two non-empty recipes happen to be byte-identical we keep
both — a redundant row, covered by the warning — which is strictly better than any risk of deleting content.
Do not build the structural compare here.

> **Residual, accept it explicitly:** a childless husk whose only difference from canonical is an edited
> *scalar on the Recipe row* (e.g. a retyped yield with no notes/photos/children) is treated as empty and
> dropped. This is vanishingly unlikely (edits that produce no child rows and touch nothing else) and
> non-catastrophic. Do **not** grow the guard into a scalar diff to chase it; note it in a comment and move
> on.

### Pass B — make the ambiguous case report, don't insert, and never delete

Change `importBundle`'s `default:` arm (count > 1) so that, when divergent duplicates survive, it:

- reports the collision at the canonical recipe — `outcome: .alreadyImported`, pointing at `matchingRefs[0]`
  — and carries `ambiguousImportIdentityWarning`;
- **does not** insert a new copy, and **does not** delete anything.

Rationale: the identity says "already imported," so silently minting a third copy is the wrong default, and
deleting is the bug we are fixing. Point at the canonical, warn loudly, let Jon sort it out. Mirror the same
change into the **preview** path (`previewImportBundle`, and
[`matchingImportRefsForPreview`](../../YesChefPackage/Sources/YesChefCore/RecipeRepository+Import.swift:576),
which today also silently `prefix(1)`s the collision away) so the preview surfaces the ambiguous warning
instead of a clean "already imported." Preview and import must agree.

> **One judgment call for Jon at review:** report-and-warn (chosen here) vs. import-as-new-and-warn (the arm's
> literal current body). Both are non-destructive; this dispatch picks report-and-warn to avoid litter.
> Flag it in the PR description; it is a one-line difference if Jon prefers the other.

### Tests (Core — the real signal; assert semantic structure, not decode/count)

The audit's explicit ask: semantic-fidelity tests, not parser-success tests. At minimum:

1. **The P0 test.** Seed canonical A and a **substantive** divergent B on one strong identity key — B carrying
   instruction steps, a note, a photo and a variation. Run the import that previously converged them. Assert:
   **B still exists**; assert its *content* is intact by reading the actual rows (the specific instruction
   step text, the note body, the photo, the variation) — not merely `count == n` or `!= nil`; assert nothing
   was deleted; assert the ambiguous warning is present; assert no third copy was created.
2. **Empty husk still merges.** A childless, snapshot-less duplicate is still repointed and deleted, and its
   references land on canonical — the existing behavior is preserved for the provably-safe case. (The current
   convergence tests should keep passing; confirm they do rather than deleting them.)
3. **Mixed.** Canonical + one empty husk + one substantive divergent → husk merged and its refs repointed,
   divergent kept intact, warning surfaced.
4. **Reference integrity.** `MealPlanItem` / `MenuItem` / `GroceryItemSource` pointing at a *merged* husk move
   to canonical; those pointing at a *surviving* divergent recipe are left pointing at it.
5. **Preview parity.** The preview path reports the ambiguous warning for the same substantive-divergent
   fixture, matching import.
6. **Title-only path unchanged** — its own branch never called the merge; add one assertion that it still
   doesn't and behaves as before.

---

## Guardrails a dispatch must not undo

- **Do not build conflict-aware / content merge here.** No copying B's notes onto A, no field-level union, no
  "promote the richer copy." That is a separate ADR. This dispatch's entire job is to *stop deleting* and
  *surface the collision*.
- **Do not flip the canonical sort** to "keep newest." It relocates the victim; it does not remove one.
- **Do not add schema.** No merge-audit table, no "supersededBy" column, no tombstone bookkeeping. The guard
  reads existing rows; the warning already exists.
- **Do not weaken the emptiness test into a fuzzy/scalar diff** to shave the residual in Pass A. Conservative
  and simple beats clever here — the cost of a false "empty" is a deleted recipe.
- **Do not delete on the divergent path**, in either import or preview, for any reason.

## Verification

- `swift build` the package; the **generic app build is required evidence** (`CURRENT_HANDOFF.md` Verification
  Pattern); `scripts/check-drift.sh`; SwiftLint clean.
- **`YesChefCoreTests` carries the correctness** — the six tests above. The P0 test must read content, not
  counts.
- **No data pass owed.** This fix only *removes* deletes; it writes nothing to existing rows, so it needs no
  backfill and no two-device convergence pass of its own.
- **Already-shipped damage is out of scope and unrecoverable in-code.** Any recipe a prior build already
  converged away is gone from live data; ADR-0030 restore is the only recovery. Note this in the PR so Jon
  knows the fix is forward-looking, and so a device pass doesn't chase a copy that was destroyed before the
  guard existed.
- **Device pass (Jon):** capture a recipe, edit it (note + photo), then re-run import of the same source and
  confirm the edited copy survives and the ambiguous warning shows — the whole point.
