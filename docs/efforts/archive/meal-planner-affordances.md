# Effort: Meal-planner (Calendar) row affordances swap (2026-07-11)

**Type:** App-layer UX rework of the meal-planner / calendar rows. No schema; the Edit-Dish sheet and the
recipe reader already exist — this reassigns which gesture opens which. **One dispatch.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready** (from Jon's 2026-07-11 two-device dogfood).

**Read before starting:** `MealCalendarViews.swift` + `MealCalendarModels.swift` (the meal-planner rows, the
current tap → Edit-Dish behavior, the existing target/"add to grocery" icon), `RecipeDetailView` (the reader
to open), and the Edit-Dish sheet in `MenuViews.swift`. Then `CURRENT_HANDOFF.md` Verification Pattern.

**Build/verify:** build once `-skipMacroValidation`; `scripts/check-drift.sh`; **no simulator install** — Jon
device-passes. Meal-planner is **iPad-primary** (`iPad Pro 13-inch (M5)`, both orientations) + `iPhone 17 Pro`.

---

## S1 — Reassign the row gestures

Today: **tapping a meal-planner recipe opens the Edit-Dish sheet.** Change to:

- **Tap the recipe → open the recipe** (the reader). This is the primary, expected gesture.
- **Right-hand affordances (two, per row):**
  1. The existing **target icon** — keep it as-is (the current grocery/target action).
  2. A new **calendar icon** → opens the **Edit-Dish sheet** (the sheet that tap currently triggers).

So the Edit-Dish sheet moves from row-tap to the explicit calendar-icon affordance, and row-tap is freed up to
open the recipe. Note-kind rows (no recipe) should keep sensible behavior — a note has nothing to "open," so it
either does nothing on tap or opens Edit-Dish directly (implementer's call; flag in the PR for Jon).

## Parked follow-on — drag-and-drop + cell images (NOT built here)

Jon wants to **retest drag-and-drop on iOS Beta 3**, scoped **per-day first** (constrain reordering within a
single day's containment to see whether the platform gesture behaves before attempting cross-day). And: show
the recipe's **photo on meal-planner cells** instead of the generic recipe icon (**notes keep the icon**).

This is the same parked drag-and-drop follow-on already noted for the menu screen
([`menu-planning-ux.md`](menu-planning-ux.md) "Out of scope", `docs/open-questions.md`) — it uses the iOS 27
reorder API (`swiftui-whats-new-27` skill). **Deferred until Jon confirms Beta 3 makes the gesture viable;**
not part of the S1 dispatch. The cell-image change can ride with the drag-drop slice or land as a tiny
standalone once the reorder question is settled.
