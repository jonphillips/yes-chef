# Current Handoff

Last updated: July 10, 2026. **Next Up = Jon picks the next effort** — ADR-0027 S1 just shipped; the
"Ready after this" candidates below are Jon's call (do not infer). **Just shipped: ADR-0027 "Capture to
menu" S1 ([#141](https://github.com/jonphillips/yes-chef/pull/141))** — the menu chat **harvest** verb
(inverse of the generative complement family): captures a chat text selection (or, absent one, the assistant
transcript) into `.note`-kind `MenuItem`s, the model segmenting + reshaping prose into recipe-looking notes
and never inventing; menu context is **not** sent (D2 — the fix for the "it sent the whole menu" surprise).
Additive `aiSettings.captureToNotePreference` column, otherwise sync-safe; device pass owed (Jon). Earlier
and also logged in [`docs/DONE-LOG.md`](DONE-LOG.md): **Instrumentation — apply-action + LLM logging
([#139](https://github.com/jonphillips/yes-chef/pull/139))** — diagnostic `os.Logger` at the `\.modelClient`
seam + apply-action lifecycle logging, so a misbehaving verb's raw LLM response and empty-`extract` reason
are legible; no `LLMClientKit` edits, no schema, no behavior change. Earlier and also logged there:
**ADR-0026 review-collection sheet ([#138](https://github.com/jonphillips/yes-chef/pull/138))
— S1+S2, one PR: the whole multi-item LLM-review collection now lives in the universal slide-up sheet
(`RecipeCollectionReviewSheet`, built host-agnostic), the cramped inline `ChatApplyReviewList` band is gone,
the adjust verb is a launch-only row that still opens the Compare-diff surface, and reader-feedback curation
in capture shares the same sheet; no schema change**.
Earlier and also logged there: **the menu-planner dogfood quick-fixes bundle
([#136](https://github.com/jonphillips/yes-chef/pull/136))** — selection-clear + clear affordance, complement
note-body (ADR-0012 Amd 2), prep-plan explain-better, variation rename; no schema. Earlier and also logged there:
**ADR-0025 D6 + D7 ([#134](https://github.com/jonphillips/yes-chef/pull/134)) — the DB-backed reader-feedback
curation-prompt preference (ADR-0018 `aiSettings`, additive `readerFeedbackPreference` column) + curated
`RecipeNote(.readerFeedback)` rows feeding a distinct bucket in `RecipeChatRecipeContext`, bundled with the
capture review-sheet host fix + inline reader-feedback editing; the ADR-0025 comment-ingestion effort is
now closed**. Earlier and also logged there: the
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

**Jon picks the next effort — do not infer.** ADR-0027 S1 shipped in
[#141](https://github.com/jonphillips/yes-chef/pull/141) (see Just Shipped, above). The candidates below are
Jon's call; a fresh dispatch must **STOP and ask Jon** which one:
- **ADR-0027 S2** — the recipe sibling (capture chat into a `RecipeNote` on a recipe). S1's shape ported
  cleanly (`MenuNoteHarvestPlan`/`HarvestedNote` + the two-mode client), so this is a straight port if Jon
  wants it. Design: [ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md) D6.
- **Recipe edit proposals S3** — the iterative refine loop + workbench-log deposit.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip).
- **Open a design ADR** — ADR-0013 meal-planner verbs (needs scope confirmation) or ADR-0014 text editing.

**ADR-0027 device pass owed (Jon):** confirm on device (primary `iPad Pro 13-inch (M5)`, both orientations;
`iPhone 17 Pro` for the compact sheet) — (1) the **selection path**: highlight a dish paragraph in an
assistant bubble → "Capture to menu" → one clean note in the collection sheet → commit lands a `.note`
`MenuItem` (the resign-retains-selection plumbing change means the highlight must survive the apply-menu tap);
(2) the **no-selection path**: no highlight → the verb scans the assistant transcript → N candidate notes;
(3) captured notes land on Day 1 / Dinner (deterministic placement, OQ1 — menu detail has no selected-day
state) and can be moved afterward.

**ADR-0026 device pass still owed (Jon):** the architect review flagged two interaction risks to confirm on
device — (1) the adjust launch row presents Compare-diff from `RecipeDetailView` while the collection sheet
dismisses from `RecipeChatPanel` in the same runloop (present-while-dismiss across two anchors — verify
Compare-diff isn't swallowed); (2) N=1 auto-drill stacks the child review sheet over the collection sheet
(functionally fine; confirm it reads cleanly, incl. iPad split-chat, OQ2).

**Parked to `docs/open-questions.md` (design forks, decide with Jon before build):** multi-bubble /
whole-transcript chat selection (per-bubble `UITextView` caps the payload); hand-editing a variation /
define a header (variations are read-only after LLM creation → feeds ADR-0014 × ADR-0021).

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), the ADR-0018 synced `aiSettings` table (PR #96) **including its additive
`readerFeedbackPreference` column** (ADR-0025 D6) **and `captureToNotePreference` column** (ADR-0027 S1,
PR #141), **and** the ADR-0021
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

**ADR-0027 "Capture to menu" harvest verb** ([ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md);
brief [`efforts/adr-0027-capture-to-menu.md`](efforts/adr-0027-capture-to-menu.md)) — **S1 DONE**
([#141](https://github.com/jonphillips/yes-chef/pull/141) → DONE-LOG; device pass owed, see Next Up). A new
**extraction** menu verb (inverse of the generative complement family): captures a chat text selection (or,
absent one, the transcript) into `.note`-kind `MenuItem`s, the model segmenting + reshaping prose into
recipe-looking notes, never inventing. Selection scopes the source; menu context is **not** sent (D2). Rode
the merged ADR-0026 sheet. **S2** (recipe `RecipeNote` sibling) deferred — Jon's pick (see Next Up). Additive
`aiSettings.captureToNotePreference` column, otherwise sync-safe.

**Instrumentation — apply-action + LLM logging**
([`efforts/instrumentation-apply-action-logging.md`](efforts/instrumentation-apply-action-logging.md))
— **DONE** ([#139](https://github.com/jonphillips/yes-chef/pull/139) → DONE-LOG): diagnostic `os.Logger` at
the `\.modelClient` seam (one `LoggingModelClient` decorator at the composition root) + apply-action
lifecycle in `RecipeChatWorkspace`, so a verb's raw LLM response and empty-`extract` reason are legible.
The last un-built item from the 2026-07-09 menu-planner dogfood; no `LLMClientKit` edits, no schema, no
behavior change. Nothing left here.

**Menu-planner dogfood 2026-07-09.**
- **Quick-fixes bundle** ([`efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md))
  — **DONE** ([#136](https://github.com/jonphillips/yes-chef/pull/136) → DONE-LOG): selection-clear bug +
  clear affordance, complement note-body (ADR-0012 Amd 2), prep-plan explain-better, variation rename. One
  PR, no schema. Nothing left here.
- **ADR-0026 review-collection sheet** ([ADR-0026](decisions/ADR-0026-review-collection-sheet.md);
  brief [`efforts/adr-0026-review-collection-sheet.md`](efforts/adr-0026-review-collection-sheet.md))
  — **DONE** ([#138](https://github.com/jonphillips/yes-chef/pull/138) → DONE-LOG): S1+S2 in one PR — the
  host-agnostic `RecipeCollectionReviewSheet` hoists the whole multi-item review collection into the slide-up
  sheet, removes the inline `ChatApplyReviewList` band, makes the adjust verb a launch-only row into
  Compare-diff, and reuses the sheet for reader-feedback curation in capture; no schema. Device pass owed
  (see Next Up). Nothing left here.

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
