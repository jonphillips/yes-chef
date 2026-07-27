# Current Handoff

Last updated: July 26, 2026.

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate everything preceded is **crossed and
holding**. We stay in CloudKit **Development** by design; prod-schema promotion is the held ops step in its
own section below.

The **short entry point** for a fresh Yes Chef conversation. This file is deliberately lean: it holds
**Next Up** (the dispatch target), the **Standing guards**, the **Ready Efforts** queue, the **prod-schema
promotion list**, and the **Verification Pattern** — nothing else. Completed-slice history, the
implemented-behavior checkpoint, and strategic background live in [`docs/DONE-LOG.md`](DONE-LOG.md)
(read-rarely archive — do **not** read it on a dispatch). `docs/AGENTS.md` remains the authoritative
project/agent guide.

## Next Up

**ONE live dispatch target: [ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) S3 — the
reference list UI + the in-app browser's "Capture to Workbench".**
Dispatch with *"Do the **ADR-0032 S3** effort in `docs/CURRENT_HANDOFF.md`."* If this section is
empty or missing, **STOP and ask Jon — never infer.** See `docs/AGENTS.md` § Work Intake & Dispatch.

**Verification: app-layer, and it wants Jon's device pass.** No schema — S1 landed the synced table and the
reducer, S2 landed the context injection, so this slice is UI over an already-complete core. The elevated
`generic/platform=iOS` build is **required evidence** (see Verification Pattern), plus
`scripts/check-drift.sh`. Keep new logic testable — anything pure belongs in `YesChefPackage`, not
`YesChefApp/`.

**Already scoped — do not re-scope it.** Full scope is the ADR-0032 entry in Ready Efforts. Four things a
dispatch must not miss:

1. **Read the ADR *including Amendment 1*.** Two of its resolutions revise the original Decision text. Do not
   scope off the pre-amendment Decision — in particular, **paste-in is demoted to a last resort**; the primary
   gated path is the in-app browser.
2. **Refresh is an explicit replacement of a durable, non-recomputable extract.** A public `fetchHTML` refresh
   of a `.browserCapture` reference can overwrite an authenticated extract with a login-wall teaser. Show the
   capture kind, confirm the replacement, route a browser-captured reference's refresh back through the
   browser. `store` throws `duplicateSourceURL(existingID)` rather than overwriting — that error is the
   "already here — refresh it?" affordance, not a failure to hide.
3. **`isThin` (raw extract under 1,500 characters) is the "Open in browser to capture" signal.** The threshold
   is a guess until real pages run through it — watch whether legitimately short notes trigger a pointless
   WebView render.
4. **Two S2 carry-forwards land naturally here.** (a) S1 caps an extract at 256,000 UTF-8 bytes while the
   frontier context budget is 160,000 characters, so an extract between the two is stored, synced and listed
   yet can **never** reach any model at any tier — either mark it in the list or pull the cap down to the
   frontier budget. (b) `WorkbenchDetailRequest` hauls full extracts on the always-on `@Fetch`
   (`WorkbenchModels.swift:167`); if the list needs only label/kind/status, keep `reducedText` out of it
   ([[sqlitedata-fetch-writer-convoy]]).

## Standing guards

Closed decisions that stay closed. Each is already written up in its ADR and `DONE-LOG`; they live here
only so a dispatch does not re-queue them. **Nothing in this section is work.**

- **⚠️ The ADR-0042 return contract is v2** — re-copy the project instructions from AI Settings or every
  verb fails the marker gate. (Operational, not historical: it bites on any hand-off dogfooding session.)
- **ADR-0021 (variations) and ADR-0023 (recipe edit proposals) have nothing queued.** ADR-0023's *iterative
  refine loop* is **WITHDRAWN** (ADR-0042 D7 — refinement happens in the live external thread; an in-app
  multi-turn proposal loop is a worse copy of it, **do not rebuild it**). Per ADR-0042 D2 the in-app adjust
  verb stays the **only** path that writes a structured delta.
- **ADR-0042 S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want, its danger receded
  rather than grew. **Do not build it on ADR momentum.** There is no S5.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted, it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged — do not re-queue either.** Variations (the whole
  ADR-0021 arc shipped and device-passed) and "Menu is under-served by hand-off verbs" (discharged by
  ADR-0043's load test). Parked **ADR-0013** meal-planner verbs remain separate and unscoped — see Ready
  Efforts.
- **The Recipe Workbench store/curate/compare arc (ADR-0019) is complete**, S1–S4 shipped. Its remaining
  parked follow-ons live in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md), not here.
