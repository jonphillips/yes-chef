# Effort — Scale ingredient ranges ("8-10 ounces") in the reader and grocery + label a blocked compare fallback

Status: Dispatched 2026-09-30. Schema-free, `YesChefCore` only (one post-engine data pass).
Summary: An ingredient written as a range ("8-10 ounces", "8–10 oz", "8 to 10 ounces") doesn't change when the
recipe is scaled, and grocery drops or garbles it. The reader scales both ends of the range; grocery shops the
upper bound (scaled), via the parser storing the upper bound as the line's quantity plus a post-engine repair of
existing range lines. Rides along: the compare aligner labels a provider-blocked response as its own fallback
reason instead of `.truncated`.
Related: [`recipe-adjustment-content-filter.md`](recipe-adjustment-content-filter.md) (PR #330, where the
label nit was raised) · ADR-0022 (grocery merge stays deterministic: the upper bound is a fixed rule, not a judgment)

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
   Put "leading ingredient range, excluding hyphenated dimensions" in **one** `QuantityParser` helper; Fix 3's
   parser uses the same helper, so the reader and grocery can never disagree about what counts as a range.
4. **The reader keys off `originalText`, not the stored columns.** So it shows the range (`16–20 ounces`)
   even though Fix 3 stores the upper bound as `quantity`, and the range check runs before today's
   `line.quantity` path.
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

## Fix 3 — grocery shops the upper bound

**Decision (Jon, 2026-09-30):** a range shops as its **upper bound**, scaled. `8-10 ounces kale` at 2× goes to
the list as 20 oz. It's better to have a little extra than too little, and a single number merges with other
lines under the existing ADR-0022 rules.

1. **Parser.** In `IngredientParser.parse`, when the ingredient part starts with a range (Fix 1's helper), store
   `quantity = upperBound` and `quantityText = the range as written` (`8-10`, `8 to 10`, `1½-2`). Then read
   unit and item from the tokens *after* the range. `8-10 ounces kale` → quantity 10, unit `ounces`, item
   `kale` (today it's quantity nil and item `8-10 ounces kale`). `8 to 10 ounces kale` → quantity 10
   (today 8). `canonicalName` then follows from the corrected item, so the kale line merges with other kale.
2. **Grocery display.** `GroceryGeneratedItemDraft` shows a range line's quantity as the formatted, scaled upper
   bound **at every scale, 1× included**. So the list always shows the amount it's actually counting: `10`,
   not `8-10` with a hidden 10. Non-range lines are unchanged: at 1× they keep their written `quantityText`.
3. **Repair existing lines: a post-engine data pass, never a migration.** Writes inside a migration get no
   sync metadata and never upload. Add `RecipeRepository.reparseIngredientRanges(in:)` to the
   `runsPostEngineDataPasses` block in `Schema.swift`, next to `backfillVariationAnchors`, and log findings
   the same way. For each non-header line whose `originalText` is a range (the same helper), re-parse it and
   write **only** the parsed fields: `quantity`, `quantityText`, `unit`, `item`, `canonicalName`,
   `preparation`, `confidence`. Keep `comment`, `shoppingCategory`, `isOptional`, `doNotShop`, `sortOrder`,
   and `originalText`. Write only when something differs, so it's idempotent and deterministic across
   devices.
   **Touch range lines only.** A general re-parse would sweep years of parser drift into synced writes.
4. **Other parse callers**, which should all get better; confirm with a test each:
   `IngredientSectionHeading` (a range line was "quantity nil"; it must not start looking like a heading or
   stop looking like one wrongly), `GroceryRapidAddItem` (`8-10 apples` typed into grocery → 10),
   `RecipeExtractionIssue` (range lines stop being flagged as unparsed).
5. Tests: the parser outputs above. Grocery generation of a range line at 1× → 10, at 2× → 20, and merged with
   a `6 ounces kale` line from another recipe → 16 (same unit). The repair pass updates a stored
   `8-10 ounces kale` line (nil quantity) and an `8 to 10` line (quantity 8), leaves a stale **non-range**
   line untouched, keeps `comment`/`shoppingCategory`, and writes nothing on a second run.

## Out of scope

- Carrying the range itself onto the grocery list (`16–20 oz`). The upper bound was chosen instead.
- Singular/plural agreement after a scaled range (`½–1 cups`). This matches the yield scaler; revisit only if it
  bothers you.

## Done when

All three fixes land with tests and `check-drift.sh` is green. Owed device pass: scale a recipe with an
`8-10 ounces` line to 2× and ½× in the reader, then add it to grocery at 2× and see the upper bound (20 oz).
On a second device, the repaired existing lines arrive through sync.
