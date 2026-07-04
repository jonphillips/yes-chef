# Current Handoff

Last updated: July 3, 2026 (Phase E Slice 3 approved, PR #79 → DONE-LOG. Next Up = Phase E Slice 4 —
`PantrySuppression` pure function + grocery-list review section (the milestone's payoff, no schema, no
dialog). Ready to dispatch to Codex. Lean verification is the default.)

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

**Phase E — grocery/pantry, Slice 4: `PantrySuppression` + grocery-list review section.** The
milestone's payoff — and its **final** slice. Full spec + build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md)
(read the **Slice 4** section, the **Definition of done** scenarios, and Decisions #2/#4/#7; boundaries in
FUTURE_INTELLIGENCE §7.5/§13/§14). **No schema change** this slice — it consumes the Slice 3 columns:
- **Pure `PantrySuppression.evaluate(list:policies:)`** over the **consolidated** list →
  `{ shown, assumedInPantry, needsReview }`. Unlimited match → `assumedInPantry`; threshold match with total
  **over or incomparable** → `needsReview`; threshold match **under** → `assumedInPantry`. Runs on the
  **cross-recipe consolidated total**, not per line (Decision #4). Incomparable units **fail safe to
  surfacing** (DoD #4). No model call on this path.
- **Wire into `GroceryModels` / `GroceryViews`:** a quiet **"Assumed in pantry"** section with one-tap
  add-back, and **promoted "You may need more — X (total)"** rows. **No blocking dialog anywhere.**
  `isPurchased` untouched (assumed-in-pantry is a distinct derived state, never written to the purchased flag).
- **Add-back is one-shot for the list** — moves a row to `shown` for that list only; it does **not** edit the
  pantry item's policy (Decision #7). A persistent "actually shop this" is a deliberate edit in the editor.
- **Tests (pure, no UI/model):** unlimited never shown; threshold under hidden, over surfaced; **cross-recipe
  total** over threshold surfaces though each line is under; incomparable units surface; add-back moves one
  row to `shown` and leaves policy untouched.
- **Done when:** the Definition-of-done scenarios all pass, suppression is a pure function, nothing is a modal.
  This **completes the grocery/pantry milestone** — tick the last box in the milestone doc.

Phase E Slice 3 (pantry policy + `canonicalName` cache migration) is **complete** (PR #79 → DONE-LOG); two
device-pass/release follow-ups recorded there (app-target build never ran in CI; promote the new CloudKit
fields to the production schema before a prod cut). Phase E Slice 1 + 2 (canonical key + `Measure`) is
**complete** (PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its named
follow-ons — **Menu + Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — in progress. Slices 1–3 (canonical key +
  `Measure` + pantry policy/`canonicalName` migration) **complete** (PRs #77, #79 → DONE-LOG). **Now Next Up =
  Slice 4** (`PantrySuppression` pure function + grocery-list review UI — the payoff and **final** slice,
  no schema change). Build order in
  [`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md);
  design rationale = [[grocery-pantry-threshold-design]]. Slice 4 closes the milestone.

- **Dogfood fixes — batch 3** — complete (PR #75 → DONE-LOG; ingredient structure · Chef It Up +
  Serve With · substitution · keep-awake). Non-blocking device-pass notes recorded in the DONE-LOG entry.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

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
