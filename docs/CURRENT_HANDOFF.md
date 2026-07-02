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

**Actionable chat — the lift + make-ahead (ADR-0011).** First cross-app instance of the
actionable-chat pattern. Full spec: [`docs/efforts/actionable-chat-make-ahead.md`](efforts/actionable-chat-make-ahead.md).
Decision: [`docs/decisions/ADR-0011-actionable-chat-make-ahead.md`](decisions/ADR-0011-actionable-chat-make-ahead.md).

Do the slices **in order**:
1. **Slice 1 — the lift** (`GalavantAI` → shared `packages/LLMClientKit`; a *move* not a copy). Three
   repos, three commits/PRs: **1a** create the package in jon-platform + EXTRACTION-NOTES row; **1b**
   galavant path-dep + delete + `import LLMClientKit` (use a **worktree** if parallel); **1c** yes-chef
   path-dep + **delete** its minimal `ModelClient`/`ClaudeAPIClient`, migrate `AISettingsView` onto the
   package's `APIKeyStore`, rewire the app to `TieredModelClient.live`. Prereq for Slice 2.
2. **Slice 2 — the abstraction + make-ahead** (yes-chef): additive `Recipe.makeAhead` column; a general
   `(extract → commit)` apply-action **catalog** (make-ahead = verb #1, not hardcoded); `MakeAheadPlan` +
   `MakeAheadPlanClient` (mirror `PlaceDiscoveryClient`); tested `applyMakeAheadPlan`; `RecipeChatContext`
   + `RecipeChatModel` (mirror `GalavantChat`) with markdown + editable pre-prompt parity; panel + button
   + "Make-ahead" section in `RecipeDetailView`.

Invariant (do not violate): the model proposes/structures; the **tap** is the only write. See the effort
doc for per-slice acceptance and the read-first list.

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
