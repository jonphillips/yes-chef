# Effort: Two canonical-key granularities (grocery vs. compare)

**Type:** Correctness, app + core only. No schema, no migration. Driven by Jon's use of the
Workbench Compare matrix (2026-07-06).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/review)
**Status:** Built 2026-07-06 (in review) — `CanonicalIngredient.comparisonKey` + matrix wiring + tests;
package tests green (215/215). Grocery key untouched; no schema.

**Why.** `WorkbenchCompare` aligns its matrix rows on the *same* canonical key the grocery list
uses for consolidation (`CanonicalIngredient.canonicalName`, via the cached `IngredientLine.canonicalName`
column). But the two surfaces want **opposite** things, because they have inverted cost-of-error:

| | False *merge* (two things → one row/key) | False *split* (one thing → two rows/keys) |
|---|---|---|
| **Grocery list** | **Expensive** — buy frozen when the recipe wanted fresh | Mildly annoying — two lines |
| **Compare matrix** | **Cheap & self-correcting** — the row is "Spinach," the cells say `8 oz fresh` vs `8 oz frozen`, and the cook *understands* | **The actual failure** — spinach on two rows defeats the comparison |

So the grocery key must **bias toward splitting** (keep `fresh`/`frozen`/`dried`/`canned` distinct —
different SKUs); the matrix key must **bias toward merging** (collapse to the base ingredient and let
the cell text carry the form). One shared key tuned to the middle serves neither. This is what Jon hit:
`dried ancho chiles` sits on a different row from `ancho chiles`, and `medium garlic cloves` from
`garlic cloves`.

