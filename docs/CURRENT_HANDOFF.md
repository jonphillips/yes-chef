# Current Handoff

Last updated: July 14, 2026 (ADR-0038 S2 shipped PR #180 → DONE-LOG; Next Up = ADR-0038 **S3a**, the Amendment 1 two-part return contract, proven on Menu).

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

**Live dispatch target — [ADR-0038 Amendment 1](decisions/ADR-0038-external-llm-handoff.md) External-LLM
handoff, S3a** ([`efforts/adr-0038-external-llm-handoff.md`](efforts/adr-0038-external-llm-handoff.md)).
**The two-part return contract, proven on Menu.** S2 (PR #180 → DONE-LOG) shipped the loop and immediately
exposed the gap: a rich multi-turn session collapses to a **context-free deliverable** — the *reasoning* dies
in ChatGPT. Amendment 1 makes the return **`(Deliverable?, Learnings?)`, either may be empty**. Build, on
**Menu only** (its serializer already exists — **no new outbound work**; Recipe/MealPlan serializers are S3b):

- **Prompt (both modes).** After the deliverable, ask for a **Learnings** section introduced by a
  **`YC-LEARNINGS:`** marker line (mirrors the `YC-HANDOFF:` convention): durable knowledge established in
  discussion (*"dried bay leaves beat fresh, and you can dry your own"*). Learnings come back as a
  **structured list of distinct bullets — never a merged blob summary** ([[llm-curation-not-synthesis]]).
  The model curates its own conversation; we are not preserving a transcript.
- **⚠️ Parse: split BEFORE you parse.** `isEditablePrepPlanSessionHeader` (`MenuPrepPlan.swift:352`) treats
  **any non-bullet, colon-terminated line** as a prep-plan session header — so handing `YC-LEARNINGS:` to
  `applyingEditableReviewText` would **swallow it as a prep band** and turn every learning into a prep step.
  Therefore: strip the token → **split the body on the `YC-LEARNINGS:` marker** → feed *only* the deliverable
  half to `applyingEditableReviewText`; parse the learnings half as bullets. No marker → whole body is the
  deliverable (today's behavior, unchanged). Marker with nothing above it → a **learning-only** return.
- **Commit — new synced `Learning` table** (decided with Jon 2026-07-14; see Amendment 1 for why *not*
  `Menu.notes` (blob), *not* day-scoped `MenuItem` note-rows, *not* `AIHandoff` (device-local)). Deliverable →
  `Menu.prepPlan` (existing path). Shape, **plain text to start**: `id: UUID`, `sourceType` (reuse
  `AIHandoffSourceType`), `sourceID: UUID`, `text: String`, `provenance` (`.externalHandoff`/`.inApp`),
  `dateCreated`, `dateModified`. **Additive + synced** → add `Learning.self` to `makeSyncEngine`'s table list
  (and the `CloudSyncTests` guard), and **add `learnings` to the standing prod-schema promotion list below**.
  **Two non-obvious consequences:** (1) `(sourceType, sourceID)` is **polymorphic → no FK → no cascade
  delete**; deleting a menu would orphan its Learnings as *synced* ghosts, so **hand-cascade in
  `MenuRepository`'s delete path**. (2) **No FK back to `AIHandoff`** (device-local — it would dangle on the
  other device); provenance is a **marker, never a link**.
- **Review.** `RecipeCollectionReviewSheet` already takes `items: [ChatApplyReviewItem]`; `HandoffReviewSheet`
  currently passes **one**. Pass **two** — Deliverable and Learnings — each independently editable and
  discardable (ADR-0024/0026: human is final author of both).
- **Learning-only is first-class.** A return with **no** deliverable is valid, not an error. Concretely:
  `AIHandoffIntentImport.stageMenuPrepPlanReview` currently throws `.emptyPlan` when `plan.steps.isEmpty` —
  that guard must relax to "empty deliverable **and** empty Learnings = error." Add the learning-only
  `taskType`.

**Bundle the [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md) D5 prompt fix** — cohesive
(same prompt): instruct the model to emit **tasks, never choreography**. A task is separable/atomic/
context-free ("salt the chicken Wednesday"); **choreography** is cooking instructions interleaved across
several recipes ("sear the beef while the salad rests"), which strips the recipe context Jon reasons with and
will never be trusted. **The prep plan must never become a merged mega-recipe** — the recipes hold the cooking.
Don't generate what won't be trusted; this makes the plan smaller and sharper. See
[[automation-decays-near-the-stove]].

**S3b** (generalize the serializer to Recipe + MealPlan; each gains its deliverable shape, Learnings ride free
on the S3a machinery) follows. **ADR-0039** (the Playbook column) is milestone-sized, Jon-gated, and
deliberately *not* queued here — design it once S3a gives it real content to hold.

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
**and the synced `learnings` table** (ADR-0038 Amd 1 / S3a); and note the app target
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
- Otherwise build `YesChef` **once** for `iPad Pro 13-inch (M5) (16GB)` (`-skipMacroValidation`).
- Run `scripts/check-drift.sh`.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.
- **Fail fast — one build attempt, then stop.** A simulator that won't boot/install, or any
  Xcode/toolchain trouble, is **never** a reason to retry with alternate incantations. Make one
  attempt; if it fails, paste the error and stop — do not try to repair the toolchain or the sim.
  That is Jon's device pass, not a Codex grind.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
