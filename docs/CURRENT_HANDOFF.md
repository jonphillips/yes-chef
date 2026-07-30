# Current Handoff

Last updated: July 30, 2026. (**Playbook edit grain is fully closed** — Dispatch 2 (S3) shipped as PR
[#261](https://github.com/jonphillips/yes-chef/pull/261), device-checked. See the DONE-LOG. **Prep-plan
Slices 1–2** are in PR [#262](https://github.com/jonphillips/yes-chef/pull/262) — day-anchored labels
device-confirmed, **merging**. New live target: **prep-plan Slice 3** (gated on #262 merging).)

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate is **crossed and holding**. We stay in
CloudKit **Development** by design; prod-schema promotion is the held ops step in its own section below.

The **short entry point** for a fresh Yes Chef conversation — Next Up, Standing guards, Ready Efforts,
prod-schema promotion list, Verification Pattern, nothing else. Completed-slice history and strategic
background live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**ONE live dispatch target: [`efforts/prep-plan-dish-links-and-dates.md`](efforts/prep-plan-dish-links-and-dates.md)
§ Slice 3 — the omission guard is for accidental drops, not for a regenerate.** Dispatch with
*"Do **prep-plan Slice 3** from `docs/CURRENT_HANDOFF.md`."* If this section is empty or missing, **STOP and
ask Jon — never infer.** See `docs/AGENTS.md` § Work Intake & Dispatch. **Gated on PR #262 merging first**
(Slices 1–2); Slice 3 is only *reachable* because Slice 1 makes a regenerate rewrite every session label.

**The finding (from the #262 device pass).** Regenerating a prep plan flags ~every existing step under "Review
omitted steps before saving." [`omittedCurrentPrepStepEvidence`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift)
diffs current-vs-returned on exact visible content (`session` + `task` + `serves`); a regenerate rewrites the
labels (Slice 1's purpose) *and* rephrases the tasks, so 100% read as "missing." The guard is ADR-0040
lossless-or-loud doing its job — but answering the wrong question. Its question is *"did the model silently
drop work I meant to keep?"*, which is only meaningful for an **incremental refine**. A regenerate is
**intended wholesale replacement**.

**The core reframe the dispatch must not undo:** the variable is **refine vs regenerate intent**, not the
transport. Refine → baseline = current plan, guard fires loud (unchanged). Regenerate → baseline = **empty**,
no omission/dropped-link list, a light "replaces your N-step plan" confirmation instead — the loss is
*declared*, not silent. **Do not** infer intent from how many steps happen to match (that heuristic *is* the
bug); **do not** add fuzzy matching to the refine diff (fights ADR-0040 and wouldn't help a reworded plan
anyway); **do not** touch Slice 1's storage or grouping.

- **The onboard fix needs no schema.** `regeneratePrepPlan()` sets `.regenerate`, chat "Apply…" stays
  `.refine`, passed in-memory — onboard staging builds a *transient* `AIHandoff` (never written). This alone
  fixes the banner Jon hit.
- **The one column is for the outboard round-trip only.** A "Handoff to Regenerate" action must survive the
  copy→paste gap, so intent persists on the `aiHandoffs` row (add e.g. `regenerates: Bool` default `false` →
  existing rows read `.refine`). **`aiHandoffs` is NOT in `CloudSync` — it is local-only**, so this is a plain
  local migration: **no prod-promotion entry, and the deterministic-UUID / post-engine sync rules do NOT
  apply** ([[migration-writes-bypass-sync-triggers]] is about *synced* tables). Keep it local — do not add it
  to the sync list on momentum.
- **Both transports converge in Core** at [`AIHandoffReviewStager.menuReview`](../../YesChefPackage/Sources/YesChefCore/AIHandoffIntentImport.swift):
  the intent chooses the baseline. Outboard "Handoff Prep" stays refine; the new "Handoff to Regenerate" is a
  sibling action in the prep-plan `…` menu.

**Verification.** Package build + Core tests + the **generic app build** (App-layer: new menu action + review
reframe). **Local migration → does *not* need a two-device sync pass.** Jon's device look confirms: (a)
onboard regenerate no longer floods omissions, (b) outboard "Handoff to Regenerate" → paste returns a clean
replacement, (c) a genuine refine still surfaces a real dropped step. No prod-promotion entry.

**⚠️ Jon's outstanding follow-through from ADR-0014 Amd1 (not a dispatch item):** three recipes still carry
`isHeader = 1` rows to hand-repair in the app — *Beef Birria Taco Filling* (4), *Broccoli Spoon Salad* (2),
*Sous Vide Indoor Pulled Pork* (2). *411 West's Rosemary Chicken* was pre-fixed 2026-07-28. Add a colon to
each header line and the row is promoted to a section and deleted on save. (Amd1-D1a, the colon-free door, is
**deferred** — the colon is the only path, which is the ratified primary anyway.) Dropping the `isHeader`
**column** afterwards is a schema change, not a data migration, and is not queued.

## Standing guards

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v2** — re-copy the project instructions from AI Settings or every
  verb fails the marker gate. (Operational: it bites on any hand-off dogfooding session.)
- **ADR-0021 (variations) and ADR-0023 (recipe edit proposals) have nothing queued.** ADR-0023's *iterative
  refine loop* is **WITHDRAWN** (ADR-0042 D7 — it happens in the live external thread; **do not rebuild it**);
  per D2 the in-app adjust verb is the **only** path that writes a structured delta. **Expected, not a bug to
  patch (ADR-0014 Amd1-D4):** adding a header inside a recipe that has variations mints a new section, so
  `derivingVariation` hits `.ingredientSectionAdded` → `variationNeedsReview`. Fixing it needs a
  delta-vocabulary decision and it is **ADR-0021's** — do not extend the delta ops on this momentum.
- **ADR-0042 S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want. **Do not build it on
  ADR momentum.** There is no S5.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged** — variations (ADR-0021, shipped + device-passed) and
  "Menu is under-served by hand-off verbs" (ADR-0043's load test). Parked **ADR-0013** meal-planner verbs are
  separate and unscoped — see Ready Efforts.
- **The Recipe Workbench store/curate/compare arc (ADR-0019) is complete**, S1–S4 shipped. Parked follow-ons
  live in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md), not here.
- **The workbench's experiment-outcome verb is NOT scoped** — only its *placement* is ratified (ADR-0042 D8's
  corollary: a conjecture suppresses learnings, a **cooked** experiment is findings, so learnings come back
  on). That amendment gets written when that half is scoped, **deliberately not now.**
- **Chat entry points are unified and closed** ([`efforts/chat-ask-uniformity.md`](efforts/chat-ask-uniformity.md),
  PR #244). Uniformity is **cross-surface, not cross-device**: modal sheets keep the iOS nav bar; embedded and
  column presentations keep the in-panel header row. **That divergence is intended — do not "unify" it.** The
  Calendar/Workbench detent split and the Recipe inspector belong to ADR-0046.

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

**[`efforts/app-target-tests-to-core.md`](efforts/app-target-tests-to-core.md) — one optional follow-on.
Small, unhurried, no decisions outstanding.** Move `WorkbenchCompareAlignmentModel` and
`RecipeScaleFormatting` — SwiftUI-free logic sitting in `YesChefApp/` — down to Core. The app target runs
again (2026-07-29), so these tests execute; the motive is the "keep pure logic out of the App layer" corollary
plus that Core runs on every dispatch with **no flag and no simulator** (the app target still needs
`YESCHEF_RUN_APP_TESTS=1`).
- **Rider:** S0.1's `ServeWithRepairPresentation` is SwiftUI-free value logic over Core types (`Recipe`,
  `ServeWithCodingError`), so it and its three tests move down cleanly and run with no flag. Only the two
  model-routing tests (`RecipeDetailModel` / `WorkbenchDetailModel` `presentServeWithRepair`) need the app
  target. Do not open a separate PR for it.
- Two older riders — the yield-scaling fix already left two app-layer assertions redundant (flagged for this
  sweep, not deleted drive-by), and a file added to `YesChefAppTests` without re-running `xcodegen generate` is
  silently excluded from the bundle.

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

**Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4).** The pipeline is **already wired**
(`.draggable`/`.dropDestination` between `MenuRecipeBrowserPanel` and `MenuDishDayList`, slide-over stays
interactive) but drag-and-drop is not firing reliably in the current betas. **Retry after Beta 4;** then it's
confirm-E2E + polish, no schema.

**Meal-Planner chat verbs** (ADR-0013 + `efforts/cooking-workspace.md`) — the one remaining named
actionable-chat verb instance. Classify each verb's commit shape first ([[chat-verb-commit-shapes]]) — likely
no-commit advisory or a per-day note, not a per-recipe write; respect [[llm-curation-not-synthesis]].
**Confirm with Jon what verb scope remains.**

**Recipe text normalization** — strip manual instruction numbers now that we auto-number (Milk Street
all-caps de-cap is the DECLINED P2 above). **Unscoped**; parked in
[`docs/open-questions.md`](open-questions.md). Interacts with ADR-0014, so sequence them.

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) leftovers — one new slice (enforce restore
procedure) and S3.**
- **OQ6 + OQ7 are CLOSED (2026-07-29, measured; ADR Amendment 3).** Do **not** re-run the measurement effort.
  - **OQ7 — CLOSED clean.** Images survive the re-push **byte-intact on the peer**; asset- and record-level
    resurrection both work. Caveat: a photo *replaced* since the backup resurrects as a **duplicate**
    (delete-row + insert-row). **Volume** (~2,163 assets at once → CKError 429 shape) stays a **real-device
    unknown** — keep it in the device pass.
  - **OQ6 — CONFIRMED data-loss path, mitigated by protocol.** A peer's **unsent/held** delete that syncs
    *after* a restore **wins and silently re-deletes the restored record on every peer** (measured E2E). So
    restore is authoritative **only against settled peer state** — this **bounds Amendment 2**, does not
    reverse it. Root cause is upstream SQLiteData tombstone handling (`upsertFromServerRecord` never clears
    `_isDeleted`; `syncChanges` sends before it fetches) → **file a point-free bug report**. The resting
    tombstone self-heals on the next relaunch in the ordinary flow; the loss needs a concurrent restore.
- **⚠️ NEW SLICE — the app must enforce the restore procedure (Jon's call).** Naive restore is unsafe:
  *quiesce every peer (delete the app → drops its unsent CKSyncEngine queue) → restore + re-enable on one
  device → reinstall the peers so they rebuild from the restored cloud.* Restore must gate on / walk the user
  through quiescing the other devices before it re-enables sync. **Verify once (throwaway install, NOT the
  measurement sims) that deleting the app clears the app-group container** — the store + pending ops live
  there, and the whole mitigation rests on that. Not-yet-scoped into slices; scope with Jon.
- **OQ1 is CLOSED (2026-07-29, measured).** Restore re-pushes the whole restored library and restored values
  win collisions **with already-settled peer state** (see Amendment 2, as bounded by Amendment 3). **Do not
  re-derive from the code.**
- **OQ5 is CLOSED — nothing to build.** "Restore-authoritative" was parked as a future slice; it turned out to
  be the shipped behaviour, with no zone reset involved.
- **The database export is also a durable archive, not just a restore artifact** (design constraint, parked to
  `open-questions.md`): the backup is a self-describing SQLite file with standard-encoded image BLOBs, so the
  library is re-extractable without the app. The "drain blobs into typed rows" direction keeps it legible;
  don't reintroduce opaque app-specific blobs. Not a build item — a constraint on future ones.
- **S3 — automatic snapshots.** Cadence/trigger + retention (keep N), local-only. **Build the pre-migration
  snapshot first** (D4): a rolling local snapshot taken right before `migrator.migrate` runs, so a
  bad/erasing migration is always recoverable from the step before it — the single cheapest catch for the
  [[debug-erase-vs-sync-triggers]] class of bug. App-update-boundary and periodic snapshots follow.
- **Temporary, in Jon's tree, not to be committed:** the test container `iCloud.com.jonphillips.yescheftest` is
  swapped into `YesChefCloudSync.configuration` and **both** entitlements files for the measurement. Revert
  before any real build; leaving it in either entitlements file is a bad thing to ship.

**Small nits — not urgent, fold into a passing dispatch:**
- **The S4 brief extractor's prompt is framed for a conversation, but S4 hands it a decision** (silent-failure
  risk). `instructions` says *"extract … from a cooking conversation … the user is asking to review"* while
  `HandoffReviewCoordinator.draftRecipeAdjustment` wraps a finished brief as one fake `.user` message
  (`selection: ""`) — so a **decided** revision reads as an **in-progress ask** and the extractor hedges, and
  under-extraction is silent (a 3-change brief yielding 2 ops just looks shorter). *Fix:* a task-specific
  framing for the brief path, **not** a second client, and **not** taste profile / known-learnings into the
  extractor (those belong to the outbound ask).
- **Workbench log-editor** (ADR-0042 S2 review): the `canSave` / `normalizedLogEntryDraft` mismatch when a body
  is combined with partially-filled typed fields, the dead save spinner, the compare `.menuPrepPlan` mislabel.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip);
  spec in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md). ⚠️ Re-read against ADR-0042 D2/OQ5
  first: it is an *in-app* draft verb and the draft is a structured write.
- **`stageReaderFeedback` defaults `unparsedLines` to `[]`**, so accepting a single tip through the *in-app*
  path clears the evidence banner (cosmetic).
- **From the PR #244 review, all one-liners:** `MenuDetailModel.tool`'s `didSet` and
  `recipeBrowserButtonTapped` both clear `activeChatStarterID` — say it once; `MenuDetailReader`'s
  `isAskActive`/`askButtonTapped`/`regeneratePrepPlan` closure params are now pure passthroughs (fine to leave
  for ADR-0046); `namesStarterContractsForEveryHost` asserts `.starters == .starters` and proves nothing.

**Still-deferred, separate future efforts:** ADR-0027 **OQ4** (a note-worthiness taste preference);
**ADR-0036 S3** — promote a `RecipeNote` deposited *on a recipe*; **ADR-0038 Amd 4 — smart Learning
curation** (an LLM pass reconciling incoming-vs-existing learnings; the deterministic exact-dedup *floor*
already shipped, so this is the paraphrase-aware ceiling, not urgent —
[[handoff-stateless-both-directions]]). Comment ingestion stays in `docs/open-questions.md`.

**Parked to `docs/open-questions.md` (decide with Jon before build):** multi-bubble / whole-transcript chat
selection (per-bubble `UITextView` caps the payload).

## Device passes owed

Not work, a checklist.

**[PR #262](https://github.com/jonphillips/yes-chef/pull/262) — prep plan dish links and dates. Merging, no
schema.** Slice 1 (day-anchored sessions on a placed menu) is **device-confirmed 2026-07-30**. **Slice 2 pass
still owed:** on iPhone compact width, confirm an inert chip relinks in two taps, a hand-authored step can be
linked, *No dish* clears and persists, and a compound `serves` proposes no dish.

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) S2** — the export →
restore → re-enable-sync round-trip **passed on two simulators 2026-07-29** (isolated test container), which
also closed OQ1. OQ6 is now diagnosed (Amendment 3): a naive real-device restore can be **silently clobbered by
any peer's in-flight delete**, so **hold the real-device pass until the enforced restore procedure gates it**
(quiesce peers → restore on one → reinstall peers). When it runs, follow that procedure and **Undo Last
Restore** is untested at all and rode the same broken binding as restore, so exercise it too.
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
- The synced **`recipeServeWith`** table (ADR-0048 S3)
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
  `YESCHEF_RUN_APP_TESTS=1`** (it boots a simulator, and there is a teardown hang). **29 tests in 9 suites
  pass as of 2026-07-29** (the SQLiteData 1.8.2 bump fixed the link wall — see the DONE-LOG arc). So the old
  "a test there counts for nothing" rule is retired — but **Core is still the default home**, because
  `YesChefPackage/Tests/` runs on every dispatch with no flag and no simulator. Put a test in the app target
  only when it genuinely needs the app target, and say in the PR that you ran it with the flag. **If the
  `Ld … SQLiteData.framework` undefined-symbols wall ever returns, `xcodebuild clean` first** — SQLiteData
  links `StructuredQueriesCore` via Swift autolinking against the `PackageFrameworks` search path, not a
  declared dependency, so it is build-order sensitive and a stale eager-linking TBD looks identical
  ([[exported-import-not-link-time]]).
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — hand straight to Jon's UI pass. Only boot a simulator
  when a change genuinely can't be confirmed from build + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** No alternate destinations, simulator resets, or install loops.
  An environment failure that prevents the elevated build reaching the compiler is an architect gate, not a
  successful Codex verification.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