**The shape of the fix.** Add a **second, coarser** key used *only* by the matrix. The comparison key
is strictly a **coarsening** of the grocery key — grocery behavior is **untouched** (zero risk to a
shipped, dogfooded feature; no migration, no re-shopping surprises). The eventual structured
`{ base, form, prep }` ingest model (deferred, Decision #5 in the grocery milestone) is the real
convergence target: once a line decomposes, the grocery key is `base + form` and the matrix key is
`base` — both fall out for free. This slice is the cheap deterministic down-payment.

**Boundary guard (do not erode).** The comparison key is **read-only for the matrix.** It must never
feed grocery consolidation, pantry matching, or the `canonicalName` column. Two matchers asking
different questions is fine *here* precisely because their costs differ; do not "unify" them.

**Read before starting:**
- `YesChefPackage/Sources/YesChefCore/CanonicalIngredient.swift` — the normalizer + `aliases` +
  `leadingDescriptors`.
- `YesChefPackage/Sources/YesChefCore/WorkbenchCompareCore.swift` — `buildColumn` keys on
  `line.canonicalIngredientName` (~L118/L130) and labels via `comparisonRowLabel` (~L160).
- `YesChefPackage/Sources/YesChefCore/GroceryPantryAssumptions.swift` — `canonicalIngredientName`
  returns the cached grocery key.

---

## The slice — `comparisonKey`, wired into the matrix

**1. `CanonicalIngredient.comparisonKey(_:)` — coarser than `canonicalName`.**
Same pipeline as `canonicalName` (base-text split, fold, alias, light singularize), plus one extra
step: strip a **form/state modifier set** from *any* position (not just leading), then re-run the
existing descriptor strip + singularize. `canonicalName` (the grocery key) is **unchanged**.

New set — `comparisonFormModifiers` (state words the grocery key deliberately keeps but the matrix
should ignore): `dried, frozen, canned, jarred, bottled, fresh, smoked, cured, raw, cooked, roasted,
toasted, ripe, whole, boneless, skinless, packed`. Strip these anywhere in the token list, then let
the existing `leadingDescriptors` (prep/size) and singularizer finish the job. (Size words
`large/medium/small` are already stripped by `leadingDescriptors`; ensure the comparison path applies
that strip **anywhere**, so `medium garlic cloves` → `garlic cloves` even when `medium` isn't first.)

Worked traces (the acceptance bar):
- `dried ancho chiles` → strip `dried` → `ancho chiles` → `ancho chile`, and `ancho chiles` →
  `ancho chile` → **same row.**
- `8 oz frozen spinach` and `8 oz fresh spinach` → both `spinach` → **one row** (`fresh` already
  stripped today; `frozen` newly stripped).
- `medium garlic cloves` and `garlic cloves` → both `garlic clove` → **same row.**

Known residual (out of scope, note in PR): true head-noun extraction — `garlic cloves` vs `cloves
garlic` vs `garlic` — is model-shaped and not attempted here. Quantity-led raw text (`2 medium garlic
cloves` when `item` is nil) may retain the leading number; the matrix feeds parsed `item` first, so
this is an edge, not the common path.

**2. Point the matrix at the new key.** In `WorkbenchCompareCore.buildColumn`, key rows on
`CanonicalIngredient.comparisonKey(line.item ?? line.originalText)` computed **on read** — *not*
`line.canonicalIngredientName` (which returns the cached grocery key). No schema, no cache; the matrix
is already a pure read over loaded `RecipeDetailData`.

**3. Row label = the coarse base, not a per-recipe line.** With coarser keys, deriving the label from
one recipe's parsed `item` gives inconsistent headers (`Frozen spinach` vs `Spinach` for the same
row). Set the row label to the **comparison key, title-cased** (fall back to the existing behavior only
if the key is empty). The neutral base belongs in the row header; `fresh`/`frozen` belong in the cells,
which already show the authored line verbatim.

**Everything else in `WorkbenchCompareCore` stays:** the per-column ambiguity guard (two lines sharing
one key → both drop to `otherLines`), ordered-union row ordering, honest blank cells.

---

## Tests (swift-testing + CustomDump, pure — no UI, no model)

**`CanonicalIngredientTests` additions:**
- `comparisonKey` collapses `dried`/`frozen`/`canned`/`fresh`/`smoked` variants of a base to the base.
- `comparisonKey("dried ancho chiles") == comparisonKey("ancho chiles")`.
- `comparisonKey("medium garlic cloves") == comparisonKey("garlic cloves")`.
- **Regression guard:** `canonicalName` (grocery key) is **unchanged** for the same inputs —
  `canonicalName("frozen spinach") != canonicalName("fresh spinach")` still holds. The whole point is
  that grocery discrimination survives.

**`WorkbenchCompareTests` additions:**
- Two recipes with `8 oz fresh spinach` and `8 oz frozen spinach` produce **one** row labeled
  `Spinach`, with each cell preserving its authored line verbatim.
- `dried ancho chiles` + `ancho chiles` align to one row.
- The existing `otherLines` ambiguity behavior is unaffected.

**No changes to** `GroceryConsolidation`/`PantrySuppression` tests — assert by omission that shopping
behavior is untouched.

---

## Constants register (jon-platform: constants need a rationale)

- **`comparisonFormModifiers` (new).** The matrix tolerates false-merge (the difference is visible in
  the cells) but is defeated by false-split, so it strips the state words the grocery key must keep.
  The asymmetric cost-of-error — cheap/visible false-merge on compare vs. expensive false-merge on the
  shop — is the entire justification for a second key rather than one shared normalizer.

## Out of scope — with destinations

- **Structured `{ base, form, prep }` ingest** (the on-device model, grocery-milestone Decision #5) —
  the real convergence target; retires the hand-maintained modifier lists. Stays deferred.
- **Head-noun extraction / semantic equivalence** (`ancho = dried poblano`, `garlic cloves` ≡
  `garlic`) — model territory; not attempted deterministically.
- **Grocery `canonicalName` behavior** — deliberately not touched. Any change to what shopping merges
  is a separate, higher-risk effort.

## Verification

Package-only logic + one app-layer wiring change. `swift build` the package; run `xcodegen generate`
if any file is added; build `YesChef` once per the `CURRENT_HANDOFF.md` Verification Pattern. Jon does
the UI pass on the Compare matrix.
