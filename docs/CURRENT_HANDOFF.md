# Current Handoff

Last updated: July 5, 2026 (**Chat persistence complete** — ADR-0015 shipped: local-only per-subject
`chatMessages` store, 1-month prune, excluded from the SyncEngine, PR #89 → DONE-LOG. **Next Up =
cooking-workspace reader + planner follow-ons** (two cohesive slices, one PR, **zero schema**):
independently-scrollable dense-reader columns + a day-scoped planner make-ahead verb. Lean verification is
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

**Cooking-workspace reader + planner follow-ons (two cohesive slices, one PR — zero schema).** Both are
queued dogfood follow-ons in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) — read that
first. Batched deliberately to keep schema mutable (see the dev-stance note below). Do both, in order:

1. **Independently-scrollable dense-reader columns** (§ Slice A "Queued reader polish"). In the two-column
   iPad reader, ingredients and directions share one scroll today; give each column its own `ScrollView`
   so a long ingredient list and long instructions scroll separately. The narrow/segmented layout is
   unaffected (only one column is visible there). Pure UI, no schema.
2. **Day-scoped planner make-ahead verb** (§ "Out of scope → Meal Planner context"). A "make-ahead
   strategy" chat verb over *all* items on the selected planner day — synthesize a prep sequence across the
   day's recipes, leaning on each recipe's saved `makeAhead` where present. **Classify the commit shape
   first** ([[chat-verb-commit-shapes]]): land it as a **no-commit advisory or a `.note` `MealPlanItem`** on
   the day — ADR-0013 already established there's **no planner container table**, so do **not** add a schema
   field. Respect [[llm-curation-not-synthesis]]: sequence/select distinct prep steps, never flatten the
   recipes into one blob.

Both are iPad-primary — Jon's device pass covers both orientations. Verify per the Verification Pattern.

**Standing release follow-up carried from Phase E (not a dispatch — a pre-cut ops step Jon runs).** We stay
in the CloudKit **Development** environment (dev stance) so the schema keeps evolving freely; promoting to
**Production** is additive-only and permanently locks those record types, so it is deliberately **held**
until an actual prod/TestFlight cut — not something to dispatch now. At that cut, deploy to the production
schema the Phase E Slice 3 pantry-policy + `canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB
(PR #82), **and** the reader-photo-affordances `Recipe.coverPhotoID` column (PR #87); and note the app
target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

Phase E is **fully complete** — Slice 4 (`PantrySuppression` + review UI, PR #80 → DONE-LOG), Slice 3
(pantry policy + `canonicalName` migration, PR #79 → DONE-LOG), Slices 1 + 2 (canonical key + `Measure`,
PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG), and **batch 4** is complete (shared-chat truncation fix · planner layout
nits · full ingredient-substitution removal incl. the synced column; PR #88 → DONE-LOG). The
cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its **Menu chat-verbs** follow-on shipped as ADR-0012 (complete), and its
**reader photo affordances** shipped (PR #87 → DONE-LOG). Its one remaining named follow-on —
**Meal-Planner chat verbs** (now incl. a day-scoped make-ahead verb) — lives in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as a separate later effort.

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

- **Meal-Planner actionable chat** (ADR-0013, **Accepted** 2026-07-04) — **complete.** Both slices shipped,
  zero schema: S1 (`.mealPlan` context + selected-day grounded chat, PR #85 → DONE-LOG) and S2 (complement
  verb → inserts a `.note` `MealPlanItem` on the selected day, PR #86 → DONE-LOG). Day-scoped (D1), inserts
  land on the subject day with model-picked slot (D2), no planner prep-plan verb (D3, no container table).
  Design in
  [`docs/decisions/ADR-0013-meal-planner-actionable-chat.md`](decisions/ADR-0013-meal-planner-actionable-chat.md).

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Its Menu chat-verbs
  follow-on is now its own effort above (ADR-0012); its reader **photo affordances** shipped (PR #87 →
  DONE-LOG). Two dogfood follow-ons folded into
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md): a **day-scoped make-ahead verb** for
  the meal planner (§ "Out of scope → Meal Planner") and **separately-scrollable ingredients/directions** in
  the dense reader (§ Slice A). Both **promoted to Next Up** (combined, one PR, zero schema).

- **Recipe text normalization** — a "normalize recipe" function (de-cap old all-caps Milk Street imports,
  strip manual instruction numbers now that we auto-number). **Unscoped** — no natural existing effort home;
  parked in [`docs/open-questions.md`](open-questions.md) until scoped. Interacts with ADR-0014 (text-editing
  model), so sequence them.

- **Chat persistence** (ADR-0015, **Accepted** 2026-07-04) — **complete** (PR #89 → DONE-LOG): local-only
  per-subject `chatMessages` store, 1-month prune, excluded from the SyncEngine (guarded by the live-schema
  audit test). Design in [`docs/decisions/ADR-0015-chat-persistence.md`](decisions/ADR-0015-chat-persistence.md).

- **Dogfood fixes — batch 4** — complete (PR #88 → DONE-LOG; shared-chat truncation fix · planner layout
  nits · full ingredient-substitution removal incl. the synced column).

- **Open design ADRs (discussion, not yet Accepted)** — [ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md)
  recipe text editing (header toggles vs. rich text / bold-italic). Opened from the 2026-07-04 dogfood pass;
  decide with Jon before any implementation.

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
