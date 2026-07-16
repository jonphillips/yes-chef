# Current Handoff

Last updated: July 16, 2026 (**ADR-0039 Amendment 2 CLOSED** — Slice D + Amendment 3 shipped, **Jon device-confirmed**, build green → PR #197 → DONE-LOG. The menu now shares the recipe's Body + Playbook grammar; the menu Playbook is **permanent** (no toggle, per-menu width, service-date seeds the first open only) and Browse/Ask slide **over** it as trailing overlays, not `.inspector` columns. All four Amendment 2 slices (A–D) are done. *(Codex is folding three cosmetic/robustness tweaks — #2 overlay size-class gate, #3 redundant material/separator, #4 dead `MenuDetailInspector.title` — into the same PR #197; re-run the build gate on that tip before merge.)* **Next Up = a four-fix dogfood polish batch** (yield-fraction scaling · scalar 10→30 · grocery aisle picker · Workbench candidates→Reference), app-layer + Core, no schema.)

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

**Live dispatch target — Dogfood polish batch (four independent fixes, one PR).** From Jon's 2026-07-16 device pass. **All app-layer + Core logic — NO schema / migration** (every field/table/placement involved already exists). The four are unrelated but each small; do all four, in order. Verify with the standard build + package tests (below); put every new pure helper in `YesChefPackage` so its tests run in `check-drift`.

1. **Recipe yield/servings with a vulgar fraction doesn't scale (Core).** Symptom: a recipe whose amount is "2½ cups" (or "2 1/2 cups") never changes with the scalar, though ingredients scale fine. Two stacked bugs: (a) [`ServingParser.servings(from:)`](../YesChefPackage/Sources/YesChefCore/RecipeCore.swift) does `Double($0)` per space-split token, so "2½" → nil and "2 1/2" → a wrong `2.0` (drops the ½) — while `IngredientParser` (`IngredientParser.swift`, `vulgarFractions`/`mixedNumberValue`/`fractionValue`, ~lines 168–215) already parses these correctly; (b) the display path reformats the parsed number as **"N servings"** (`ScaleText.scaledServingsSummary`, `YesChefApp/RecipeScaleFormatting.swift`), which would lose the unit ("cups") even once it parses. **Fix:** extract `IngredientParser`'s fraction/mixed-number parsing into a **shared** Core helper both parsers call (don't duplicate), and add a pure `YesChefPackage` function that **scales the leading quantity in place inside the text, preserving the trailing unit words** ("2½ cups" → "5 cups"; keep the existing range handling: "4–6 servings" → "8–12 servings"). Wire the recipe metadata line + the "Makes" row (`RecipeDetailView.swift` ~502–514 and ~950) to use it. Scaling-from-text fixes **existing** recipes with no migration (their stored `Recipe.servings` Double stays nil). Keep the `ServingParser` Double fix too (it feeds `scaleSummary` and `nearestSelection`). **Tests (Core):** "2½ cups", "2 1/2 cups", "4 servings", "4-6 servings", plain "6", and a no-number string.

2. **Scalar range 10 → 30 (app).** Jon batches single-serving cocktails, so the multiplier must reach 30. Two sites, and they **must move together** or a >10× scale snaps back when the picker reopens: the wheel `ForEach(0...10)` at `RecipeDetailView.swift:920`, and the `for whole in 0...10` in `ScaleFraction.nearestSelection(to:)` at `RecipeScaleFormatting.swift:72`. Introduce **one shared constant** (e.g. `maximumWholeMultiplier = 30`) and use it in both. No other cap sites exist (grep confirmed). The scale picker is shared across recipe/menu-item/meal-plan via `ScaleContext`, so this covers all three.

3. **Grocery "Aisle" becomes a Picker (app).** The add/edit item form's free-text `StackedTextField(title: "Aisle")` (`GroceryViews.swift:823`) becomes a `Picker` over [`GroceryStoreArea.canonicalAreas`](../YesChefPackage/Sources/YesChefCore/GroceryStoreArea.swift) (display names). `aisle` stays a `String` on the item — the picker just writes the selected area's display name. **Keep any existing non-canonical `aisle` value selectable** (a "custom" row showing the current string) so old items don't lose their aisle on edit. App-layer only.

4. **Workbench "Archive All candidates" → "Move to Reference" (Core + app).** Jon wants curated-out candidates **placed as Reference, not archived**. In `WorkbenchRepository.archiveAllCandidates` (`WorkbenchRepository+DogfoodPolish.swift`) swap the per-candidate `RecipeRepository.archive(recipeID:…)` call for `RecipeRepository.setLibraryPlacement(.reference, recipeID:…)` (already exists, `RecipeCore.swift:474`); still remove the `WorkbenchCandidate` links after. Rename the function to match, and update the app: the `.archiveCandidates` destination/case (`WorkbenchModels.swift:99,148`), the "Archive All" button + `archivebox` icon (`WorkbenchViews.swift:455–457`), and the confirmation copy (`WorkbenchViews.swift:250`) → "Move to Reference." **Replace** Archive here (Jon's call — not both actions). Note-only candidates (no `recipeID`) skip, same as today. Reference placement is a per-recipe flag ([[reference-placement-and-original-provenance]]).

**Verify:** app-layer + Core — the architect's local `generic/platform=iOS` build is **required evidence**; also `scripts/check-drift.sh` (the #1 Core helper + tests run there). Confirm on device (Jon): a "2½ cups" recipe scales its yield; the multiplier wheel reaches 30 and a 25× scale persists on reopen; the grocery aisle field is a pulldown that preserves an existing custom aisle; the Workbench candidate action reads "Move to Reference" and lands the recipes in Reference (not Archived).

*(Separately in flight, NOT part of this dispatch: Codex is folding three cosmetic/robustness tweaks into the still-open PR #197 — overlay size-class gate, redundant material/separator, dead `MenuDetailInspector.title`. Re-run the `generic/platform=iOS` build gate on that tip before merge; then the DONE-LOG "prepared ahead" line comes off. Keep this batch on its own branch/PR, separate from #197.)*


**Feature efforts still on the board — Jon picks; do not infer:**
- **Recipe edit proposals S3** — the iterative refine loop + workbench-log deposit.
- **Workbench synthesis-shaped apply-action** — the draft verb's own action shape (no last-reply gate/chip).
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
**and the synced `learnings` table** (ADR-0038 Amd 1 / S3a) **and the synced `prepPlanSteps` table**
(ADR-0040 S2 — which also **retires the `Menu.prepPlan` BLOB**: restructure it *before* this cut, because
promotion locks the record type permanently); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

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
`recipeVariations` table + reader fold + grocery fold). **S3 queued** = the iterative refine loop +
workbench-log deposit (was gated behind the 2026-07-08/09 dogfood ADRs, now all shipped — so S3 is unblocked
whenever Jon picks it). Extends ADR-0021 (the variation destination) — do not duplicate it.

**Recipe Workbench** (ADR-0019 + `efforts/recipe-workbench.md`) — the store + curate + compare arc is
complete (S1–S4 all shipped → DONE-LOG). Remaining parked follow-ons in the effort doc: the
**synthesis-shaped apply-action** (the draft verb's own action shape — a distinct action enabled by workbench
state, no last-reply gate/chip; app-layer only, small, spec in the effort doc's "Out of scope" section — this
was the prior Next Up, demoted here, not yet built), plus AI effort/tier as a user-facing setting,
AI-generated log entries, and the S3 review notes.

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
menu note-item S1+S2 shipped in PR #178 → DONE-LOG; S3 is the remaining, separate slice). Comment ingestion
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
