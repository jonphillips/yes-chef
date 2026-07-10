# Current Handoff

Last updated: July 9, 2026. **Next Up = Menu-planner dogfood quick-fixes bundle**
([`docs/efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md),
4 slices, one PR), **then ADR-0026 review-collection sheet as a separate dispatch** — both from Jon's
2026-07-09 menu-planner dogfood pass (see Next Up below). **Just shipped: ADR-0025 D6 + D7
([#134](https://github.com/jonphillips/yes-chef/pull/134)) — the DB-backed reader-feedback
curation-prompt preference (ADR-0018 `aiSettings`, additive `readerFeedbackPreference` column) + curated
`RecipeNote(.readerFeedback)` rows feeding a distinct bucket in `RecipeChatRecipeContext`, bundled with the
capture review-sheet host fix + inline reader-feedback editing; the ADR-0025 comment-ingestion effort is
now closed** (full contents in [`docs/DONE-LOG.md`](DONE-LOG.md)). Earlier and also logged there: the
**ADR-0025 curation revision** ([#131](https://github.com/jonphillips/yes-chef/pull/131)) + a latent
meal-planner build fix ([#132](https://github.com/jonphillips/yes-chef/pull/132)); **ADR-0024 fully done**
([#127](https://github.com/jonphillips/yes-chef/pull/127)/[#128](https://github.com/jonphillips/yes-chef/pull/128));
**Dogfood batch 5** ([#126](https://github.com/jonphillips/yes-chef/pull/126)); **ADR-0025 scaffolding**
([#129](https://github.com/jonphillips/yes-chef/pull/129)); **Recipe edit proposals S1/S2**
([#122](https://github.com/jonphillips/yes-chef/pull/122)/[#123](https://github.com/jonphillips/yes-chef/pull/123));
the **LLM-aligned Compare matrix** (ADR-0022, [#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120)),
**Compare-key granularity** ([#114](https://github.com/jonphillips/yes-chef/pull/114)), and the **Workbench
build arc S1–S4** ([#101](https://github.com/jonphillips/yes-chef/pull/101)–[#113](https://github.com/jonphillips/yes-chef/pull/113)).

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

**Menu-planner dogfood quick-fixes bundle — then ADR-0026, separately.** From Jon's 2026-07-09
menu-planner dogfood pass. Two dispatches, deliberately **not** merged (a low-risk fix bundle vs. a shared
apply-action refactor with ripple risk):

1. **Dispatch 1 — the quick-fixes bundle.** Do the effort in
   [`docs/efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md)
   — **4 slices, one PR**, in order: (A) chat selection never clears on deselect (real bug + explicit
   clear affordance); (B) complement suggestions carry a `body` so ingredients land in `MenuItem.notes`
   (**ADR-0012 Amendment 2**, schema-safe); (C) prep-plan empty result explains itself (**keep the
   contract strict** — compose from stored Make-Ahead fields, never chat prose — just name the source in a
   per-action empty message); (D) rename an existing variation (missing repository call + detail-view
   affordance). Read the effort's "Read first" list and per-slice acceptance. No schema change.
2. **Dispatch 2 — the review-collection sheet.** Build [ADR-0026](decisions/ADR-0026-review-collection-sheet.md)
   (Proposed 2026-07-09): hoist the whole multi-item LLM-review **collection** into the slide-up sheet (the
   universal "evaluate content from the LLM" surface), removing the cramped inline `ChatApplyReviewList`
   band. **Separate dispatch on purpose** — it re-touches the shared `RecipeChatWorkspace` apply-action
   presentation state (the ADR-0024 D3 generics), so it must not ride with Dispatch 1. Prove S1 on the
   complements verb; S2 points ADR-0025 curation at the same surface. No schema change.

**Parked to `docs/open-questions.md` (design forks, decide with Jon before build):** multi-bubble /
whole-transcript chat selection (per-bubble `UITextView` caps the payload); hand-editing a variation /
define a header (variations are read-only after LLM creation → feeds ADR-0014 × ADR-0021).

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), the ADR-0018 synced `aiSettings` table (PR #96) **including its additive
`readerFeedbackPreference` column** (ADR-0025 D6), **and** the ADR-0021
synced `recipeVariations` table (Recipe edit proposals S2); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**Dogfood 2026-07-08 — ADR-gated design efforts (both Accepted 2026-07-09).**
- **ADR-0024 editable proposal preview** ([ADR-0024](decisions/ADR-0024-editable-proposal-preview.md)) —
  **DONE** (S1 + S2 both shipped → DONE-LOG). S1 = the roomy/scrollable/editable sheet + the D3
  `commit(approvedText:)` contract for the single-string verbs ([#127](https://github.com/jonphillips/yes-chef/pull/127));
  S2 = list / structured verbs (Serve-With, complements, prep-plan) + the workbench draft's prose fields get
  editable review, each commit shape intact (per-shape parse round-trip), plus the unchanged-payload fidelity
  guard (un-edited commit re-writes the original, never a lossy re-parse). Nothing left here.
- **ADR-0025 reader-comment ingestion** ([ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) +
  `efforts/reader-feedback-comment-ingestion.md`) — **DONE / effort closed** (D1/D2 harvest, curation
  scaffolding #129, curation revision #131, and **D6/D7 + S6 (#134)** all shipped → DONE-LOG). NYT "Most
  Helpful" harvest → LLM-curate distinct tips → reviewable `RecipeNote(.readerFeedback)` + curation-prompt
  preference + chat-context feed; additive enum + `aiSettings` column, no new table. Nothing left here.

**Menu-planner dogfood 2026-07-09 (now Next Up, above).**
- **Quick-fixes bundle** ([`efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md))
  — selection-clear bug, complement note-body (ADR-0012 Amd 2), prep-plan explain-better, variation rename.
  One dispatch, one PR; no schema.
- **ADR-0026 review-collection sheet** ([ADR-0026](decisions/ADR-0026-review-collection-sheet.md), Proposed)
  — the universal LLM-evaluation slide-up sheet; **separate dispatch** (shared apply-action generics). Extends
  ADR-0024; serves ADR-0025 curation.

**Recipe edit proposals** ([ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) +
`efforts/recipe-edit-proposals.md`) — the "Adjust this recipe" verb; **S1 + S2 shipped** (overwrite
destination with section-aware multi-section overwrite/undo; the "keep as a variation" destination = ADR-0021's
`recipeVariations` table + reader fold + grocery fold). **S3 queued** = the iterative refine loop +
workbench-log deposit (behind the dogfood ADRs above). Extends ADR-0021 (the variation destination) — do
not duplicate it.

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — the store + curate + compare arc is
complete (S1–S4 all shipped → DONE-LOG). Remaining parked follow-ons in the effort doc: the
**synthesis-shaped apply-action** (the draft verb's own action shape — a distinct action enabled by workbench
state, no last-reply gate/chip; app-layer only, small, spec in the effort doc's "Out of scope" section — this
was the prior Next Up, demoted here, not yet built), plus AI effort/tier as a user-facing setting,
AI-generated log entries, and the S3 review notes.

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
recipe text editing (header toggles vs. rich text / bold-italic), opened from the 2026-07-04 dogfood pass.
Decide with Jon before any implementation. *(Note: [ADR-0021](decisions/ADR-0021-recipe-variations.md) recipe
variations is no longer a standalone queue item — it is now the **S2 destination** of the Recipe edit
proposals effort above, reached via the same proposal/review surface; ADR-0023 D1/S2 supersedes its
standalone framing.)*

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
- **Fail fast — one build attempt, then stop.** A simulator that won't boot/install, or any
  Xcode/toolchain trouble, is **never** a reason to retry with alternate incantations. Make one
  attempt; if it fails, paste the error and stop — do not try to repair the toolchain or the sim.
  That is Jon's device pass, not a Codex grind.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
