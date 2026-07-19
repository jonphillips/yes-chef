# Current Handoff

Last updated: July 18, 2026 (**ADR-0041 S2 shipped → Next Up = S2.5.** **ADR-0041 Slice 2** — the section-scoped external hand-off, incl. the load-bearing `matches()` section-routing fix — merged as PR #205 and moved to DONE-LOG. Jon's device look on the shipped column surfaced two corrections, now recorded as **[ADR-0041 Amendment 1](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-1--a-return-never-stomps-existing-content-and-the-toolbar-collapses-into-the-overflow-2026-07-18)** (doc landed in #205): a section return currently **replaces wholesale**, so "Hand off again" on a filled section discards hand-authored content; and D2's prominent per-section buttons shout on every view. **Next Up = ADR-0041 Slice 2.5** — non-destructive returns + the collapsed section toolbar. S3 (synced section-meta + conversation URL) stays queued behind it.)

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate everything preceded is **crossed and
holding**. We stay in CloudKit **Development** by design; prod-schema promotion is the held ops step under
Next Up. Recently-closed efforts and their PRs live in [`docs/DONE-LOG.md`](DONE-LOG.md).

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

**Live dispatch target — ADR-0041 Slice 2.5: non-destructive section returns + the collapsed section toolbar (app + core, no schema).** Full spec in [ADR-0041 **Amendment 1**](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-1--a-return-never-stomps-existing-content-and-the-toolbar-collapses-into-the-overflow-2026-07-18). Follows S2 (PR #205, shipped). Two independent concerns, one PR. Do all in order.

1. **⚠️ A section return must never silently discard existing content (Amd1-D1).** S2 pairs an outbound prompt that *excludes the section being regenerated* (regenerate-fresh — correct, keep it) with an inbound commit that *replaces wholesale* (`updateChefItUp` / `commitMakeAheadText` for the blobs; `replaceServeWithPlan` for the list, which drops every row absent from the return). The model therefore cannot echo existing content back, so **"Hand off again" on a filled section destroys hand-authored work.** **Fix on the return side only — do NOT put the current section back into the prompt.**
2. **Serve With (list) — lossless union prefill.** Seed the review sheet's `editableText` with **existing lines first, then returned lines**, exact-dedup on the `title: note` rendering. `reconciledServeWithItems` (`RecipeEnrichment.swift:310`) already matches on `title == && note ==`, so surviving rows **keep their existing UUIDs** — verify no row churn. `replaceServeWithPlan` stays the only write path; it stops being lossy because the box now starts out containing everything. **Put the union/dedup in `YesChefPackage` (`ServeWithPlan`) with a unit test, not in the App layer** — pure logic belongs where the package build can catch it (Verification Pattern corollary).
3. **Make-ahead / Chef It Up (blob) — explicit commit choice, no default.** Empty section → commit stays just *Save*. **Filled** section → the review item offers **Replace** *and* **Append**, with **no pre-selected default**; the human picks. `ChatApplyReviewItem` (`RecipeChat.swift:603`) carries a single `commit` closure today — take the **smallest possible widening** (an optional secondary commit: title + closure). Do **not** restructure the type; it backs every apply-action in the app. Append joins with a blank line.
4. **Show what's at risk (both shapes).** `ChatApplyReviewItem.supportingEvidenceTitle` / `supportingEvidenceRows` already exist and are unused on this path — populate them with the section's current content under *"Currently saved."*
5. **Collapse the section toolbar into one `•••` (Amd1-D2 — this SUPERSEDES D2 on prominence).** Remove the button row entirely. Every section action — Hand off, Hand off again, Paste, Edit / Write manually, Ask, Clear — moves into a single overflow menu, and the `•••` moves **into the section header row** right of the fill-dot (`Chef It Up ○ ••• ⌄`). Render it **only when the section is expanded**; collapsed sections keep `title + fill-dot + chevron`. The state-aware *contents* of the menu (empty vs. filled) stay exactly as D2 defined them — only prominence and placement change. Rationale: three sections × two filled-tint buttons shouts on **every view** for actions taken a few times a week ([[automation-decays-near-the-stove]]).
6. **Retire `PasteButton`; accept the system paste alert.** `PasteButton` is a system-rendered `UIPasteControl` and **cannot render inside a `Menu`** — its implicit no-alert pasteboard access is granted only for a visibly-tapped standalone control. Replace with a plain `Button` reading `UIPasteboard.general.string`. The *"Allow Paste?"* alert is **accepted (Jon, 2026-07-18)**: the grant is scoped to the current pasteboard contents, so it is ~**one alert per hand-off round-trip**, not per tap. Gate the menu row on `UIPasteboard.general.hasStrings` (which does **not** prompt) so it is disabled when the clipboard has no string. Keep the existing "Unmatched Handoff" alert path intact — do not stack it with the paste alert in the same runloop.

**Verify:** Core → `swift build` + a package unit test proving the union prefill **preserves existing rows and their UUIDs** while deduping an exact repeat. App-layer → the elevated `generic/platform=iOS` build (see Verification Pattern) + `scripts/check-drift.sh`. No simulator installs. Confirm on device (Jon): (a) Hand off again → Paste on a **filled** Serve With preserves existing rows in the review sheet; (b) the same on a filled Make-ahead offers Replace/Append with neither pre-selected; (c) the Playbook column reads calm — no filled buttons on any section, `•••` only when expanded; (d) the paste alert fires once per round-trip, not per tap.


**Feature efforts still on the board — Jon picks; do not infer:**
- **Recipe edit proposals S3** — the iterative refine loop + workbench-log deposit.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip).
- **Open a design ADR** — ADR-0013 meal-planner verbs (needs scope confirmation) or ADR-0014 text editing.

**ADR-0026 device pass still owed (Jon):** two interaction risks — (1) the adjust launch row presents
Compare-diff from `RecipeDetailView` while the collection sheet dismisses from `RecipeChatPanel` in the same
runloop (verify Compare-diff isn't swallowed); (2) N=1 auto-drill stacks the child review sheet over the
collection sheet (confirm it reads cleanly, incl. iPad split-chat).

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
synced `recipeVariations` table (Recipe edit proposals S2), **and `Menu.externalProjectName`** (ADR-0038 S2),
**and the synced `learnings` table including its `sortOrder` column** (ADR-0038 Amd 1 / Amd 5) **and the synced `prepPlanSteps` table**
(ADR-0040 S2 — which also **retires the `Menu.prepPlan` BLOB**: restructure it *before* this cut, because
promotion locks the record type permanently); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**ADR-0041 Playbook section hand-off — S3** ([ADR-0041](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md); follows S1 + S2 shipped; queued behind **S2.5 in Next Up above**). **S3 (schema + app) — the synced section meta + conversation URL.** New synced `PlaybookSectionMeta` `@Table` keyed `(recipeID, sectionKind)` carrying `{ provenance, conversationURL, dateModified }` (real FK → cascade-delete, no polymorphic-orphan problem); the `conversationURL` field in the review + edit sheets; the **"Open chat"** reopen deep-link. **Refines [ADR-0038 Amd 3](decisions/ADR-0038-external-llm-handoff.md)** (moves the URL off the device-local handoff onto this synced home) and is **gated on the same live-`/c/`-link device check Amd 3 owes**. When S3 ships, add `PlaybookSectionMeta` to the standing prod-schema promotion list below.

**Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4)** — surfaced by the Amendment 3 *over*
presentation (PR #197). The pipeline is **already wired**: `MenuRecipeBrowserPanel` rows are
`.draggable(MenuDraggedRecipe)` and `MenuDishDayList` has
`.dropDestination(for: MenuDraggedRecipe.self) { model.addRecipesToMenu(…) }`, and the slide-over keeps the
Dishes body interactive beneath it. **But drag-and-drop is not firing reliably in the current betas** — Jon
(with Fable and GPT-5.6 Sol) could not get it to work; **retry after Beta 4.** Not dispatchable until then; when
it unblocks it's mostly confirm-E2E + polish (drop highlight, autoscroll, multi-select), no schema.

**Recipe edit proposals** ([ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) +
`efforts/recipe-edit-proposals.md`) — the "Adjust this recipe" verb; **S1 + S2 shipped** (overwrite
destination with section-aware multi-section overwrite/undo; the "keep as a variation" destination = ADR-0021's
`recipeVariations` table + reader fold + grocery fold). **S3 queued** = the iterative refine loop +
workbench-log deposit (was gated behind the 2026-07-08/09 dogfood ADRs, now all shipped — so S3 is unblocked
whenever Jon picks it). Extends ADR-0021 (the variation destination) — do not duplicate it.

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

**Still-deferred, separate future efforts** (not follow-through on any shipped effort): ADR-0027 **OQ4**
(a note-worthiness taste preference); **ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe* (the
menu note-item S1+S2 shipped in PR #178 → DONE-LOG; S3 is the remaining, separate slice); **ADR-0038 Amd 4 —
smart Learning curation** (an LLM pass reconciling incoming-vs-existing learnings — dedup/merge/supersede —
with the review sheet surfacing existing learnings; the deterministic exact-dedup *floor* shipped in PR #202,
so this is the paraphrase-aware ceiling, not urgent — [[handoff-stateless-both-directions]]). Comment ingestion
stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work history and the
implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the
device pass regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files.
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise run the app build with **elevated/unsandboxed permissions**, no simulator, and no signing
  identity:
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- Run `scripts/check-drift.sh`.
- **The generic app build is required evidence for `YesChefApp/` changes.** `scripts/check-drift.sh` compiles
  only `YesChefPackage`; a green package build and `swiftc -parse` are not App-target evidence. The default
  Codex sandbox can SIGTERM Xcode before compilation by denying Xcode's user-level service/cache access, so
  start with the elevated command above. A sandbox-shaped `143` is not an expected green result. If the
  elevated build cannot reach the compiler, record the full-log path and **the architect runs the same generic
  build locally before approving.** Once a build reaches the compiler, source errors must be fixed and the
  same command rerun to verify.
- **Corollary — keep pure logic out of the App layer.** String formatting, serialization, and parsing belong
  in `YesChefPackage` (which Codex *can* compile and test), not in `YesChefApp/`. #185's build break was
  `HandoffIntents.swift` calling `date: .full` (invalid `Date.FormatStyle.DateStyle`) — logic that belongs in
  `MealPlanHandoffContext` in Core, where the package build would have caught it instantly.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** Do not try alternate destinations, simulator resets, or install
  loops. The only build command is the elevated generic command above; an environment failure that prevents it
  reaching the compiler is an architect gate, not a successful Codex verification. Device install is Jon's pass.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
