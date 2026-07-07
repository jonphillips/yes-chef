# Current Handoff

Last updated: July 6, 2026 (**Next Up = Workbench S4: Compare (the ingredient-diff matrix)**.) Recently
completed and moved to [`docs/DONE-LOG.md`](DONE-LOG.md):
Workbench S3 durable log ([#110](https://github.com/jonphillips/yes-chef/pull/110), Jon device-passed),
Workbench S2 + dogfood-hardening ([#107](https://github.com/jonphillips/yes-chef/pull/107)), chat controls
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

**Workbench S4 — Compare (the ingredient-diff matrix).** App-layer only — no migration, no new fetch, no sync
touch. Full spec in `efforts/recipe-workbench.md` (slice plan → S4); read it before starting. In brief: an
aligned ingredient matrix — rows = canonical ingredients, columns = recipes, each cell = that recipe's
`IngredientLine` (blank cell = ingredient absent) — with the working recipe pinned as a frozen first column
while candidates scroll horizontally. The data is already loaded in `WorkbenchDetailData` (`WorkbenchCore.swift`
~L145), so Compare is a pure read. Load-bearing alignment rule: align only on exact `canonicalName` match
(`CanonicalIngredient.canonicalName(_:)`, as grocery dedup does); unmatched/ambiguous lines drop to a
per-column "other" tail, never force-merged — a wrong alignment is worse than an honest blank. Nav: a "Compare"
button in the Candidates section header (`WorkbenchViews.swift` ~L184) → full-screen `.detailOnly` cover on
iPad (no third pane — the chat split owns the detail), sheet + horizontal pager on iPhone. Segmented control:
Ingredients | Full — Ingredients (the matrix) ships this slice; Full (the tabbed whole-recipe quick-view)
folds in as the second segment, same PR or fast follow.

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

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — S1, chat controls, S2, and S3 all shipped
(→ DONE-LOG); the store + curate arc is complete. The **synthesis-shaped apply-action** follow-on is drawn
into the current Next Up (item 2); the rest stay parked in the effort doc (AI effort/tier as a user-facing
setting, tabbed candidate/working-recipe quick-view, AI-generated log entries, the S3 review notes).

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
dogfooding 2026-07-06 — **milestone-sized; dogfood more before slicing.**
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
