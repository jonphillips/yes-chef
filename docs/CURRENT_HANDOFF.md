# Current Handoff

Last updated: July 16, 2026 (ADR-0039 **Amendment 2 — Peek detent dropped**, **Jon device-confirmed**: the Playbook resize handle cycles **Comfortable ↔ Wide** only, no sliver reachable, toolbar Show/Hide owns the honest hide — PR #196 → DONE-LOG. **Next Up = Slice D, the last Amendment 2 slice — the menu adopts the Playbook/Enrichment column** (Dishes + placements = Body in the main pane; Prep Plan + Learnings + ChatGPT handoff = the resizable companion column), reusing the recipe's shared detent + resize-handle machinery. App-layer only, no schema. This closes Amendment 2.)

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

**Live dispatch target — [ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#menu-dishes-are-the-body-the-playbook-is-the-companion) Slice D: the menu adopts the Playbook/Enrichment column.** The **fourth and final** Amendment 2 slice — it gives the menu the *same* spatial grammar the recipe now has (Slices A–C, all shipped + device-confirmed). **App-layer only — no schema / migration** (view composition + local `@AppStorage`; the prep-plan/learnings/handoff data all already exist). This **closes Amendment 2.**

**The shape.** On wide (13" target), split `MenuDetailReader` into two co-visible regions, mirroring the recipe's `wideRecipeColumns` (`RecipeDetailView.swift:579`):
- **Body (main pane):** `MenuDetailHeader` + `MenuExternalProjectField` + `MenuDishList` + `MenuPlacementList` — the dishes/placements, always in view.
- **Playbook (resizable companion column):** `MenuPrepPlanSection` + `MenuLearningsSection`. The **ChatGPT handoff already lives inside `MenuPrepPlanSection`** (`handoffSource`/`handoffTransport`, `MenuViews.swift:390`) — it rides along, no separate wiring; just keep `handoffTransport` threaded.

**Reuse the shared machinery — do NOT fork it.** `RecipePlaybookColumnDetent` (`comfortable · wide`), `RecipePlaybookResizeHandle`, and `RecipeWideColumnMetrics` in `RecipePlaybookColumnLayout.swift` are surface-agnostic — reuse as-is (the two resize surfaces are *meant* to stay identical, per the Slice B precedent). Only the width **math** differs: the recipe's `RecipeWideColumnLayout` is 3-region (Ingredients + Directions + Playbook); the menu is **2-region** (Body floor + Playbook detent-driven remainder). **Recommended:** add a small peer `MenuWideColumnLayout` struct in the same file (Body minimum-fraction floor + `playbookWidth(for:)`/`nearestDetent`/`proposedPlaybookWidth` over the shared detent enum). Don't over-abstract into one generic layout in this slice unless it falls out cleanly — a consistent peer struct is the lower-risk call. Gate the split on the **same signal the recipe uses** — `proxy.size.width >= 640` inside a `GeometryReader` — and add a **Show/Hide Playbook** toolbar button gated identically (the recipe's is at `RecipeDetailView.swift:279`). New **menu-scoped** `@AppStorage` keys for visibility + detent (do **not** share the recipe's global keys — different surface).

**Service-date soft default (this replaces, doesn't delete, D4's behavior).** Today `isServiceDateTodayOrPast` (`MenuViews.swift:368`) *reorders* the single column — dishes jump to top, prep plan collapses — on/after service. Under Slice D the **dishes are always the Body (always in view), so the reorder is gone**; the service date instead sets only the *default Playbook detent* (**narrower — Comfortable — on/after service so Dishes get emphasis; never forced, always draggable back**, honoring "never invisible unless I ask"). **Sub-decision flagged for Jon's device pass:** a single global menu detent fights a per-menu service-date default. **Recommended resolution:** service date seeds the *initial* default only; once the user drags, that persisted detent wins and is never silently overridden by the heuristic. Exact per-menu-vs-global + whether service-date re-asserts is **Jon's device call** — pick the least-surprising option, keep it draggable-back always. OQ3's **collapsible days / prep-plan horizon bands stay as-is** ([[prep-plan-horizon-redesign]]) — watch the band list rendered in a narrower companion-width column.

**Leave these alone.** **Ask + Browse Recipes stay `.inspector` slide-overs** on `MenuDetailView` (`MenuViews.swift:227`) — the Playbook is a *structural column*, NOT a second inspector (two competing inspectors is the exact thing the ADR says to avoid; Ask is never promoted to a column). **Compact is unchanged** — single scroll, Playbook sections stack below the Body as today; the split is **wide-only**. The Body pane's current `maxWidth: 900` readable cap (`MenuViews.swift:428`) is a device-tune knob, not a decided width.

**Verify:** app-layer SwiftUI — the architect's local `generic/platform=iOS` build is **required evidence**. Confirm on wide iPad: the menu shows Dishes + placements as the Body with a resizable Playbook (Prep Plan + Learnings + ChatGPT handoff) companion; handle cycles Comfortable ↔ Wide; toolbar Show/Hide collapses + restores the last detent; on/after service the Playbook opens narrower by default and still drags back; Ask + Browse still open as slide-overs (no second inspector fighting the column); collapsible days still work; compact menu is untouched. Exact detent widths + the Body cap are **Jon's device-pass call.**


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
