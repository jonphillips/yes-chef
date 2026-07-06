# Current Handoff

Last updated: July 6, 2026 (**Next Up = Recipe Workbench — grounding fix + S1 polish** — chat-grounding
verify/fix + editable title + candidate-picker search + full-screen focus; immediately dogfoodable. **S2**
(draft verb + `libraryPlacement`) split into the next dispatch right behind it. `efforts/recipe-workbench.md`,
ADR-0019. **Meal-Planner chat
verbs** demoted back to the Ready Efforts queue — still pending, just not the immediate target. **Menu planning
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

**Recipe Workbench — grounding fix + S1 polish (ADR-0019 + `efforts/recipe-workbench.md`).** Slice 1 landed
([yes-chef #101](https://github.com/jonphillips/yes-chef/pull/101), architect-approved): `Workbench` +
`WorkbenchCandidate`, candidate picker, editable annotations, grounded `.workbench` chat, both entry
points. This dispatch makes S1 **immediately dogfoodable** — the chat-grounding fix + three review
papercuts, all pure app-layer UX (no schema, no core-model change). Do all, in order:

- **(0) Chat grounding — verify + fix.** Jon reports the workbench chat "can't see the recipes." The
  wiring is correct on *initial* open (candidate ingredients + steps reach `systemPrompt()` via
  `WorkbenchChatContext.serialized(for: activeTier)`), **but** `ChatWorkspaceSplit` snapshots the context
  in `@State` at first appearance ([`RecipeChatWorkspace.swift`](../YesChefApp/RecipeChatWorkspace.swift)
  line ~55) and never refreshes it — so candidates added *after* the chat pane appears are invisible to
  the model, and the context goes stale for the life of the view. Repro on device, then fix: refresh the
  chat model's `context` when the workbench detail changes (e.g. re-init `ChatWorkspaceSplit` via `.id()`
  keyed on a candidate-set signature, or expose a `context` setter on `RecipeChatModel` the view updates
  `onChange`). Confirm the same staleness isn't silently biting recipe/menu chat.
- **(1) Editable workbench title.** `WorkbenchReader` renders the title read-only; the multi-select
  "Workbench These" path auto-titles "Recipe Workbench" with no rename. Add `WorkbenchRepository`
  `updateWorkbenchTitle` (sibling of `updateWorkbenchNotes`, reuse `nonEmptyWorkbenchText`, bump
  `dateModified`) + a rename affordance in the reader.
- **(2) Search in the Add Candidates picker.** `WorkbenchCandidatePickerView` lists all recipes with no
  filter — unusable against a 2000-recipe library. Add a `.searchable` title filter over
  `availableRecipeRows` (mirror the recipe-library search).
- **(3) Full-screen focus for a selected workbench.** Mirror Menu: `MenuDetailColumn` takes
  `isFocusActive: columnVisibility == .detailOnly` + `focusButtonTapped` flipping
  `.detailOnly`/`.doubleColumn` in `AppMainLayout`; `WorkbenchDetailColumn` takes only `model`. Wire the
  same binding through `WorkbenchDetailColumn` → `WorkbenchDetailView` + a focus toolbar button
  (regular-width iPad only).
- **Stop here for review + dogfood.** **S2** (draft verb + `libraryPlacement`) is the very next dispatch —
  detailed below — **not** part of this PR.

**Recipe Workbench — S2 (the next dispatch, not this one).** The draft verb that turns a workbench into a
real working recipe — the first real commit surface:

- Synthesis apply-action + review card that writes a **new `Recipe`**, links it via
  `Workbench.draftRecipeID`, captures the pristine `originalSnapshot`, and opens the result in the existing
  `RecipeDetailView` reader/editor. `high` effort (ADR-0017). Route the write through the staging card —
  the model proposes, the tap writes.
- Additive `recipes.libraryPlacement` column (`main | reference`, "future → now") so in-progress working
  recipes stay out of default browse until promoted. New working recipes non-`main`; "Promote to library"
  flips to `main`.
- Guardrail: the draft must be a coherent editorial choice with rationale referencing candidates — **not**
  a blended average of every candidate ([[llm-curation-not-synthesis]]).
- Stop at S2. **S3** (durable `WorkbenchLogEntry` log + save-to-log tap) stays queued behind it.

**Sync-safe, post-sync** (UUID PKs, soft FKs + denormalized snapshots, read-time dedup, additive
migrations). Full slice detail + resolved review calls in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md);
design in [ADR-0019](decisions/ADR-0019-recipe-design-studies.md) (whole, incl. both amendments).

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

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — **Slice 1 landed (PR #101, approved);
grounding fix + S1 polish promoted to Next Up** (2026-07-06): chat-grounding fix + editable title + picker
search + full-screen focus, immediately dogfoodable. Split from S2 to keep merge boundaries tight. **S2**
(draft verb + `libraryPlacement`) is the dispatch right behind; **S3** (`WorkbenchLogEntry` durable log +
save-to-log tap) queued after. Milestone-sized — one slice at a time. Design in
[ADR-0019](decisions/ADR-0019-recipe-design-studies.md).

**Meal-Planner chat verbs** (ADR-0013 follow-on + `efforts/cooking-workspace.md`) — **demoted back to the
queue** (2026-07-06; Recipe Workbench S1 took the target). Still the one remaining named actionable-chat
verb instance: a day-scoped **"make-ahead strategy"** across all of a planner day's recipes (dogfood
2026-07-04). Classify the commit shape first ([[chat-verb-commit-shapes]]) — likely no-commit advisory or
a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]]. Design in
[ADR-0013](decisions/ADR-0013-meal-planner-actionable-chat.md) +
[`efforts/cooking-workspace.md`](efforts/cooking-workspace.md).

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
