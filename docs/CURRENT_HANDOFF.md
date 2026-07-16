# Current Handoff

Last updated: July 16, 2026 (ADR-0039 **Amendment 2 Slice B** — the resizable recipe **Playbook column**: wide iPad now three co-visible (Ingredients + Directions + Playbook), wide Cook/Plan toggle retired; Playbook width = toolbar show/hide + drag-snap detents (Peek/Comfortable/Wide) + persist via `@AppStorage`, with a `w/3` Directions floor; new `RecipePlaybookColumnLayout.swift` mirroring the `RecipeChatWorkspace` resize affordance — architect-approved, app-build-gate **green** (architect local `generic/platform=iOS` → BUILD SUCCEEDED), Jon device-pass **pending**, PR #194. One review finding carried into Slice C (not fixed on-branch): the Show/Hide toolbar toggle is gated on `isSplitEnabled` but the columns on detail-pane width ≥ 640, so the button is a dead control when the sidebar narrows the pane; Slice C rebuilds that region and re-gates it. Next Up = **ADR-0039 Amendment 2 Slice C** — the recipe header **nests beside Ingredients** (the real Paprika composition), correcting Slice A's full-width band. **Slice D (menu adopts the column — the old "Slice C," renumbered) stays parked.**)

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

**Live dispatch target — [ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column) Slice C — the recipe header nests beside Ingredients (the real Paprika composition).** Corrects Slice A's full-width band; the *third* Amendment 2 dispatch (A + B shipped → DONE-LOG; **D = menu adopts the Playbook column — do NOT start D**; D is the old "Slice C," renumbered when this header correction was inserted). **App-layer only — no schema / migration** (pure view composition; Slice B's `@AppStorage` keys untouched). Read the ADR's *"Recipe header (Slice C): nests beside Ingredients"* section — it is the spec; the below is the surgical map.

**Kill the full-width band.** In `RecipeReaderView.body`'s two-column branch (`RecipeDetailView.swift:264`), drop the outer `VStack` that stacks the `header`/`metadata` band + `Divider` above `wideRecipeColumns(in:)` (~lines 269–279). The two-column reader becomes just the three columns filling full height.

**Header nests at the top of the Directions column only.** Move the `header(recipe)` + `metadata(recipe)` composition inside the Directions `ScrollView`, above `directionsColumn`, spanning the Directions width and scrolling with it. **Not** Directions + Playbook — Directions-only keeps identity + method together and lets the Playbook stay top-anchored (Jon's chosen fork). Ingredients + Playbook both rise to the top edge — no strip above them.

**Cheat Ingredients narrower.** Drop `RecipeWideColumnLayout.contentColumnFraction` below ⅓ (`RecipePlaybookColumnLayout.swift`) — a **device knob, not a decided point width**. The Directions-floor + max-Playbook math keys off this fraction, so **verify the three columns still reconcile at the Wide detent** after narrowing (narrower Ingredients → wider Directions floor + Playbook max).

**Photo grows into the taller header box.** Beside a full-height Ingredients column the header box can be taller than the band allowed — size the cover photo up past its band thumbnail (`HeaderMetrics`, `RecipeDetailView.swift`). A **deliberate** departure from Paprika's stamp thumbnail, recorded in the ADR so it doesn't later read as drift.

**Fold in the Slice B review finding (same region).** Re-gate the **Show/Hide Playbook** toolbar button on the real two-column width signal instead of `isSplitEnabled` (`RecipeDetailView.swift:137`). Today it shows whenever iPad + non-compact, but the columns only render at detail-pane width ≥ 640 — so with the sidebar narrowing the pane the toggle is a dead control. Thread the two-column decision up to the toolbar, or move the toggle into the reader where the geometry lives.

**Compact is unchanged.** The `compactRecipeBody` segmented picker keeps its own header/metadata stack; this slice only touches the wide two-column branch. Ask + Browse stay `.inspector` slide-overs on top — the Playbook is the one *structural* column.

**Verify:** app-layer SwiftUI — the architect's local `generic/platform=iOS` build is **required evidence**. Confirm on wide iPad: no band, header nested at the top of Directions, all three columns rising to the ceiling; Ingredients visibly narrower; the cover photo larger; the toolbar toggle present *only* when the three columns actually render. **Watch the header at the Wide Playbook detent** — Directions hits its floor and the nested header gets tight; confirm it still reads (the fallback is a scale-with-width header, **not** a return to the band). Header legibility-at-Wide, exact Ingredients width, and photo size are **Jon's device-pass calls — flag them, don't hard-decide.**


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
