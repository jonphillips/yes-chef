# Effort: Fraction input accessory for ingredient authoring (2026-07-11)

**Type:** New authoring affordance — a Paprika-style set of **fraction pills** offered while entering
ingredient text, so the cook picks pretty glyphs (¼ ½ ¾ ⅓ ⅔ ⅛ …) instead of typing clumsy `1/4`, `1/2`.
App-layer; no schema. **Standalone slice** (larger than the mechanical chrome bundle — its own dispatch).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **DONE — implemented, architect-reviewed, and device-passed (Jon, 2026-07-12).** Shipped as an
inline pill row above the ingredient editor (`safeAreaInset`/`@FocusState`), the full glyph set
¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞ (`ScaleFraction.ingredientInputCases`), append-at-end insertion, unit-tested. Archive to
DONE-LOG on merge. Surface + scope decided with Jon 2026-07-11/12 (see Decided).

**Read before starting:** the structured ingredient editor (`IngredientLine`/`IngredientSection` authoring UI),
and [`recipe-multiplier-rework.md`](recipe-multiplier-rework.md) Slice A — the vulgar-fraction glyph map
(¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞) and the mixed-number *rendering* already exist there for **scaling**; this reuses the
same glyph set for **input**. Then `CURRENT_HANDOFF.md` Verification Pattern.

## Design

Paprika surfaces a row of fraction pills (Jon: "maybe on the keyboard") while editing an ingredient quantity.
Adopt the same as an **inline pill row** (decided with Jon 2026-07-11): a horizontal row of fraction glyphs
shown above/near the focused ingredient field, gated on `@FocusState`, tapping one **appends** the glyph to
that field's bound string. Reuse the existing glyph set from the multiplier work so authoring and scaling
agree on which fractions are "nice".

**Why inline row, not a keyboard `inputAccessoryView`:** the inline row is pure SwiftUI (`@FocusState` +
conditional view), whereas a real keyboard accessory on a SwiftUI `TextField` requires `UIViewRepresentable`
or introspection. **Shared caveat:** SwiftUI `TextField` exposes no cursor position, so insertion is
**append-to-the-focused-field** rather than insert-at-cursor — acceptable for fractions (type "1 ", tap ½).
Only introspect down to UIKit if append-at-end proves too clumsy in the device pass.

**Why this over free typing:** the scaler already parses vulgar-fraction glyphs correctly (multiplier-rework
Slice A), so a `1 ½ tsp` authored via pills scales properly — whereas hand-typed `1 1/2` is a second-class
citizen. Pills make the well-supported path the easy path.

## Decided (Jon, 2026-07-12) — all confirms closed

- **Surface — inline pill row** (see Design). Not the keyboard accessory.
- **Scope of glyphs — the FULL multiplier-rework set** (¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞), so authoring and scaling stay in
  lockstep on which fractions are "nice". Not the reduced common-four set.
- **Independence — ships on its own now.** The "ingredient authoring — formatting fidelity" fork
  (`docs/open-questions.md`, 2026-07-02: bold/italic/header structure) is a **separate, later** effort;
  fractions are orthogonal and are **not** designed together with it.
