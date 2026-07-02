# Current Handoff

Last updated: July 2, 2026

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

- **Dogfood fixes — batch 1, Slice 7 — Edit a grocery item (name + amount).**
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) §Slice 7. Grocery rows
  can't be edited today. Add an edit affordance for a grocery item's **name** and
  **amount/quantity**, kept compatible with the source-provenance model — a manual edit to a
  *generated* row must not silently corrupt its `GroceryItemSource` breakdown. Decide and test the
  interaction (e.g. an edited row detaches to a custom/edited state, or the edit is preserved
  distinctly) and **flag the provenance interaction in the PR.** **Done when:** name and amount are
  editable and the change persists without breaking the source breakdown.

  **Remaining batch-1 order after this:** UX Slices 8–9 (×2/×3 recipe multiplier, add image to a
  manual recipe). These are independent one-file view tweaks — **candidates to batch into a single
  dispatch/PR** (see `docs/AGENTS.md` § Work Intake & Dispatch on batching cohesive slices).

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batch 1 (bugs + near-term UX)** — in progress.
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md). Slices 1–6 done (see
  [DONE-LOG](DONE-LOG.md)); Slice 7 is Next Up; Slices 8–9 remain.

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
