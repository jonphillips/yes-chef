# Current Handoff

Last updated: July 20, 2026 (**ADR-0042 S0 + S1 DONE (verified; Jon: device is fine) → Next Up = S2, the experiments verb + its schema.** S0 moved the return contract into the ChatGPT/Claude project's custom instructions (one Core constant `AIHandoffReturnContract` + a Settings copy button + the `YC-CONTRACT: v1` marker gate on every return path; it also closed the `.discuss`-no-example gap behind the S2.5 blob-report). S1 wired `.workbench` as a hand-off source with the **compare** deliverable (prose into `workbenchLog` rows a human reads) + the promoted committed-adjustment → `.rationale` log deposit (D6). Both schema-free; they ride in the S0/S1 slice PR ([#212](https://github.com/jonphillips/yes-chef/pull/212); `f865250` + review fix `3662aa2`). **⚠️ The feature is inert until the v1 project instructions are pasted from AI Settings** — the marker gate now applies to every verb. S2 is UN-GATED (OQ6 passed): the experiments verb, the label-cycle parser, three nullable synced `workbenchLog` columns, and D8's no-learnings rule. — Prior close: **ADR-0041 COMPLETE at S2.6** (PRs #206/#209 + ADR-0038 Amd 5 sparse learning ordering #210); **its S3 was WITHDRAWN** — no live `/c/` URL to house, meta-only fallback rejected (see [ADR-0041 Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19) + [ADR-0038 Amd 3](decisions/ADR-0038-external-llm-handoff.md#amendment-3--an-optional-user-pasted-conversationurl-to-reopen-the-live-chat-2026-07-15)). Device passes still owed (Jon) for #206/#209/#210.)

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

**Live dispatch target — [ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) S2 (Accepted 2026-07-20; the experiments verb + its schema). UN-GATED — OQ6 passed on device 2026-07-20.** Its own dispatch because it is the **schema slice** (S0 + S1 shipped — see DONE-LOG).

**S2 — the experiments verb (`workbenchExperiments`) + three synced `workbenchLog` columns.** Pin the return to labeled three-line blocks — `Hypothesis:` / `Change:` / `Rationale:`, in that order, one sentence each (D5). **The parser splits on the label cycle — a new `Hypothesis:` line opens a block — and NEVER on blank lines**, because OQ6's live run proved the blank-line separators do not survive the paste path; **unit-cover the run-together (no-blank-line) shape explicitly — it is what the live run actually produced, not a hypothetical.** Parse lossless-or-loud (ADR-0040). Add three nullable synced columns to `workbenchLog` — `hypothesis` / `change` / `rationale` (OQ2: an experiment is write-many, its `outcome` is filled in later, so the triple is typed fields, not prose smeared into `body`) + the migration + the per-field edit affordance that justifies typing them. Experiments land as `.experiment` rows. **Emits NO learnings (D8** — an experiment is a conjecture; knowledge belongs in its `outcome` after it is tried, so drop `YC-LEARNINGS:` from the outbound prompt and ignore it if returned).

**Schema step, same PR:** add the three `workbenchLog` columns to the standing prod-schema promotion list below. We are pre-prod by design — that is the reason to fix the shape *now*, before promotion locks it.

**Verify** per the Verification Pattern below — `swift build` + Core tests (with the no-blank-line parser test), one elevated `generic/platform=iOS` build, `scripts/check-drift.sh`. Device pass is Jon's: an experiments hand-off round-trips into typed rows and a single field edits without regenerating the others.

**S0/S1 groundwork already shipped (context for S2, not a task):** `.workbench` is a hand-off source, the return contract lives in the project's custom instructions behind the `YC-CONTRACT: v1` marker gate, and compare + the `.rationale` deposit are wired. **⚠️ Paste the v1 project instructions from AI Settings** before any round-trip — the marker gate makes every verb inert without them.

**Do not** wire `adjustRecipe` as a paste-back (D2 — it's a structured canonical write, stays the in-app verb) or build the ADR-0019 S3 `experiments` BLOB (superseded — rows, not a blob). `workbenchDraft` stays deferred (D5/S3).

**Device pass owed (Jon) on ADR-0042 S2 — unmerged, PR [#214](https://github.com/jonphillips/yes-chef/pull/214).** Architect review of `6c71c8a` found the slice faithful to the ADR (label-cycle parser, D8 no-learnings enforced in prompt + contract + import, per-field edit affordance, promotion list updated); package build + 378/378 tests + generic-iOS build all green. Two review fixes landed in `a7b66b9`: the experiments **migration was registered mid-list, ahead of the already-applied ADR-0040 prep-plans migration** — moved to the end so applied migrations stay a stable prefix (additive and independent, so no data risk either way); and the pasted contract now carries a **human-visible `v2` version label**, since the version previously appeared only inside the "second line must be `YC-CONTRACT: v2`" clause and a human could not tell which version their project held. **⚠️ The contract is v2 — re-copy the project instructions from AI Settings before any round-trip, or every verb fails the marker gate.** *Verify on device:* an experiments hand-off round-trips into typed rows; editing one field leaves the other two untouched; a stale-v1 paste surfaces the friendly re-copy error. Non-blocking follow-ups left for Codex: the `canSave`/`normalizedLogEntryDraft` mismatch on body-plus-partial-typed-fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.

**Workbench dogfooding polish (Jon's asks, `aa100d0`, rides in #214).** Candidate rows open their recipe on tap (header only — the row also hosts the annotation field); copy and save now confirm via the existing `AppToastCenter` toast + success haptic, on all four hand-off surfaces plus workbench annotation and log-entry saves. Toast hosting differs by surface because an overlay mounted by a presenting view does not draw over the sheet it presents: workbench and `RecipeDetailView` host their own (the latter is built from four call sites and only `RecipeFullScreenCover` mounted one, so the iPad `AppMainLayout` path was silent), while Menu and Meal Calendar reuse their model's shared center. *Verify on device:* toasts appear over the workbench sheet and on the iPad split recipe path.

**Device passes owed (Jon) on already-merged work** — S2.5 (#206): filled Serve With prefill retains existing rows; filled Make-ahead offers Replace/Append with neither pre-selected; section actions live only in the expanded-header `•••`; paste prompts once per round-trip; Meal Calendar uses compact layout in iPad Slide Over. S2.6 (#209): every Clear asks first, editor sheets have no Clear, Serve With deletes by swipe with no visible `x`, pasted bullets render singly. ADR-0038 Amd 5 (#210): learnings drag-reorder on all three surfaces and hold across a two-device sync — and watch the recorded tradeoff, that a newly returned learning still prepends **ahead of** a deliberate manual arrangement.


**Feature efforts still on the board — Jon picks; do not infer** (ADR-0042 S2 is in Next Up above; these are *after* it):
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip). ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
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
writes a structured delta.

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — the store + curate + compare arc is
complete (S1–S4 all shipped → DONE-LOG). Remaining parked follow-ons in the effort doc: the
**synthesis-shaped apply-action** (the draft verb's own action shape — a distinct action enabled by workbench
state, no last-reply gate/chip; app-layer only, small, spec in the effort doc's "Out of scope" section — this
was the prior Next Up, demoted here, not yet built), plus AI effort/tier as a user-facing setting,
AI-generated log entries, and the S3 review notes. **New direction —
[ADR-0042](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) (Accepted 2026-07-20; S0/S1 shipped —
DONE-LOG; S2 is the Next Up dispatch above):** the workbench becomes an **external hand-off source**, since its product is deliberation
and the chat apps do that unmetered in a live thread. Compare + experiments outboard; the **draft verb does
not** (a structured canonical write, D2); experiments land as `workbenchLog` rows, **not** ADR-0019 S3's
`experiments` BLOB, which is superseded. **S1 is schema-free; S2 adds three nullable synced `workbenchLog`
columns** (`hypothesis`/`change`/`rationale` — OQ2 resolved 2026-07-20: an experiment is write-many, so the
triple is typed fields per ADR-0040, and being pre-prod is the reason to fix the shape *now*). **When S2
ships, add those columns to the standing prod-schema promotion list above.** **S2 is UN-GATED — OQ6 passed
on device 2026-07-20:** with the v1 contract living in the ChatGPT project's custom instructions (**not** in
the prompt), a long real conversation still switched cleanly into the return block on `finalize`, echoed
`YC-CONTRACT: v1`, held all three field labels across four experiments, and honored D8's learnings
suppression stated many turns earlier — confirming **D1, D4 and D8** in the shape we'd ship. **One failure
that binds the parser: the blank lines between blocks did not survive** (model or paste — indeterminable,
which is the point), so **the parser splits on the label cycle, never on whitespace**, and must be
unit-covered for the run-together shape the live run actually produced. Also from that run: **D8** (3 of 4
returned learnings were the verb's own untested hypotheses restated as fact — knowledge belongs in the
experiment's `outcome`, after it's tried) and **D9** (threads get a derived `<TaskType>: <Object>` title —
task, not object-kind, because ADR-0041 section-scoping means one recipe can have three live threads; the
title is **advisory only**, nothing parses it, since the auto-titler paraphrased it in testing).

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
