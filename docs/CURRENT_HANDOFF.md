# Current Handoff

Last updated: July 24, 2026 (**both parallel dispatch targets SHIPPED and the board is clear.** The [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) load test (PR [#226](https://github.com/jonphillips/yes-chef/pull/226)) and [ADR-0021](decisions/ADR-0021-recipe-variations.md) V3 (PR [#225](https://github.com/jonphillips/yes-chef/pull/225)) were both approved and merged 2026-07-24 → [`DONE-LOG`](DONE-LOG.md). The parallel run worked exactly as scoped — no code contention. **ADR-0021's variations arc is now COMPLETE** (V1+V2+V3, nothing queued under it), and **ADR-0043's record survived its load test** with a real verdict: `omitted:` earned its place. **TWO new live dispatch targets are now up, again in PARALLEL — Jon's call, 2026-07-24:** (1) **[ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md) V1**, the seeded section-scoped Ask — ADR ratified the same day, and it fixes the grayed-verbs defect from that day's dogfood pass; (2) **[ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) S3**, tier-policy unification, with ADR-0045 V3 riding along. Each is its own dispatch and its own PR — parallel does not mean bundled.) Completed-slice history and strategic background live in [`docs/DONE-LOG.md`](DONE-LOG.md).



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

**TWO live dispatch targets as of 2026-07-24, running in PARALLEL — Jon's call — so the dispatch must NAME
one.** They are independent efforts, each its own dispatch and its own **separate PR**; parallel does **not**
mean bundled, and neither blocks the other. Dispatch with *"Do the **ADR-0045 V1** effort in
`docs/CURRENT_HANDOFF.md`"* **or** *"Do the **ADR-0043 S3** effort in `docs/CURRENT_HANDOFF.md`."* A bare
*"do the Next Up effort"* is **ambiguous by construction**: the agent must **STOP and ask Jon — never infer
which one.** If this section is empty or missing, likewise STOP. See `docs/AGENTS.md` § Work Intake &
Dispatch. A single dispatch may bundle **several cohesive slices** (one PR); do all listed, in order — but
**never bundle across the two targets below.** *(They barely touch: V1 is app-layer threading into the Ask
entry points, S3 is tier resolution in Core plus AI Settings. This is the same shape as the
2026-07-24 parallel run, which finished with zero code contention.)*

**LIVE DISPATCH TARGET — [ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md) V1: the seeded,
section-scoped Ask (app; no schema).** **ADR-0045 was ratified by Jon 2026-07-24** — Accepted, D1–D7 as
written, with **OQ4 resolved: auto-send** (a pre-filled composer leaves the buttons grayed until the cook
types, which is most of the defect still standing). OQ1/OQ2 are **V2** concerns and do not gate this. Read the
ADR first — it is the spec; this entry is the dispatch.

**The defect it fixes is live and was hit on the 2026-07-24 dogfood pass:** tap Ask → empty panel → every
apply-verb grayed → the cook concludes the feature was removed. The cause is one unfinished affordance —
`Ask` is the single per-section menu item that does **not** carry its section, routing to the un-scoped
`chatButtonTapped`, which seeds no prompt, so `canRun` never sees a subject. **Thread `PlaybookSectionKind`
through the entry points and seed the opener from the existing outboard `.discuss` ask** (D2 — one authored
prompt per verb serving both paths), auto-sending it on open. Mostly threading, not thinking.

**⚠️ Two things are load-bearing and both are ways this slice can go wrong.** First, **do not loosen
`requiresSubject`** (D6) — seeding is what enables the buttons, because a sent seed produces an assistant
reply and `latestReplySubject` goes non-nil. Forcing the buttons on instead would let an apply-action fire
with an **empty subject**, which is the silent-garbage path, not a fix. Second, **scope is exactly the three
section-scopable entry points** — the recipe column-top Ask, the recipe per-section menu Ask, and the Menu's
Ask. **[OQ3's pre-dispatch check found FIVE cold-start entry points, not the three D3 claims](decisions/ADR-0045-onboard-path-stays-viable.md#open-questions):**
the meal-calendar day-header Chat and the Workbench Chat have the same dead end but **no section to carry**,
so their seeds are a different authoring job. They are a **recorded follow-on, deliberately not folded in** —
do not expand V1 to cover them on this ADR's momentum.

**Verification:** app-layer, so the elevated `generic/platform=iOS` build is required evidence, plus the Core
suite and `scripts/check-drift.sh`.

**SECOND LIVE DISPATCH TARGET (parallel) — [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) S3: policy
unification (Core + app; the first slice in this arc that changes behavior).** One slice, one PR. **Now
unblocked:** D5 sequenced S3 *after* the record and the load test, and [the load test landed 2026-07-24](https://github.com/jonphillips/yes-chef/pull/226)
finding **no tier-policy change needed** — so S3 is independently scoped rather than folded into it. Read the
ADR first; this entry is the dispatch.

**One shared `resolveTier()` honoring BOTH `recipeChatProviderPreference` and `recipeChatTierPreference`, with
an honest error when the only available tier cannot do the job** — replacing the silent `.onDevice` fallback
that today surfaces to the cook as `responseTruncated` on a 16k strict-JSON call instead of *"add an API
key."* **This absorbs the extractor tier-selection half** of the S4 nit in Ready Efforts (removed from there,
not tracked twice — its *prompt-authoring* half stays separate and is not in this dispatch). It is also where
**`ModelCallTierResolution` widens past its two cases**: the chat path's user-selected tier is a real third
shape the enum currently flattens into `.callerProvided`, and S1's approval left it under-modeled on purpose
until a consumer existed. This is that consumer.

**[ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md) V3 rides with this slice** (its own sequencing
note asks for exactly that): the frontier **model** becomes a user setting — `FrontierProvider.defaultModel`
is a hardcoded LLMClientKit constant the S2 inventory now displays read-only, and the override point already
exists (`AnthropicModelClient(apiKey:model:session:)`); it is only `TieredModelClient.live()` that declines to
expose it. **This crosses into `jon-platform`**, which is why it belongs here — S3 is the one slice with both
repos open. **Landing S3 also fires [ADR-0044](decisions/ADR-0044-provenance-engine-to-llmclientkit.md)'s
trigger** (the provenance-engine lift to `LLMClientKit`, validated by Galavant) — **that is a signal to write
the design, not licence to build it in this PR.**

**Verification:** touches Core, the App layer, and `jon-platform`, so the elevated `generic/platform=iOS`
build is required evidence alongside the Core suite and `scripts/check-drift.sh`. ⚠️ A worktree build needs
the `.claude/jon-platform` symlink ([[worktree-jon-platform-symlink]]).

**Not a dispatch target, but the next thing that wants Jon's time — the [ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md)
scoping session.** Accepted 2026-07-23, but only its *Decision* was ratified; its six open questions still
need one scoping pass (OQ5, the gated-fetch UX, carries no architect recommendation at all) and its slice plan
is still marked proposed. It unblocks the whole gated workbench phase, and its reference material is the
**first genuinely new context layer** ADR-0043's record must express — a second, harder load test than the
three advisory verbs. **Ratified ≠ scoped: do not dispatch S1 off the ADR alone.**

**ADR-0042 closed 2026-07-21.** S0/S1/S2/S4 shipped and device-passed (→ [`DONE-LOG`](DONE-LOG.md)); **S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want, its danger receded rather than grew, **do not build it on ADR momentum**; there is no S5. **⚠️ The return contract is v2 — re-copy the project instructions from AI Settings or every verb fails the marker gate.**

**The workbench phase is ratified but NOT yet dispatchable — the distinction matters** (the ADR-0032 half is
**Candidate C** above; this is the rest of it). The **experiment-outcome verb** has only its *placement*
ratified — an **ADR-0042 amendment** (D8's corollary: a conjecture suppresses learnings, but a **cooked**
experiment is findings, so learnings come back on) — and that amendment gets written **when the phase is
scoped, deliberately not now**, so it is not built on ADR-0043's momentum
([[withdraw-not-defer-orphaned-schema]]).

**Both candidates Jon named 2026-07-21 are now DISCHARGED — do not re-queue either.**
- **Variations — the whole ADR-0021 arc shipped and device-passed.** V1 + V2 in PR [#221](https://github.com/jonphillips/yes-chef/pull/221) (2026-07-23) and **V3, the recipe-scoped deliberation log, in PR [#225](https://github.com/jonphillips/yes-chef/pull/225) (2026-07-24)** → [`DONE-LOG`](DONE-LOG.md). Hand-edit through the resolved view with ops **derived** on save, split-off, promote-to-base, and the deliberation log with its Playbook read surface are all live. **Nothing is queued under ADR-0021.** Its one synced table (`recipeDeliberationLog`) is on the promotion list below.
- **Menu is under-served by hand-off verbs** — **discharged by ADR-0043's load test** (PR [#226](https://github.com/jonphillips/yes-chef/pull/226)), where `menuComplement` and `mealPlanComplement` shipped their hand-off asks and did double duty as the record's first real load. Parked **ADR-0013** meal-planner verbs remain separate and unscoped; classify each new verb's commit shape first ([[chat-verb-commit-shapes]]).

**Feature efforts still on the board — Jon picks; do not infer** (the live dispatch targets are ADR-0045 V1 and ADR-0043 S3, running in parallel at the top of this section, and nothing else):
- **Workbench log-editor nits (small, from the S2 review; not urgent)** — the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision (small; found 2026-07-21; silent-failure risk).** `instructions` opens *"You extract a proposed edit … from a cooking **conversation**,"* the prompt says *"**Conversation so far:**"* and closes *"Extract only the concrete recipe edit **the user is asking to review**"* — while `HandoffReviewCoordinator.draftRecipeAdjustment` wraps the finished brief as a single fake `.user` message and passes `selection: ""`. So a **decided** revision is presented as an **in-progress ask**, inviting the extractor to infer or hedge where the whole point of Amd1-D1 is that the human already decided. Under-extraction here is **silent** — a 3-change brief that yields 2 ops just shows a shorter side-by-side. *Fix:* a task-specific framing for the brief path ("this is a decided revision; transcribe every change faithfully and completely"), **not** a second client.
  - **Its sibling — the re-implemented tier selection — is no longer tracked here.** That half (ignored `recipeChatTierPreference`, `availableProviders.first` fallback, silent `.onDevice` on a 16k strict-JSON call → `responseTruncated` instead of *"add an API key"*) is **absorbed by [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) S3 — now a live dispatch target above**, which removes it structurally rather than patching one call site. **Do not fix it here and do not track it twice.** The two halves are genuinely separate: one is *policy*, the other is *prompt authoring*.
  - **Deliberately NOT part of this:** adding the taste profile or known-learnings to the *extractor*. Those belong to the outbound hand-off ask (where `RecipeHandoffContext` already sends both) because that is where judgment happens. The extractor transcribes a settled decision, and feeding it preference context invites exactly the editorializing D1 exists to stop — and ADR-0043 D6 makes this asymmetry *visible* rather than flattening it.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip). ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
- **The inbound learnings parser has no floor, and it fails silently (small; real defect, not a nit).** `AIHandoff.learningBullets` (`AIHandoff.swift:860`) keeps only lines starting `- ` / `* ` / `• ` and **drops everything else with no trace** — a learning returned as a naked sentence or a paragraph vanishes, which is a straight [[editable-at-the-grain-stored]] *lossless-or-loud* violation and is named as a defect in [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md). *Fix:* tolerant extraction plus a **loud remainder** (the `unparsedLines` pattern PR #226 just established on the three advisory verbs — reuse it, do not invent a second convention). This is the deterministic **floor** and it goes **ahead of** ADR-0038 Amd 4's LLM curation ceiling ([[handoff-stateless-both-directions]]).
- **Two small carry-forwards from the PR [#226](https://github.com/jonphillips/yes-chef/pull/226) review (both non-blocking, noted at approval).** `stageReaderFeedback` defaults `unparsedLines` to `[]`, so accepting a single tip through the *in-app* path clears the evidence banner (cosmetic). And a **crowding** observation from the device pass: the Prep Plan disclosure now renders two Copy + two Paste buttons, the meal-plan day header four — routing is correct (a complement result pasted into the prep-plan button hits the unmatched-result confirmation), but it wants a feel on iPhone before anyone adds a fifth.
- **Open a design ADR** — ADR-0013 meal-planner verbs (needs scope confirmation) or ADR-0014 text editing.

**Parked to `docs/open-questions.md` (design forks, decide with Jon before build):** multi-bubble /
whole-transcript chat selection (per-bubble `UITextView` caps the payload). *(Hand-editing a variation and
promote-to-standalone are **no longer parked and no longer queued** — answered 2026-07-21 by ADR-0021 Amds
1 + 2 and **shipped** in PR [#221](https://github.com/jonphillips/yes-chef/pull/221). ADR-0014 remains a
dependency **only** for section headers, the one edit the op vocabulary cannot express.)*

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
promotion locks the record type permanently), **and the synced `workbenchLog` table including its nullable `hypothesis` / `change` / `rationale` columns** (ADR-0042 S2), **and the synced `recipeDeliberationLog` table** (ADR-0021 V3, PR [#225](https://github.com/jonphillips/yes-chef/pull/225) — **shipped 2026-07-24**; [Amd 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23); the *only* schema that variations arc added — V1+V2 added none); and note the app target
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
(Accepted 2026-07-21) shipped as S4 in PR [#216](https://github.com/jonphillips/yes-chef/pull/216)** — it extends the same pattern to the recipe body:
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
express. *(ADR-0021 itself is closed: its original standalone framing was superseded by ADR-0023 D1/S2 —
variations are created through the adjust proposal/review surface — and its three amendment slices all
shipped.)*

**[ADR-0045](decisions/ADR-0045-onboard-path-stays-viable.md) — the onboard path stays viable (Accepted
2026-07-24; V1 is a live dispatch target above, V2 is queued here).** Keeps the onboard/outboard choice
**reversible**: outboarding was a *pricing* judgment, not an architectural one, and deleting the onboard path
would convert a commercial bet into an irreversible code fact. **V2 — the Finalize button + the shared return
parser** (add the control, send the finalize instruction, run the reply through the same `AIHandoffReturn`
parser the paste path uses, route into the existing review sheet) **wants V1 first** — there is nothing to
finalize without a seeded discussion — and it is where **OQ1** (how Finalize and the apply-verbs coexist
without reading as two buttons for one job; recommendation: one control, mechanism chosen by tier) and **OQ2**
(at what tier the terminal turn is trustworthy — answer it *empirically* with one on-device attempt, do not
guess) get settled. **V3 rides with ADR-0043 S3**, not here. Also recorded in the ADR and **deliberately not
folded into V1**: the meal-calendar day-header Chat and the Workbench Chat are the fourth and fifth cold-start
entry points OQ3's check turned up — same dead end, no section to carry, so each is its own small slice.

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
