# Current Handoff

Last updated: July 22, 2026 (**Live dispatch target = the iPhone chrome pass** — two compact-width defects from Jon's 2026-07-22 iPhone pass, bundled into one PR: the seven-tab compact `TabView` overflowing into the system **More** tab (which nests a second `UINavigationController` and draws the double back chevron on Menu detail), and the recipe hand-off door being buried in the nav-bar `•••`. Both app-layer, no schema. Two further reports from the same pass — the Playbook's *"Hand off to ChatGPT"* label and its missing per-section `•••` — are **excluded pending a reinstall**, because that string no longer exists in the codebase and both symptoms match a pre-#199 build. **ADR-0042 remains COMPLETE and closed**; after this chrome pass the next feature effort is Jon's pick. S4 (Amd 1) shipped and device-passed: the recipe body now hands off and a prose *revision brief* returns, with the structured write still authored in-app ([#216](https://github.com/jonphillips/yes-chef/pull/216) + follow-ups `2446ed0` restoring the missing paste affordance and `31d2089` adding the base-write guard) → DONE-LOG. **S3 (`workbenchDraft`) stays deferred and un-queued; there is no S5.** **⚠️ The return contract is v2 — re-copy the project instructions from AI Settings or every verb fails the marker gate.** Two things surfaced by the S4 dogfood pass and carried forward, not lost: **variations are half-built** — no edit, no promote — which is **[ADR-0021 Amds 1 + 2](decisions/ADR-0021-recipe-variations.md) (Proposed, ratify before dispatching)**, and until then a variation is a display-time overlay that every read folds and **no write understands**, so editing with one active writes to the base (guarded now, not fixed); and **the "why" dies at the commit boundary** — the brief's per-change rationale has no home, recorded as a fork in [`open-questions.md`](open-questions.md) to ride with those amendments. Jon also named **Menu's thin hand-off verb coverage** as a surface needing love. — Prior closes: **ADR-0042 S2** ([#214](https://github.com/jonphillips/yes-chef/pull/214)) and **S0 + S1** ([#212](https://github.com/jonphillips/yes-chef/pull/212)) → DONE-LOG; **ADR-0041 COMPLETE at S2.6** (PRs #206/#209 + ADR-0038 Amd 5 #210), **its S3 WITHDRAWN**.)

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

**LIVE DISPATCH TARGET — iPhone chrome pass (two cohesive slices, one PR).** Both are compact-width
defects from Jon's 2026-07-22 iPhone pass; both are **app-layer only, no schema, no Core**. Do them in
order under one PR.

**Slice 1 — the compact tab bar stops overflowing into the system "More" tab.** `AppSection` has **seven**
cases and `AppCompactTabView` (`YesChefApp/AppMainLayout.swift`) renders all seven with `.tabItem`. On
iPhone iOS collapses everything past the fifth into a **system-managed More tab, which is its own
`UINavigationController`** — so `MenusStack`'s `NavigationStack` nests inside it and every Menu detail
draws **two stacked back chevrons**. Confirmed on `iPhone 17 Pro` against `main`: the tab bar reads
Recipes / Workbench / Browser / Calendar / **More**, with Menus, Groceries and Settings all buried.

**Jon's call (2026-07-22): the four primary tabs are Recipes, Menus, Calendar, Groceries** — the cooking
workflow. Browser, Workbench and Settings move into a **More tab we own**: one `NavigationStack` whose root
is a `List` of the three overflow sections, pushing them via `navigationDestination`.

Traps, in the order they will bite:
- **Push the *content* views, never the `*Stack` wrappers.** `BrowserStack`, `WorkbenchesStack` and
  `SettingsStack` each wrap their content in a `NavigationStack` — pushing those from the More stack
  recreates the exact nesting this slice removes. Push `BrowserWorkspaceView`, `WorkbenchListView(style:
  .navigation)` and `SettingsView` instead, and decide explicitly whether the three now-unused wrappers get
  deleted or kept for the iPad path (they are not used there today — `AppMainLayout`'s split view builds its
  own columns).
- **Workbench has its own list→detail push.** `WorkbenchesStack` owns
  `.navigationDestination(for: Workbench.ID.self)` bound to `model.navigationPath`. Once the list is pushed
  from the More stack that destination must be registered **on the More stack**, and you must decide whether
  the More stack's path binds to `WorkbenchLibraryModel.navigationPath` or the model's path becomes
  iPad-only. Say which in the PR.
- **`selectedSection` must still round-trip.** The compact `TabView` selection is
  `Binding<AppSection?>` shared with the iPad sidebar. `.browser` / `.workbenches` / `.settings` are no
  longer valid tab tags — make sure selecting them cannot silently no-op the tab bar. The only programmatic
  writer today is `openMenuFromCalendar` (`selectedSection = .menus`), which this layout **promotes to a real
  tab** — that path gets simpler, not harder.
- **Do not touch the regular-width path.** `AppMainLayout`'s `NavigationSplitView` + `AppSidebar` use all
  seven sections and are correct as-is. This slice is `horizontalSizeClass == .compact` only.

**Slice 2 — the recipe hand-off door comes out of the system overflow.** `RecipeDetailView.recipeToolbar`
puts **Hand off** and **Paste** in `ToolbarItemGroup(placement: .secondaryAction)`, which on iOS collapses
into the nav-bar `•••`. They are wired correctly (this is *not* the PR #216 `PasteButton` bug — `2446ed0`
already fixed that), but buried: on iPhone Jon read the recipe toolbar as simply **not having** copy/paste.
ADR-0042 Amd 1's whole premise is a **round trip**, so the return door must be visible.

**Shape:** replace the two `.secondaryAction` buttons with a single **`.primaryAction` `Menu`** labelled
`sparkles.square.filled.on.square`, holding *Hand off* and *Paste* — the same idiom as the Playbook section
`•••` menu. **Keep using plain buttons that read `UIPasteboard.general.string` directly; `PasteButton` does
not render inside a `Menu`** (the constraint is documented on `HandoffCopyPasteControls` — do not
re-litigate it). `View Original` and `Archive` stay in `.secondaryAction`. Preserve the existing
`activeVariation` guard: a variation being active must still route through the
`isConfirmingBaseRecipeHandoff` confirmation rather than copying straight out (Amd1-OQ3).

**⚠️ Decide with Jon before building Slice 2:** `.primaryAction` already carries four buttons (Edit,
Groceries, Plan, Workbench) plus a fifth on wide layouts (the Playbook toggle). Adding a hand-off menu makes
**five or six** on a 393pt iPhone, and iOS will start overflowing them again — which is the same failure in
a new place. The architect's recommendation is to **demote `Workbench` into `.secondaryAction`** to pay for
the hand-off menu, on the grounds that hand-off is now a daily round-trip and the workbench is an
occasional deep-dive. That is a product tradeoff, not an implementation detail — **confirm it, do not
assume it.**

**Verification:** app-layer only, so the elevated `generic/platform=iOS` build is the required evidence,
plus `scripts/check-drift.sh`. Jon does the iPhone pass — and this dispatch exists *because* that pass had
been skipped, so call out in the PR exactly what to look at on a phone.

**Two further 2026-07-22 reports are NOT in this dispatch — they are probably a stale device build.** Jon
reported the recipe Playbook showing a *"Hand off to ChatGPT"* button and **no per-section `•••` menu**. That
string **does not exist anywhere in the codebase**: ADR-0041 S1 (`4a3a564`, PR #199, confirmed an ancestor of
`HEAD`) deleted the column-top button and replaced it with the per-section menu, and the current
`playbookHeader` holds only *Ask*. Seeing the old label **and** no `•••` is exactly what a pre-#199 build
looks like. Jon is reinstalling `main` to confirm. **Do not "fix" either one** — if they survive a current
build they are a genuine and surprising regression and get their own scoped entry. (Note also: the **Notes**
section has no `•••` *by design* — ADR-0041 scoped the section toolbar to Make Ahead / Chef It Up / Serve
With.)

**ADR-0042 closed 2026-07-21.** S0/S1/S2/S4 shipped and device-passed (→ [`DONE-LOG`](DONE-LOG.md)); **S3 (`workbenchDraft`) stays deferred and un-queued** — no concrete want, its danger receded rather than grew, **do not build it on ADR momentum**; there is no S5. **⚠️ The return contract is v2 — re-copy the project instructions from AI Settings or every verb fails the marker gate.**

**Candidates Jon named 2026-07-21 (unscoped — none is a dispatch target until scoped with him):**
- **Variations are half-built, and it shows in daily use.** No way to **edit** a variation ([ADR-0021 Amd 1](decisions/ADR-0021-recipe-variations.md), Proposed) and no way to **promote** one (Amd 2, Proposed) — **ratify both before dispatching.** Until then a variation is a display-time overlay that every read folds and no write understands; the interim guard (editor notice + hand-off confirmation) only *says so*, it does not fix it. The **"why" fork** in [`open-questions.md`](open-questions.md) wants to ride with these.
- **Menu is under-served by hand-off verbs.** Menu has exactly one (`prepPlan`) and the meal-plan day has one (`mealPlanMakeAheadStrategy`); there is no *"let's talk about this day's dishes"* and no *"let's discuss the whole menu."* Deliberation-shaped and advisory, so ADR-0042 D2 puts it on the safe side of the line — but classify each verb's commit shape first ([[chat-verb-commit-shapes]]) and check it against the parked **ADR-0013 meal-planner verbs** entry below, which overlaps.

**Feature efforts still on the board — Jon picks; do not infer** (the live dispatch target above is the iPhone chrome pass and nothing else; the two candidates named 2026-07-21 are unscoped, and the first of them is the ADR-0021 entry immediately below):
- **[ADR-0021](decisions/ADR-0021-recipe-variations.md) V1 + V2 — variations become hand-editable, and promotion gets its two destinations.** **Amendments 1 + 2 are Proposed — ratify with Jon before dispatching** (Amd1-D7 and Amd2-D4 are already ratified). **V1:** editing a variation edits the **resolved** recipe and the ops are **re-derived** on save — the overlay and highlighting survive because the delta is recomputed, never hand-authored; the derivation returns `(ops, unrepresentable[])` so an inexpressible edit reports at save and offers the split-off, never saving a partial (Amd1-D7). **The editor must be the ID-preserving structured one** — a text round-trip diffs a one-word change as remove+add and destroys the color comparison (Amd1-D4). **V2:** split off as its own recipe (B1) and promote-to-base with the old base auto-derived into a variation (B2); **no probation machinery** — no cook counts, no verdict prompts (Amd2-D4). **Bundle V1+V2** so the save-time report has a split-off to offer. **Schema-free — the `deltas` BLOB stays** (Amd1-D3: ADR-0040 keys on the grain the *human* edits, and no human edits an op). ADR-0023 OQ3 (rebasing existing variations onto a new base) **must be answered in V2**, not deferred again.
- **Workbench log-editor nits (small, from the S2 review; not urgent)** — the `canSave` / `normalizedLogEntryDraft` mismatch when a body is combined with partially-filled typed fields, the dead save spinner, and the pre-existing compare `.menuPrepPlan` mislabel.
- **The S4 brief extractor borrows the in-app Ask machinery without re-aiming it (small; found 2026-07-21, not urgent but the second item is a silent-failure risk).** Two independent drifts in `HandoffReviewCoordinator.draftRecipeAdjustment` → `RecipeAdjustmentClient`:
  - **Tier selection is re-implemented, not shared.** The in-app path passes `chatModel.activeTier`; the S4 path has no chat session so it re-derives one from `recipeChatProviderPreference` + `apiKeyStore`. Reasonable in principle, but it **ignores `recipeChatTierPreference`** (the Ask path honors both), and its no-preference fallback is `availableProviders.first` — arbitrary enum order, not a user-meaningful choice. Worse, with **no API keys it silently drops to `.onDevice`** for a call demanding `maxTokens: 16_384`, `reasoningEffort: .high`, and **strict JSON that must parse or throw** ([[reasoning-budget-starves-output]]) — so a missing key surfaces as `responseTruncated` / `responseUnreadable` on a carefully-argued brief rather than as "add an API key." *Fix:* one shared `resolveTier()` used by both call sites, and an honest error when the only available tier cannot do the job.
  - **The prompt is framed for a conversation, but S4 hands it a decision.** `instructions` opens *"You extract a proposed edit … from a cooking **conversation**,"* the prompt says *"**Conversation so far:**"* and closes *"Extract only the concrete recipe edit **the user is asking to review**"* — while the coordinator wraps the finished brief as a single fake `.user` message and passes `selection: ""`. So a **decided** revision is presented as an **in-progress ask**, inviting the extractor to infer or hedge where the whole point of Amd1-D1 is that the human already decided. Under-extraction here is **silent** — a 3-change brief that yields 2 ops just shows a shorter side-by-side. *Fix:* a task-specific framing for the brief path ("this is a decided revision; transcribe every change faithfully and completely"), not a second client.
  - **Deliberately NOT part of this:** adding the taste profile or known-learnings to the *extractor*. Those belong to the outbound hand-off ask (where `RecipeHandoffContext` already sends both) because that is where judgment happens. The extractor transcribes a settled decision, and feeding it preference context invites exactly the editorializing D1 exists to stop.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip). ⚠️ Re-read against [ADR-0042 D2/OQ5](decisions/ADR-0042-workbench-handoff-and-the-return-block.md) before dispatching: it is an *in-app* draft verb, and the draft is a structured write.
- **Open a design ADR** — ADR-0013 meal-planner verbs (needs scope confirmation) or ADR-0014 text editing.

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
