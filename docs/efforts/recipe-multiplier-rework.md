# Effort: Recipe-multiplier rework (dogfood-driven)

**Type:** Correctness + UX + small schema. Driven by Jon's own use of recipe scaling.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** Scoped + decisions locked 2026-07-02. Not yet dispatched.

**Why:** Jon scales recipes constantly and hit three problems: the 1×/2×/3× buttons are a poor fit for
how he actually dials scale; unicode fractions ("1 ¼ tsp") scale wrong; and the multiplier is ephemeral
(resets on every navigation) with no way to hold different scales for the same recipe in different places.

**Locked decisions (Jon, 2026-07-02):**
- Bare-recipe scale persists as a **synced `viewScale` column on `recipes`** (not device-local).
- The dial **scales down and up** (⅓×, ½×, ¾× … through the top of the range), not 1×-and-up only.

**Do the slices in order-ish.** A and B both touch the scaling surface and can bundle into one dispatch;
C is its own dispatch (schema + navigation). Invariant: parsing/scaling stays pure and tested in
`YesChefCore`; the app model only holds/persists the chosen factor.

**Test/build reality (house constraint):** `swift build` for the package; build the app with
`-skipMacroValidation`; run `xcodegen generate` after adding Swift files; then the Verification Pattern
in `CURRENT_HANDOFF.md`. Jon does the primary UI pass.

**Read before starting:** `YesChefApp/RecipeModels.swift` (the `RecipeDetailModel` scaling block ~L828–L971
and `ScaleFraction`/`ScaleText` ~L997–L1088), `YesChefPackage/Sources/YesChefCore/RecipeCore.swift`
(`IngredientScaler` ~L860, `IngredientParser` is its own file), and
`YesChefPackage/Sources/YesChefCore/Models.swift` (`Recipe`, `menuItems` L288, `mealPlanItems` L162).

---

## SLICE A — Unicode-fraction parsing (pure bug fix, ship first)

**Bug:** `IngredientParser.fractionValue` only understands ASCII `n/d` (it splits on `"/"`). A vulgar
fraction glyph ("¼") has no slash, so "1 ¼ teaspoon" falls back to `Double("1")` = 1.0 and the ¼ leaks
into the item text unscaled → ×2 renders "2 ¼ teaspoons".

**Fix (all in `YesChefCore`, unit-tested):**
- In `IngredientParser.fractionValue`, map the vulgar-fraction glyphs to decimals: ¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞
  (and ⅕/⅖/⅗/⅘, ⅙/⅚ if trivial). Handle both spaced ("1 ¼") and unspaced ("1¼") mixed numbers — the
  unspaced form is a single token that currently bypasses the two-token whole+fraction branch.
- In `IngredientScaler.format`, render results back as mixed-number fractions ("2 ½") rather than "2.5"
  for the common denominators, so scaled output reads like a recipe. Keep 0–2 decimal fallback for
  values that don't land on a nice fraction.

**Acceptance:** "1 ¼ teaspoon salt" ×2 → "2 ½ teaspoons salt"; "⅓ cup" ×3 → "1 cup"; a non-fraction
quantity is unchanged. Tests cover spaced, unspaced, glyph-only, and scale-to-whole cases.

---

## SLICE B — Dials become the multiplier

**Change:** Make the servings-style dial set the **scale factor directly** and retire the "target
servings" framing. Servings becomes a read-only derived line.

The model already collapses both controls onto `scaleFactor`; there is already a no-servings branch
(`RecipeModels.swift:960`) that treats the dial value as a direct multiplier. Generalize that branch:
- `scalePickerChanged` sets `scaleFactor = Double(scaleWholePart) + scaleFraction.value` **always**.
- Remove `setScaledServings` and the `scaledServings`/`baseServings`-as-target math from the input path.
- Keep a **read-only** "makes ~N servings" line derived from `baseServings × scaleFactor` when a serving
  count is parseable; it's informational, not an input.
- Relabel the picker as a multiplier (1×, 1¼×, 1½×, 2×, 3× …) and extend `ScaleFraction`/the whole-number
  range to include **sub-1×** steps (⅓×, ½×, ¾×). Retire or fold the 1×/2×/3× quick buttons into the dial.

**Acceptance:** dial reads as "×N"; scaling up and down both work; a recipe with no parsed servings behaves
identically to one with servings (no dead "0 servings" state); "makes ~N servings" shows only when known.

---

## SLICE C — Per-placement persisted scale

**Change:** Scale stops being ephemeral view state and becomes a property of the **placement** the recipe
was opened from, persisted so it survives navigation and doesn't bleed across contexts.

Model:
- Add additive, sync-safe `scale: Double` (default 1.0) columns to `menuItems` and `mealPlanItems`, and a
  `viewScale: Double` (default 1.0) column to `recipes` (the bare-recipe placement). One migration.
- Introduce a small `ScaleContext` (e.g. `.recipe(Recipe.ID)` / `.menuItem(id)` / `.mealPlanItem(id)`)
  injected into `RecipeDetailModel`. The model reads the initial factor from, and writes changes back to,
  the storage site the context names — via one read/write seam, not a branch per screen. `RecipeDetailView`
  stays context-agnostic: "load the scale for how I got here; persist it when the dial changes."
- Construct the detail model with the matching context at each entry point.

**Investigation (do this first in Slice C):** today all three `RecipeDetailView(` constructions live in
`RecipeLibraryView.swift`; `MenuViews`/`MealCalendarViews` don't currently open recipe detail. So "scale it
in the menu / the planner" likely requires those surfaces to **route into the detail view carrying their
placement context** — confirm whether that navigation exists or must be added, and size it before building.
This is the one part that can grow beyond "add a column."

**Acceptance:** set 3× on a recipe inside a menu; leave and reopen it there → still 3×; open the same recipe
from the library → shows its own (bare) scale, unaffected; the meal planner holds its own scale
independently. Scales round-trip through iCloud sync (they're on synced rows).

---

## Out of scope (named, deferred)
- Unit conversion / "smart" halving of awkward quantities (3 eggs ÷ 2). Scaling stays arithmetic.
- Re-parsing or normalizing ingredient text on scale — we scale the parsed quantity, not rewrite the line.
