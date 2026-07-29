# Current Handoff

Last updated: July 29, 2026. (**Playbook edit grain Dispatch 0** is closed — `ServeWithCoding.decode` is loud
and compiler-enforced, and S0.1 gave the block its exit: a repair sheet that validates before it writes and
stores the cook's bytes verbatim, reachable from every surface the block takes down. Live target stays
**playbook edit grain**, now at **Dispatch 1 (S1)**.)

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate everything preceded is **crossed and
holding**. We stay in CloudKit **Development** by design; prod-schema promotion is the held ops step in its
own section below.

The **short entry point** for a fresh Yes Chef conversation. It holds **Next Up** (the dispatch target), the
**Standing guards**, the **Ready Efforts** queue, the **prod-schema promotion list**, and the **Verification
Pattern** — nothing else. Completed-slice history and strategic background
live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**ONE live dispatch target: [`efforts/playbook-edit-grain-2026-07-26.md`](efforts/playbook-edit-grain-2026-07-26.md)
— Playbook edit affordances are a readout of storage grain.** Dispatch with
*"Do **playbook edit grain** from `docs/CURRENT_HANDOFF.md`."* If this section is empty or missing, **STOP and
ask Jon — never infer.** See `docs/AGENTS.md` § Work Intake & Dispatch. Ratified in
[ADR-0048](decisions/ADR-0048-playbook-edit-grain.md), all OQs closed; the effort doc is the spec and it was
**amended 2026-07-29** by architect review, then again on S0's approval to add **S0.1**.

**The core reframe the dispatch must not undo:** the three different edit interactions are an accurate readout
of **three different storage grains**. Do not unify by making the chrome uniform over blob storage.

**Dispatch 0 (S0 + S0.1) is closed. Two dispatches remain, and they are strictly sequenced.**

1. **DISPATCH 1 (S1) — extract the Learnings row editor; Reader Feedback adopts it.** Schema-free. Reorder,
   add, and the provenance badge are **opt-in** capabilities of the shared component: `RecipeNote` has no
   `sortOrder`, so Reader Feedback edits and deletes per row but does **not** reorder — and does **not** gain
   a column to make the shape uniform. Learnings must be visually and behaviorally **unchanged**. Expect the
   slice to **delete more than it adds** (the four bulk-edit members die); a growing diff means something was
   misread.
2. **DISPATCH 2 (S3) — `recipeServeWith`; the only one with schema.** Sequenced behind S1.
   - **⚠️ Every migrated column must be a deterministic function of the already-synced blob — no `UUID()`, no
     `now`** ([[migration-writes-bypass-sync-triggers]]). `recipeServeWith` is a **brand-new** table, so the
     `start()` sweep makes **each device upload its own copy** unless the rows are identical everywhere. The
     data is already shaped for this: reuse the blob item's own `ServeWithItem.id` as the row `id` (which also
     satisfies the "ids intact" acceptance), rank from array index × `rankStride`, dates from the recipe's
     `dateModified`. Done that way it is safe to leave in the migrator with no post-engine pass.
   - **The regeneration path is the primary test, not a detail:** it must **upsert by identity and preserve
     hand-authored rows and their ranks**. Delete-and-reinsert reproduces the exact identity loss the slice
     exists to remove.
   - **`provenance` is its own enum** (model-suggested vs hand-authored). Do **not** reuse
     `LearningProvenance` — it records *transport*, and both its cases are model paths.
   - **Do not drop the `Recipe.serveWith` column in this PR.** Stop reading it; leave it a release. A stranded
     DELETE gets one attempt and is unrecoverable.

**Out of scope, named so it does not ride in on momentum:** Make Ahead and Chef It Up stay prose (ADR-0048
D4 — they only *look* like lists because `PlaybookEnrichmentDisplayText` splits at render time); `sortOrder`
on `RecipeNote`; fixing `LearningProvenance`'s transport/authorship conflation; the menu's Playbook sections.

**Verification.** Dispatch 1 is app-layer: the elevated `generic/platform=iOS` build plus the package
suite for anything landing in Core. **Dispatch 2 is schema + sync and does *not* close on a green build** —
it wants Jon's two-device pass, and it adds to the prod-schema promotion list in the same PR.

**⚠️ Jon's outstanding follow-through from ADR-0014 Amd1 (not a dispatch item):** three recipes still carry
`isHeader = 1` rows to hand-repair in the app — *Beef Birria Taco Filling* (4), *Broccoli Spoon Salad* (2),
*Sous Vide Indoor Pulled Pork* (2). *411 West's Rosemary Chicken* was pre-fixed 2026-07-28. Add a colon to
each header line and the row is promoted to a section and deleted on save. (Amd1-D1a, the colon-free door, is
**deferred** — the colon is the only path, which is the ratified primary anyway.) Dropping the `isHeader`
**column** afterwards is a schema change, not a data migration, and is not queued.

⚠️ **`check-drift.sh` fails on clean `main` at `Ld … SQLiteData.framework`, and the cause is fully known —
do not investigate it, do not try to fix it, and do not treat it as your regression.** sqlite-data's manifest
omits `StructuredQueriesCore` while its source uses those symbols; a test bundle turns every package product
into a dynamic framework and the link fails ([[exported-import-not-link-time]]). **Our two layers of the same
defect are fixed** (`1a56994`); the remaining one is upstream's and needs their release. Report it as
pre-existing; the package suite and the elevated `generic/platform=iOS` build are your evidence.

## Standing guards

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v2** — re-copy the project instructions from AI Settings or every
  verb fails the marker gate. (Operational: it bites on any hand-off dogfooding session.)
