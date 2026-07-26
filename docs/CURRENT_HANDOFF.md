# Current Handoff

Last updated: July 26, 2026 (**ADR-0045's V1+V2+V3 arc is complete and device-passed.** V2 — the Finalize button (PR [#229](https://github.com/jonphillips/yes-chef/pull/229)) — merged 2026-07-24 → [`DONE-LOG`](DONE-LOG.md), joining V1 (PR [#227](https://github.com/jonphillips/yes-chef/pull/227)) and S3 + V3 (PR [#228](https://github.com/jonphillips/yes-chef/pull/228) / `jon-platform` PR [#33](https://github.com/jonphillips/jon-platform/pull/33)). The architect review of #229 drove three tested in-PR fixes (failed-finalize staging, the RecipeEnrichment truncation sweep, a Finalize→action resolution test). **The dogfood cleanup batch shipped in PR [#230](https://github.com/jonphillips/yes-chef/pull/230)** (iPhone menu layout, deterministic make-ahead ordering + a settled timing vocabulary, in-memory seed chip; the architect review drove the vocabulary expansion + prompt-contract fix) → [`DONE-LOG`](DONE-LOG.md) on merge. **The `Menu.prepPlan` BLOB is retired** — PR [#231](https://github.com/jonphillips/yes-chef/pull/231) merged 2026-07-25 → [`DONE-LOG`](DONE-LOG.md): the `DROP COLUMN` migration landed, the 2026-07-14 historical migration was frozen to raw SQL so it no longer pins the live `Menu` struct, and the property is gone from `Menu`, so the dead CKAsset field never enters the prod schema. **The inbound-learnings parser floor is fixed** — PR [#232](https://github.com/jonphillips/yes-chef/pull/232) merged 2026-07-25 → [`DONE-LOG`](DONE-LOG.md): `learningBullets` now emits a loud `unparsedLines` remainder threaded into each caller's existing evidence/throw, so a naked-sentence learning can no longer vanish. **The 2026-07-25 dogfood ferry pass is now the live track and it reordered appetite.** [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) runs **1 → 1.5 → 2 → 3**, one PR each: **Dispatches 1, 1.5 and 2 have all shipped** (PR [#233](https://github.com/jonphillips/yes-chef/pull/233), then PRs [#234](https://github.com/jonphillips/yes-chef/pull/234) + [#235](https://github.com/jonphillips/yes-chef/pull/235), then PR [#237](https://github.com/jonphillips/yes-chef/pull/237) → [`DONE-LOG`](DONE-LOG.md)), and **Dispatch 3 is Next Up.** Dispatch 2's device pass caught a day-scoped prep ask **silently deleting the other days** — the scoped *ask* had shipped without the **woven return** its own acceptance criterion required, and the fix was one prompt string, not a schema change. Its review also produced an architect error worth remembering: a `sourceDish` behavior guarded by a test whose *name asserted it was deliberate* was called a bug and "fixed," reversing [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) D3's corollary; it was reverted in round 3. **A test name that asserts intent is a decision until proven otherwise.** Its one new column (`aiHandoffs.dayOffset`) is **local — `AIHandoff` is not registered in `CloudSync`**, so nothing joined the promotion list. 1.5 stopped the embedded chat panel renting the host's navigation bar on the Recipe and the Menu, hoisted the Calendar's chat out of day-mode-only, made Ask a plain toggle, and settled the shared panel header to `Discuss ▾ · ⋯ · ✕`. Its device pass then caught two things worth remembering: the tier **checkmarks could never render** (a SwiftUI `Menu` gives a `Button` label one title and one image; the trailing `Image` was silently discarded, masked for months by the header chip that G5 retired), and a mid-thread provider switch produced a reply **claiming the previous provider** — routing was correct, but `history()` replays the transcript, so the new model continued the old one's persona. Assistant turns now carry the tier that produced them (`chatMessages.resolvedTier`), and **that table is local-only — nothing was added to the prod-promotion list.** **[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) S1 is demoted to Ready Efforts, unchanged and still dispatch-ready** — it lost the slot to appetite, not to a problem. **Landing ADR-0043 S3 fired [ADR-0044](decisions/ADR-0044-provenance-engine-to-llmclientkit.md)'s trigger** — a signal to write the provenance-engine-lift design, not to build it.) Completed-slice history and strategic background live in [`docs/DONE-LOG.md`](DONE-LOG.md).



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

**ONE live dispatch target: [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) Dispatch 3 — workbench lifecycle and hand-authored learnings.**
Dispatch with *"Do the **Dogfood ferry Dispatch 3** effort in `docs/CURRENT_HANDOFF.md`."* If this section is
empty or missing, **STOP and ask Jon — never infer.** See `docs/AGENTS.md` § Work Intake & Dispatch.

**The ferry effort is a live multi-dispatch track and the doc is its own dispatcher.** Sequence:
**1 (shipped) → 1.5 (shipped) → 2 (shipped) → 3 (this, and last).** Each dispatch is one PR and is spec'd in
full in the effort doc — read the dispatch's own section there, not a summary here ([`AGENTS.md`](AGENTS.md)
rule 4: the handoff points, it does not duplicate).

**⚠️ Dispatch 3 is the one that adds synced schema, and the obligation cannot live in the effort doc alone.**
Slice E2 adds **`workbenches.dateCompleted TEXT`** (nullable, synced) and **must add it to the prod-promotion
list below in that same PR** ([[handoff-bump-rides-in-slice-pr]]). A new synced column is cheap
([[synced-table-cost-calibration]]) — the cost is forgetting to register it before the prod cut.

**Its four slices:** **E1** retires the workbench Save Title / Save Notes buttons for commit-on-blur, with a
revert-to-last-good guard because `updateWorkbenchTitle` throws on empty. **E2** is the Active / Completed
lifecycle (the schema slice) — and it must **decide and state in the PR** whether a completed workbench stays
in the recipe picker and chat context (recommendation: exclude from pickers, keep reachable by search).
**E3** rewrites the delete confirmation, which today reads as though it deletes the recipes and does not.
**H** gives menu Learnings a hand-authored path: `LearningProvenance.inApp` **is constructed nowhere in the
codebase**, so the case is orphaned and there is no way to write one — this is the producer, plus wiring menu
learnings into `MenuChatContext`'s outbound ask, where they do not reach today.

**Verification:** package `swift build` + Core tests (the `dateCompleted` migration + filter, the `.inApp`
write path, the title-revert guard); then the generic app build (elevated, no signing) +
`scripts/check-drift.sh`. Device pass on `iPad Pro 13-inch (M5)` + `iPhone 17 Pro`.

**When Dispatch 3 lands the ferry track is complete** — retire it from Next Up and promote from Ready Efforts;
[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) S1 and
[`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) are both dispatch-ready and waiting.

**[ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md) is unblocked but unscheduled.** Its gate
("ferry Dispatch 1 lands first") was satisfied on 2026-07-25 and Dispatch 1.5's panel work is now merged, so
nothing holds it except appetite. **When it is picked up, [`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md)
S2–S4 want the slot immediately before it** — see Ready Efforts for why.

**ADR-0042 closed 2026-07-21.** S0/S1/S2/S4 shipped and device-passed (→ [`DONE-LOG`](DONE-LOG.md)); **S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want, its danger receded rather than grew, **do not build it on ADR momentum**; there is no S5. **⚠️ The return contract is v2 — re-copy the project instructions from AI Settings or every verb fails the marker gate.**

**The workbench phase is now half-dispatchable — the distinction matters.** Its **reference-material half is
[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md), scoped 2026-07-25 and dispatch-ready in
Ready Efforts below** (S1 → S2 → S3) — demoted from Next Up 2026-07-26 for the ferry track, not for a problem.
The **experiment-outcome verb** half is still NOT scoped: it has only
its *placement* ratified — an **ADR-0042 amendment** (D8's corollary: a conjecture suppresses learnings, but a
**cooked** experiment is findings, so learnings come back on) — and that amendment gets written **when that
half is scoped, deliberately not now**, so it is not built on ADR-0043's momentum
([[withdraw-not-defer-orphaned-schema]]).

**Both candidates Jon named 2026-07-21 are now DISCHARGED — do not re-queue either.**
- **Variations — the whole ADR-0021 arc shipped and device-passed.** V1 + V2 in PR [#221](https://github.com/jonphillips/yes-chef/pull/221) (2026-07-23) and **V3, the recipe-scoped deliberation log, in PR [#225](https://github.com/jonphillips/yes-chef/pull/225) (2026-07-24)** → [`DONE-LOG`](DONE-LOG.md). Hand-edit through the resolved view with ops **derived** on save, split-off, promote-to-base, and the deliberation log with its Playbook read surface are all live. **Nothing is queued under ADR-0021.** Its one synced table (`recipeDeliberationLog`) is on the promotion list below.
- **Menu is under-served by hand-off verbs** — **discharged by ADR-0043's load test** (PR [#226](https://github.com/jonphillips/yes-chef/pull/226)), where `menuComplement` and `mealPlanComplement` shipped their hand-off asks and did double duty as the record's first real load. Parked **ADR-0013** meal-planner verbs remain separate and unscoped; classify each new verb's commit shape first ([[chat-verb-commit-shapes]]).

**Feature efforts still on the board — Jon picks; do not infer** (the live dispatch target is ferry Dispatch 3 at the top of this section, and nothing else):
- **Workbench log-editor nits (small, from the S2 review; not urgent)** — the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision (small; found 2026-07-21; silent-failure risk).** `instructions` opens *"You extract a proposed edit … from a cooking **conversation**,"* the prompt says *"**Conversation so far:**"* and closes *"Extract only the concrete recipe edit **the user is asking to review**"* — while `HandoffReviewCoordinator.draftRecipeAdjustment` wraps the finished brief as a single fake `.user` message and passes `selection: ""`. So a **decided** revision is presented as an **in-progress ask**, inviting the extractor to infer or hedge where the whole point of Amd1-D1 is that the human already decided. Under-extraction here is **silent** — a 3-change brief that yields 2 ops just shows a shorter side-by-side. *Fix:* a task-specific framing for the brief path ("this is a decided revision; transcribe every change faithfully and completely"), **not** a second client.
  - **Its sibling — the re-implemented tier selection — is no longer tracked here.** That half (ignored `recipeChatTierPreference`, `availableProviders.first` fallback, silent `.onDevice` on a 16k strict-JSON call → `responseTruncated` instead of *"add an API key"*) is **absorbed by [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md) S3 — now a live dispatch target above**, which removes it structurally rather than patching one call site. **Do not fix it here and do not track it twice.** The two halves are genuinely separate: one is *policy*, the other is *prompt authoring*.
  - **Deliberately NOT part of this:** adding the taste profile or known-learnings to the *extractor*. Those belong to the outbound hand-off ask (where `RecipeHandoffContext` already sends both) because that is where judgment happens. The extractor transcribes a settled decision, and feeding it preference context invites exactly the editorializing D1 exists to stop — and ADR-0043 D6 makes this asymmetry *visible* rather than flattening it.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip). ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
- **One small carry-forward from the PR [#226](https://github.com/jonphillips/yes-chef/pull/226) review (non-blocking, noted at approval).** `stageReaderFeedback` defaults `unparsedLines` to `[]`, so accepting a single tip through the *in-app* path clears the evidence banner (cosmetic). *(Its sibling — the hand-off button **crowding** on the Prep Plan disclosure and the meal-plan day header — was **discharged by ferry Dispatch 2**, PR [#237](https://github.com/jonphillips/yes-chef/pull/237): the button rows are overflow menus now.)*
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
(ADR-0040 S2). *(The `Menu.prepPlan` BLOB it replaced was **dropped outright** in PR [#231](https://github.com/jonphillips/yes-chef/pull/231),
so it never enters the prod schema.)* **and the synced `workbenchLog` table including its nullable `hypothesis` / `change` / `rationale` columns** (ADR-0042 S2), **and the synced `recipeDeliberationLog` table** (ADR-0021 V3, PR [#225](https://github.com/jonphillips/yes-chef/pull/225) — **shipped 2026-07-24**; [Amd 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23); the *only* schema that variations arc added — V1+V2 added none); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**[`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) — the prep plan knows things the model doesn't (scoped 2026-07-26 from the PR [#237](https://github.com/jonphillips/yes-chef/pull/237) review + device pass).** Two slices, **no schema** — both use fields that already exist and already sync.
- **S1 (Core only) — the menu's placement dates reach `MenuChatContext`.** [ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D2 retired the fixed horizon enum *because* real session labels are concrete ("Wednesday evening", "Saturday · ~3 hrs out") — but the context carries **no date of any kind**, so a placed menu and an unplaced one send byte-identical context and the model falls back to relative horizons ("One day ahead" — ahead of *which* day?). That is the exact ambiguity ADR-0034's Context section opens with. Serialize the per-day dates, and ask for day-anchored sessions **only when the menu is placed** (unplaced keeps today's relative wording). **No app build needed** — no UI.
- **S2 — the dish picker; `sourceDish` becomes human-settable for the first time.** It is write-only from the LLM today (`PrepPlanStepEditorDraft` has no dish field, `PrepPlanStepRepository.update` has no parameter), while every outboard text return drops it by design (ADR-0040 D3). So links only decay and nothing can restore them. A picker defaulting to a `serves` → menu-item match, **suggestion visibly marked as a suggestion**, nothing written until save.
- **Sequence S1 → S2** — S1 changes the shape of `serves` ("Saturday's Korean Bavette"), so S2's matcher wants writing against the post-dates output. They can still share one dispatch.
- **Do not auto-relink without a human gate** (ADR-0040 D3), and **do not add a date to `PrepPlanStepRecord`** (ADR-0034 D1). The dogfood data shows why the first is wrong: exact match succeeds on `Korean Bavette` and fails on `…Salad (Korean)`, so half the chips would silently return and half would not.

**[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) — the workbench reference-material fetch (scoped 2026-07-25, *demoted from Next Up 2026-07-26*).** Fully scoped and dispatch-ready; it lost the slot to the ferry track because the 2026-07-25 dogfood pass reordered appetite, **not** because anything about it changed. Promote it back when the ferry finishes.
- **Read the ADR *including Amendment 1*.** The six-OQ pass resolved every open question and ratified the slice plan; **two resolutions revise the original Decision, and S1 depends on both** — gated capture moves into the **in-app browser** (OQ5) and the **reduced extract becomes synced content** (OQ2). Do **not** scope S1 off the pre-amendment Decision text.
- **S1 — a `WorkbenchReference` model + a reduce/cache/store core, no UI** (`YesChefCore`; package-verifiable).
  **`WorkbenchReference` is a *synced* record type** — the entry (URL / label / kind / provenance) **and** the reduced extract, both synced workbench content (OQ2: the extract is authenticated, browser-captured, and **not recomputable** on a second device, so it is captured content, not a device-local cache). Register it in `CloudSync` ([`CloudSync.swift`](YesChefPackage/Sources/YesChefCore/CloudSync.swift)) **and add it to the prod-promotion list below in that same PR** ([[handoff-bump-rides-in-slice-pr]]). Typed table, not a notes dump ([[decompose-notes-into-typed-homes]]); a synced table is cheap ([[synced-table-cost-calibration]]).
  **One reduce path, two inputs** — **either a URL** (fetched via `WebRecipeCaptureClient.fetchHTML`, ADR-0007) **or already-captured content** (what S3's in-app browser hands it), both through the **same** reducer. Cache the reduced text on the entry (copy the `CompareAlignmentCacheStore` per-set pattern, ADR-0022); an explicit refresh re-fetches. Raw HTML is transient — only the reduced text persists.
  **The reducer is *generic readability*, not the recipe parser (OQ1)** — reference pages are arbitrary (a technique writeup, a food-science post), so strip boilerplate → main/article prose; do **not** route through the recipe-schema editorial-prose parser, which assumes recipe structure. **Deterministic** — the LLM reduce pass stays parked (when it ships it is ADR-0043's harder load test, not S1).
  **Advisory read, never a write** ([[llm-vs-determinism-surface-boundary]]) — reference material never touches grocery, pantry, or any persisted recipe field. Fetched/captured web text is **untrusted data, never instructions**.
  **Verification:** package-only — `swift build` + `scripts/check-drift.sh` + unit tests with a **stubbed** fetch client (fixture HTML → asserted reduced text; no network in CI). **No app build, no device pass** — S1 adds no UI.
- **Then S2 — inject reference material into `WorkbenchChatContext`** (behind the frontier budget, deduped against candidates, trimmed-first on-device; because the extract is durable synced content, the same layer also composes into the ADR-0042 outboard handoff payload — one source, both surfaces; package-verifiable). **S3 — the list UI + in-app browser "Capture to Workbench"** (the gated path; paste-in demoted to last resort; device pass on iPad + iPhone). Sequence **S1 → S2 → S3**.

**[`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) — the chat panel gets a surface contract (scoped 2026-07-26 from the PR [#235](https://github.com/jonphillips/yes-chef/pull/235) architect review).** App-layer only; no Core, no schema. `RecipeChatPanel` is shared but its **contract** is not: eight call sites, eight parameters, **six defaulted** — so four surfaces silently opted out of a dismiss control (Calendar, Calendar-day, Workbench and Compare on iPhone are swipe-only) and three inherited Recipe's copy. Replace the loose argument list with one `ChatSurface` descriptor that takes **no default** on dismissal, sections, or presentation.
- **This does NOT jump the ferry queue.** [`efforts/dogfood-ferry-2026-07-25.md`](efforts/dogfood-ferry-2026-07-25.md) has one dispatch left (**3**, workbench lifecycle), which this effort shares no files with. It competes only with [ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md).
- **S1 (the four sheets get a `Done`) is a live defect and can ship alone**, at whatever moment is convenient — it does not wait on the descriptor.
- **S2–S4 want the slot immediately before [ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md), whenever the ferry gets there.** That rewrite moves all eight call sites, so landing the descriptor first means it relocates **one type** instead of eight argument lists; landing it after means the new shell inherits the same defaulted-omission shape.
- **S4 (the per-surface resolution test) is a gate on S2, not a nicety** — the panel has no direct coverage today, which is exactly why the four missing dismiss controls went unnoticed.

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
