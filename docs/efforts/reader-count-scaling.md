# Effort — Reader: scale count-only ingredients ("1 large onion") + fix unit plural agreement

Status: Dispatched 2026-09-30. Schema-free, `YesChefCore` only.
Summary: In the reader, ingredients with no unit ("1 large onion", "3 garlic cloves") show their unscaled amount
at any scale. It's a regression from the reader-density change (#323): the split two-line presentation
formats the stored quantity for unitless lines instead of taking the amount from the scaled text. Take it
from the scaled text. Rides along: a scaled unit reads singular at or below one ("¼ teaspoon", "1 tablespoon").
Related: [`ingredient-range-scaling.md`](ingredient-range-scaling.md) (#332, the reader range fix this sits
beside) · [`recipe-reader-density.md`](recipe-reader-density.md) (#323, which introduced the split rows)

## The bug (Jon, 2026-09-30, device screenshots at 4 → 8 servings)

Lines with a unit scale correctly (`3 tablespoons olive oil` → 6, `1 quart chicken stock` → 2 quarts, ranges
→ `16–20 ounces`). Lines with no unit don't: `1 large onion`, `1 large carrot`, and `3 garlic cloves` stay
at 1, 1 and 3.

`IngredientScaler.scaledText` is correct for these. The reader throws it away:
`IngredientLineReaderPresentation.display(for:scaledText:)` (`RecipeEnrichment.swift`) builds the primary
line from `amountAndUnit + item`, and when `line.unit` is nil it uses
`IngredientScaler.formattedQuantity(line.quantity)`. That's the **stored, unscaled** quantity. The unit
branch slices the amount out of `scaledText`, which is why measured lines work. `3 garlic cloves` lands in the
unitless branch because the parser only reads a unit right after the number, so here the unit is nil and the
item is `garlic cloves`.

## Fix 1 — unitless amount comes from the scaled text

In the `line.unit == nil` branch, take the amount from `scaledText`: the substring covered by
`QuantityParser.leadingQuantity(in: scaledText)`. That covers ranges too, so `2-3 carrots` at 2× reads
`4–6 carrots`. If no leading quantity is found, show no amount, as today when `quantity` is nil. At factor 1
the output must be unchanged.

Audit the rest of `display(for:scaledText:)` for any other read of stored `quantity` / `quantityText`
where the scaled text should be used, and fix those the same way.

## Fix 2 — plural agreement for a scaled unit

`IngredientScaler.pluralized(_:quantity:)` adds an `s` for any quantity other than 1, so `1/8 teaspoon` at 2×
reads `¼ teaspoons`. And it never singularizes, so `2 tablespoons` at ½× reads `1 tablespoons`. Use the
plural only when the scaled value is **greater than 1**. At or below 1, use the singular form of a unit the
parser knows (the singular/plural pairs in `IngredientParser.units`: `teaspoons` → `teaspoon`, `bunches` →
`bunch`, `boxes` → `box`, …). Leave a unit the parser doesn't know unchanged. Ranges keep their unit text as
written, as decided in #332.

## Tests

Next to the existing `IngredientLineReaderPresentation` tests (`RecipeEnrichmentTests`) and scaler tests:
- `1 large onion, diced` at 2× → primary `2 large onion`, secondary `diced`.
- `3 garlic cloves, minced` at 2× → `6 garlic cloves`.
- A unitless range at 2× (`2-3 carrots`) → `4–6 carrots`.
- Factor 1 is unchanged for every case.
- `1/8 teaspoon` at 2× → `¼ teaspoon`; `2 tablespoons` at ½× → `1 tablespoon`; `1 teaspoon` at 3× →
  `3 teaspoons`; an unknown unit is untouched.

## Out of scope

- Pluralizing the *item* (`2 large onion` rather than `2 large onions`). Nouns need an inflection table; not
  now.
- Scaling amounts inside preparation or comment prose (`preferably kale (up to 12 ounces`).

## Done when

Both fixes land with tests and `check-drift.sh` is green. Owed device pass: the soup at 4 → 8 servings shows
`2 large onion`, `2 large carrot`, `6 garlic cloves`, and `¼ teaspoon red-pepper flakes`.
