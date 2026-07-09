# Current Handoff

Last updated: July 9, 2026. **Next Up = ADR-0024 Slice 1** (editable proposal preview — the roomy,
scrollable, *editable* review sheet for the single-string verbs, dismiss-hardening first; ADR-0024 +
ADR-0025 both Accepted 2026-07-09). **Riding to merge: Dogfood fixes — batch 5 (mechanical polish),
[#126](https://github.com/jonphillips/yes-chef/pull/126)** — gated on Jon's device pass (the app target
never compiled in CI; one `PreferenceKey` concurrency error already fixed on-branch); full contents logged in
[`docs/DONE-LOG.md`](DONE-LOG.md), alongside **Recipe edit proposals — Slice 2**
([#123](https://github.com/jonphillips/yes-chef/pull/123)) and **Slice 1**
([#122](https://github.com/jonphillips/yes-chef/pull/122)); the **LLM-aligned Compare matrix** (ADR-0022,
Accepted, [#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120)),
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

**ADR-0024 Slice 1 — editable proposal preview (single-string verbs), dismiss-hardening first.**
Implements S1 of [ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (Accepted). Two steps:
(1) **shared review-sheet dismiss hardening** — the fragility ADR-0024 OQ1 and ADR-0025 S1 both raise:
`interactiveDismissDisabled`/`isModalInPresentation` while edits are unsaved + Cancel-with-confirm, applied
once to the capture review sheets (`RecipeCaptureView` / `ShareViewController`) and built into the new
sheet. (2) **the editable sheet for single-string verbs** — replace the cramped inline
`ChatApplyReviewCard` (`RecipeChatWorkspace.swift` ~745) with a roomy, scrollable, presented sheet; make
Chef-It-Up / Make-ahead / workbench rationale **editable**; thread the edited string through commit (the
ADR-0024 **D3** contract change — `commit` takes the sheet's current text, not a frozen payload). List /
structured verbs get the roomy sheet now; their editing lands in S2. **Schema-free, app-wide.** Read first:
ADR-0024 (esp. D3 + the OQ1/OQ3/OQ4 leans), `ChatApplyReviewItem`/`ChatApplyReviewCard`/`AnyChatApplyAction`
in `RecipeChatWorkspace.swift`, and `RecipeCaptureView`/`ShareViewController` for the dismiss pattern.

**Riding to merge (not a dispatch): Dogfood fixes — batch 5 (mechanical polish),
[#126](https://github.com/jonphillips/yes-chef/pull/126).** Built and logged in DONE-LOG; gated on Jon's
device pass (app target never compiled in CI; the `PreferenceKey` concurrency error already fixed on-branch);
this handoff bump rides in #126. (The other 2026-07-08 dogfood items were always ADR-gated, separate from
batch 5: editable AI preview + comment ingestion are now ADR-0024/0025 Accepted — see Ready Efforts;
workbench provenance + browser autofill remain ADR-pending.)

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), the ADR-0018 synced `aiSettings` table (PR #96), **and** the ADR-0021
synced `recipeVariations` table (Recipe edit proposals S2); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**Dogfood 2026-07-08 — ADR-gated design efforts (both Accepted 2026-07-09).**
- **ADR-0024 editable proposal preview** ([ADR-0024](decisions/ADR-0024-editable-proposal-preview.md)) —
  the roomy/scrollable/editable review sheet + edited-text-through-commit contract. **S1 is Next Up**
  (above). **S2** (list / structured verbs — Serve-With, complements, workbench draft prose fields; keep
  each commit shape, never flatten) remains queued behind it.
- **ADR-0025 reader-comment ingestion** ([ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) +
  `efforts/reader-feedback-comment-ingestion.md`) — NYT "Most Helpful" harvest → LLM-curate distinct tips →
  reviewable `RecipeNote(readerFeedback)` + chat feed; additive enum, no schema. **Not a straight Codex
  dispatch:** it starts with a fixture step (S2 — harvest a real authenticated-NYT comment DOM via the
  browser MCP; selectors/OQ2 are unknowable until then), which Jon or the architect drives before S3–S5 can
  be specced. Its S1 (dismiss hardening) is shared with ADR-0024 S1 above — done once.

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
