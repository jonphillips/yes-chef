# Current Handoff

Last updated: July 17, 2026 (**ADR-0041 accepted → Next Up.** Two efforts shipped since the last bump and moved to DONE-LOG: the **dogfood polish batch** (PR #198) and **ADR-0039 Amendment 2 / Slice D + Amd 3** (PR #197, menu adopts the permanent Playbook column). **Next Up = ADR-0041 Slice 1** — the per-section Playbook toolbar + per-section edit sheet, **app-layer only, no schema, no new verbs**. ADR-0041's S2 (section-scoped hand-off) + S3 (synced section-meta + conversation URL) are queued in Ready Efforts; S2 is now **un-gated** (OQ3 resolved 2026-07-17 by a live ChatGPT paste-back taste — the Serve-With list round-trips clean).)

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

**Live dispatch target — ADR-0041 Slice 1: the per-section Playbook toolbar + per-section edit sheet.** Full spec in [ADR-0041](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) (read **D1, D2, D4, D7** and the S1 line). **App-layer only — NO schema / migration, NO new verbs, NO hand-off-routing changes** (S1 reuses existing enrichment content + the ADR-0024 editable review sheet; the new scoped hand-off is S2). All in `YesChefApp/` (`RecipePlaybookView.swift`, `RecipeDetailModel+Enrichment.swift`, `RecipeEditorView.swift`); do all four in order.

1. **State-aware per-section toolbar (D2), rendered in the expanded content (not the header).** For each Playbook section in `RecipePlaybookView.swift` (Make-ahead, Chef It Up, Serve With), show a toolbar at the top of the expanded content; **collapsed** sections keep only title + fill-dot + chevron. Two-visible-plus-`•••`, state-dependent — **empty:** primary + `•••`(Write manually · Ask); **filled:** **Edit** · `•••`(Paste-to-replace · **Clear**). **Relocate `Clear` out of the always-visible content row** into the overflow (and the edit sheet, item 3): the existing `clearMakeAheadButtonTapped` / `clearChefItUpButtonTapped` and the Serve-With per-item remove all stay, just move.
2. **Make-ahead's external round-trip moves into its section; retire the column-top duplicate.** Make-ahead is the **one** section with a working external hand-off today (the column header's `handoffButton` + `pasteResultButton`, wired to `handoffTransport.copyPrompt(for: .recipe(id))` / `pastedResultsReceived`). **Relocate those two into the Make-ahead section toolbar** (empty → **Hand off** *(prominent, spark icon)* · **Paste**; filled → **Edit** · **Redo**) and **remove `handoffButton` + `pasteResultButton` from `playbookHeader`** (keep `askButton`). Pure relocation of working code — no new routing. **⚠️ Chef It Up + Serve With get NO Hand off / Redo / Paste-result in S1** — their scoped export doesn't exist until S2, so do **not** render a dead/fake external button on them; their empty-state offer is **Ask** + Write-manually, filled is **Edit** · `•••`(Clear).
3. **Per-section edit sheet (D4), lifted off the monolithic editor.** Each section's **Edit** opens its **own** sheet reusing the ADR-0024 editable-review presentation (roomy, scrollable, human-as-final-author), committing through the existing `commitMakeAheadText` / `commitChefItUpText` / Serve-With `applyingEditableReviewText` paths (`RecipeDetailModel+Enrichment.swift`). Reader Feedback's inline Edit/Done editor (`RecipePlaybookView.swift:226`) is the shape to mirror. The sheet also hosts **Clear**. Drain make-ahead / chef-it-up / serve-with editing **out of** `RecipeEditorView`.
4. **Brand-free copy (D7).** New per-section controls read **Hand off / Redo / Paste / Edit** — **no "ChatGPT"** on any per-section button; the spark icon carries the external signal. (The provider-name-in-Settings line is out of S1 scope — just don't add brand nouns.)

**Verify:** app-layer — the architect's local `generic/platform=iOS` build is **required evidence** (see Verification Pattern). Confirm on device (Jon): each section shows the correct toolbar for empty vs filled; collapsed headers are clean; `Clear` works from overflow + edit sheet; Make-ahead **Hand off/Paste still round-trip** after the move and the column-top duplicate is gone; the per-section edit sheet commits and that field no longer appears in the main recipe editor; Chef It Up / Serve With show **no** external button yet.


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
**and the synced `learnings` table** (ADR-0038 Amd 1 / S3a) **and the synced `prepPlanSteps` table**
(ADR-0040 S2 — which also **retires the `Menu.prepPlan` BLOB**: restructure it *before* this cut, because
promotion locks the record type permanently); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**ADR-0041 Playbook section hand-off — S2 then S3** ([ADR-0041](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md); follows S1 above). **S2 (core + app) — the section-scoped external hand-off.** `HandoffExportSource` gains `.recipeSection(Recipe.ID, PlaybookSectionKind)`; `AIHandoffTaskType` gains `chefItUp` + `serveWith`; **⚠️ the `matches()` / token router must key on the section kind** (`HandoffIntents.swift:173`) — today it compares only `sourceType + sourceID`, so two sections of one recipe are indistinguishable and a pasted Chef-It-Up result would route onto Make-ahead. Wire Chef It Up + Serve With **Hand off / Redo / Paste** through the same in-app door (ADR-0038 Amd 2). **OQ3 resolved (2026-07-17), so S2 is un-gated.** A live ChatGPT paste-back taste parsed **7/7 clean** through the real `cleanedEditableReviewLine` + `suggestion(fromEditableReviewLine:)` — the Serve-With *list* round-trips via `ServeWithPlan.editableReviewText()`/`applyingEditableReviewText()` (`RecipeEnrichment.swift:42`). S2 work is small: **pin the `title: note` per-line format in the outbound prompt** (the load-bearing fix — the model complies) and **strip `**`/`*` emphasis from the parsed title**; junk otherwise gets caught in the ADR-0024 review sheet before commit, not by a paranoid parser. **S3 (schema + app) — the synced section meta + conversation URL.** New synced `PlaybookSectionMeta` `@Table` keyed `(recipeID, sectionKind)` carrying `{ provenance, conversationURL, dateModified }` (real FK → cascade-delete, no polymorphic-orphan problem); the `conversationURL` field in the review + edit sheets; the **"Open chat"** reopen deep-link. **Refines [ADR-0038 Amd 3](decisions/ADR-0038-external-llm-handoff.md)** (moves the URL off the device-local handoff onto this synced home) and is **gated on the same live-`/c/`-link device check Amd 3 owes**. When S3 ships, add `PlaybookSectionMeta` to the standing prod-schema promotion list below.

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
menu note-item S1+S2 shipped in PR #178 → DONE-LOG; S3 is the remaining, separate slice). Comment ingestion
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