- **The workbench's experiment-outcome verb is NOT scoped** — only its *placement* is ratified (an ADR-0042
  amendment: D8's corollary that a conjecture suppresses learnings but a **cooked** experiment is findings,
  so learnings come back on). That amendment gets written **when that half is scoped, deliberately not now.**

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**[`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) — the prep plan knows things the model doesn't (scoped 2026-07-26).** Two slices, **no schema** — both use fields that already exist and already sync.
- **S1 (Core only) — the menu's placement dates reach `MenuChatContext`.** [ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D2 retired the fixed horizon enum *because* real session labels are concrete ("Wednesday evening", "Saturday · ~3 hrs out") — but the context carries **no date of any kind**, so a placed menu and an unplaced one send byte-identical context and the model falls back to relative horizons ("One day ahead" — ahead of *which* day?). That is the exact ambiguity ADR-0034's Context section opens with. Serialize the per-day dates, and ask for day-anchored sessions **only when the menu is placed** (unplaced keeps today's relative wording). **No app build needed** — no UI.
- **S2 — the dish picker; `sourceDish` becomes human-settable for the first time.** It is write-only from the LLM today (`PrepPlanStepEditorDraft` has no dish field, `PrepPlanStepRepository.update` has no parameter), while every outboard text return drops it by design (ADR-0040 D3). So links only decay and nothing can restore them. A picker defaulting to a `serves` → menu-item match, **suggestion visibly marked as a suggestion**, nothing written until save.
- **Sequence S1 → S2** — S1 changes the shape of `serves` ("Saturday's Korean Bavette"), so S2's matcher wants writing against the post-dates output. They can still share one dispatch.
- **Do not auto-relink without a human gate** (ADR-0040 D3), and **do not add a date to `PrepPlanStepRecord`** (ADR-0034 D1). The dogfood data shows why the first is wrong: exact match succeeds on `Korean Bavette` and fails on `…Salad (Korean)`, so half the chips would silently return and half would not.

**[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) — the workbench reference-material fetch (scoped 2026-07-25; S1 + S2 shipped).** **S3 is under Next Up and is the last slice.**
- **Read the ADR *including Amendment 1*.** The six-OQ pass resolved every open question and ratified the slice plan; **two resolutions revise the original Decision** — gated capture moves into the **in-app browser** (OQ5) and the **reduced extract becomes synced content** (OQ2). Do **not** scope off the pre-amendment Decision text.
- **What S1 + S2 already give it:** `WorkbenchReferenceRepository` stores/refreshes/reads/deletes the rows (each carrying `reducedText`, tracking-stripped `sourceURL`, `captureKind`, `reductionStatus`), `WorkbenchReferenceCapture.reduce` serves both a public URL and already-captured authenticated HTML through one reducer, and `WorkbenchDetailData` → `WorkbenchChatContext` already carries the extracts into the chat and both outboard hand-offs. **S3 adds no core** — it is the acquisition and management UI over a finished core.
- **S3 — the list UI + in-app browser "Capture to Workbench"** (the gated path; paste-in demoted to last resort; device pass on iPad + iPhone).
  **Refresh is an explicit replacement of a durable extract, and S1 deliberately does not rank or merge sources.** A public `fetchHTML` refresh of a `.browserCapture` reference can replace an authenticated extract with a login-wall teaser, and it is **not recomputable** ([[paywall-gating-taxonomy]]) — so S3 shows the capture kind, confirms the replacement, and routes a browser-captured reference's refresh back through the browser. `store` throws `duplicateSourceURL(existingID)` rather than overwriting; that error is S3's "already here — refresh it?" affordance.
  **`WorkbenchReferenceReducedContent.isThin`** (raw extract under 1,500 characters) is the signal for the "Open in browser to capture" offer. The threshold is a guess until real pages run through it — watch whether legitimately short notes trigger a pointless WebView render.
- **Parked, unchanged:** the LLM reduce pass (when it ships it is [ADR-0043](decisions/ADR-0043-model-call-chokepoint.md)'s harder load test), candidate-source prose, `web_search` discovery.

**[`efforts/chat-surface-contract.md`](efforts/chat-surface-contract.md) S2–S4 — the chat panel gets a surface contract (scoped 2026-07-26).** App-layer only; no Core, no schema. `RecipeChatPanel` is shared but its **contract** is not: eight call sites, eight parameters, **six defaulted** — so four surfaces silently opted out of a dismiss control and three inherited Recipe's copy. Replace the loose argument list with one `ChatSurface` descriptor that takes **no default** on dismissal, sections, or presentation. **S1 (the four missing `Done` controls) has shipped; S2–S4 stay here.**
- **S2–S4 want the slot immediately before [ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md).** That rewrite moves all eight call sites, so landing the descriptor first means it relocates **one type** instead of eight argument lists; landing it after means the new shell inherits the same defaulted-omission shape.
- **S4 (the per-surface resolution test) is a gate on S2, not a nicety** — the panel has no direct coverage today, which is exactly why the four missing dismiss controls went unnoticed.

**[`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) — the app test target runs nothing; move the logic (scoped 2026-07-26).** No schema, no UI, no behavior change, no device pass. `YesChefAppTests` holds **23 tests executed by nothing**; only 4 are stranded by the target, the other **19 by pure logic sitting in `YesChefApp/`**. Five moves recover them — S1 two whole files (11 tests), S2 three extractions (8), S3 marks the rest.
- **The pass signal is the test count, not a green run** — 462 today, **481** after S1+S2. Green at 462 means the moved suites were never discovered, which is the failure this ends.
- **Do not try to fix the test target.** Confirmed against cleared DerivedData: `CloudSyncKitdynamic-product` cannot link `SwiftUICore` ("not an allowed client"). Real linkage defect, cross-repo in `jon-platform`, for four tests, plus a simulator run this project does not do.

