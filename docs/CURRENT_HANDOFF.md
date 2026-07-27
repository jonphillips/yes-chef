# Current Handoff

Last updated: July 27, 2026.

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate everything preceded is **crossed and
holding**. We stay in CloudKit **Development** by design; prod-schema promotion is the held ops step in its
own section below.

The **short entry point** for a fresh Yes Chef conversation. It holds **Next Up** (the dispatch target), the
**Architect track**, the **Standing guards**, the **Ready Efforts** queue, the **prod-schema promotion
list**, and the **Verification Pattern** — nothing else. Completed-slice history and strategic background
live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**ONE live dispatch target: [`efforts/recipe-editor-section-grain.md`](efforts/recipe-editor-section-grain.md)
— recipe sections are stored, read, and edited at three different grains.**
Dispatch with *"Do the **recipe section grain** effort in `docs/CURRENT_HANDOFF.md`."* If this section
is empty or missing, **STOP and ask Jon — never infer.** See `docs/AGENTS.md` § Work Intake & Dispatch.

Both halves found in Jon's device pass of PR [#245](https://github.com/jonphillips/yes-chef/pull/245) on the
Samin capture: **the edit sheet showed only the first section** of each, and **instructions display with no
sections at all** while ingredients display grouped. Three slices, **no schema** — S1 read-side instruction
grouping, S2 Core editor draft, S3 editor UI. **Dispatch S1 alone first.**

**Four things a dispatch must not miss:**

1. **Nothing is lost and nothing is corrupt** — `mergedSections` / `mergedIngredientLines` replace only the
   edited section, and import assigns instruction steps a **global** running `sortOrder` so document order
   is intact. This is "you cannot edit or see most of your recipe," not "editing eats your recipe." Do not
   open it as a data-loss fix.
2. **S1 is a correctness fix wearing a display fix's clothes.** The flat instruction list depends on step
   `sortOrder` being globally unique, and an editor save renumbers one section from 0 — ties, then unstable
   order. Grouping by section and sorting `(section.sortOrder, step.sortOrder)` retires that dependency.
   **Ship S1 before S2** so the editor work cannot trip it.
3. **Deletion is the new behaviour in S2.** The save path only ever merges, so removing a section is the one
   case with no existing expression — that is where the tests should be hardest.
4. **⚠️ One open question is Jon's and is NOT the dispatch's to settle** — whether the editor's text box
   promotes typed `For the sauce:` headings into sections the way the capture channel does. The
   recommendation is no (ADR-0040 D2). **Do not implement heading promotion in the editor without an
   answer.**

**Verification.** S1/S2 are package tests where `scripts/check-drift.sh` actually runs (put the grouping rule
in Core, not the app display model). S1 and S3 touch `YesChefApp/` and need the elevated
`generic/platform=iOS` build as required evidence. No simulator installs; Jon device-passes on the captured
Samin recipe — a single-section recipe looking unchanged is the canary.

## Architect track (parallel — NOT a Codex dispatch)

**Fix the app test target.** Jon has the prompt; Claude works this in its own session, off to the side of
the Codex dispatch above. It touches build/test infrastructure and jon-platform, not product code, so the
two should not collide. **Do not fold this into a product dispatch and do not let a dispatch "fix it along
the way."**

**The diagnosis has now been wrong three times, each time by reading the first error as the blocker.** The
record, corrected 2026-07-27 by direct probe:

- `xcodebuild build-for-testing` first dies on **two missing `await`s** in `YesChefAppTests/AIHandoffMenuPasteTests.swift`
  (`:92` and `:127` — `database.write` / `database.read` inside an async `operation:`). Real, pre-existing
  on `main`, two lines.
- Patch those and it clears them and hits **`CloudSyncKitdynamic-product: clang: error: linker command
  failed`** — the same wall the original brief recorded. The 2026-07-27 "missing GRDB /
  StructuredQueriesCore conformance symbols" reading never got past this either.
- So the wall has not moved, and **the `.dynamic` product missing conformance symbols from its own static
  dependencies still reads like a SwiftPM product-type problem, not a hard restriction.** First step is one
  probe that captures the *complete* undefined-symbol list rather than the first line.

