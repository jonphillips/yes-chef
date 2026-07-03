# Current Handoff

Last updated: July 3, 2026 (Cooking workspace Slice A approved, PR #73 → DONE-LOG; Next Up = Slice B — selection-scoped apply-actions + review card, ADR-0011 Amendment 1. Lean verification is now the default; reader photo affordances roadmapped in the effort doc.)

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

**Cooking workspace — Slice B (selection-scoped apply-actions + review card).** Full spec:
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice B, implementing
[ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md) Amendment 1. Slice A shipped the split +
dense reader + context-general host (PR #73). Now make *what the model writes* precise and human-chosen:
change `ChatApplyAction.extract` / `AnyChatApplyAction.run` from `(_ messages: [RecipeChatMessage])` to
`(_ selection: String, _ context: [RecipeChatMessage])`; text-selection over assistant messages arms the
action bar; **empty selection falls back to the whole last assistant reply** (selection is a precision
override, never a dead-button gate). Add the **review-before-commit card** in the inspector
(Commit / Discard; Commit lands in the reader in place — no chat turn writes on its own). Stage the review
surface as a **list** of committable results (N = 1 for make-ahead today) so Menu's multi-card motion
slots in later without a rewrite — don't build the multi-card UI. Now that the host is context-general,
**fold in the action-verb strings** Slice A deliberately left (`"Saving make-ahead…"` / `"Saved to
Make-ahead"` — drive them off the action, not hardcoded), since Slice B reshapes that surface anyway.
Own PR. In-memory-DB test the commit; `swift build` the package (FM bundle can't run here).

Then: **Phase E (grocery/pantry)** — [[grocery-pantry-threshold-design]] — while Jon experiments with the
new chat/make-ahead tools.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Cooking workspace** — Slice A complete (PR #73 → DONE-LOG); **Slice B is now Next Up**. Full spec
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md). Menu + Meal-Planner chat and the
  reader **photo affordances** (manual set-as-cover, pinch-zoom in the viewer) are named there as later
  efforts (host built context-general to receive them).

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
