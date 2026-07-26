# Effort: Dogfood ferry pass — 2026-07-25 (expand control, hand-off regrouping, workbench lifecycle)

**Status:** Designed (spec'd, not dispatched) — **three dispatches, three PRs**, sequenced 1 → 2 → 3.
**Summary:** Jon's 2026-07-25 ferry pass over Menu, Recipe, Calendar and Workbench. One shared full-screen
expand control replaces four drifted copies; the Menu grows the Recipe's pinned-Ask onboard treatment;
prep-plan/complement hand-offs regroup from button rows into per-day and per-plan overflow menus with settled
vocabulary; the Workbench gains an Active/Completed lifecycle and edit-in-place; Menu learnings become
hand-authorable through the `.inApp` provenance that already exists.
**Related:** [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) (the woven prep plan this
effort must not fragment) · [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md) (the
playbook column and its sidebar-icon collision) · [ADR-0041](../decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md)
(scoped hand-off sources) · [ADR-0038](../decisions/ADR-0038-external-llm-handoff.md) (learnings + provenance)
· [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (the tab-bar shell — **gated behind
Dispatch 1**, not part of this effort).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

**Jon's decisions, ratified 2026-07-25 — do not re-litigate:**

1. **Per-day prep plan is a scoped *ask*, not scoped *storage*.** The master plan stays woven.
2. **The Calendar's verb is Make-ahead, not Prep Plan.** Already true in code; only labels change.
3. **There is no week-scoped hand-off.** Each day cell on the week grid gets its own menu for *that day*.
4. **Deleting a workbench leaves the un-promoted working recipe in the library.**
5. **Hand-authored menu learnings are Learnings, not notes** — distinguished by `provenance`, which is
   already modeled.

---

## The finding that shapes Dispatch 2

`PrepPlanStepRecord` ([`MenuPrepPlan.swift:10`](../../YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift))
has **no `dayOffset`**. Its only grouping axis is `session`, mapped onto the `PrepPlanSessionBand` horizon
bands (Flexible / Earlier in the week / The day before / The day of / At service). That is
[ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md)'s decision, made deliberately on
2026-07-12: **one weaveable master plan per menu**, banded by horizon, so cross-dish work interleaves.

Adding `dayOffset` to the step record would fragment that plan into N per-day mini-plans and reverse
ADR-0034. So the per-day affordance is a **scoped ask with a woven return**: the day's menu builds a prompt
carrying only that day's dishes, and the return merges into the single master plan through the existing
`prepPlanPasted` reconciliation ([`MenuModels.swift:579`](../../YesChefApp/MenuModels.swift)). Steps land in
horizon bands as they do today.

This also fixes the ambiguity the per-day ask was reacting to: horizon bands are relative to **service**, and a
multi-day menu has several service dates, so "the day before" is already under-specified. Anchoring the *ask*
to a day resolves it without moving the storage.

**The asymmetry to expect:** `MenuComplement` already carries `dayOffset` on its suggestions
([`MenuComplement.swift:29`](../../YesChefPackage/Sources/YesChefCore/MenuComplement.swift)), so day-scoping
the complement is a prompt scope plus a fixed offset on the return. **Complement is cheap; prep plan is the
work.**

---

# DISPATCH 1 — the expand control and the onboard column (view layer only, no Core, no schema)

**Why these ship together:** all four surfaces' expand controls and the Menu's Ask placement are the same
class of drift — one interaction pattern, four independent implementations. Fixing them in one PR is what
stops a fifth copy appearing. **Nothing here touches `YesChefPackage`.**

**Read first:** [`RecipeDetailView.swift`](../../YesChefApp/RecipeDetailView.swift) (focus button ~141–155,
`primaryAction` group ~157–208, the reader's playbook toggle ~370–383),
[`MenuViews.swift`](../../YesChefApp/MenuViews.swift) (~216–224),
[`WorkbenchViews.swift`](../../YesChefApp/WorkbenchViews.swift) (~178–187),
[`AppMainLayout.swift`](../../YesChefApp/AppMainLayout.swift) (calendar branch ~46–56, focus wiring ~91–110),
[`RecipePlaybookView.swift`](../../YesChefApp/RecipePlaybookView.swift) (`playbookHeader` + `askButton`
~99–136 — the reference treatment),
[`MenuPlaybookColumnView.swift`](../../YesChefApp/MenuPlaybookColumnView.swift) (~61–65, ~159–185).

## SLICE A — one expand control, four surfaces

**Recipe is the reference and it is already correct** — `.topBarLeading`,
`arrow.up.left.and.arrow.down.right` becoming `….circle.fill` when active, `.tint(active ? .accentColor :
.primary)`, label `Focus` / `Exit Focus`, `.accessibilityValue("Focused" / "Split view")`.

1. **Extract it once.** A single `FocusToolbarButton` (or `ToolbarContent` helper) carrying icon, tint,
   label, and accessibility value. Every surface below uses it — no surface re-authors the glyph choice.
2. **Menu conforms.** Today `.primaryAction` with a `rectangle.expand` icon and no tint
   (`MenuViews.swift` ~216–224). Move to `.topBarLeading`, adopt the shared control.
3. **Workbench conforms.** Identical drift (`WorkbenchViews.swift` ~178–187). **Note for Jon's phrasing:**
   the "Focus" button is not being *removed* — it is the same control, non-conforming. After this slice it
   *is* the double-arrows.
4. **Calendar gains one.** It has none today. Its branch
   (`AppMainLayout.swift` ~46–56) is a two-column `NavigationSplitView` with **no `columnVisibility`
   binding** — add one, mirroring the wiring at ~91–110, so the control collapses to the detail column.

**Acceptance:** all four surfaces show the same glyph in the same place, highlight identically when active,
and exit with the same tap. Exactly one definition of the icon/tint pair exists in the codebase.

## SLICE B — Recipe toolbar: Edit right-most-but-visible

Edit is currently **first** in the trailing group (`RecipeDetailView.swift:158`), ahead of Groceries, Plan and
the Hand-off menu.

**The wrinkle that makes this more than a reorder:** the playbook show/hide button is contributed by
`RecipeReaderView`'s *own* `.toolbar` (~370–383), a different view. Toolbar order follows view-hierarchy
order, so anything in `RecipeDetailView`'s group renders **before** it — Edit can never become right-most by
reordering within its own group.

**Resolution:** hoist the playbook toggle into `RecipeDetailView`'s `primaryAction` group and place Edit last,
giving `Groceries · Plan · Hand off · Playbook · Edit · ⋯`. The toggle's `proxy.size.width >=
twoColumnThreshold` gate must travel with it (a width preference or a passed flag) — do not drop the gate, or
the toggle appears on iPhone where there is no second column.

**Acceptance:** Edit is the last visible trailing item, immediately left of the overflow `⋯`; the playbook
toggle still only appears at two-column width; the secondary-action overflow is unchanged.

## SLICE C — the Menu's onboard column echoes the Recipe's

1. **Pin Ask to the top of the playbook column.** Menu's Ask lives in the *toolbar* today
   (`MenuViews.swift` ~236–249). Move it into a `menuPlaybook` header matching
   `RecipePlaybookView.playbookHeader` (~99–103): trailing-aligned, `.bordered`, tinted stroke overlay while
   its panel is open, `.accessibilityValue("Panel open" / "Panel closed")`.
2. **The Ask dropdown carries Regenerate.** Recipe's Ask is a `Menu` over `PlaybookSectionKind.allCases`.
   Menu's list is **Prep Plan · Complement**, plus **Regenerate whole plan** as a distinct item —
   which retires the standalone `Regenerate` button now sitting inside the Prep Plan section
   (`MenuViews.swift` ~487–493).
3. **Give the column a show/hide toggle.** `MenuPlaybookColumnView` hardcodes `isPlaybookVisible: true`
   (~64). Adopt the Recipe's `@AppStorage`-backed visibility with the same `sidebar.trailing` toolbar button.
   **Heed [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md)'s recorded collision:** the
   Menu already has a *Browse Recipes* button using `sidebar.right`, one glyph away. Two trailing-sidebar
   icons on one toolbar is the exact confusion ADR-0039 flagged — resolve it in this slice (distinguish the
   panel toggle from the structural column toggle), do not ship both glyphs side by side.

**Acceptance:** Menu's Ask sits pinned at the top of the playbook column, lights up while its panel is open,
and offers Prep Plan / Complement / Regenerate; the column hides and shows; no two toolbar buttons read as
the same control.

## SLICE F1 — Calendar's onboard affordance

Calendar's onboard column is **not** the playbook pattern — it is `ChatWorkspaceSplit` with a persisted detent
([`MealCalendarViews.swift:268`](../../YesChefApp/MealCalendarViews.swift)), and `chatButtonTapped` only
*forces* `.balanced`, never collapses (~366–372).

**Do not converge the patterns in this slice.** Give the existing split a pinned Ask affordance and make the
button a real toggle (visible → collapse; hidden → `.balanced`), matching the fix already applied to the
recipe chat button in batch 5.

**Recorded, not scoped:** there are now **three** chat presentation patterns — inspector (Recipe),
`ChatWorkspaceSplit` (Calendar, Workbench compare), and sheet (compact). That convergence is a real question
and it is **explicitly out of scope here.**

**Acceptance:** the Calendar day's Chat button opens *and* closes the panel on repeated taps; the Ask
affordance is discoverable without selecting a day first.

**Dispatch 1 verification:** generic app build (elevated, no signing) + `scripts/check-drift.sh`. No package
tests — nothing here touches Core. Jon does the device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.

---

# DISPATCH 2 — hand-off regrouping, scoped asks, and the vocabulary cleanup

**Why these ship together:** the regrouping and the renaming are the same edit to the same controls. Splitting
them means touching every hand-off button twice.

**Read first:** [`MenuDetailSections.swift`](../../YesChefApp/MenuDetailSections.swift) (`MenuDaySection`
~150–197, its Add button ~185–196), [`MenuViews.swift`](../../YesChefApp/MenuViews.swift) (prep-plan header
~450–502, `PrepPlanHandoffControls` ~593–628), [`MealCalendarViews.swift`](../../YesChefApp/MealCalendarViews.swift)
(`MealCalendarDayHeader` ~808–919, `MealCalendarWeekCell` ~734–777),
[`MealCalendarHandoffSource.swift`](../../YesChefApp/MealCalendarHandoffSource.swift),
[`MenuChatContext.swift`](../../YesChefPackage/Sources/YesChefCore/MenuChatContext.swift),
[`MenuComplement.swift`](../../YesChefPackage/Sources/YesChefCore/MenuComplement.swift).

## SLICE D1 — the Menu day overflow menu

Each `MenuDaySection` header gets a `⋯` menu **to the right of its existing Add button** (~185–196), holding
four items in this order:

> **Handoff Prep · Paste Prep · Handoff Complement · Paste Complement**

- **Complement is the cheap half** — scope the existing `.menuComplement` prompt to the day's dishes and fix
  the returned `dayOffset` to that day. `MenuComplement` already carries the field.
- **Prep is the scoped ask** — the prompt carries only that day's dishes and asks for steps for that day; the
  return merges into the one master plan via `prepPlanPasted`. **No `dayOffset` is added to
  `PrepPlanStepRecord`.** Steps continue to land in horizon bands.
- `PasteButton` does not render inside a `Menu`, so the Paste items read `UIPasteboard.general` directly and
  hand the empty case to the transport — copy the pattern at
  [`RecipeDetailView.swift:191`](../../YesChefApp/RecipeDetailView.swift), including the
  `.disabled(!UIPasteboard.general.hasStrings)` gate.

**This slice discharges a logged concern.** The PR #226 device pass noted the Prep Plan disclosure rendering
two Copy + two Paste buttons and the meal-plan day header four, with the note *"wants a feel on iPhone before
anyone adds a fifth."* Moving them into overflow menus **is** that fix — say so in the PR.

## SLICE D2 — the plan-level overflow menu and a Clear that asks

Right-align a `⋯` on the **Prep Plan title row** (`MenuViews.swift` ~452–469) holding the whole-plan actions:
**Handoff Prep · Paste Prep · Clear Prep Plan**. Retire the `PrepPlanHandoffControls` button row (~593–628)
and the standalone Clear button (~495–501).

**Clear currently fires immediately with no confirmation** — it calls `clearPrepPlan()` straight from the tap.
That is a destructive, un-undoable action on generated content. Add a `confirmationDialog` with a destructive
role, matching the section-clear pattern at
[`RecipePlaybookView.swift:89`](../../YesChefApp/RecipePlaybookView.swift).

## SLICE D3 — the Calendar day and week-cell menus

- **Day header** (`MealCalendarDayHeader` ~873–892): collapse the two `HandoffCopyPasteControls` into one `⋯`
  beside the Add menu, reading **Handoff Make-ahead · Paste Make-ahead · Handoff Complement · Paste
  Complement**. The sources already exist and are already per-day.
- **Week grid** (`MealCalendarWeekCell` ~734–777): each cell gets the same menu **for its own date**. The cell
  already receives a `summary` carrying `.date` and `.rows`, so it can build its own source — but today's
  `handoffAnchorItemID` reads `model.selectedDayRows`
  ([`MealCalendarHandoffSource.swift`](../../YesChefApp/MealCalendarHandoffSource.swift)), the **selected**
  day. **Parameterize the source by date** so a cell's menu acts on the cell you tapped, not on the selection.
- The cell is currently one large `Button`; place the menu in the header `HStack` where `Spacer(minLength: 0)`
  sits, and verify the nested control doesn't swallow the cell's own selection tap.

**There is no week-scoped hand-off.** Jon ruled this out explicitly — a week has no comprehensive ask.

## SLICE D4 — kill "Prep Plan" where it means Make-ahead

**Three concepts, deliberately distinct — only the leak is a bug:**

| Concept | Type / task | Correct name |
|---|---|---|
| Recipe → per-recipe make-ahead | `MakeAheadPlan`, `.recipeMakeAhead` | **Make-ahead** |
| Menu → woven, horizon-banded step rows | `PrepPlanStepRecord`, `.prepPlan` | **Prep Plan** |
| Calendar day → prose day strategy | `.mealPlanMakeAheadStrategy` | **Make-ahead Strategy** |

**Two sites leak "Prep Plan" onto the Recipe surface, and they are a coupled pair:**

1. [`RecipeDetailModel+Enrichment.swift:38`](../../YesChefApp/RecipeDetailModel+Enrichment.swift) —
   `ChatApplyAction<MakeAheadPlan>(title: "Create Prep Plan", …)`. Every *other* string in that same
   initializer already says make-ahead. → **`"Create Make-ahead"`**.
2. [`RecipeChatPanelSupport.swift:13`](../../YesChefApp/RecipeChatPanelSupport.swift) —
   `case .makeAhead: actionID = "Create Prep Plan"`.

> ⚠️ **`AnyChatApplyAction` defines `public var id: String { title }`**
> ([`RecipeChat.swift:604`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)). **The action's
> identity is its user-facing title.** `ChatFinalizeConfiguration` resolves Finalize by that string, so
> renaming one line without the other breaks Finalize on the recipe Make-ahead section **with no compile
> error**. Same family as the `editableSummary` no-op that bit ADR-0027 Amd-1
> ([[editable-summary-unchanged-commit-path]]). Change both in one commit and **extend the existing
> Finalize→action resolution test** (added in the PR #229 review) to cover the make-ahead section.

**Do not blanket-rename.** These stay as they are: the Menu section title, its alerts and empty state,
`MenuModels`' apply-action strings, `menuPrepPlanReviewItems`, `AIHandoffTaskType.prepPlan`,
`MenuChatContext`'s *"Current prep plan:"*, and every `PrepPlanStep` / `MenuPrepPlan` identifier. The Menu's
prep plan is a different artifact from a recipe's Make-ahead and is deliberately **composed from** it —
collapsing the words makes that relationship unsayable.

**Never touch:** the three `migrator.registerMigration` names containing "prep plan"
([`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) ~627, ~887, ~960). Migration
identifiers are frozen history.

**Also correct already, needing no change:** the Calendar's `"Copy Make-ahead Prompt"` and
`.mealPlanMakeAheadStrategy` → `"Make-ahead Strategy"`; and `AISettings`' **"Make-ahead & Prep Plans"**, whose
conjunction accurately covers both concepts.

**Dispatch 2 acceptance:** each Menu day and each Calendar day/week cell offers its four hand-off items scoped
to *that* day; a day-scoped prep ask returns steps that merge into the single master plan in horizon bands;
Clear asks first; the word "Prep Plan" no longer appears on any recipe surface; Finalize still resolves on the
recipe Make-ahead section (test).

**Dispatch 2 verification:** package `swift build` + Core tests for the scoped prompt construction and the
Finalize resolution test; then the generic app build + `scripts/check-drift.sh`.

---

# DISPATCH 3 — workbench lifecycle and hand-authored learnings

**Read first:** [`WorkbenchViews.swift`](../../YesChefApp/WorkbenchViews.swift) (list + swipe ~5–58,
title/notes editors ~334–372), [`WorkbenchModels.swift`](../../YesChefApp/WorkbenchModels.swift) (~66–86),
[`WorkbenchCore.swift`](../../YesChefPackage/Sources/YesChefCore/WorkbenchCore.swift) (`Workbench` ~5–31,
`updateWorkbenchTitle` ~400–413, `deleteWorkbench` ~415–421),
[`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) (~696–731),
[`MenuPrepPlanEditingViews.swift`](../../YesChefApp/MenuPrepPlanEditingViews.swift) (`LearningsSection`
~104–136), [`AIHandoff.swift`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift) (`Learning` ~136,
`LearningProvenance` ~170).

## SLICE E1 — edit-in-place title and notes

Drop the **Save Title** and **Save Notes** buttons (~348–372); commit on blur with a short debounce.

**Guard:** `updateWorkbenchTitle` throws on an empty title (~406). Edit-in-place must **revert to the last
good title** on empty rather than surfacing an error alert on every transient empty field during typing.
Notes have no such guard — empty is a legal value there (`nonEmptyWorkbenchText` maps it to `nil`).

## SLICE E2 — Active / Completed

**One nullable synced column: `workbenches.dateCompleted TEXT`.** A new synced table or column is cheap
([[synced-table-cost-calibration]]); register the change and **add it to the prod-promotion list in
`CURRENT_HANDOFF` in this same PR** ([[handoff-bump-rides-in-slice-pr]]).

1. A segmented **Active / Completed** control on `WorkbenchListView`, filtering on `dateCompleted == nil`.
2. **Search over the Completed list** (the Active list stays unfiltered — it is short by construction).
3. The swipe row gains **Mark Completed** alongside Delete; completing moves the row between lists.
4. **Decide and state in the PR:** whether a completed workbench still appears in the recipe detail's
   workbench picker and in chat context. Recommendation: **exclude from pickers, keep reachable by search** —
   completing is about clearing the working set, not hiding history.

## SLICE E3 — the delete confirmation tells the truth

**Deleting a workbench already does not delete recipes.** `workbenchCandidates.workbenchID … ON DELETE
CASCADE` drops only the join rows; `recipeID … ON DELETE SET NULL` points the other way
([`Schema.swift:711`](../../YesChefPackage/Sources/YesChefCore/Schema.swift)). The defect is the **copy**:
`deleteWorkbenchMessage` ([`AppMainLayout.swift:145`](../../YesChefApp/AppMainLayout.swift)) renders *"Delete
Braises and its 3 candidates?"*, which reads as deleting the recipes.

Rewrite it to say what happens — the workbench and its list go away, **the recipes stay in the library**.

**Jon's ruling on the adjacent case:** `workbenches.draftRecipeID → recipes ON DELETE SET NULL` means an
un-promoted working recipe outlives its workbench. **Leave it in the library.** No change; record the choice
in the PR so it is not "fixed" later by someone reading it as a leak.

## SLICE H — hand-authored menu learnings

Jon's want — *"6 lbs of chicken turned out to be the right amount and 2 pork shoulders was twice what we
needed"* — is distinguished from model output by **authorship**, and that is **already modeled**:
`LearningProvenance` has `.externalHandoff` and `.inApp`
([`AIHandoff.swift:170`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift)).

**`.inApp` is constructed nowhere in the codebase.** It is an orphaned case with no producer, which is why
there is no way to write one. This is **not** a new table and **not** `Menu.notes` — dumping a new content
kind into a generic notes field is the thing [[decompose-notes-into-typed-homes]] forbids, and `Menu.notes` is
display-only today ([`MenuViews.swift:700`](../../YesChefApp/MenuViews.swift)).

1. **Add an Add affordance** to `LearningsSection`, writing `provenance: .inApp`. No schema change.
2. **Fix the empty state.** It currently reads *"Useful ideas returned from an AI handoff appear here"*
   (~114), which actively tells the cook this isn't a place they can write.
3. **Mark provenance in the row** so a hand-authored observation is distinguishable from a returned one.
4. **Feed them back out.** `knownLearningsBlock` exists only in the *recipe* hand-off context
   ([`AIHandoffContext.swift:76`](../../YesChefPackage/Sources/YesChefCore/AIHandoffContext.swift)) — menu
   learnings do **not** reach the menu's outbound ask. A quantity observation is precisely what should go out
   the next time that menu is planned, so wire menu learnings into `MenuChatContext`'s ask alongside the
   existing dedup instruction.

**Dispatch 3 acceptance:** title/notes commit without Save buttons and never clobber a good title with an
empty one; Active/Completed filters and searches, and the swipe completes; the delete dialog no longer implies
recipe deletion; a learning can be typed by hand on a Menu, is marked as hand-authored, survives sync, and
appears in the next outbound menu ask.

**Dispatch 3 verification:** package `swift build` + Core tests (the `dateCompleted` migration + filter, the
`.inApp` write path, the title-revert guard); then the generic app build + `scripts/check-drift.sh`.

---

## Explicitly out of scope

- **The sidebar-adaptable tab bar** — [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md), its
  own decision and its own PR, **sequenced after Dispatch 1** so the shared expand control exists before the
  container moves underneath it.
- **Converging the three chat presentation patterns** (inspector / `ChatWorkspaceSplit` / sheet). Named in
  Slice F1, not scoped.
- **Any `dayOffset` on `PrepPlanStepRecord`.** Reverses ADR-0034; ruled out.
- **Week-scoped hand-off sources or contexts.** Ruled out.
