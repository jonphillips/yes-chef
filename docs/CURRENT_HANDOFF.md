# Current Handoff

Last updated: July 14, 2026 (ADR-0038 **S3b** shipped PR #185 → DONE-LOG; Next Up = **ADR-0038 S3c** — the in-app handoff door for Recipe + MealPlan, per Amendment 2).

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

**Live dispatch target — [ADR-0038 Amendment 2](decisions/ADR-0038-external-llm-handoff.md) External-LLM
handoff, S3c** ([`efforts/adr-0038-external-llm-handoff.md`](efforts/adr-0038-external-llm-handoff.md)).
**Give Recipe + MealPlan an in-app handoff door.** S3b (PR #185 → DONE-LOG) shipped the two-part contract for
those two sources, but **intent-only** — the sole entry point is a hand-built Shortcut running the *Immediate*
autopilot, which discards the discussion that is the point of a make-ahead hand-off (the dogfood finding behind
Amendment 2). S3c makes an in-app door the **primary** path; the App Intent stays the hands-free bonus (D4,
amended). **App-layer only — no core / schema / migration:**

- **In-app Copy-Prompt / Paste-Result** on `RecipeDetailView` and the meal-plan day view, mirroring Menu's
  `Copy Prep Prompt` / `Paste Prep Plan` (`MenuViews.swift`) — **discuss-first**. Copy emits the S3b tokenized
  prompt (`YC-HANDOFF:` header + the source's `DeliverableFormat`); Paste feeds
  `AIHandoffIntentImport.stageReview` → the review sheet.
- **Route the paste through the review sheet** (editable-at-grain, lossless-or-loud, Learnings ride along) —
  strictly better than Menu's older direct-write manual path; **opportunistically move Menu's buttons onto the
  same review-routed path** while here.
- **Secondary:** register an `AppShortcut` so export/import reach Action Button / Spotlight / Siri without a
  hand-built shortcut.
- **Defer** per-section prompt checkboxes (add only if the default make-ahead context proves wrong); the
  `Ask ChatGPT` double-fire is a Shortcuts / ChatGPT-action app-switch artifact, not ours.

**Then [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md)** (the Playbook column) —
milestone-sized, Jon-gated, a **design conversation, not a Codex dispatch**. The learnings corpus is now real
and editable; design the Playbook once it has content to hold.

**Deferred — [ADR-0040 S3](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md), the lossless-or-**loud**
pass** (not yet queued; fold in when a handoff/paste slice is already open). Two known **silent** paths remain:
(1) a learning/step edit saves with **no confirmation** — it just appears or doesn't; (2) "Paste Prep Plan"
**silently no-ops** on an empty clipboard or a missed iOS *Allow Paste* prompt (`MenuViews.swift`
`pastePrepPlanButtonTapped`, `guard let text … else { return }`). Every import path should end in a visible
outcome.

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
