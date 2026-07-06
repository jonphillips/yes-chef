# Current Handoff

Last updated: July 6, 2026 (**Next Up = Recipe Workbench S2** — draft verb + `libraryPlacement` +
workbench task framing: the first real commit surface. **Chat controls is done** —
[yes-chef #105](https://github.com/jonphillips/yes-chef/pull/105), architect-approved + Jon device-passed
2026-07-06 → DONE-LOG: persisted frontier/on-device tier, clear, and stop/interrupt in the shared panel.
**Workbench S1 polish + grounding fix is done** —
[yes-chef #103](https://github.com/jonphillips/yes-chef/pull/103), architect-approved, build-green,
pending Jon's device pass → DONE-LOG. `efforts/recipe-workbench.md`, ADR-0019, ADR-0020 (chat UI harvest).
**Meal-Planner chat
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

**Recipe Workbench — S1 done.** Slice 1 landed
([yes-chef #101](https://github.com/jonphillips/yes-chef/pull/101)); grounding fix + S1 polish landed
([yes-chef #103](https://github.com/jonphillips/yes-chef/pull/103), architect-approved): shared
`ChatWorkspaceSplit` now refreshes the chat model's context `onChange` (recipe/menu benefit too), editable
title, candidate-picker search, full-screen focus. Build-green; pending Jon's device pass → DONE-LOG.

**Chat controls — done** ([yes-chef #105](https://github.com/jonphillips/yes-chef/pull/105),
architect-approved + Jon device-passed 2026-07-06 → DONE-LOG). All three affordances landed in the **shared
panel** (`RecipeChatPanel`), so every chat surface inherited them at once: persisted `useFrontier` tier (new
`RecipeChatTierPreference`, mirrors `RecipeChatProviderPreference`; one global key ⇒ "remember the last model
I used anywhere"), `clear()` + confirm button (disposable scratch, no undo), and `stop()`/interrupt
(send↔stop off `isResponding`, cancellation checked on both tiers). Seam discipline held (ADR-0020) — generic
model methods + shared-panel controls, no domain pattern-match, no lift yet.

**Recipe Workbench — S2 (the dispatch target).** The draft verb that turns a workbench
into a real working recipe — the first real commit surface:

- Synthesis apply-action + review card that writes a **new `Recipe`**, links it via
  `Workbench.draftRecipeID`, captures the pristine `originalSnapshot`, and opens the result in the existing
  `RecipeDetailView` reader/editor. `high` effort (ADR-0017). Route the write through the staging card —
  the model proposes, the tap writes.
- Additive `recipes.libraryPlacement` column (`main | reference`, "future → now") so in-progress working
  recipes stay out of default browse until promoted. New working recipes non-`main`; "Promote to library"
  flips to `main`.
- Guardrail: the draft must be a coherent editorial choice with rationale referencing candidates — **not**
  a blended average of every candidate ([[llm-curation-not-synthesis]]).
- **Workbench task framing (do this first, it's cheap and it grounds everything below).** Today the
  `.workbench` chat gets the candidate *data* but the generic recipe/menu framing ("Help with timing, prep,
  troubleshooting, and planning") — the model is never told *what a workbench is for*. Add a per-context
  task-framing string on `RecipeChatContext` (empty for `.recipe`/`.menu`; the paragraph below for
  `.workbench`) and insert it into `systemPrompt()` where that generic line sits. Define it **once** and
  reuse the same string as the spine of the draft-verb apply-action prompt, so free chat and the commit path
  can't drift on what "synthesize" means. Exact wording:
  > The user is assembling candidate versions of a dish to compare them, reconcile their differences, and
  > reason toward one working recipe. Help them see how the candidates differ and what's worth borrowing
  > from each — don't blend everything into a bland average. The working recipe needn't be a single
  > monolithic version: the user may want a base recipe plus a few deliberate variations, and those
  > variations can live inside the one working recipe.

  (The taste profile is already appended to every request at the client boundary as "honor unless it
  conflicts with the task rules," so this framing's "don't average" rule correctly outranks a stray
  taste-profile line — no extra plumbing needed.)
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
grounding fix + S1 polish landed (PR #103, approved, 2026-07-06)** — chat-grounding fix + editable title +
picker search + full-screen focus, now dogfoodable. **S2** (draft verb + `libraryPlacement` + workbench
task framing) is the current dispatch target (Chat controls shipped, PR #105); **S3** (`WorkbenchLogEntry`
durable log + save-to-log tap) queued after. Milestone-sized — one slice at a time. Design in
[ADR-0019](decisions/ADR-0019-recipe-design-studies.md).

**On-device chat context overflow — robustness** (surfaced 2026-07-06 dogfooding a large taste profile in
workbench chat; Apple `FoundationModels` threw `exceededContextWindowSize` after one turn). Two real bugs,
lower priority now that tier-memory lets you live on frontier: **(a)** the taste profile is appended to
`system` **unbudgeted** at the client boundary (jon-platform `TieredModelClient` →
`appendingPromptPreferences`), outside `WorkbenchChatContext`'s 24k-char accounting — a large one is pure
uncounted overhead; **(b)** the on-device fitter (`OnDeviceModelClient.fit`) only trims the *prompt tail*
and reserves `system` whole, so when `system` (base + context + taste profile) alone exceeds Apple's
~4k-token window it cannot recover. Fix: budget context + taste profile into the on-device window (not just
the prompt tail), lower the 24k on-device candidate budget to something realistic, and catch
`exceededContextWindowSize` to surface "too big for on-device — switch to a frontier model" instead of a raw
error. Cross-repo (jon-platform LLMClientKit + Yes Chef budgets).

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
  recipe text editing (header toggles vs. rich text / bold-italic), opened from the 2026-07-04 dogfood pass;
  and [ADR-0021](decisions/ADR-0021-recipe-variations.md) recipe variations (named deltas on a base recipe,
  selected in the reader → folds into method display + grocery; ingredients structured, method as prose,
  selection persisted-not-synced; closes ADR-0019 D1(c)'s promote-target gap), opened from Workbench S1
  dogfooding 2026-07-06 — **milestone-sized, must not derail Workbench S2; dogfood more before slicing.**
  Decide with Jon before any implementation.

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
