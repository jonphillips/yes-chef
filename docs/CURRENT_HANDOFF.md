# Current Handoff

Last updated: July 3, 2026 (Dogfood batch 2 merged, PR #71 → DONE-LOG; Next Up = Cooking workspace Slice A. Workspace design converged with Jon + spec'd; ADR-0011 Amendment 1 Accepted; Menu/Planner chat named as later efforts)

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

**Cooking workspace — Slice A (the split + dense reader).** Full spec:
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice A. Re-present
`RecipeDetailView`: replace the photo-forward reader + chat `.sheet` with the **detented draggable split**
— a width-responsive reader (two-column ≥ threshold in both iPad orientations; iPhone segmented
ingredients/directions layout when narrow) + the existing `RecipeChatModel` re-hosted into the inspector
pane (no chat *behavior* change in this slice). Scale control → toolbar (structurally supersedes batch 2's
tactical clip fix). Grabber + detents (reader-only / balanced / chat-dive) + persistence + a VoiceOver
detent-cycler. **iPad-only split**; iPhone keeps chat as a separate presentation. **Build the host
context-general** (takes a `RecipeChatContext` + catalog — do not weld into `RecipeDetailView`) so Menu +
Meal-Planner chat (Jon, 2026-07-03) slot in later. Then **Slice B** (selection-scoped apply-actions +
review card, ADR-0011 Amendment 1) as its own PR.

Then: **Phase E (grocery/pantry)** — [[grocery-pantry-threshold-design]] — while Jon experiments with the
new chat/make-ahead tools.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Cooking workspace** — now **Next Up (Slice A)**; full spec
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md). Menu + Meal-Planner chat named
  there as later efforts (host built context-general to receive them).

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
