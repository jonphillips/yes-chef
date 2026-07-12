# Effort: Fraction input accessory for ingredient authoring (2026-07-11)

**Type:** New authoring affordance — a Paprika-style set of **fraction pills** offered while entering
ingredient text, so the cook picks pretty glyphs (¼ ½ ¾ ⅓ ⅔ ⅛ …) instead of typing clumsy `1/4`, `1/2`.
App-layer; no schema. **Standalone slice** (larger than the mechanical chrome bundle — its own dispatch).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready.** Surface decided (inline pill row, Jon 2026-07-11); only the glyph-set scope is still an
open confirm (see Open).

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

## Open (confirm with Jon before build)

- **Surface: DECIDED — inline pill row** (see Design). Not the keyboard accessory.
- **Scope of glyphs:** the multiplier-rework set (¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞) — confirm that covers what Jon wants, or
  whether it's just the common four (¼ ½ ¾ ⅓).
- **Interaction with the "ingredient authoring — formatting fidelity" open question** (`docs/open-questions.md`,
  2026-07-02): that fork is about bold/italic/header structure, a different axis; fractions are orthogonal and
  can ship independently. Confirm no one wants them designed together.
