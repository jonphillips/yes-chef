# Current Handoff

Last updated: July 3, 2026 (Recipe-multiplier A+B approved, PR #69 → DONE-LOG; Next Up = Slice C per-placement persisted scale)

The **short entry point** for a fresh Yes Chef conversation. This file is deliberately lean: it holds
**Next Up** (the dispatch target), the **Ready Efforts** queue, and the **Verification Pattern** —
nothing else. Completed-slice history, the implemented-behavior checkpoint, and strategic background
live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**Single dispatch target.** Dispatch to the coding agent with:
*"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."* If this section is empty, missing, or
ambiguous, the agent must **STOP and ask Jon — never infer the next task.** See
`docs/AGENTS.md` § Work Intake & Dispatch. A dispatch may bundle **several cohesive slices** (one
PR); do all listed, in order.

**Recipe-multiplier rework — Slice C (per-placement persisted scale).** Slices A+B approved and merging
(PR #69: unicode-fraction parse fix + dial-as-multiplier). Full spec:
[`docs/efforts/recipe-multiplier-rework.md`](efforts/recipe-multiplier-rework.md) § Slice C. Add additive,
sync-safe `viewScale: Double` (default 1.0) to `recipes` and `scale: Double` (default 1.0) to `menuItems`
and `mealPlanItems` (one migration); introduce a small injected `ScaleContext`
(`.recipe(id)`/`.menuItem(id)`/`.mealPlanItem(id)`) so `RecipeDetailModel` reads the initial factor from,
and writes changes back to, the storage site the context names — one read/write seam, not a branch per
screen. Locked: bare-recipe scale **syncs** (recipes column); scales round-trip through iCloud.
**Investigation first (do before building):** confirm whether the menu/planner surfaces route into recipe
detail today (all three `RecipeDetailView(` constructions currently live in `RecipeLibraryView.swift`;
`MenuViews`/`MealCalendarViews` may not open detail at all) — sizing that navigation is the one part that
can grow beyond "add a column."

Then: **Phase E (grocery/pantry)** — [[grocery-pantry-threshold-design]] — while Jon experiments with the
new chat/make-ahead tools.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batch 1 (bugs + near-term UX)** — complete.
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md). The Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in the effort doc for a later grocery
  slice.

- **Recipe → grocery list w/ pantry checking** (Phase E) — make it slick early (canonical-key merge,
  static pantry thresholds, dialog-free); spec = [[grocery-pantry-threshold-design]]. Lower priority
  than the dogfood batch per Jon's stated intent (2026-07-01).

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Before checkpointing UI work:

- Run `xcodegen generate` after adding Swift source files.
- Build `YesChef` for `iPad Pro 13-inch (M5) (16GB)`.
- Run `scripts/check-drift.sh`.
- Install and launch on both active iOS 27 simulators:
  - `iPad Pro 13-inch (M5) (16GB)`
  - `iPhone 17 Pro`

Jon performs the primary UI testing pass.