**What it unblocks.** [`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) (23 tests
executed by nothing; only 4 are stranded by the target, the other 19 by pure logic sitting in `YesChefApp/`)
and the standing "a test only counts in `YesChefPackage/Tests/`" rule in the Verification Pattern. **Three
efforts in a row have now written a test into a target that runs nothing.** The move-to-Core slices stand on
their own merits either way — the *"don't bother fixing it"* conclusion is what this track retires.

## Standing guards

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v2** — re-copy the project instructions from AI Settings or every
  verb fails the marker gate. (Operational: it bites on any hand-off dogfooding session.)
- **ADR-0021 (variations) and ADR-0023 (recipe edit proposals) have nothing queued.** ADR-0023's *iterative
  refine loop* is **WITHDRAWN** (ADR-0042 D7 — refinement happens in the live external thread; **do not
  rebuild it**). Per D2 the in-app adjust verb stays the **only** path that writes a structured delta.
- **ADR-0042 S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want. **Do not build it on
  ADR momentum.** There is no S5.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged** — variations (whole ADR-0021 arc shipped and
  device-passed) and "Menu is under-served by hand-off verbs" (discharged by ADR-0043's load test). Parked
  **ADR-0013** meal-planner verbs remain separate and unscoped — see Ready Efforts.
- **The Recipe Workbench store/curate/compare arc (ADR-0019) is complete**, S1–S4 shipped. Parked follow-ons
  live in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md), not here.
- **The workbench's experiment-outcome verb is NOT scoped** — only its *placement* is ratified (ADR-0042 D8's
  corollary: a conjecture suppresses learnings, a **cooked** experiment is findings, so learnings come back
  on). That amendment gets written when that half is scoped, **deliberately not now.**
- **Chat entry points are unified and closed** ([`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md),
  PR #244). Uniformity is **cross-surface, not cross-device**: modal sheets keep the iOS nav bar, embedded
  and column presentations keep the in-panel header row. **That divergence is intended — do not "unify" it.**
  The Calendar/Workbench detent split and the Recipe inspector belong to ADR-0046, not to a chat pass.

## Ready Efforts (queue)

Drawn into **Next Up** as needed; not itself a dispatch target. Completed efforts live in
[`docs/DONE-LOG.md`](DONE-LOG.md).

**[`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md) — the prep plan
knows things the model doesn't (scoped 2026-07-26).** Two slices, **no schema** — both use fields that
already exist and already sync.
- **S1 (Core only) — the menu's placement dates reach `MenuChatContext`.**
  [ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D2 retired the fixed horizon enum
  *because* real session labels are concrete ("Saturday · ~3 hrs out") — but the context carries **no date of
  any kind**, so a placed menu and an unplaced one send byte-identical context and the model falls back to
  "One day ahead" — ahead of *which* day? Serialize the per-day dates; ask for day-anchored sessions **only
  when the menu is placed**. **No app build needed.**
- **S2 — the dish picker; `sourceDish` becomes human-settable for the first time.** It is write-only from the
  LLM today, while every outboard text return drops it by design (ADR-0040 D3), so links only decay. A picker
  defaulting to a `serves` → menu-item match, **suggestion visibly marked as a suggestion**, nothing written
  until save.
- **Sequence S1 → S2** (S1 changes the shape of `serves`), one dispatch. **Do not auto-relink without a human
  gate** and **do not add a date to `PrepPlanStepRecord`** (ADR-0034 D1) — exact match succeeds on
  `Korean Bavette` and fails on `…Salad (Korean)`, so half the chips would silently return.

**[`efforts/grocery-rapid-add-2026-07-26.md`](efforts/grocery-rapid-add-2026-07-26.md) — persistent grocery
Add Item field + Accept All on review. READY.** One dispatch, five slices, **no schema**; all three product
confirms closed. A/B the field + fraction pills, C the debounce, D the stale-sheet fix, E the review-sheet
Accept All (unrelated, rides along).
- **Slice C decides whether the feature is good, and it is the one that looks skippable.**
  `categorizeUncachedItems()` already fires after every add and does **three whole-table `fetchAll` scans +
  two write transactions + two full `$itemRows` reloads** — fine at one add, an
  [ADR-0029](decisions/ADR-0029-main-thread-write-and-fetch-cost.md) writer convoy at ten adds in twenty
  seconds, which is exactly what A/B create.
- **Two scope cuts already found:** deterministic area assignment is **already wired** (`addCustomItem` falls
  back to `GroceryStoreArea.seed`), and so is the deferred model sweep. Do not add a second seeding path.
- **Slice E's trap:** the file holds *two* definitions of "unedited" (`.sheet` → `editableText ?? summary`;
  `.inline` → `summary`). Extract one `unmodifiedApprovedText` so they cannot drift.

**[`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md) — Playbook edit
affordances are a readout of storage grain. Dispatch 1 READY; Dispatch 2 behind it.** Ratified in
[ADR-0048](decisions/ADR-0048-playbook-edit-grain.md), all OQs closed. **Dispatch 1 (S1+S2) is schema-free**:
extract the Learnings row editor, Reader Feedback adopts it (already `recipeNotes` rows); S2 is the loud
decode. S3 is the real one — `Recipe.serveWith` is a **JSON blob whose items are `Identifiable` with UUIDs**,
identity without a row, with `reconciledServeWithItems` existing solely to carry those UUIDs across whole-blob
rewrites by matching on content.
- **S3's primary test, not a detail:** the regeneration path must **upsert by identity and preserve
  hand-authored rows**. Delete-and-reinsert reproduces the exact identity loss the slice exists to remove.
