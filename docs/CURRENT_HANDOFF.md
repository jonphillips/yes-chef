# Current Handoff

Last updated: July 6, 2026 (**Next Up = Recipe Workbench S3** — durable `WorkbenchLogEntry` log +
save-to-log tap.) Recently completed and moved to [`docs/DONE-LOG.md`](DONE-LOG.md): Workbench S2 +
dogfood-hardening ([#107](https://github.com/jonphillips/yes-chef/pull/107)), chat controls
([#105](https://github.com/jonphillips/yes-chef/pull/105), Jon device-passed), Workbench S1 + grounding
fix/polish ([#101](https://github.com/jonphillips/yes-chef/pull/101) /
[#103](https://github.com/jonphillips/yes-chef/pull/103)), and the menu-planning overhaul
([#98](https://github.com/jonphillips/yes-chef/pull/98)).

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

**Recipe Workbench — S3.** The durable workbench log — ship the store + manual/curate path **before**
the AI-generated verbs (ADR-0019 Amdt 1):

- Migration + model **`WorkbenchLogEntry`** (`id`, `workbenchID` FK cascade, extensible
  `kind: rationale | experiment | fork | observation | note`, `body: String`, `outcome: String?` for tried
  experiments, `relatedRecipeID: UUID?` soft FK, `sortOrder`, `dateCreated`). Editable/deletable, append-only
  in practice. Additive-nullable ⇒ sync-safe.
- Log surface on the workbench screen (dated, typed entries) + a **"save to workbench log"** tap that
  distills an entry from the ephemeral chat (ADR-0015 ~1-month) into the durable log — the two-histories
  bridge (ADR-0019 A2/A4).
- Ship the store + manual/curate path first; AI-*generated* experiment/fork entries layer on later as
  dogfooding shapes them (new `kind` or new compose path = no migration).

Sync-safe, post-sync (UUID PKs, soft FKs + denormalized snapshots, additive migrations). Full slice detail
+ resolved review calls in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md); design in
[ADR-0019](decisions/ADR-0019-recipe-design-studies.md) (whole, incl. both amendments).

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), **and** the ADR-0018 synced `aiSettings` table (PR #96); and note the
app target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — S1, chat controls, and S2 shipped
(→ DONE-LOG); **S3** (`WorkbenchLogEntry` durable log + save-to-log tap) is the current **Next Up**.
Milestone-sized — one slice at a time. Dogfood-surfaced follow-ons (synthesis-shaped draft action, AI
effort/tier as a user-facing setting, tabbed candidate/working-recipe quick-view) parked in the effort doc.

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

**Meal-Planner chat verbs** (ADR-0013 follow-on + `efforts/cooking-workspace.md`) — the one remaining named
actionable-chat verb instance. Classify each new verb's commit shape first ([[chat-verb-commit-shapes]]) —
likely no-commit advisory or a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]].
Design in [ADR-0013](decisions/ADR-0013-meal-planner-actionable-chat.md) +
[`efforts/cooking-workspace.md`](efforts/cooking-workspace.md). (Note: the day-scoped make-ahead-strategy
verb this entry used to name already shipped in PR #91 → DONE-LOG; confirm with Jon what verb scope remains.)

**Recipe text normalization** — a "normalize recipe" function (de-cap old all-caps Milk Street imports,
strip manual instruction numbers now that we auto-number). **Unscoped** — no natural existing effort home;
parked in [`docs/open-questions.md`](open-questions.md) until scoped. Interacts with ADR-0014 (text-editing
model), so sequence them.

**Open design ADRs (discussion, not yet Accepted)** — [ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md)
recipe text editing (header toggles vs. rich text / bold-italic), opened from the 2026-07-04 dogfood pass;
and [ADR-0021](decisions/ADR-0021-recipe-variations.md) recipe variations (named deltas on a base recipe,
selected in the reader → folds into method display + grocery; ingredients structured, method as prose,
selection persisted-not-synced; closes ADR-0019 D1(c)'s promote-target gap), opened from Workbench S1
dogfooding 2026-07-06 — **milestone-sized, must not derail Workbench S3; dogfood more before slicing.**
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
