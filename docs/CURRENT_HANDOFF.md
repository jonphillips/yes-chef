# Current Handoff

Last updated: July 9, 2026. **Next Up = ADR-0025 curation — revise per the Amendment 2026-07-09:
[#129](https://github.com/jonphillips/yes-chef/pull/129) shipped the scaffolding (enum, extractor bridge,
display, review-sheet, per-tip note storage — all stands); reprompt to two-provenance curation
(synthesize *within* a point, never across), show comment provenance in review, raise the token budget**
(Codex dispatch — see below). **Just shipped: ADR-0024 fully
done — S1 editable proposal preview ([#127](https://github.com/jonphillips/yes-chef/pull/127)) + S2
list / structured editable verbs (this PR, architect-approved 2026-07-09, including the unchanged-payload
fidelity guard so an un-edited commit re-writes the original, never a lossy re-parse)** and **Dogfood fixes —
batch 5 (mechanical polish), [#126](https://github.com/jonphillips/yes-chef/pull/126)** — all
merged/device-passed; full contents logged in
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

**ADR-0025 curation — revise per the [Amendment 2026-07-09](decisions/ADR-0025-reader-comment-ingestion.md#amendment--2026-07-09-dogfood-revision-of-d3d5-post-129).**
[#129](https://github.com/jonphillips/yes-chef/pull/129) shipped the working **scaffolding** — the
`readerFeedback` enum case, the `RecipeReaderCommentExtractor` bridge (Load Comments → `[RawComment]`), the
Reader Feedback display section, the ADR-0024 review-sheet reuse, and per-accepted-tip
`RecipeNote(readerFeedback)` storage — but Jon flagged its auto-curate flow as **too magical** and the tip
shape as wrong. **All of that scaffolding stands.** This dispatch revises the **curation prompt, the review
UI, and the token budget** to hit the amendment's target (a human editor's numbered list of atomic recipe
changes — some consensus-distilled, some singular-preserved). Do all four, in order:

1. **A1 — two-provenance curation (revises D3).** Reprompt the existing `ReaderFeedbackCurationClient` so
   the output is a **JSON array of atomic points** where the model **may collapse a change many commenters
   converge on into one point** (with a support count) **and must keep distinct changes as separate
   entries** — *synthesize within a point, never across points*. Two kinds are both first-class:
   **consensus-distilled** (many → one) and **singular-preserved** (one rich comment kept intact). Keep D3's
   bar: precision over recall, cut blabber, **empty list is valid.** Reuse `LLMClientKit` + `apiKeyStore` —
   do **not** build a new client. Still [[llm-curation-not-synthesis]] — the array shape *is* the guard.
2. **A2 — provenance-in-review (revises D4/D5).** Each proposed point shows its **provenance** at review:
   a support count + the **backing anonymized comments**, expandable in the ADR-0024 sheet. Accept / edit /
   reject **each point** (Jon's editorial voice is added here, at review). Add a **"promote a comment the
   model missed"** escape hatch. Storage unchanged: each accepted point → one `RecipeNote(readerFeedback)`.
   Provenance is **transient/advisory** (review-only unless OQ6 says otherwise).
3. **A3 — no dedup pre-filter.** Do **not** collapse near-duplicate comments before the frontier —
   redundancy *is* the consensus signal A1 counts. Strip only truly empty/garbage. (On-device first pass
   stays deferred.)
4. **A4 — budget + truncation.** The whole thread must reach the frontier for the tally, so raise
   `maxTokens` above 2048 (billing is per token *used*, so a generous ceiling is free) **and** check
   `ModelResponse.wasTruncated` — a cut-off tally under-counts consensus; surface a distinct "couldn't
   finish — try again," never a silent empty. Ties [[reasoning-budget-starves-output]].

Also fold in the **cooking-mode fix**: `readerFeedback` notes currently fall into cooking mode's flat
"Notes" list unlabeled ([CookingModeView.swift:66](../YesChefApp/CookingModeView.swift)); give them their
own section or drop them from the at-the-stove step view (Jon's call — likely out).

**Fast follow (next slice, not this one):** **D6** the DB-backed `AIPromptPreferenceKind.readerFeedback`
curation-prompt setting (ADR-0018, *not* `AppStorage`), **D7** feed curated notes into
`RecipeChatRecipeContext`, then **S6** Jon's end-to-end device test on a real NYT recipe. Read first: ADR-0025
**Amendment 2026-07-09** + **D3–D5** (as amended). **Schema note:** `readerFeedback` is an additive enum
case, sync-safe; the new note rows ride the existing `RecipeNote` table — no new table/column.

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
  **DONE** (S1 + S2 both shipped → DONE-LOG). S1 = the roomy/scrollable/editable sheet + the D3
  `commit(approvedText:)` contract for the single-string verbs ([#127](https://github.com/jonphillips/yes-chef/pull/127));
  S2 = list / structured verbs (Serve-With, complements, prep-plan) + the workbench draft's prose fields get
  editable review, each commit shape intact (per-shape parse round-trip), plus the unchanged-payload fidelity
  guard (un-edited commit re-writes the original, never a lossy re-parse). Nothing left here.
- **ADR-0025 reader-comment ingestion** ([ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) +
  `efforts/reader-feedback-comment-ingestion.md`) — NYT "Most Helpful" harvest → LLM-curate distinct tips →
  reviewable `RecipeNote(readerFeedback)` + chat feed; additive enum, no schema. **The harvest half is already
  built** (2026-07-01 pre-ADR effort, currently orphaned): S1 dismiss hardening (shared with ADR-0024 S1), the
  D1 Load-Comments playbook + D2 anonymizing `RecipeReaderCommentExtractor` + the real 76-comment
  `nyt-comments.html` fixture with passing tests — so OQ1/OQ2 are resolved. **The curation slice (D3–D5) is
  Next Up** (above): bridge the extractor in → LLM-curate → `readerFeedback` notes reviewed via the ADR-0024
  sheet. **Fast follow:** D6 prompt preference (ADR-0018 DB-backed) + D7 chat feed + S6 device test.

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