**[ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md) — the sidebar-adaptable app shell. Unblocked but unscheduled.** Its gate ("ferry Dispatch 1 lands first") was satisfied 2026-07-25 and Dispatch 1.5's panel work is merged, so nothing holds it except appetite.

**ADR-0045 leftovers — two cold-start entry points, each its own small slice.** The meal-calendar day-header Chat and the Workbench Chat are the fourth and fifth cold-start entry points OQ3's check turned up — same dead end, no section to carry. Recorded in the ADR and deliberately not folded into V1.

**ADR-0041 deferred follow-ons** (on the record in the ADR, **not** dispatchable without Jon scoping them) — the **menu** Playbook sections getting the same per-section toolbar (ADR-0039 Amd 2/3's shared Enrichment column; ADR-0041 deliberately scoped to the *recipe*), and section-selection checkboxes on the whole-recipe hand-off (the scoped per-section verbs make these *less* necessary, not more).

**Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4)** — surfaced by the Amendment 3 *over*
presentation (PR #197). The pipeline is **already wired**: `MenuRecipeBrowserPanel` rows are
`.draggable(MenuDraggedRecipe)` and `MenuDishDayList` has
`.dropDestination(for: MenuDraggedRecipe.self) { model.addRecipesToMenu(…) }`, and the slide-over keeps the
Dishes body interactive beneath it. **But drag-and-drop is not firing reliably in the current betas** — Jon
(with Fable and GPT-5.6 Sol) could not get it to work; **retry after Beta 4.** Not dispatchable until then; when
it unblocks it's mostly confirm-E2E + polish (drop highlight, autoscroll, multi-select), no schema.

**Meal-Planner chat verbs** (ADR-0013 follow-on + `efforts/cooking-workspace.md`) — the one remaining named
actionable-chat verb instance. Classify each new verb's commit shape first ([[chat-verb-commit-shapes]]) —
likely no-commit advisory or a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]].
Design in [ADR-0013](decisions/ADR-0013-meal-planner-actionable-chat.md) +
[`efforts/cooking-workspace.md`](efforts/cooking-workspace.md). **Confirm with Jon what verb scope remains.**

**Recipe text normalization** — a "normalize recipe" function (de-cap old all-caps Milk Street imports,
strip manual instruction numbers now that we auto-number). **Unscoped** — no natural existing effort home;
parked in [`docs/open-questions.md`](open-questions.md) until scoped. Interacts with ADR-0014 (text-editing
model), so sequence them.

**Open design ADR (discussion, not yet Accepted)** — [ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md)
recipe text editing (header toggles vs. rich text / bold-italic), opened from the 2026-07-04 dogfood pass.
Decide with Jon before any implementation — **and note it narrowed on 2026-07-21**: ADR-0021 Amd1-D5 needs
ADR-0014 only for **section headers inside a variation**, which is the one edit the op vocabulary cannot
express.

