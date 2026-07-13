# Current Handoff

Last updated: July 12, 2026. **🎉 iCloud sync works end-to-end across two physical devices** (`iPad Pro 13-inch (M5)`
↔ `iPhone 17 Pro`) — recipes, images, menus all round-trip; the M4 one-way gate everything preceded is
**crossed and holding** (logged in [`docs/DONE-LOG.md`](DONE-LOG.md); we stay in CloudKit **Development** by
design — prod-schema promotion is the held ops step below). **Two big things closed with it:**
**ADR-0028** (sync status-indicator accuracy — the "Up to date" indicator that lied mid-download; now shows
"Downloading changes from iCloud" via `SyncHealth.isFetchingChanges` + `SyncDisplayStatus.downloading`, on
main, device-passed) and **ADR-0029** (the UI-stall pass — archive/variation-switch took **5.6–6.8 s**; root
cause Finding 8 = `GroceryIngredientChoiceRequest`, an always-on whole-library `@Fetch` re-running
**synchronously on the writer inside every commit**; S7 fix made the grocery selection reads on-demand +
scoped, and **Jon device-confirmed writer-api-return dropped from ~5000 ms → tens of ms**; PRs
[#148](https://github.com/jonphillips/yes-chef/pull/148)/[#149](https://github.com/jonphillips/yes-chef/pull/149),
holds [[sqlitedata-fetch-writer-convoy]]; the S7 test `GroceryIngredientChoiceTests.swift` now rides in the
Chrome-polish slice commit).

**The 2026-07-11 dogfood batch is now fully cleared — all four efforts DONE.** Chrome & navigation polish,
Workbench dogfood polish, and the Meal-planner (Calendar) affordance swap
([#154](https://github.com/jonphillips/yes-chef/pull/154), architect-reviewed 2026-07-12; package builds +
tests pass; app build + device pass are Jon's), plus the **Fraction input accessory** (inline pill row,
architect-reviewed + **device-passed** 2026-07-12; on this branch, archived to DONE-LOG). **[ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md)
prep-plan work-session timeline S1 + S2 landed** ([#163](https://github.com/jonphillips/yes-chef/pull/163),
architect-reviewed 2026-07-12); **S3 (parse-robustness + clipboard) shipped**
([#164](https://github.com/jonphillips/yes-chef/pull/164), architect-reviewed 2026-07-12) — **S3c (enrich the
exported dish context: frontier budget + full method, ADR-0034 Amendment 1) remains in the Ready queue.**
**ADR-0035 grocery store-area grouping S1 is ready for review in [#172](https://github.com/jonphillips/yes-chef/pull/172)
(device pass owed), so Jon picks the next dispatch — do not infer.** The whole **ADR-0027 harvest + deposit family (base + Amendment 1) is now COMPLETE
and device-passed** (2026-07-12) — merged to main, archived to DONE-LOG; only the ADR's own deferred items
(OQ4 taste preference, A6 promote-note-to-recipe) remain, each a separate future effort.

**Grocery scaling bug — FIXED (architect-reviewed 2026-07-12, device pass owed to Jon).** Scaling a recipe /
menu item / meal-plan item never scaled the quantities added to the grocery list — generation and the
source-removal recompute both read raw `line.quantity`. Fixed in `GroceryCore.swift` with one
source-provenance-keyed `groceryScale` helper (priority `menuItem.scale → mealPlanItem.scale → recipe.viewScale`),
applied in both `GroceryGeneratedItemDraft` (scale 1 preserves fraction text byte-for-byte) and `generatedMeasure`;
free-text quantities left unscaled. New + updated tests in `GroceryTests`/`GroceryPlanningTests` (293 pass).
On branch `menu-within-day-reorder`, not yet PR'd.

Earlier and logged in [`docs/DONE-LOG.md`](DONE-LOG.md): **ADR-0027 "Capture to menu" S1**
([#141](https://github.com/jonphillips/yes-chef/pull/141)); **Instrumentation — apply-action + LLM logging**
([#139](https://github.com/jonphillips/yes-chef/pull/139)); **ADR-0026 review-collection sheet**
([#138](https://github.com/jonphillips/yes-chef/pull/138)); **the menu-planner dogfood quick-fixes bundle**
([#136](https://github.com/jonphillips/yes-chef/pull/136)); **ADR-0025 D6 + D7**
([#134](https://github.com/jonphillips/yes-chef/pull/134)); the **ADR-0025 curation revision**
([#131](https://github.com/jonphillips/yes-chef/pull/131)) + its same-day curation/capture companion
([#132](https://github.com/jonphillips/yes-chef/pull/132)); **ADR-0024 fully done**
([#127](https://github.com/jonphillips/yes-chef/pull/127)/[#128](https://github.com/jonphillips/yes-chef/pull/128));
**Dogfood batch 5** ([#126](https://github.com/jonphillips/yes-chef/pull/126)); **ADR-0025 scaffolding**
([#129](https://github.com/jonphillips/yes-chef/pull/129)); **Recipe edit proposals S1/S2**
([#122](https://github.com/jonphillips/yes-chef/pull/122)/[#123](https://github.com/jonphillips/yes-chef/pull/123));
the **LLM-aligned Compare matrix** (ADR-0022, [#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120)),
**Compare-key granularity** ([#114](https://github.com/jonphillips/yes-chef/pull/114)), and the **Workbench
build arc S1–S4** ([#101](https://github.com/jonphillips/yes-chef/pull/101)–[#113](https://github.com/jonphillips/yes-chef/pull/113)).

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

**No live dispatch target — ADR-0035 S1 is ready for review in [#172](https://github.com/jonphillips/yes-chef/pull/172).**
Jon picks the next effort from the Ready queue; a fresh dispatch must **STOP and ask Jon** — never
infer the next task. S1 adds the deterministic seed, normalizer, dedicated-migration backfill, and store-ordered “To Buy”
sections; it has **no model and no schema change**. Its categorization only places items; it never invents or merges list data
([[llm-vs-determinism-surface-boundary]]).

**ADR-0035 device pass owed (Jon):** generate a grocery list from a multi-recipe menu, confirm items land in the
right departments in store-walk order, and confirm a hand-set aisle survives regeneration. Purchased remains a
flat crossed-off tail.

**Design forks — decide with Jon, not a Codex dispatch** (parked in `docs/open-questions.md`, 2026-07-11):
edit-a-variation, promote-variation-to-standalone, and the umbrella **variation-workspace ↔ Workbench overlap**
question Jon flagged twice this pass. Future ADR (0014 × 0021 × 0019/0023 territory), not built yet.

**Feature efforts still on the board — Jon picks; do not infer.** Lower priority than the dogfood batch above:
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
synced `recipeVariations` table (Recipe edit proposals S2); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**[ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) S3c — enrich the exported dish context
(Amendment 1).** *Was Next Up; displaced 2026-07-12 by the dogfood grocery pick, not dropped — promote back
when Jon chooses.* Make the menu "Copy Dish Context" button a self-contained **frontier** prompt: serialize at
`.frontier` budget, thread full recipe **method** into `MenuChatItemContext` (with `InstructionSection`
sub-headers, a method-first trim rung on the on-device path), **uncap ingredients** on the frontier path (8 stays
the on-device starting ceiling only), and **prepend a real intro prompt** (adapted `MenuPrepPlanClient.instructions`
+ `tasteProfile`/`makeAheadPrepPlanPreference` via `aiPromptPreferences`) that asks for the **review-text** output
format (not strict JSON) so ChatGPT's answer pastes back cleanly; rename button → **"Copy Prep Prompt"**. Do
**not** touch the meal-calendar per-day make-ahead-strategy verb. Full spec: ADR-0034 Amendment 1. Verify: package
build + `MenuChatContext`/`MenuPrepPlan` tests + `check-drift.sh`; one iPad app build (no new source files → no
`xcodegen`). (Per Jon, this one's handoff bump + the ADR Amendment ride in their own doc PR.)

**Dogfood 2026-07-12 — trip-prep pass (3 items triaged, written up 2026-07-12; Jon picks order, none dispatched).**
- **Grocery list by store area** — [ADR-0035](decisions/ADR-0035-grocery-store-area-grouping.md) (**Accepted**;
  **S1 ready for review in [#172](https://github.com/jonphillips/yes-chef/pull/172); device pass owed — see Next Up**).
  The existing synced `GroceryItem.aisle` column now receives a deterministic seed and the flat “To Buy” list
  groups by store area; no migration. **S2 = on-device long-tail classifier**, queued after S1 reads well on
  device. OQ1 resolved 2026-07-12: store-walk order fixed to Jon's 13 areas (perishables last); seed mapping
  contents remain incrementally editable.
- **Promote a note → a real recipe** — [ADR-0036](decisions/ADR-0036-promote-note-to-recipe.md). Formalizes
  ADR-0027 D5/A6. Parse recipe-shaped note prose → `WorkbenchDraftRecipe` → ADR-0024 review → real `Recipe`
  (reuses web-capture parse + editable-proposal surface). Real design work is **placement + provenance**.
  **OQ1 resolved 2026-07-12:** scope is a **menu note-item** in recipe shape → S1 library commit, S2 swaps
  the note-item for a recipe-kind menu item. The "just add notes to grocery" alternative was rejected as a
  trap (secretly the same parse, none of the reuse).
- **Menu note-item truncation** — [`efforts/menu-note-truncation.md`](efforts/menu-note-truncation.md).
  One-line `.lineLimit(5)` at `MenuDetailSections.swift` ~272. Trivial free rider — bundle into any adjacent
  menu/list dispatch.

**Dogfood 2026-07-11 — two-device pass. BATCH CLEARED — all four efforts DONE → [`docs/DONE-LOG.md`](DONE-LOG.md).**
- **Fraction input accessory** — inline pill row, full glyph set ¼ ½ ¾ ⅓ ⅔ ⅛ ⅜ ⅝ ⅞; **DONE + device-passed**
  2026-07-12 (this branch).
- Chrome & navigation polish, Workbench dogfood polish, and the Meal-planner affordance swap
  ([#154](https://github.com/jonphillips/yes-chef/pull/154)) are **DONE** (all three owe Jon's device pass).
  Parked follow-ons (Beta 3 drag-and-drop retest + cell images) stay in the meal-planner effort doc.
- Design forks (edit-variation, promote-variation, variation ↔ Workbench overlap) → `docs/open-questions.md`.

**Recently completed → all archived in [`docs/DONE-LOG.md`](DONE-LOG.md).** ADR-0033 recipe-detail polish
(metadata chips + servings-attached scaler + toolbar-scaler crash fix, [#160](https://github.com/jonphillips/yes-chef/pull/160),
device pass owed to Jon); ADR-0027 harvest + deposit family
(base + Amendment 1, COMPLETE + device-passed 2026-07-12); ADR-0026 review-collection sheet (#138, device pass
owed — see Next Up); ADR-0025 reader-comment ingestion (effort closed, #129/#131/#134); ADR-0024 editable
proposal preview (S1 #127 + S2); the menu-planner-dogfood-2026-07-09 quick-fixes bundle (#136); and the
apply-action + LLM logging instrumentation (#139). **Still-deferred, separate future efforts** (not follow-through
on any of the above): ADR-0027 **OQ4** (a note-worthiness taste preference) and **A6/D5** (promote-a-note → a real
recipe — placement + provenance).

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

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — **UNBLOCKED / underway.** Sync now round-trips end-to-end
  across `iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro` (see top). The 2026-07-11 pass is the first real
  multi-device dogfood and produced the batch now in **Next Up**; the gaps found there choose the next
  milestone after the batch clears.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

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