- **Make Ahead / Chef It Up stay prose (D4)** — they only *look* like lists because
  `PlaybookEnrichmentDisplayText` splits multi-line strings at render time. Do not decompose them on momentum.
- **Reorder is opt-in:** `RecipeNote` has no `sortOrder`, so Reader Feedback edits and deletes per row but does
  **not** reorder, and does **not** gain a column to make the shape uniform.

**[ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md) — the sidebar-adaptable app shell. Unblocked
but unscheduled.** Its gate was satisfied 2026-07-25; nothing holds it except appetite. It moves all eight
chat call sites, which now inherit **one** Ask rather than six.

**ADR-0045 leftovers — two cold-start entry points, each its own small slice.** The meal-calendar day-header
Chat and the Workbench Chat, same dead end, no section to carry. Recorded in the ADR, deliberately not folded
into V1. **Open for Jon:** now that starters are host-supplied, do the Calendar and Workbench want starters of
their own ("Plan this week", "What should I prep tonight?")? They pass `.none` today, which is an explicit
answer rather than an omission — worth deciding before ADR-0046 rearranges these surfaces.

**ADR-0041 deferred follow-ons** (on the record, **not** dispatchable without Jon scoping them) — the **menu**
Playbook sections getting the same per-section toolbar, and section-selection checkboxes on the whole-recipe
hand-off (the scoped per-section verbs make these *less* necessary, not more).

**Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4).** The pipeline is **already wired** —
`MenuRecipeBrowserPanel` rows are `.draggable(MenuDraggedRecipe)`, `MenuDishDayList` has a matching
`.dropDestination`, and the slide-over keeps the Dishes body interactive beneath it — but drag-and-drop is not
firing reliably in the current betas. **Retry after Beta 4;** then it's confirm-E2E + polish, no schema.

**Meal-Planner chat verbs** (ADR-0013 + `efforts/cooking-workspace.md`) — the one remaining named
actionable-chat verb instance. Classify each verb's commit shape first ([[chat-verb-commit-shapes]]) — likely
no-commit advisory or a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]].
**Confirm with Jon what verb scope remains.**

**Recipe text normalization** — de-cap old all-caps Milk Street imports, strip manual instruction numbers now
that we auto-number. **Unscoped**; parked in [`docs/open-questions.md`](open-questions.md). Interacts with
ADR-0014, so sequence them.

**Open design ADR (discussion, not yet Accepted)** —
[ADR-0014](decisions/ADR-0014-recipe-text-editing-model.md) recipe text editing (header toggles vs. rich
text). Decide with Jon before any implementation — **it narrowed on 2026-07-21**: ADR-0021 Amd1-D5 needs it
only for **section headers inside a variation**, the one edit the op vocabulary cannot express.

**Small nits — not urgent, fold into a passing dispatch:**
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision** (silent-failure
  risk). `instructions` opens *"You extract a proposed edit … from a cooking **conversation**"* and closes
  *"the user is asking to review"* — while `HandoffReviewCoordinator.draftRecipeAdjustment` wraps a finished
  brief as one fake `.user` message with `selection: ""`. A **decided** revision is presented as an
  **in-progress ask**, inviting the extractor to hedge where Amd1-D1's whole point is that the human already
  decided; under-extraction is **silent** (a 3-change brief yielding 2 ops just looks shorter). *Fix:* a
  task-specific framing for the brief path, **not** a second client. **Deliberately NOT part of this:** taste
  profile or known-learnings into the *extractor* — those belong to the outbound ask, where judgment happens.
