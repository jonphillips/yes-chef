# Current Handoff

Last updated: July 15, 2026 (ADR-0039 **D3** — the "Ask" chat demotion — architect-approved, app-build-gate **green** (architect's local `generic/platform=iOS` → BUILD SUCCEEDED), Jon device-pass + merge pending, PR #190. The wide recipe `ChatWorkspaceSplit` + draggable divider are **retired** and the Playbook header now owns both AI tiers — the doubled-up AI column from the D1/D2 intermediate state is gone. Next Up = **ADR-0039 D3 follow-on** — build the *true* "Ask" slide-over (Amendment 1; D3 shipped it as the reused sheet) with the two PR-#190 review-polish notes folded in).

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

**Live dispatch target — [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md) D3 follow-on — the
*true* "Ask" slide-over + Playbook-header polish.** D3 (PR #190) demoted the in-app chat and retired the wide
`ChatWorkspaceSplit` + draggable divider, but shipped "Ask" by **reusing the existing recipe-scoped `.sheet`**
(`model.chatButtonTapped` → `.sheet(item: $model.destination.chat)`).
[ADR-0039 Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#L59) specifies "Ask" as **a true
slide-over, decoupled from any resize bar** — an edge-anchored companion panel, not a modal bottom sheet. This
slice builds that presentation and folds in the two PR-#190 review notes. **App-layer — no schema/migration
expected.**

**What this slice does:**
- **Build the true slide-over for "Ask" on wide iPad.** Replace the reused `.sheet` with an edge-anchored
  slide-over companion so Ask reads as the lightweight, non-blocking "quick one" the ADR calls for (it should not
  dim/steal the reader the way a modal sheet does). Keep the plain sheet on **compact**, where a side slide-over
  has no room. The Playbook-header **Ask** button is already wired (`model.chatButtonTapped`); this is a
  presentation change, not a new entry point. Leave the exact panel mechanics to the device pass — the bar is
  "companion, not modal."
- **Fold in — PR #190 review notes (both cosmetic, App-layer):**
  1. **PasteButton styling** — `pasteResultButton` (`YesChefApp/RecipePlaybookView.swift:106`) has no
     `buttonStyle` while its header siblings are `.borderedProminent` (handoff) / `.bordered` (Ask); the retired
     `HandoffCopyPasteControls` group was uniformly `.bordered`. Give the PasteButton a matching style so the
     header reads as one control cluster.
  2. **"Playbook" vs "Plan" heading** — the new `.title.bold()` "Playbook" title
     (`YesChefApp/RecipePlaybookView.swift:65`) sits directly under a segmented control labeled "Playbook"
     (compact) / "Plan" (wide): mild redundancy in compact, a Plan/Playbook mismatch in wide. Resolve by dropping
     the in-view title **or** aligning the wide segment label — decide which reads better on device.

**Verification:** App-layer SwiftUI — the architect's local `generic/platform=iOS` build is **required evidence**
(see Verification Pattern; D1/D2 shipped 4 compile errors past `check-drift.sh` because it compiles only the
package — [[codex-build-excuse-reproduce]]).

**Queued behind it — the remaining ADR-0039 UI slice (its own Jon-gated dispatch):**
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
