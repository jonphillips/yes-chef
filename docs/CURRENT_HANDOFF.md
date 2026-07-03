# Current Handoff

Last updated: July 3, 2026 (Cooking workspace Slice B approved, PR #74 → DONE-LOG — cooking-workspace effort complete; Next Up = Phase E (grocery/pantry). Lean verification is the default; Menu/Planner chat verbs + reader photo affordances roadmapped in the effort doc.)

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

**Recipe → grocery list w/ pantry checking (Phase E).** Full spec: [[grocery-pantry-threshold-design]].
Make it slick early — canonical-key merge across recipes, static pantry thresholds, dialog-free (no
inventory). Lower priority than the (now-complete) dogfood/cooking-workspace work per Jon's stated intent
(2026-07-01), so slice scope is open — **STOP and confirm the first slice's shape with Jon before
dispatching** rather than inferring it from the design memo.

The cooking-workspace effort is **complete** (Slices A + B shipped, PRs #73 / #74 → DONE-LOG). Its named
follow-ons — **Menu + Meal-Planner chat verbs** and **reader photo affordances** (manual set-as-cover,
pinch-zoom) — live in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate
later efforts; the host was built context-general to receive them. Jon is dogfooding the new
chat/make-ahead tools, which may reprioritize.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Recipe → grocery list w/ pantry checking** (Phase E) — **now Next Up**. Make it slick early
  (canonical-key merge, static pantry thresholds, dialog-free); spec = [[grocery-pantry-threshold-design]].

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Menu + Meal-Planner chat
  verbs and the reader **photo affordances** (manual set-as-cover, pinch-zoom in the viewer) are named in
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as later efforts (host built
  context-general to receive them).

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the
device pass regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files.
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise build `YesChef` **once** for `iPad Pro 13-inch (M5) (16GB)` (`-skipMacroValidation`).
- Run `scripts/check-drift.sh`.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
