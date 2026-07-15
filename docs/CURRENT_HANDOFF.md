# Current Handoff

Last updated: July 15, 2026 (ADR-0040 **S3** — lossless-or-**loud** surface-outcomes pass — architect-approved, app-build-gate **green**, PR #187 (device-pass + merge pending, Jon); Next Up = **ADR-0039 D5** — the prep-plan *tasks-never-choreography* prompt amendment, the smallest-first opening slice of the now-designed Playbook milestone).

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

**Live dispatch target — [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md) D5, the
prep-plan *tasks-never-choreography* prompt amendment.** ADR-0039's design is **complete** (Amendment 1,
2026-07-15, resolved OQ1–OQ4 + corrected the recipe framing), so the milestone moves from design conversation
to build — **smallest-first**. This opening slice is **Core-only — no app / schema / migration** (so Codex can
actually build *and* test it; keep pure prompt/parse logic in the package per the Verification Pattern below).

**D5 — the prep plan holds tasks, never choreography.** Amend the prep-plan generation prompt contract so the
model emits **separable, atomic, context-free tasks** ("Salt the chicken Wednesday", "Pull the beef to temp at
4") and **never choreography** — interleaved cross-recipe cooking instructions ("sear the beef while the salad
rests"). Choreography strips the recipe context the cook actually reasons with, so it will never be trusted;
generating it is noise that buries the tasks that *are* trustworthy. The recipes hold the cooking; the prep
plan must never become a merged mega-recipe. See ADR-0039 §D5 +
[ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md).

- **Primary contract:** `MenuPrepPlan.instructions`
  (`YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift:293`) — today it instructs the model to "invent
  grounded **sequencing**, work sessions, and new prep steps." Tighten toward atomic tasks and drop the
  invitation to weave cross-dish sequencing; preserve the existing JSON shape (`session`/`task`/`serves`/
  `sourceDish`) and the "compose from stored Make-Ahead notes" behavior.
- **Sibling contract:** `MealPlanMakeAheadStrategy.instructions`
  (`YesChefPackage/Sources/YesChefCore/MealPlanMakeAheadStrategy.swift:183`) — apply the same
  tasks-never-choreography constraint so the meal-plan variant doesn't drift.
- **Test in Core.** Assert the constraint in the package suite (this is exactly why the logic lives in
  `YesChefPackage`, not the app layer).

**Queued behind it — the ADR-0039 UI slices (each its own Jon-gated dispatch, in likely order):**
- **Recipe Playbook region** (D1/D2/OQ1/OQ2) — the anchor: Playbook as a **third peer region** (compact = a
  third `CompactSection` picker segment in `RecipeDetailView.swift`; wide iPad = a Cook/Plan toggle with
  Ingredients pinned as a ⅓ anchor, retiring the manual `ChatWorkspaceDivider`). **Full-move** make-ahead +
  notes + Chef It Up + Serve With out of `directionsColumn`; collapsible sections with filled/empty content
  indicators. A first brick already landed (the persistent Make-ahead header, PR #186).
- **"Ask" slide-over + chat demotion** (D3) — the in-app chat becomes the secondary "quick one" slide-over;
  "Hand off to ChatGPT" is the primary affordance; the draggable divider's old reader-vs-chat job retires.
- **Menu launcher mode** (D4/OQ3) — delete the menu's third column, foreground the dish list with collapsible
  days (collapsed by default once the service date is today-or-past), collapse the prep plan near service.

**Design forks — decide with Jon, not a Codex dispatch** (parked in `docs/open-questions.md`, 2026-07-11):
edit-a-variation, promote-variation-to-standalone, and the umbrella **variation-workspace ↔ Workbench overlap**
question Jon flagged twice this pass. Future ADR (0014 × 0021 × 0019/0023 territory), not built yet.

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
- Otherwise attempt the app build **once** with no simulator or signing identity:
  `xcodebuild -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- Run `scripts/check-drift.sh`.
- **The app-target build is the *architect's* gate, not Codex's — a green package `swift build` is NOT
  evidence the app compiles.** Codex's environment cannot reliably run the generic build (it SIGTERMs — exit
  143 — with "CoreSimulator unavailable": no working CoreSimulator subsystem to enumerate destinations against,
  and/or a cold-build timeout). This slipped **three** uncompiled PRs through (#183, #184, #185); the earlier
  "just mandate the generic build" fix did not hold because Codex *can't execute it*. So: Codex attempts it
  once and **pastes the exact error** (incl. the 143/CoreSimulator failure) into the PR — that failure is
  expected and does **not** block handoff — and **the architect runs the generic build locally before
  approving any PR touching `YesChefApp/`.** A warm build is ~1 min; cold ~3 min.
- **Corollary — keep pure logic out of the App layer.** String formatting, serialization, and parsing belong
  in `YesChefPackage` (which Codex *can* compile and test), not in `YesChefApp/`. #185's build break was
  `HandoffIntents.swift` calling `date: .full` (invalid `Date.FormatStyle.DateStyle`) — logic that belongs in
  `MealPlanHandoffContext` in Core, where the package build would have caught it instantly.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.
- **Fail fast — one build attempt, then stop.** Xcode/toolchain trouble is never a reason to retry with
  alternate incantations. Make the generic build attempt once; if it fails, paste the error and stop — do
  not try to repair the toolchain. Device install is Jon's pass, not a Codex grind.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