- **ADR-0021 (variations) and ADR-0023 (recipe edit proposals) have nothing queued.** ADR-0023's *iterative
  refine loop* is **WITHDRAWN** (ADR-0042 D7 — refinement happens in the live external thread; **do not
  rebuild it**). Per D2 the in-app adjust verb stays the **only** path that writes a structured delta.
  **Now live, not theoretical (ADR-0014 Amd1-D4):** the editor's split mints a genuinely new section, so
  `derivingVariation` — which diffs structures matched by section ID — hits `.ingredientSectionAdded` →
  `variationNeedsReview` whenever a header is added inside a recipe that has variations. **That is expected
  behavior, not a bug to patch.** Fixing it needs a delta-vocabulary decision and it is **ADR-0021's** — do
  not extend the delta ops on this momentum.
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

**[`efforts/import-text-normalization.md`](efforts/import-text-normalization.md) — ATK's "Gather Your
Ingredients" is a latent grocery bug (scoped 2026-07-28). P1 only; **no schema**.** 101 shoppable ingredient
lines + 70 section names across **171 recipes** are page chrome captured as content, all canonicalizing to
one key, so any of those recipes on a menu puts "Gather your ingredient" on the grocery list.
- **Delete, do not de-cap.** Lines: delete the row. Sections: **clear the name, keep the section**
  (`sectionID` is `ON DELETE CASCADE` — dropping it takes every ingredient with it).
- **⚠️ Needs the post-engine pass** ADR-0014 Amd1-D3 described and dodged at 10 rows: a repair in the migrator
  uploads nothing and each device diverges, and **the 101 deletes are unrepeatable** — a delete that never
  uploads stays alive in CloudKit and any full-zone fetch resurrects it
  ([[migration-writes-bypass-sync-triggers]]). Back up first.
- **P2 (Milk Street's all-caps) is DECLINED**; P3's Amd1-D1 dependency is now discharged (shipped 2026-07-28)
  but it stays parked behind the declined P2. Don't build either on momentum.

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

**[`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) — the one optional follow-on
left after the app test target was fixed. Small, unhurried, no decisions outstanding.** Move
`WorkbenchCompareAlignmentModel` and `RecipeScaleFormatting` — SwiftUI-free logic sitting in `YesChefApp/` —
down to Core. **Queue it on the "keep pure logic out of the App layer" corollary, not on testability:** the
original "these tests execute nowhere" premise is gone, the target runs. Two riders — the yield-scaling fix
already left two app-layer assertions redundant (flagged in place for this sweep rather than deleted
drive-by), and adding a file to `YesChefAppTests` without re-running `xcodegen generate` silently excludes it
from the bundle, so fewer files in that target is fewer chances to hit it.

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

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) leftovers — one owed confirmation and S3.**
- **The owed OQ1 confirmation (small, do it before trusting the net).** Amendment 1 is **Proposed**, not
  Accepted: its four-step mechanism is a code reading. Confirm it in an **isolated CloudKit container** — one
  line in `YesChefCloudSync.configuration.containerIdentifier` plus a new container in the dashboard — against
  a small seeded library on two simulators: export → mutate → restore → re-enable → observe. **Explicitly not
  against the live zone**, where the same experiment costs a ~44k-record push and can resurrect deleted rows
  on both devices with no undo. The one thing to watch is whether a missing `_lastKnownServerRecordAllFields`
  really collapses the merge into a whole-record overwrite; if SQLiteData backfills a baseline first, the
  amendment softens considerably.
- **S3 — automatic snapshots.** Cadence/trigger + retention (keep N), local-only. **Build the pre-migration
  snapshot first** (D4): a rolling local snapshot taken right before `migrator.migrate` runs, so a
  bad/erasing migration is always recoverable from the step before it — the single cheapest catch for the
  [[debug-erase-vs-sync-triggers]] class of bug. App-update-boundary and periodic snapshots follow.
- **OQ5 (restore-authoritative — reset the zone and re-upload) is parked, not queued.** It is the only true
  cure for a poisoned zone and it is irreversible; **do not build it on ADR momentum**
  ([[withdraw-not-defer-orphaned-schema]]). It gets its own slice and its own justification, or none at all.

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

Not work, a checklist. **[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S2**
(PR [#252](https://github.com/jonphillips/yes-chef/pull/252)) owes the **local** round-trip on device — pick a
backup through the Files importer, confirm, relaunch, and land on the restored library, then Undo Last Restore
back. **Keep sync off for this pass**; the sync-reconciliation half is the separate isolated-container job in
Ready Efforts, deliberately not run against the live zone. *(Delete this if you already ran it.)*
**Recipe section grain S1** (PR [#246](https://github.com/jonphillips/yes-chef/pull/246))
owes the Samin capture showing its three instruction sections with subheads, and — the canary — a
single-section recipe looking and spacing exactly as it did before; the reader and Compare restart numbering
per section while the adjustment review stays continuous, which is deliberate.
**[ADR-0032](decisions/ADR-0032-workbench-reference-material-fetch.md) S3** (complete,
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
- **`YesChefAppTests` compiles and links on every `check-drift.sh` run, but only *executes* behind
  `YESCHEF_RUN_APP_TESTS=1`** (it boots a simulator, and there is a teardown hang). All 29 pass as of
  2026-07-29. So the old "a test there counts for nothing" rule is retired — but **Core is still the default
  home**, because `YesChefPackage/Tests/` runs on every dispatch with no flag and no simulator. Put a test in
  the app target only when it genuinely needs the app target, and say in the PR that you ran it with the flag.
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — hand straight to Jon's UI pass. Only boot a simulator
  when a change genuinely can't be confirmed from build + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** No alternate destinations, simulator resets, or install loops.
  An environment failure that prevents the elevated build reaching the compiler is an architect gate, not a
  successful Codex verification.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