**Small nits — not urgent, fold into a passing dispatch:**
- **Workbench log-editor** (from the ADR-0042 S2 review): the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision** (found 2026-07-21; silent-failure risk). `instructions` opens *"You extract a proposed edit … from a cooking **conversation**,"* the prompt says *"**Conversation so far:**"* and closes *"Extract only the concrete recipe edit **the user is asking to review**"* — while `HandoffReviewCoordinator.draftRecipeAdjustment` wraps the finished brief as a single fake `.user` message and passes `selection: ""`. So a **decided** revision is presented as an **in-progress ask**, inviting the extractor to infer or hedge where the whole point of Amd1-D1 is that the human already decided. Under-extraction here is **silent** — a 3-change brief that yields 2 ops just shows a shorter side-by-side. *Fix:* a task-specific framing for the brief path ("this is a decided revision; transcribe every change faithfully and completely"), **not** a second client. **Deliberately NOT part of this:** adding the taste profile or known-learnings to the *extractor* — those belong to the outbound hand-off ask (where `RecipeHandoffContext` already sends both) because that is where judgment happens; feeding the extractor preference context invites exactly the editorializing D1 exists to stop.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip); app-layer only, small, spec in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md)'s "Out of scope" section. ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app* path clears the evidence banner (cosmetic).

**Still-deferred, separate future efforts** (not follow-through on any shipped effort): ADR-0027 **OQ4**
(a note-worthiness taste preference); **ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe*;
**ADR-0038 Amd 4 — smart Learning curation** (an LLM pass reconciling incoming-vs-existing learnings —
dedup/merge/supersede — with the review sheet surfacing existing learnings; the deterministic exact-dedup
*floor* already shipped, so this is the paraphrase-aware ceiling, not urgent —
[[handoff-stateless-both-directions]]). Comment ingestion stays in `docs/open-questions.md` until it is a
scoped effort.

**Parked to `docs/open-questions.md` (design forks, decide with Jon before build):** multi-bubble /
whole-transcript chat selection (per-bubble `UITextView` caps the payload).

## Prod-schema promotion list

**Standing release follow-up — not a dispatch. A pre-cut ops step Jon runs.** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and **permanently locks those record types**, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy the following to the production schema:

- Phase E Slice 3 **pantry-policy + `canonicalName`** fields
- **`Recipe.coverPhotoID`** (reader photo affordances, PR #87)
- The synced **`aiSettings`** table (ADR-0018, PR #96), **including** its additive `readerFeedbackPreference`
  (ADR-0025 D6) and `captureToNotePreference` (ADR-0027 S1, PR #141) columns
- The synced **`recipeVariations`** table (ADR-0021 / recipe edit proposals S2)
- **`Menu.externalProjectName`** (ADR-0038 S2)
- The synced **`learnings`** table, **including** its `sortOrder` column (ADR-0038 Amd 1 / Amd 5)
- The synced **`prepPlanSteps`** table (ADR-0040 S2)
- The synced **`workbenchLog`** table, **including** its nullable `hypothesis` / `change` / `rationale`
  columns (ADR-0042 S2)
- **`workbenches.dateCompleted`** (Dogfood ferry Dispatch 3)
- The synced **`workbenchReferences`** table (ADR-0032 S1)
- The synced **`recipeDeliberationLog`** table (ADR-0021 V3 / [Amd 3](decisions/ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23))

*The `Menu.prepPlan` BLOB is **not** on this list and must not be re-added — it was dropped outright, so the
dead CKAsset field never enters the prod schema.*

**The check is the registration list, in both directions.** A column on a synced table is on this list; a
column on a table that is *not* registered in `CloudSync` is local and belongs nowhere near it. Both
mistakes have been made — verify against `CloudSync.swift`, not against intuition.

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
- **⚠️ `YesChefAppTests` is compiled and run by nothing — do not put a new test there.** Not
  `scripts/check-drift.sh` (it ends in `swift test --package-path YesChefPackage`), not CI (same command), and
  not the generic app build (`build` never compiles the test target). A `build-for-testing` attempt dies at a
  CloudSyncKit dynamic-product link error before reaching the target, so the seven files already in it are not
  even known to compile. **A test only counts if it lands in `YesChefPackage/Tests/`** — which is the same
  corollary above, arriving from the other direction: if the logic is pure enough to test, move it to Core and
  test it there. *Recovering the 23 tests already stranded there is scoped as
  [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) in Ready Efforts.*
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** Do not try alternate destinations, simulator resets, or install
  loops. The only build command is the elevated generic command above; an environment failure that prevents it
  reaching the compiler is an architect gate, not a successful Codex verification. Device install is Jon's pass.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
