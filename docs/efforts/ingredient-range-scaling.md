# Effort — Scale ingredient ranges ("8-10 ounces") + label a blocked compare fallback

Status: Dispatched 2026-09-30. Schema-free, `YesChefCore` only.
Summary: An ingredient written as a range ("8-10 ounces", "8–10 oz", "8 to 10 ounces") doesn't change when the
recipe is scaled. Scale both ends of a leading range at display time, the way the yield scaler already does,
so existing lines are fixed without re-parsing. Rides along: the compare aligner labels a provider-blocked
response as its own fallback reason instead of `.truncated`.
Related: [`recipe-adjustment-content-filter.md`](recipe-adjustment-content-filter.md) (PR #330, where the
label nit was raised) · ADR-0022 (grocery merge stays deterministic; not touched here)

## The bug (Jon, 2026-09-30)

Scaling a recipe leaves range lines unchanged. There are two paths, and both end in "return the original text":

- **`8-10 ounces kale` / `8–10 ounces kale`** (no spaces). `IngredientParser.parse` tries the first token,
  `8-10`, as a number. `Double`, the fraction parse and the mixed-number parse all fail, so the line is stored
  with `quantity == nil`, and `IngredientScaler.scaledText(for:factor:)` returns early on its `line.quantity`
  guard.
- **`8 to 10 ounces kale` / `8 - 10 ounces`** (spaced). The line stores `quantity = 8, quantityText = "8"`, and
  the unit is read correctly because `strippingAlternateMeasurement` drops `to 10`. But
  `replacingLeadingMeasure` expects the unit straight after `quantityText`, finds `to 10 …`, and returns
  nil.

The pieces already exist. `QuantityParser.leadingQuantity(in:)` reads all four spellings as a range
(`value`, `upperBound`, and the `range` covering both numbers), and `RecipeYieldScaler.scaledText` already
scales a range as `lo–hi`.

## Fix 1 — range-aware `IngredientScaler.scaledText(for:factor:)`

1. Before the existing `line.quantity` path, when `factor != 1`: if
   `QuantityParser.leadingQuantity(in: line.originalText)` has an `upperBound`, replace its `range` with
   `formattedQuantity(value × factor)–formattedQuantity(upperBound × factor)` and keep the rest of the text
   unchanged. That mirrors `RecipeYieldScaler`: it normalizes to an en dash and leaves the unit's wording alone.
   Otherwise, fall through to today's code, unchanged.
2. **Keep it anchored.** Use `leadingQuantity`, never `firstQuantity`. Its doc comment explains why ("onions,
   about 2 handfuls" must not scale).
3. **Don't treat a hyphenated dimension as a range.** `2-3-inch pieces` and `1-2-inch chunks` describe a size,
   not an amount. If the character right after the parsed range is `-`, it's not a range, so fall through.
   (`1-inch piece ginger` already doesn't parse as a range, since `inch` isn't a number, but test it anyway.)
4. **Don't change `IngredientParser.parse` or the stored columns.** Grocery reads `quantity`, and changing what
   gets stored changes grocery merging (ADR-0022). Fixing this at display time also covers lines already
   stored, with no backfill.
5. Tests: add them next to the existing scaler tests. At 2×: `8-10 ounces kale` → `16–20 ounces kale`;
   `8–10 oz` and `8 to 10 ounces` and `8 - 10 ounces` → `16–20 …`; `1½-2 cups` at 2× → `3–4 cups`; ½× gives
   fractions (`8-10` → `4–5`). Factor 1 returns the text unchanged. `2-3-inch pieces` and `1-inch piece ginger`
   don't scale as ranges. Single-quantity lines behave exactly as today (existing tests stay green).

Both reader call sites (`RecipeDetailView` ingredient rows and `GroceryIngredientChoiceViews`) go through this
one function, so neither needs changing.

## Fix 2 — `WorkbenchAlignedComparison.FallbackReason.blocked`

`WorkbenchCompareAligner` records a provider-blocked response (`wasBlockedByProvider`, #330) as
`.fallback(.truncated)`. The fallback behaviour is right, but the label is wrong. Add `case blocked` to
`FallbackReason` and return `.fallback(.blocked)` there. `FallbackReason` is `Codable`, but nothing persists it
or switches on it outside Core, so adding a case is safe. Extend the aligner tests so a `content_filter` stop
returns `.fallback(.blocked)`.

## Out of scope

- **Grocery for range lines.** `8-10` lines reach grocery with no quantity and unscaled text, and `8 to 10`
  lines merge as 8. What grocery should do with a range is a product decision (upper bound? keep the text?),
  parked in `open-questions.md`.
- Singular/plural agreement after a scaled range (`½–1 cups`). This matches the yield scaler; revisit only if it
  bothers you.

## Done when

Both fixes land with tests and `check-drift.sh` is green. Owed device pass: scale a recipe with an
`8-10 ounces` line to 2× and ½× in the reader.
