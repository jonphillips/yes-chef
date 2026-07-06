# Current Handoff

Last updated: July 5, 2026 (**Next Up = Meal-Planner chat verbs** — the last remaining actionable-chat
verb instance; `efforts/cooking-workspace.md` § "Out of scope → Meal Planner context". **Menu planning
overhaul (ADR-0012 Amdt 1) is done** — [yes-chef #98](https://github.com/jonphillips/yes-chef/pull/98),
build-green, pending Jon's device pass → DONE-LOG. **AI config (ADR-0017/0018) is done** — cross-repo PRs
[yes-chef #96](https://github.com/jonphillips/yes-chef/pull/96) +
[jon-platform #23](https://github.com/jonphillips/jon-platform/pull/23), pending Jon's device pass →
DONE-LOG. Details below.)

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

**Meal-Planner chat verbs — ADR-0013 follow-on + `efforts/cooking-workspace.md` (§ "Out of scope → Meal
Planner context").** The one remaining named actionable-chat verb instance; the `.mealPlan` context
already ships grounded chat + a complement verb (ADR-0013). Queued follow-on verb (dogfood 2026-07-04):

- **Day-scoped "make-ahead strategy"** for all items on a planner day — synthesize a prep sequence across
  *all* that day's recipes, leveraging each recipe's saved `makeAhead` where present but reasoning across
  the combined set. Distill motion, cross-recipe (the planner analogue of the Menu make-ahead verb).

**Classify the commit shape first** ([[chat-verb-commit-shapes]]) — likely a no-commit advisory or a
per-day note, **not** a per-recipe field write. Respect [[llm-curation-not-synthesis]]: sequence/select
distinct prep steps, don't flatten the day's recipes into one blob. Design in
[ADR-0013](decisions/ADR-0013-meal-planner-actionable-chat.md) +
[`efforts/cooking-workspace.md`](efforts/cooking-workspace.md).

**Menu planning overhaul (ADR-0012 Amendment 1 + `efforts/menu-planning-ux.md`) is done** —
[yes-chef #98](https://github.com/jonphillips/yes-chef/pull/98) (build-green), all five slices shipped
(tier-aware AI context + prep-plan-in-context + living-artifact refinement · swipe-delete/move · inline
meal-slot pill · full-screen focus · toolbar reorg). Pending Jon's device pass → DONE-LOG. Drag-drop
reorder of dishes stays parked as the named follow-on (swipe-move is the interim).

**AI configuration & transparency — ADR-0017 + ADR-0018 — is done** (architect-approved 2026-07-05,
cross-repo [yes-chef #96](https://github.com/jonphillips/yes-chef/pull/96) +
[jon-platform #23](https://github.com/jonphillips/jon-platform/pull/23); pending Jon's device pass → then
DONE-LOG). Shipped: `gpt-5.5` default + retired `gpt-5.2-chat-latest`; provider-agnostic `ReasoningEffort`
on `ModelRequest` (OpenAI wire emits top-level `reasoning_effort`, omits when `nil`); per-feature effort on
all 9 frontier call sites (chat `medium`, judgment `high`, complements `medium`); taste profile + ~4
per-task preferences injected at the `TieredModelClient` boundary so they reach **every** generative call
(closes the recipe-chat-only gap); synced `aiSettings` table that clears the live-schema audit
([[extension-sync-construct-not-run]]); read-only active-model rows in `AISettingsView`. **Standing
release follow-up: the synced AI-preferences column ships to the prod schema at the next cut (noted
below).**

ADR-0016 multi-recipe cook session is **done** (PR #93 merged 2026-07-05 → DONE-LOG; Codex's follow-up
PR #94 was a wasted effort, rejected). The Meal-Planner chat-verbs follow-on stays parked in the Ready
Efforts queue below, not a dispatch target.

**Standing release follow-up carried from Phase E (not a dispatch — a pre-cut ops step Jon runs).** We stay
in the CloudKit **Development** environment (dev stance) so the schema keeps evolving freely; promoting to
**Production** is additive-only and permanently locks those record types, so it is deliberately **held**
until an actual prod/TestFlight cut — not something to dispatch now. At that cut, deploy to the production
schema the Phase E Slice 3 pantry-policy + `canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB
(PR #82), the reader-photo-affordances `Recipe.coverPhotoID` column (PR #87), **and** the ADR-0018 synced
`aiSettings` table (PR #96); and note the app target (`PantryViews.swift` /
`GroceryViews.swift`) compiles only in Jon's device pass, not CI.

Phase E is **fully complete** — Slice 4 (`PantrySuppression` + review UI, PR #80 → DONE-LOG), Slice 3
(pantry policy + `canonicalName` migration, PR #79 → DONE-LOG), Slices 1 + 2 (canonical key + `Measure`,
PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG), and **batch 4** is complete (shared-chat truncation fix · planner layout
nits · full ingredient-substitution removal incl. the synced column; PR #88 → DONE-LOG). The
cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its **Menu chat-verbs** follow-on shipped as ADR-0012 (complete), its
**reader photo affordances** shipped (PR #87 → DONE-LOG), and its **independently-scrollable dense-reader
columns + day-scoped make-ahead verb** shipped (PR #91 → DONE-LOG). Its one remaining named follow-on —
the broader **Meal-Planner chat verbs** effort — lives in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as a separate later effort.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

**Menu planning overhaul** (ADR-0012 Amendment 1 + `efforts/menu-planning-ux.md`) — **complete**
([yes-chef #98](https://github.com/jonphillips/yes-chef/pull/98), build-green; pending Jon's device pass →
DONE-LOG). All five slices shipped; drag-drop dish reorder stays parked as the named follow-on.

**Meal-Planner chat verbs** (ADR-0013 follow-on + `efforts/cooking-workspace.md`) — **promoted to Next
Up** (menu overhaul now done). Full detail lives in Next Up above.

- **AI configuration & transparency** (ADR-0017 + ADR-0018) — **complete** (architect-approved 2026-07-05;
  cross-repo PRs [yes-chef #96](https://github.com/jonphillips/yes-chef/pull/96) +
  [jon-platform #23](https://github.com/jonphillips/jon-platform/pull/23); pending Jon's device pass →
  DONE-LOG). `gpt-5.5` default + `ReasoningEffort` knob + per-feature effort + boundary-injected taste
  profile / per-task preferences (synced `aiSettings` table). Design in
  [ADR-0017](decisions/ADR-0017-llm-model-and-reasoning-effort.md) +
  [ADR-0018](decisions/ADR-0018-prompt-customization-taste-profile.md).

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
