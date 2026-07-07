# Current Handoff

Last updated: July 7, 2026 (**Next Up = Recipe edit proposals — Slice 1**, the "Adjust this recipe" verb,
ADR-0023). Recently completed and moved to [`docs/DONE-LOG.md`](DONE-LOG.md): the **LLM-aligned Compare
matrix** (ADR-0022, now Accepted — shipped S1–S4 + the Compare→chat affordance,
[#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120)),
**Compare-key granularity** ([#114](https://github.com/jonphillips/yes-chef/pull/114)), and **Workbench S4 —
Compare** ([#113](https://github.com/jonphillips/yes-chef/pull/113), completing the Workbench build arc
S1–S4). Earlier, also in DONE-LOG: Workbench S3 durable log
([#110](https://github.com/jonphillips/yes-chef/pull/110)), Workbench S2 + dogfood-hardening
([#107](https://github.com/jonphillips/yes-chef/pull/107)), chat controls
([#105](https://github.com/jonphillips/yes-chef/pull/105)), Workbench S1 + grounding fix/polish
([#101](https://github.com/jonphillips/yes-chef/pull/101) / [#103](https://github.com/jonphillips/yes-chef/pull/103)),
and the menu-planning overhaul ([#98](https://github.com/jonphillips/yes-chef/pull/98)).

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

**Recipe edit proposals — Slice 1: the "Adjust this recipe" verb (preview + side-by-side review + overwrite;
schema-free).** Implements [ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S1. **Read before
starting:** ADR-0023 in full (vocabulary banner + D1–D6 are load-bearing) and
[`efforts/recipe-edit-proposals.md`](efforts/recipe-edit-proposals.md) (the S1 reuse map + out-of-scope);
skim [ADR-0021](decisions/ADR-0021-recipe-variations.md) D2 for the delta op vocabulary this reuses.

*Why:* no chat verb anywhere edits a recipe's **canonical** ingredients/method — Make-ahead, Chef-It-Up, and
Serve-With each write an additive **sidecar section** (`RecipeDetailModel+Enrichment.swift`), and the
workbench draft only ever *creates* a recipe. This is the first canonical-edit verb, made safe by
construction: the model writes only to a transient preview, never to a stored recipe, until a human tap.

*Build (S1 is schema-free — no migration, no synced column):*
- **`.adjustRecipe` apply-action** on `RecipeDetailModel.applyActionCatalog`
  (`RecipeDetailModel+Enrichment.swift`, sibling of the make-ahead/chef-it-up/serve-with actions). Because it
  lives on the recipe reader it lands on **every recipe and the workbench working recipe** at once
  (ADR-0023 D1) — not workbench-gated.
- **Delta extractor** — a new LLM client mirroring `WorkbenchDraftRecipeClient` (`WorkbenchDraftRecipe.swift`:
  system prompt + strict-JSON parse). It emits a **structured delta** in ADR-0021 D2's closed op vocabulary
  (`add`/`remove`/`substitute`/`scale` for ingredients; a prose method note / whole-step text replacement for
  method) — **not** a whole-recipe blob (ADR-0023 D4). `high` effort (ADR-0017); generous `maxTokens` that
  budgets reasoning **and** output, throwing on truncation, not returning an empty delta
  ([[reasoning-budget-starves-output]] — the draft verb's `ModelResponse.wasTruncated` in
  `ModelResponse+Truncation.swift` is the pattern). Hold [[llm-curation-not-synthesis]]: distinct ops, never a
  re-blended recipe.
- **Ephemeral proposal store** — transient, **device-local, SyncEngine-excluded** (ADR-0015 precedent, same
  live-schema audit test that excludes chat). Discarded on dismiss; nothing persists until a commit tap
  (ADR-0023 D2).
- **Side-by-side review view** — reuse `WorkbenchCompareCore` canonical-name alignment + the two-column
  `WorkbenchCompareView`, pointed at *(current recipe, proposed recipe)* instead of *(working recipe,
  candidates)*. Ingredients diff **structurally** (added/removed/substituted read as aligned rows + blanks);
  method shows as a **prose before/after** (no structural per-step merge — ADR-0023 D3/OQ1, holds the ADR-0016
  line). Full-screen cover on iPad via the `.detailOnly` focus pattern; sheet on iPhone.
- **Commit = overwrite-in-place** through the existing structured-editor update (ADR-0004), **after** stashing
  a **pre-edit restore point** for a one-level undo (ADR-0023 D5). Reuse the `RecipeBundleCoding` snapshot
  codec + the existing snapshot-viewer UI (`RecipeModels.swift` `originalSnapshotButtonTapped`), but store it
  as a **distinct, device-local, sync-excluded** restore point — **do not** write the pristine
  `originalSnapshot` column (set-once "as captured/imported" provenance in `RecipeCore.swift`; clobbering it
  loses the import baseline).

*Invariant:* the model proposes → writes only to the preview → the tap writes (extends ADR-0011/0012). The
side-by-side review is the guard against roughshod edits.

*Out of S1 (do NOT build here):* the **"keep as a variation"** commit destination (that's S2 = ADR-0021's
`recipeVariations` table + reader/grocery fold), the **iterative refine loop + workbench-log deposit** (S3),
a multi-level undo stack, and any structural per-step method merge. Watch **OQ4**: the plain-recipe and
working-recipe paths must be the *same* code (a `Recipe` + a proposed delta) — confirm the reader/compare
wiring is identical, no fork.

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), **and** the ADR-0018 synced `aiSettings` table (PR #96); and note the
app target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**Recipe edit proposals** ([ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) +
`efforts/recipe-edit-proposals.md`) — the "Adjust this recipe" verb; **S1 is the current Next Up**. **S2** =
the *"keep as a variation"* commit destination (this is ADR-0021's build: `recipeVariations` table + reader
fold + grocery fold). **S3** = the iterative refine loop + workbench-log deposit. Extends ADR-0021 (the
variation destination) — do not duplicate it.

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
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

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