- **Workbench log-editor** (ADR-0042 S2 review): the `canSave` / `normalizedLogEntryDraft` mismatch when a body
  is combined with partially-filled typed fields, the dead save spinner, the compare `.menuPrepPlan` mislabel.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip);
  spec in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md). ⚠️ Re-read against ADR-0042 D2/OQ5
  first: it is an *in-app* draft verb and the draft is a structured write.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app*
  path clears the evidence banner (cosmetic).
- **From the PR #244 review, all one-liners:** `MenuDetailModel.tool`'s `didSet` and
  `recipeBrowserButtonTapped` both clear `activeChatStarterID` — say it once
  (`didSet { if chatModel == nil { … } }`); `MenuDetailReader`'s `isAskActive`/`askButtonTapped`/
  `regeneratePrepPlan` closure params are now pure passthroughs to a `detailModel` it already receives (fine
  to leave for ADR-0046); `namesStarterContractsForEveryHost` asserts `.starters == .starters` and proves
  nothing.

**Still-deferred, separate future efforts:** ADR-0027 **OQ4** (a note-worthiness taste preference);
**ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe*; **ADR-0038 Amd 4 — smart Learning
curation** (an LLM pass reconciling incoming-vs-existing learnings; the deterministic exact-dedup *floor*
already shipped, so this is the paraphrase-aware ceiling, not urgent —
[[handoff-stateless-both-directions]]). Comment ingestion stays in `docs/open-questions.md`.

**Parked to `docs/open-questions.md` (decide with Jon before build):** multi-bubble / whole-transcript chat
selection (per-bubble `UITextView` caps the payload).

## Device passes owed

Not work, a checklist. **[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) S3** (complete,
nothing queued) carries two live caveats into its pass: `pastedText` is a new raw value in a synced enum
column, so **update both devices before saving a pasted-text reference**, and the `isThin` 1,500-character
threshold is still a guess against real pages. **PRs #243 + #244** owe one combined pass over all four chat
surfaces — Menu, Recipe (the canary, must be unchanged), Calendar, Workbench — plus the new
rotation behaviour: the Menu panel now migrates between overlay and sheet in both directions instead of being
torn down.

## Prod-schema promotion list

**Standing release follow-up — not a dispatch. A pre-cut ops step Jon runs.** We stay in the CloudKit
**Development** environment so the schema keeps evolving freely; promoting to **Production** is
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

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the device pass
regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files.
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise run the app build with **elevated/unsandboxed permissions**, no simulator, no signing identity:
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- Run `scripts/check-drift.sh`.
- **The generic app build is required evidence for `YesChefApp/` changes.** `check-drift.sh` compiles only
  `YesChefPackage`; a green package build and `swiftc -parse` are not App-target evidence. The default Codex
  sandbox can SIGTERM Xcode before compilation by denying user-level service/cache access, so start with the
  elevated command. A sandbox-shaped `143` is not a green result. If the elevated build cannot reach the
  compiler, record the full-log path and **the architect runs the same build locally before approving.**
- **Corollary — keep pure logic out of the App layer.** String formatting, serialization, and parsing belong
  in `YesChefPackage` (which Codex *can* compile and test). #185's break was `HandoffIntents.swift` calling
  `date: .full` — logic that belonged in Core, where the package build would have caught it instantly.
- **⚠️ `YesChefAppTests` is compiled and run by nothing — do not put a new test there.** Not
  `check-drift.sh`, not CI (same command), not the generic app build (`build` never compiles the test
  target). **A test only counts if it lands in `YesChefPackage/Tests/`.** *The Architect track above is
  actively retiring this constraint; until it lands, the rule holds — and **report the first error you hit as
  the first error, not as the blocker**, which is how this diagnosis went wrong three times.*
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — hand straight to Jon's UI pass. Only boot a simulator
  when a change genuinely can't be confirmed from build + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** No alternate destinations, simulator resets, or install loops.
  An environment failure that prevents the elevated build reaching the compiler is an architect gate, not a
  successful Codex verification.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
