# Current Handoff

Last updated: July 21, 2026 (**ADR-0042 S2 DONE (device-passed; PR [#214](https://github.com/jonphillips/yes-chef/pull/214)) → Next Up = S4, the recipe-body hand-off + revision brief ([Amendment 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21), Accepted 2026-07-21).** S2 shipped the experiments verb, the label-cycle parser, the three typed `workbenchLog` columns and D8's no-learnings rule → DONE-LOG. **⚠️ The contract is now v2 — re-copy the project instructions from AI Settings or every verb fails the marker gate.** **S3 (`workbenchDraft`) stays deferred and is NOT next** — no concrete want; do not build it on ADR momentum. Two new amendment sets landed as architecture-only docs: **ADR-0042 Amd 1** (Accepted — the ask outboards, a prose *revision brief* returns, the in-app extractor still writes the delta; its prompt is hand-validated) and **[ADR-0021 Amds 1 + 2](decisions/ADR-0021-recipe-variations.md)** (Proposed — variations become hand-editable because the ops are *derived*, plus promote-to-base / split-off-as-its-own-recipe; ratify before dispatching). — Prior closes: **ADR-0042 S0 + S1** ([#212](https://github.com/jonphillips/yes-chef/pull/212) — `.workbench` as a hand-off source, the contract moved into the project's custom instructions, compare + the `.rationale` deposit) → DONE-LOG. — Prior close: **ADR-0041 COMPLETE at S2.6** (PRs #206/#209 + ADR-0038 Amd 5 sparse learning ordering #210); **its S3 was WITHDRAWN** — no live `/c/` URL to house, meta-only fallback rejected (see [ADR-0041 Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19) + [ADR-0038 Amd 3](decisions/ADR-0038-external-llm-handoff.md#amendment-3--an-optional-user-pasted-conversationurl-to-reopen-the-live-chat-2026-07-15)). Device passes still owed (Jon) for #206/#209/#210.)

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

**Live dispatch target — [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) S4 ([Amendment 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21), Accepted 2026-07-21): the recipe body gets a hand-off door, and a prose *revision brief* comes back.** One dispatch, two cohesive slices, **one PR. Schema-free** — `AIHandoff` is device-local, so nothing here touches the prod-schema promotion list. **Read Amendment 1 in full before starting; Amd1-D1/D2 and Amd1-D7 are load-bearing.**

**The shape, so it is not mis-built:** the ask goes out, **prose comes back, and the delta is still written in-app by the shipped extractor.** The return is a *revision brief* — a decided revision in a cook's language, one change per line — never ops, never IDs, never a rewritten recipe. **D2 is upheld, not relaxed:** nothing carrying identity crosses the paste door.

**S4a — the door out.** A task-keyed entry point on `RecipeHandoffContext` beside `prompt(for: section)` (the recipe body is **not** a `PlaybookSection` — do not force it into one), sending the **whole** recipe (no `excludingPlaybookSections:` filter) plus the taste profile and known-learnings block the section prompts already send. `.discuss` is the default mode. Wire the recipe-body export into `HandoffIntents` metadata and the in-app Copy door (ADR-0038 Amd 2), with the derived D9 title line (`Adjust Recipe: <recipe name>`). **Ship the ask verbatim from the ADR's S4a slice block — it is hand-validated (2026-07-21), including its three illustrative lines and Amd1-D7's learnings sentence.** A `DeliverableFormat` case alone is **not** sufficient: `discussInstruction` is one clause, so the shape must live in the `RecipeHandoffContext` ask, exactly as `lineListFormat` does for the sections.

**S4b — the door back.** Replace the `.recipe` × `.adjustRecipe` `throw .wrongTask` with a real import route → a **brief review sheet** (the ADR-0024 editable preview: brief text + learnings) → a *"Draft the revision"* action calling the existing `recipeAdjustmentClient` with the brief as the conversation → the existing side-by-side review → the existing two commit destinations. **No new commit shape and no new storage** — the brief is transient (Amd1-D5).

**Do not:** wire a **delta** paste-back (D2 — the structured write stays in-app); restate the return contract in the prompt (D4 — it lives in the project instructions, and this verb needs **no contract stanza and no version bump**, Amd1-D6); extend the ingredient/method **op vocabulary** from inside this slice (it belongs to [ADR-0021 Amd1-D5](decisions/ADR-0021-recipe-variations.md), where step insertion is now the first candidate); or build `workbenchDraft` (D5/S3 — deferred, no want).

**Known trap, must be handled (Amd1-OQ3):** adjust applies its proposal to the **base** `detail` while the reader resolves a variation for **display only**, so a brief argued about an active variation would silently anchor to the base. **Export the base recipe and say so in the sheet, or refuse to export while a variation is active** — do not ship it ambiguous.

**Verify** per the Verification Pattern below — `swift build` + Core tests (the routing case and a return-payload round-trip: token, `YC-CONTRACT: v2`, prose body, learnings), one elevated `generic/platform=iOS` build, `scripts/check-drift.sh`. Device pass is Jon's: outboard a real revision, argue it, `finalize`, paste, edit the brief, draft, review side by side, commit as a variation.

**Device passes owed (Jon) on already-merged work** — S2.5 (#206): filled Serve With prefill retains existing rows; filled Make-ahead offers Replace/Append with neither pre-selected; section actions live only in the expanded-header `•••`; paste prompts once per round-trip; Meal Calendar uses compact layout in iPad Slide Over. S2.6 (#209): every Clear asks first, editor sheets have no Clear, Serve With deletes by swipe with no visible `x`, pasted bullets render singly. ADR-0038 Amd 5 (#210): learnings drag-reorder on all three surfaces and hold across a two-device sync — and watch the recorded tradeoff, that a newly returned learning still prepends **ahead of** a deliberate manual arrangement.


**Feature efforts still on the board — Jon picks; do not infer** (ADR-0042 S4 is in Next Up above; these are *after* it):
- **[ADR-0021](decisions/ADR-0021-recipe-variations.md) V1 + V2 — variations become hand-editable, and promotion gets its two destinations.** **Amendments 1 + 2 are Proposed — ratify with Jon before dispatching** (Amd1-D7 and Amd2-D4 are already ratified). **V1:** editing a variation edits the **resolved** recipe and the ops are **re-derived** on save — the overlay and highlighting survive because the delta is recomputed, never hand-authored; the derivation returns `(ops, unrepresentable[])` so an inexpressible edit reports at save and offers the split-off, never saving a partial (Amd1-D7). **The editor must be the ID-preserving structured one** — a text round-trip diffs a one-word change as remove+add and destroys the color comparison (Amd1-D4). **V2:** split off as its own recipe (B1) and promote-to-base with the old base auto-derived into a variation (B2); **no probation machinery** — no cook counts, no verdict prompts (Amd2-D4). **Bundle V1+V2** so the save-time report has a split-off to offer. **Schema-free — the `deltas` BLOB stays** (Amd1-D3: ADR-0040 keys on the grain the *human* edits, and no human edits an op). ADR-0023 OQ3 (rebasing existing variations onto a new base) **must be answered in V2**, not deferred again.
- **Workbench log-editor nits (small, from the S2 review; not urgent)** — the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip). ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
- **Open a design ADR** — ADR-0013 meal-planner verbs (needs scope confirmation) or ADR-0014 text editing.

**ADR-0026 device pass still owed (Jon):** two interaction risks — (1) the adjust launch row presents
Compare-diff from `RecipeDetailView` while the collection sheet dismisses from `RecipeChatPanel` in the same
runloop (verify Compare-diff isn't swallowed); (2) N=1 auto-drill stacks the child review sheet over the
collection sheet (confirm it reads cleanly, incl. iPad split-chat).

**Parked to `docs/open-questions.md` (design forks, decide with Jon before build):** multi-bubble /
whole-transcript chat selection (per-bubble `UITextView` caps the payload). *(Hand-editing a variation and
promote-to-standalone are **no longer parked** — answered 2026-07-21 by ADR-0021 Amds 1 + 2, queued in Ready
Efforts. ADR-0014 remains a dependency **only** for section headers, the one edit the op vocabulary cannot
express.)*

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
promotion locks the record type permanently), **and the synced `workbenchLog` table including its nullable `hypothesis` / `change` / `rationale` columns** (ADR-0042 S2); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**ADR-0041 deferred follow-ons** (on the record in the ADR, **not** dispatchable without Jon scoping them) — the **menu** Playbook sections getting the same per-section toolbar (ADR-0039 Amd 2/3's shared Enrichment column; ADR-0041 deliberately scoped to the *recipe*), and section-selection checkboxes on the whole-recipe hand-off (the scoped per-section verbs make these *less* necessary, not more). **ADR-0041 itself is complete** (closed at S2.6; S3 withdrawn). **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it**; if section provenance is ever wanted, it designs its own storage against its own consumer ([ADR-0041 Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).

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
`recipeVariations` table + reader fold + grocery fold). **S3 is closed — split by
[ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) (2026-07-20):** its *iterative
refine loop* half is **WITHDRAWN** (D7 — refinement happens in the live external thread; an in-app multi-turn
proposal loop is a worse copy of it, **do not rebuild it**), and its *workbench-log deposit* half is
**promoted into ADR-0042 S1** (D6). **Nothing remains queued under ADR-0023.** Extends ADR-0021 (the
variation destination) — do not duplicate it. Per ADR-0042 D2 the in-app verb stays the **only** path that
writes a structured delta — **unchanged by ADR-0042 Amd 1**, which adds an *export* door and a prose brief
feeding this same extractor; the in-app verb is complementary, not replaced (OQ5).

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — the store + curate + compare arc is
complete (S1–S4 all shipped → DONE-LOG). Remaining parked follow-ons in the effort doc: the
**synthesis-shaped apply-action** (the draft verb's own action shape — a distinct action enabled by workbench
state, no last-reply gate/chip; app-layer only, small, spec in the effort doc's "Out of scope" section — this
was the prior Next Up, demoted here, not yet built), plus AI effort/tier as a user-facing setting,
AI-generated log entries, and the S3 review notes. **Direction — [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md)
(Accepted 2026-07-20; **S0/S1/S2 all shipped** → DONE-LOG):** the workbench is an **external hand-off source**,
since its product is deliberation and the chat apps do that unmetered in a live thread. Compare + experiments
outboard; the **draft verb does not** (a structured canonical write, D2), and `workbenchDraft` (S3) **stays
deferred with no want — do not build it on ADR momentum**. Experiments landed as typed `workbenchLog` rows,
**not** ADR-0019 S3's `experiments` BLOB, which is superseded. **[Amendment 1](decisions/ADR-0042-workbench-handoff-and-the-return-block.md#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21)
(Accepted 2026-07-21) is the live dispatch (S4) above** — it extends the same pattern to the recipe body:
**prose out, prose back, structure derived in-app, a human gate at each end**, with D2's line restated as
**the paste door never carries identity.**

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
Decide with Jon before any implementation — **and note it narrowed on 2026-07-21**: ADR-0021 Amd1-D5 needs
ADR-0014 only for **section headers inside a variation**, which is the one edit the op vocabulary cannot
express. *(Note: [ADR-0021](decisions/ADR-0021-recipe-variations.md)'s original standalone framing was
superseded by ADR-0023 D1/S2 — variations are created through the adjust proposal/review surface — but it
**is a queue item again** as V1 + V2 above, on the strength of its 2026-07-21 amendments.)*

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
