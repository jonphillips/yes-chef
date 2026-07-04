# Current Handoff

Last updated: July 4, 2026 (**ADR-0013 Accepted** — Meal-Planner actionable chat, D1–D3 ratified.
**Next Up = ADR-0013 Slice 1** — `.mealPlan` chat context + selected-day grounded chat, no commit verb,
no schema (dispatchable to Codex). ADR-0012 fully complete (S3, PR #83 → merged). Lean verification is
the default.)

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

**ADR-0013 Slice 1 — `.mealPlan` chat context + selected-day grounded chat (no commit verb).** Read
[`docs/decisions/ADR-0013-meal-planner-actionable-chat.md`](decisions/ADR-0013-meal-planner-actionable-chat.md)
first — **Accepted**, D1–D6 resolved, do not re-open them. This is the planner instance of actionable chat,
the follow-on ADR-0012 named. It mirrors **ADR-0012 S1** (the `.menu` context slice, PR #81) on the
absolute-date planner surface. This dispatch is **S1 only**; the complement verb is S2. **No schema change.**

S1 concretely:
- Add **`case mealPlan(MealPlanChatContext)`** to `RecipeChatContext` (additive enum case, alongside
  `.recipe`/`.menu`), with a `serialized()` that builds the **selected-day composite grounding** (ADR-0013
  D1 + D6): one structured summary per `MealPlanItem` on the subject day — the day's **absolute date rendered
  as weekday + date** ("Tuesday, July 8"), `mealSlot`, title, and for recipe-kind items the key ingredients
  (capped), prep/cook/total times, and the recipe's existing `makeAhead` verbatim. Same budget guardrail as
  ADR-0012 D4 (summaries only, never full bodies); N is a single day, so this is cheap. Model the context
  type and its serializer on `MenuChatContext`.
- **Host the existing `ChatWorkspaceSplit`** in `MealCalendarDayAgendaView`, scoped to
  `MealCalendarModel.selectedDate` — the same wiring `MenuViews` uses (`ChatWorkspaceSplit(context:...,
  applyActions:)` + a compact `RecipeChatModel` path). The apply-action catalog is **empty this slice**
  (`applyActions: { _ in [] }`) — S2 fills it. **Critique works immediately as plain chat** (D5): with the
  day seeded, "what's missing / what's wrong on Tuesday" is answered conversationally for free, no verb.
- **No commit path, no schema, no repository change** this slice. The tap-writes invariant is trivially held
  because there is nothing to commit yet.

Reuse the ADR-0012 S1 shapes throughout (context case + serializer + split host). Classify commit shape only
when S2 lands (per-item insert → `MealPlanItem`; [[chat-verb-commit-shapes]] / [[menu-item-recipe-id-invariant]]).

**Next after this (not this dispatch): ADR-0013 S2** — the complement verb → inserts a `MealPlanItem` onto the
selected day (coerce to `.note`), reusing the `MealCalendarRepository` insert path. No schema change.

**Standing release follow-up carried from Phase E (not a dispatch on its own):** before any prod/TestFlight
cut, promote to the **production** schema both the Phase E Slice 3 pantry-policy + `canonicalName` CloudKit
fields **and** the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82 — the effort's first schema touch), and
note the app target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

Phase E is **fully complete** — Slice 4 (`PantrySuppression` + review UI, PR #80 → DONE-LOG), Slice 3
(pantry policy + `canonicalName` migration, PR #79 → DONE-LOG), Slices 1 + 2 (canonical key + `Measure`,
PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its **Menu chat-verbs** follow-on shipped as ADR-0012 (complete). Its remaining
named follow-ons — **Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — **complete.** All four slices shipped: canonical
  key + `Measure` (PR #77), pantry policy + `canonicalName` migration (PR #79), `PantrySuppression` + review
  UI (PR #80) — all → DONE-LOG. Design rationale = [[grocery-pantry-threshold-design]]. Standing release
  follow-up (promote CloudKit fields to prod schema) noted under Next Up.

- **Actionable chat / LLMClientKit** (ADR-0011) — **complete.** The lift (Slice 1, 3 repos) + make-ahead
  (Slice 2) + Chef It Up / Serve With / per-line substitution shipped 2026-07-02/03 (PRs #73–#75 →
  DONE-LOG); `LLMClientKit` is a live path-dep. The **Menu** verb instance shipped as ADR-0012 (complete,
  above). The one remaining named-later verb — **Meal-Planner chat verbs** (`MealPlanItem`, absolute-date) —
  lives in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md); classify each new verb's
  commit shape first ([[chat-verb-commit-shapes]]).

- **Dogfood fixes — batch 3** — complete (PR #75 → DONE-LOG; ingredient structure · Chef It Up +
  Serve With · substitution · keep-awake). Non-blocking device-pass notes recorded in the DONE-LOG entry.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Menu actionable chat** (ADR-0012, **Accepted** 2026-07-03) — **complete.** All three slices shipped:
  S1 (`.menu` context + composite grounding + grounded chat, PR #81 → DONE-LOG, no schema), S2 (prep-plan verb
  → `Menu.prepPlan`, PR #82 → DONE-LOG; the effort's first schema touch), S3 (complement verb → inserts a
  `MenuItem`, PR #83 → DONE-LOG, no schema). The Planner-day (`MealPlanItem`, absolute-date) version is a
  **separate follow-on ADR** (now ADR-0013, Accepted — in Next Up). Design + all five resolved decisions in
  [`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Meal-Planner actionable chat** (ADR-0013, **Accepted** 2026-07-04) — the planner instance of actionable
  chat over `MealPlanItem`'s absolute `scheduledDate`; the ADR-0012 planner follow-on. **S1 is in Next Up**
  (`.mealPlan` context + selected-day grounded chat, no schema); **S2** = complement verb → inserts a
  `MealPlanItem` on the selected day (coerce to `.note`, no schema). Two slices, zero schema touch. Day-scoped
  (D1), inserts land on the subject day with model-picked slot (D2), no planner prep-plan verb (D3, no
  container table). Design in
  [`docs/decisions/ADR-0013-meal-planner-actionable-chat.md`](decisions/ADR-0013-meal-planner-actionable-chat.md).

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Its Menu chat-verbs
  follow-on is now its own effort above (ADR-0012). The reader **photo affordances** (manual set-as-cover,
  pinch-zoom in the viewer) remain a named later effort in
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) (host built context-general to
  receive them).

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
