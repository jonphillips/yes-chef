# Current Handoff

Last updated: July 14, 2026 (ADR-0038 **S3a** approved PR #183 → DONE-LOG; Next Up = **ADR-0040 S1 + S2** — make LLM-populated content editable at row grain: the Learnings surface, then prep-plan BLOB → step rows, *before* the prod-schema cut locks the blob and *before* S3b scales the writers).

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

**Live dispatch target — [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md), S1 + S2
(one PR, in order).** **Make LLM-populated content editable by the human who has to live with it.** The prep
plan today is **all-or-nothing**: `Menu.prepPlan` is a BLOB, so there is no *step 3* to delete, no step to add,
no typo to fix — the only way to change it is to make the LLM regenerate the whole thing. That is a **schema
defect wearing a missing-button costume**, and ADR-0038 S3a just shipped a second table (`learnings`) that
nobody can read. Both get fixed here, and **both get fixed before [ADR-0038 S3b](decisions/ADR-0038-external-llm-handoff.md)**
adds two more sources writing LLM content into more fields.

**Read [ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) first — its two rules govern every
line below:** (1) store LLM output at **the grain the human will manipulate** (a row with an id, never an
element inside a blob); (2) **the human never authors the serialization format**, and any text we do parse is
**lossless or loud** — never silently dropped.

**S1 — the Learnings surface** (the ADR-0038 S3a follow-on; see
[`efforts/adr-0038-external-llm-handoff.md`](efforts/adr-0038-external-llm-handoff.md)).

- **Read.** A **Learnings** section on the menu detail (`YesChefApp/MenuViews.swift`, alongside
  `MenuPrepPlanSection`), this menu's learnings newest-first. Fetch **scoped to the menu** — extend
  `MenuDetailQuery`/`MenuDetailData` (`MenuCore.swift:18`/`:101`), already a per-menu `@Fetch`. **Never a
  whole-library `@Fetch`** — [[sqlitedata-fetch-writer-convoy]] (ADR-0029 Finding 8) cost us a week.
- **Delete one.** Swipe-to-delete a single learning; `LearningRepository` has `create`/`deleteAll` only, so add
  `delete(id:)`. This is the slice's reason to exist — today a bad learning is **synced and unremovable**
  except by deleting the whole menu.
- **Edit one.** Inline text edit → write `dateModified`; **leave `provenance` alone** (it records origin; a
  human touch-up does not make an externally-returned learning in-app-authored).
- **No new AI, prompt, or commit path** — the S3a review sheet stays the only writer.

**S2 — prep plan → step rows** (ADR-0040 D1/D4; reshapes [ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md)'s
storage, **not** its model).

- **Migrate** the `Menu.prepPlan` BLOB → a synced **`prepPlanSteps`** table (`id`, `menuID`, `sortOrder`,
  `session`, `task`, `serves`, `sourceDish`), decoding existing blobs per menu (the ADR-0034 `when`→`session`
  back-compat decode already exists). Unlike `learnings`, this **is** a real child of `Menu` → give it a
  proper **FK + cascade delete** (multi-FK does not block sync — [[sqlitedata-single-fk-sync-limit]]).
  **Add `prepPlanSteps` to the standing prod-schema promotion list below.**
- **Edit at row grain:** add / edit / delete / **reorder** a step, via a `PrepPlanStepRepository`.
- **The human edits fields, not the wire format** (D2): task + serves fields and a **session picker** drawn
  from an explicit band vocabulary — no typing colons, no typing the `→` (a character Jon cannot reliably
  type), no guessing which heading words land a step in the Flexible band (today that is sniffed from prose:
  `MenuViews.swift:491`). `applyingEditableReviewText` survives **only as an inbound parser**; it stops being
  the storage round-trip.
- **⚠️ Kill the silent-loss paths** (D3): today an unparseable line is `continue`d away, a bullet before any
  session header is dropped, and `sourceDish` is re-attached by **matching task text** — so editing a task's
  wording silently severs its recipe link. Rows carry `sourceDish` by identity; leftover text is surfaced,
  never swallowed.
- **Why now:** `Menu.prepPlan` is on the prod-promotion list but **not promoted**, and promotion is
  additive-only and **permanently locks the record type**. This restructuring is **free today, expensive
  forever** after the first prod/TestFlight cut (ADR-0040 D4).

**Then [ADR-0038 S3b](efforts/adr-0038-external-llm-handoff.md)** (generalize the serializer to Recipe +
MealPlan; recipe → `Recipe.makeAhead`, meal-plan → make-ahead strategy — classify each commit shape first per
[[chat-verb-commit-shapes]]; Learnings ride free on the S3a machinery). Sequenced **after** the above on
purpose: it should inherit editable-at-grain, not add three more places that need retrofitting.

**Then [ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md)** (the Playbook column) —
milestone-sized, Jon-gated, a **design conversation, not a Codex dispatch**. S1 is its evidence-gatherer: design
the Playbook once a real corpus of learnings exists to hold, in a shape the human can already fix.

**ADR-0038 S3a device pass owed (Jon):** the two-item review sheet (prep plan + learnings, each independently
savable/discardable), and a learning-only return through **both** paths — the Shortcuts `Import Handoff Result`
intent *and* the in-app paste box.

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
