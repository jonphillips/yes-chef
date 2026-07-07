# Current Handoff

Last updated: July 7, 2026 (**Next Up = Recipe edit proposals — Slice 2**, the "keep as a variation" commit
destination, ADR-0021/ADR-0023). Recently completed and moved to [`docs/DONE-LOG.md`](DONE-LOG.md):
**Recipe edit proposals — Slice 1** (the "Adjust this recipe" verb + section-aware multi-section
overwrite/undo, ADR-0023, schema-free); the **LLM-aligned Compare
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

**Recipe edit proposals — Slice 2: the "keep as a variation" commit destination (this is ADR-0021's build —
first schema change in this effort).** Implements [ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S2
by adding a second commit path on the *same* S1 proposal. **Read before starting:**
[ADR-0021](decisions/ADR-0021-recipe-variations.md) in full (the `recipeVariations` table shape, D2 delta
vocabulary, the reader fold + grocery fold, OQ1/OQ2), ADR-0023 **D6 + OQ3**, and
[`efforts/recipe-edit-proposals.md`](efforts/recipe-edit-proposals.md) S2. The S1 code this extends:
`RecipeAdjustment.swift` (the structured delta the extractor already produces **is** the ADR-0021 variation
payload — do **not** re-extract) and `RecipeAdjustmentReviewView.swift` (the side-by-side is the staging
surface — add the second commit button beside Overwrite).

*Why:* S1 shipped overwrite-in-place with a one-level undo; dogfooding tells us how often "adjust" wants
"keep both" instead. S2 gives the non-destructive destination: the same reviewed delta persists as a **named
variation overlay** on the base recipe (ADR-0021, [[recipe-variations-overlay]]), leaving canonical
ingredients/method intact.

*Build (S2 introduces schema — the first migration + synced column in this effort):*
- **`recipeVariations` table + BLOB** (the ADR-0021 D2 delta payload) + migration. This is a **real durable,
  synced** row — schema-evolves freely in the CloudKit **Development** environment; **add it to the Standing
  release follow-up list** so it deploys at the eventual prod cut.
- **"Keep as a variation"** as the **second commit button** on `RecipeAdjustmentReviewView`, alongside
  Overwrite. Reuses the S1 proposal/delta unchanged — **ADR-0021 OQ1 resolved** (no separate extraction),
  **OQ2 resolved** (the S1 side-by-side is the staging surface).
- **Reader fold** — the variation renders **highlighted-in-place** on the base recipe (ADR-0021); the active
  selection is **persisted-not-synced** ([[recipe-variations-overlay]]).
- **Grocery fold** — the active variation's delta folds into the grocery list **deterministically**
  ([[llm-vs-determinism-surface-boundary]] — this is a reproducible data-merge, keep it LLM-free).
- **Resolve ADR-0023 OQ3** — an S1 **overwrite** of a recipe that already carries variations must
  re-validate/rebase the variation deltas against the new base (or warn): the delta anchors on
  base-ingredient identity, which S1's `id`/`sectionID`-preserving in-place mutation is what makes tractable.

*Invariant (unchanged):* the model proposes → writes only to the preview → the tap writes (ADR-0011/0012).
The variation tap now writes a **durable overlay** instead of overwriting; the side-by-side review remains
the guard against roughshod edits.

*Out of S2 (do NOT build here):* the **iterative refine loop + workbench-log deposit** (S3 — re-extract with
the live proposal as context, then drop a `rationale` entry into the ADR-0019 workbench log), a multi-level
undo stack, and any structural per-step method merge (declined, ADR-0016/0023 OQ1).

**Standing release follow-up (not a dispatch — a pre-cut ops step Jon runs).** We stay in the CloudKit
**Development** environment (dev stance) so the schema keeps evolving freely; promoting to **Production** is
additive-only and permanently locks those record types, so it is deliberately **held** until an actual
prod/TestFlight cut. At that cut, deploy to the production schema the Phase E Slice 3 pantry-policy +
`canonicalName` fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), the reader-photo-affordances
`Recipe.coverPhotoID` column (PR #87), the ADR-0018 synced `aiSettings` table (PR #96), **and** the ADR-0021
synced `recipeVariations` table (Recipe edit proposals S2); and note the app target
(`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target. Completed efforts and their full write-ups live in [`docs/DONE-LOG.md`](DONE-LOG.md).

**Recipe edit proposals** ([ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) +
`efforts/recipe-edit-proposals.md`) — the "Adjust this recipe" verb; **S1 shipped** (overwrite destination,
section-aware multi-section overwrite/undo). **S2 is the current Next Up** = the *"keep as a variation"*
commit destination (this is ADR-0021's build: `recipeVariations` table + reader fold + grocery fold). **S3**
= the iterative refine loop + workbench-log deposit. Extends ADR-0021 (the variation destination) — do not
duplicate it.

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
