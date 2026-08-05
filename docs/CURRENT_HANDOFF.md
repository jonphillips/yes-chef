# Current Handoff

Last updated: August 5, 2026. (**The entire ADR-0049 facet/labeling arc is closed as a gate.** Amendment 2 (the
facet model) is complete and archived ([`DONE-LOG.md`](DONE-LOG.md)): D1–D5, F1/F2, and the OQ4 editorial-facet
seed all shipped and device-passed (PRs [#275](https://github.com/jonphillips/yes-chef/pull/275)–[#277](https://github.com/jonphillips/yes-chef/pull/277)),
D4 hand pass done. The S5/S6 + D8 labeling-backfill **tooling** shipped (PR [#278](https://github.com/jonphillips/yes-chef/pull/278)),
the ADR-0004 S4 structured-output correction merged (PR [#280](https://github.com/jonphillips/yes-chef/pull/280) +
jon-platform [#36](https://github.com/jonphillips/jon-platform/pull/36)), and **Amendment 4's deterministic
exact-match label floor shipped** (PR [#281](https://github.com/jonphillips/yes-chef/pull/281); Edit Tags
two-column refinement in PR [#282](https://github.com/jonphillips/yes-chef/pull/282)). **Filling in per-recipe
facet/tag coverage is Jon's ongoing hand work and gates nothing** — Power Browser (ADR-0050) and everything
downstream move forward without waiting on it. Records in [`DONE-LOG.md`](DONE-LOG.md).)

**Standing state (not a task):** iCloud sync round-trips end-to-end across two physical devices
(`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`) — the M4 one-way gate is **crossed and holding**. We stay in
CloudKit **Development** by design; prod-schema promotion is the held ops step in its own section below.

The **short entry point** for a fresh Yes Chef conversation — Next Up, Standing guards, Ready Efforts,
prod-schema promotion list, Verification Pattern, nothing else. Completed-slice history and strategic
background live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**The facet/labeling gate is cleared — no hard-gated dispatch is queued.** Amendment 4's deterministic floor
shipped (PR [#281](https://github.com/jonphillips/yes-chef/pull/281)) and filling in per-recipe coverage is Jon's
ongoing hand work (Edit Tags + DEBUG Facet Coverage) that **gates nothing**. Live candidates:

- **⚠️ Dispatch now — [`efforts/variation-anchor-repair.md`](efforts/variation-anchor-repair.md) Dispatch 0
  (+ Dispatch 3, one PR).** A **standing data-loss defect**: a variation's anchors are copied from model output
  and never normalized to base row IDs (`keepAdjustmentProposalAsVariation` at
  [`RecipeAdjustment.swift:560/565`](../YesChefPackage/Sources/YesChefCore/RecipeAdjustment.swift) resolves the
  anchors against the live base and *throws the result away*), so correcting a typo in a base step orphans the
  variation permanently and `resolved(applying:)` **throws** — taking out the editor, the reader fold, and the
  grocery contribution. **Every base edit Jon makes before this lands is another chance to lose a variation.**
  Core-heavy (tests carry it), no schema; Pass B is a backup-first data pass over the `deltas` BLOB owing a
  convergence check. Dispatch 3 rides along (missing `.alert` + progress + sheet-handoff fixes).
- **Then — Variations → the Playbook = [ADR-0021](decisions/ADR-0021-recipe-variations.md) Amendment 4, V4a.
  Amd 4 is RATIFIED (Jon, 2026-08-05); V4a is dispatchable.** *(This is the idea Jon recalled — the record was
  the never-applied APPLY file, folded into ADR-0021 2026-08-05.)* **V4a** relocates the variation picker from
  the Body to a Playbook **Choices** section (Amd4-D5, correcting an ADR-0039 D1 drift), renders variations as a
  proper list, and inherits ADR-0041 S2's section-scoped hand-off — **app-only, schema-free**, the whole of
  complaint (1); ships alone and first. V4b (related-recipe edge table — **OQ2 resolved: order by name, no
  ordering column**; the schema slice, two-device pass owed) and V4c (the two new step ops — **gated behind
  anchor-repair Dispatch 1**) follow.
- **[ADR-0050](decisions/ADR-0050-recipe-power-browser.md) Power Browser S1.** All the facet infrastructure it
  needs is shipped (facets, editable membership, the deterministic floor, the three coverage views). Its old
  "wait until primary facets classify a majority of the library" gate is **retired** — the manual backfill no
  longer gates anything (Jon, 2026-08-05). Needs its own scoping pass. (Amd4-OQ1 wants variation/related-recipe
  indexing answered while `RecipeBrowserQuery` is still being designed.)
- **[ADR-0046](decisions/ADR-0046-sidebar-adaptable-app-shell.md) — the sidebar-adaptable app shell.** Unblocked
  since 2026-07-25; moves all eight chat call sites onto one Ask. Ready but larger.

The ATK grocery-bug slice ([`efforts/import-text-normalization.md`](efforts/import-text-normalization.md)) is a
**data migration wanting backup-first + a device pass** — hold it until Jon is local. D3's settled
hidden-vocabulary rule lives in ADR-0049 D11.

## Standing guards

Closed decisions that stay closed, here only so a dispatch does not re-queue them. **Nothing in this
section is work.**

- **⚠️ The ADR-0042 return contract is v2.1** (`AIHandoffReturnContract.version`) — re-copy the project
  instructions from AI Settings or every verb fails the marker gate. (Operational: it bites on any hand-off
  dogfooding session.)
- **ADR-0021 (variations) V1–V3 are shipped; Amendment 4 is RATIFIED (2026-08-05) and queued in Next Up (V4a
  dispatchable, app-only) — see there.** ADR-0023 (recipe edit proposals) has nothing queued: its
  *iterative refine loop* is **WITHDRAWN** (ADR-0042 D7 — it happens in the live external thread; **do not
  rebuild it**); per D2 the in-app adjust verb is the **only** path that writes a structured delta. **Expected,
  not a bug to patch (ADR-0014 Amd1-D4):** adding a header inside a recipe that has variations mints a new
  section, so `derivingVariation` hits `.ingredientSectionAdded` → `variationNeedsReview`. Fixing it needs a
  delta-vocabulary decision and it is **ADR-0021's** — do not extend the delta ops on this momentum. **Note:
  Amd4-D4's two new step ops (`stepInsert`/`stepRemove`) are the sanctioned widening, and V4c is gated behind
  anchor-repair Dispatch 1 — that is the disciplined path, not an ad-hoc extension here.**
- **ADR-0042 S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want. **Do not build it on
  ADR momentum.** There is no S5.
- **`PlaybookSectionMeta` is not queued anywhere — do not resurrect it.** ADR-0041 closed at S2.6, S3
  withdrawn ([Amd 3](decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md#amendment-3--s3-is-withdrawn-the-conversation-url-does-not-exist-2026-07-19)).
  If section provenance is ever wanted it designs its own storage against its own consumer
  ([[withdraw-not-defer-orphaned-schema]]).
- **Both candidates Jon named 2026-07-21 are discharged** — variations (ADR-0021 V1–V3, shipped + device-passed;
  Amd 4 is a *later* 2026-08-01 reopening, queued separately in Next Up) and "Menu is under-served by hand-off
  verbs" (ADR-0043's load test). Parked **ADR-0013** meal-planner verbs are separate and unscoped — see Ready
  Efforts.
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

**⚠️ [`efforts/variation-anchor-repair.md`](efforts/variation-anchor-repair.md) — variation anchors are
unrepairable; the adjust surface fails silently (2026-08-01). Designed, nothing shipped.** A standing
**data-loss** defect (model-supplied anchors are never normalized to base IDs; `resolved(applying:)` throws on
one dead anchor, taking out editor + reader fold + grocery). Four dispatches, **no schema**. **Dispatch 0 (+3)
should ship immediately** and is drawn into Next Up above; Dispatch 1 (degrade-don't-throw) then gates ADR-0021
Amd4 V4c. Pass B is a backup-first data pass over `recipeVariations.deltas` owing a convergence check.

**[`efforts/recipe-facets.md`](efforts/recipe-facets.md) — ADR-0049 (the facet model + labeling): COMPLETE and
archived.** D1–D5, F1/F2, OQ4 seed, the S5/S6+D8 backfill tooling, and the Amd-4 deterministic floor all shipped
and device-passed (PRs #275–#282); full record in [`DONE-LOG.md`](DONE-LOG.md). The **only** live thread it hands
off is **F3/OQ5** (retire the typed freeform Cuisine/Course editor fields, **preserving** the per-facet
single-select picker affordance — rebind, don't delete), deferred to **ADR-0050 S3.5**, do not fold in elsewhere.

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

**[ADR-0030](decisions/ADR-0030-local-backup-and-restore.md) leftovers — two unbuilt slices.** The measurement
arc is closed (OQ1/5/6/7 → DONE-LOG + [[restore-is-authoritative]]); the net covers a lost/blank zone and
restore is authoritative **only against settled peer state**. Do **not** re-run the measurement. Two things
remain to build, plus one upstream loose end:
- **⚠️ NEW SLICE — enforce the restore procedure (scope with Jon).** Naive restore is unsafe: a peer's
  unsent/held delete that syncs *after* a restore silently re-deletes the restored record on every peer (OQ6,
  measured E2E). Restore must gate on / walk the user through *quiesce every peer (delete the app → drops its
  unsent CKSyncEngine queue) → restore + re-enable on one device → reinstall the peers.* Verify once (throwaway
  install) that deleting the app clears the app-group container — the whole mitigation rests on it.
- **S3 — automatic snapshots.** Cadence/trigger + retention (keep N), local-only. **Build the pre-migration
  snapshot first** (D4): a rolling local snapshot taken right before `migrator.migrate` runs, so a bad/erasing
  migration is always recoverable from the step before it — the single cheapest catch for the
  [[debug-erase-vs-sync-triggers]] class of bug. App-update-boundary and periodic snapshots follow.
- **Loose end — file a point-free bug report:** upstream SQLiteData tombstone handling never clears
  `_isDeleted` in `upsertFromServerRecord` (and `syncChanges` sends before it fetches), which is the root of the
  OQ6 data-loss path above.

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

*(The full ADR-0049 facet/labeling arc — PRs #270/#272/#274 (D1–D3), #275 (D5), #276 (F1/F2), #277 (OQ4 seed),
#278 (S5/S6+D8 backfill tooling), #281 (Amd-4 floor), #282 (Edit Tags refine) — is device-passed 2026-08-05 and
removed. D4 hand pass done.)*

**[PR #262](https://github.com/jonphillips/yes-chef/pull/262) — prep plan dish links and dates. Merged
2026-07-30, no schema.** Slice 1 (day-anchored sessions on a placed menu) is **device-confirmed 2026-07-30**.
**Slice 2 pass still owed:** on iPhone compact width, confirm an inert chip relinks in two taps, a hand-authored
step can be linked, *No dish* clears and persists, and a compound `serves` proposes no dish.

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
- **`Category.color`**, **`Category.facetID`**, and **`Category.hidden`**, plus the synced **`facets`**
  table (ADR-0049 Amendment 2)
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
