# Current Handoff

Last updated: July 9, 2026. **Next Up = ADR-0025 curation slice (D3–D5) — wire the already-built NYT comment
harvest into an LLM-curation review that writes `readerFeedback` notes** (straight Codex dispatch; the
harvest/extractor + fixture are already done — see below). **Just shipped: ADR-0024 fully
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

**ADR-0025 curation slice (D3–D5) — wire the existing NYT harvest into an LLM-curation review that writes
`readerFeedback` notes.** The harvest half of [ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md)
(Accepted) is **already built** from the 2026-07-01 pre-ADR effort and is currently **orphaned** — nothing
consumes it: the interactive **Load Comments** playbook (D1 — `BrowserCommentLoadingPlaybook.nytCooking` in
`RecipeModels.swift`: Most-Helpful sort + bounded 4× Load-More, host-gated, wired to a browser button in
`BrowserViews.swift`), the anonymizing **extractor** (D2 — `RecipeReaderCommentExtractor.extract(html:sourceURL:)`
→ `[RawComment]{text, helpfulCount}` in `WebRecipeCapture/`, fixture-tested in `WebRecipeReaderCommentTests`
against the real 76-comment `nyt-comments.html`), and the **fixture** itself (the effort's S2 deliverable).
So OQ1/OQ2 (cap + NYT selectors) are **resolved and grounded in a passing test**. This dispatch does the
**consumption** half:

1. **Bridge** — after Load Comments succeeds, extract the loaded DOM to `[RawComment]` via the existing
   `RecipeReaderCommentExtractor` (today the button only loads + counts; it never calls the extractor).
2. **D3 curation** — LLM curates the `[RawComment]` down to distinct, non-obvious, genuinely-useful tips
   (cut the noise). Reuse `LLMClientKit` + Keychain `apiKeyStore` — **do not** build a new client (the effort
   doc's Slice 4 is moot). Respect [[llm-curation-not-synthesis]]: select/trim distinct tips, never merge into
   one summary.
3. **D4/D5** — add an **additive** `readerFeedback` note kind (absent today), review each curated tip through
   the **just-shipped ADR-0024 editable sheet**, commit accepted tips as `RecipeNote(readerFeedback)`, and
   display them in a "Reader Feedback" section.

**Fast follow (next slice, not this one):** **D6** the DB-backed `AIPromptPreferenceKind.readerFeedback`
curation-prompt setting (ADR-0018, *not* `AppStorage`), **D7** feed curated notes into
`RecipeChatRecipeContext`, then **S6** Jon's end-to-end device test on a real NYT recipe. Read first: ADR-0025
(esp. **D3–D5**) + `efforts/reader-feedback-comment-ingestion.md` (note its "two slices are stale" header).
**Schema note:** `readerFeedback` is an additive enum case, sync-safe; the new note rows ride the existing
`RecipeNote` table — no new table/column.

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
