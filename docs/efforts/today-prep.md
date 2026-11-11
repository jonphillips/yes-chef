# Effort — Today's Prep

Status: Ready
Summary: A **Prep** button beside **Cook these** opens a full-screen checklist of the prep steps due now, with each step's recipe in a pane beside it. Checks are a new synced `completedAt` on `prepPlanSteps`, so they last overnight and show on both devices, and every writer keeps them or starts them at nil. Light edits only: check off, move to tomorrow, add or edit a step. One nullable synced column, with a Production deploy.

Origin: Jon, 2026-11-11: the prep plan is fine for designing and "much less fun for actually doing the prep work". One
dispatch, one PR. **Persistent model change, authorized by ADR-0067 D5.** Thanksgiving is Thu Nov 26. Landing by about
Sat Nov 21 means the device pass is real use.

Decisions: [ADR-0067](../decisions/ADR-0067-todays-prep.md) (D1–D10). Read it first. Patterns to copy: the cook
session ([ADR-0016](../decisions/ADR-0016-multi-recipe-cook-session.md); `CookSessionView`, its root-level cover) and
the archived [`prep-plan-time-order`](archive/prep-plan-time-order.md) brief, which threaded `timeOfDay` through every
writer of `prepPlanSteps`. This effort touches the same writers.

## Where things are (architect, 2026-11-11, `origin/main` ab00a36)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `MenuPrepPlan.swift`: `PrepPlanStepRecord`; `PrepPlanStep` (the draft and wire type, **which doesn't change**);
  `PrepPlanStepRepository` (`create`, `update`, `replace` and its `Contents`, `reorder`, `writeSortOrder`,
  `delete`).
- `MenuPrepPlanBands.swift`: `MenuPrepPlanBanding.bands(steps:dayCount:placementStartDate:today:calendar:)`, its
  day titles, and `isToday`.
- `ChatPrepPlanImport.swift`: `apply`. Kept rows get column-targeted updates and new rows are inserted.
- `MenuBringIn.swift`: `copyMenuContents`, which inserts copied steps (around line 64).
- `ChatAccessExport.swift`, `MenuChatContext.swift`: the export and the prompts, which **don't** gain the field.
- `MenuCore.swift`: `MenuDetailData`, which has `placements`, `prepPlanSteps` and `itemRows`.
- `Models.swift`: `MenuPlacement` (`startDate`).
- `AppHelp.swift`: `AppHelpPage.menus`, the "Prep plan" section. `MenuAddMenuTests` holds the page's
  `plainText.count <= 1_800` test.
- `Schema.swift`: append the migration after the last one. `CloudSync.swift`: bump `declaredSchemaVersion` by one on
  top of whatever main has when you branch. `prepPlanSteps` is already registered for sync.

**App (`YesChefApp/`)**
- `MenuViews.swift`: the toolbar (around line 178, **Cook these**); `cookSessionPresentation`;
  `MenuPrepPlanSection` (around line 386), the Prep Plan column's banded list and step rows.
- `MenuPlaybookColumnView.swift`: builds `MenuPrepPlanSection` (around line 152).
- `AppNavigationModels.swift`: `CookSessionPresentation`, `CookSessionItem`. `CookSessionPresentation(menuDetail:)`
  maps menu items to recipes with `.menuItem` scale contexts.
- `AppMainLayout.swift`, `MealCalendarViews.swift`: how `onCookSessionRequested` is passed down.
  `RecipeLibraryView.swift`: `presentedCookSession` and `CookSessionFullScreenCover` (around line 452), the root
  cover with **Close** and the toast overlay.
- `CookSessionView.swift`: the kept-alive Readers (`TabView` paging with the index hidden) and
  `.keepsScreenAwakeWhilePresented()`.
- `MenuModels.swift`: `MenuDetailModel(menuID:toastCenter:)`, with `@Fetch var detail: MenuDetailData?` and `now`.
  `MenuDetailModel+PrepPlanEditing.swift`: `createPrepPlanStep`, `updatePrepPlanStep`.
- `MenuPrepPlanEditingViews.swift`: `PrepPlanStepEditorDraft` (`init()`, `init(step:)`) and
  `PrepPlanStepEditorSheet`.

**Repo root:** `cloudkit-expected-fields.txt`.

## The slice

### Schema (D5)
- Append the migration "Add prep plan completion", `ALTER TABLE "prepPlanSteps" ADD COLUMN "completedAt" TEXT`, and
  bump `declaredSchemaVersion`.
- Add `completedAt: Date?` to `PrepPlanStepRecord` only, with a defaulted init parameter. **Don't** add it to
  `PrepPlanStep`, the editable review text, `ChatAccessExport.PrepStepRecord`, `get_menu`, `MenuChatContext` or any
  prompt.
- Add `prepPlanSteps completedAt` and `prepPlanSteps sqlitedata_icloud_userModificationTime_completedAt` to
  `cloudkit-expected-fields.txt`, in sorted order.

### Writers (D5)
Every writer either keeps the date or starts it at nil:
- **`replace`:** a survivor matched by `Contents` is built with `completedAt: existing?.completedAt`. `Contents`
  doesn't gain it. This is the one writer that needs new code: the upsert writes a fresh record, so without the copy a
  re-weave would erase every check.
- **`update`:** don't add it to the column-targeted update. Editing a done step leaves it done.
- **`create`**, **`ChatPrepPlanImport.apply`** inserts, and **`MenuBringIn`** copies: nil (the default).
  `ChatPrepPlanImport.apply`'s Kept-row updates stay column-targeted.
- **New:** `PrepPlanStepRepository.setCompleted(id:at: Date?, in:)` writes one step, and
  `uncheckAll(menuID:in:)` writes nil to every step of a menu. Neither touches `Menu.dateModified`, because progress
  isn't an edit and shouldn't reorder the Menus list.

### The run and done rule (D2, D6) — pure Core, next to `MenuPrepPlanBanding`

> **ADR-0067 D6 is refined in this PR** (the same plan PR as this brief). Read the ADR's D6 as merged. In short:

- **The current run** is the placement whose work range (start − 7 days through start + `dayCount` − 1) contains
  today. If none does, it's the next placement to start, and if none is upcoming, the latest one. An unplaced menu has
  no run.
- **Done:** a step is done when `completedAt` is later than the end of the **previous run**, meaning the placement with
  the latest start before the current run's start, through its last day. If there's no previous run, or the menu is
  unplaced, any `completedAt` counts.
- Put both in one function that returns the set of done step ids, for example
  `PrepPlanProgress.doneStepIDs(steps:dayCount:placements:today:calendar:)`. The Prep view and the Prep Plan column
  both use it.

### Sections (D2) — pure Core
`TodayPrepLayout.make(steps:dayCount:placements:today:calendar:)`, or an equivalent, returns one of two modes:
- **Dated:** the menu is longer than one day, and exactly one placement's work range contains today. Let `t` be
  today's offset from that placement's start. Sections in order:
  - **Still open:** dated steps with `workDayOffset < t` that aren't done, grouped by day with the banding's day
    titles. Leave it out when it's empty.
  - **Today:** `workDayOffset == t`, with all of its steps.
  - **Get ahead:** the Flexible steps.
  - **Tomorrow:** `t + 1`, only when that's within the menu.

  Each section keeps plan order (`sortOrder`) and records where the session label changes, as the banding does.
- **Manual:** anything else. It returns `MenuPrepPlanBanding.bands(...)` unchanged, plus the id of the first band
  with a step that isn't done (or the first band).

### App: entry and cover (D1)
- In the menu toolbar, before **Add Recipes** and beside **Cook these**: when `detail.prepPlanSteps` isn't empty,
  `Label("Prep", systemImage: "checklist")`. The glyph is a literal, per ADR-0065 D3.
- Present it at the root, like the cook session: a `TodayPrepPresentation(menuID:title:)`, passed down the way
  `onCookSessionRequested` is, to a `.fullScreenCover` in `RecipeLibraryView` next to `presentedCookSession`. You can
  either add a second callback or widen the existing one into an enum. Pick whichever changes fewer call sites. The
  cover wraps a `NavigationStack` with **Close**, the toast overlay and `.keepsScreenAwakeWhilePresented()`, as
  `CookSessionFullScreenCover` does.
- `TodayPrepView` owns a `MenuDetailModel(menuID:)` for its data and step edits. Don't build a second fetch. Starting
  it the way `MenuDetailView` does is enough.

### App: the view (D2–D4, D6, D7)
- **Title:** dated mode is "Today's Prep" with the day's title as a subtitle. Manual mode is "Prep", with a band
  `Picker` at the top that starts on the layout's first open band. The selection isn't saved.
- **Rows:** a leading check button (`circle` / `checkmark.circle.fill`) and the task in body text. A second line holds
  the `serves` text and the make-ahead window in the column's style. Show the session sub-label where it changes. A
  done row stays in place, dimmed. Tapping the check calls `setCompleted(id:, at: now)`, or nil when it's already
  done. Use a light sensory feedback. Don't show the time.
- **Sections:** Still open and Today expanded; Get ahead and Tomorrow as collapsed `DisclosureGroup`s whose labels
  include the count of steps not done. Each section's footer reads "N of M done".
- **Reader pane (regular width):** list on the leading side and Reader on the trailing side, split as the playbook
  layout does. The pane pages one `RecipeDetailView` per recipe dish from `CookSessionPresentation(menuDetail:)`'s
  items, kept alive as in `CookSessionView`. Tapping a row's body selects it. When the step's `sourceDish` maps to an
  item, the pane switches to it. Otherwise it stays as it was. Before anything is selected, show the first dish.
- **Compact width:** tapping a row's body pushes that dish's `RecipeDetailView`. A step with no dish doesn't push.
- **Move to tomorrow:** a trailing swipe action and a context-menu item on unchecked dated steps. The label is
  "Tomorrow" (manual mode: "Next Day"). It calls `update` with `workDayOffset` = `t + 1` (manual mode: the selected
  band's day + 1), keeping every other field. That re-places the step by time. Hide it when the target day would be
  past the menu's last day, on Flexible steps, and on one-day menus.
- **Add Step** at the foot of Today, or of the selected band, opens `PrepPlanStepEditorSheet` with a fresh draft
  whose `workDayOffset` is that day. **Edit Step…** in the context menu opens it with `init(step:)`. Both save
  through `MenuDetailModel`'s existing functions.
- **⋯ › Uncheck All**, after a confirmation dialog, calls `uncheckAll`.

### App: the Prep Plan column (D8)
`MenuPrepPlanSection` takes `doneStepIDs: Set<PrepPlanStepRecord.ID>`, computed in `MenuPlaybookColumnView` with
the Core function. A done step's row dims and shows a small trailing `checkmark`. It has no toggle.

### Help (D9)
Append to the Menus page's "Prep plan" section: "**Prep** opens the steps due now as a checklist, with each dish's
recipe beside it. Checks sync to your other devices. Swipe a step to move it to tomorrow." Check it against the app as
built and fix any label that doesn't match, listing each fix in the PR body. The page has to stay within the 1,800-character
test. If it doesn't fit, shorten this bullet, not the others.

## Tests

**Core**
- The migration adds the column to a database that has rows, following `SchemaColumnTests`. Old rows read nil.
- **Writers:** `replace` with identical drafts keeps both `completedAt` and the id. `replace` where only the time or
  window changes keeps `completedAt`. A changed task starts nil. `update` on a done step keeps `completedAt`. A Kept row
  in `ChatPrepPlanImport.apply` keeps it, and a new row starts nil. A bring-in copy of a done step starts nil.
  `reorder` keeps it.
- `setCompleted` and `uncheckAll` write only `completedAt`, and `Menu.dateModified` doesn't change.
- **Wire stays clean:** a done step's `ChatAccessExport` record has no completion key, and
  `ChatPrepPlanImport.plan`'s `planChangedSinceStage` stays false after checking a step.
- **Run and done:** unplaced, any date counts. With one placement, any date counts. Placed 2025 and 2026 with today in
  the 2026 range, a check dated during the 2025 run isn't done, and one dated after the 2025 run ended is (including a
  Flexible step checked 10 days before the 2026 start). Placed 2025 and 2026 with today between them, the 2026 run is
  current.
- **Sections:** with today on Day 2 of a placed 3-day menu, Still open holds Day 1's unchecked steps and not its done
  ones, Today holds Day 2, Tomorrow holds Day 3, and Get ahead holds Flexible. On the last day there's no Tomorrow
  section. A day before Day 1 (offset −1) counts as "today". Unplaced, one-day, and two placements covering today all
  give manual mode, and the first open band is the first band with an unchecked step.
- The Menus help page stays within 1,800 characters.

**App (`YesChefTests`)**
- Checking and unchecking through the view's model writes `completedAt`.
- Move to tomorrow sets `workDayOffset` to `t + 1` and keeps the task, window and time.
- Uncheck All clears every step of the menu and no other menu's.

This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- **Prep** opens today's steps in dated mode, or the band picker in manual mode. Checks persist, sync, and survive a
  re-weave of unchanged steps. Move to tomorrow, Add Step, Edit Step and Uncheck All work. The Prep Plan column shows
  done steps.
- Nothing in the export, `get_menu`, the review text or the prompts changed.
- Tests above. Verification per [`verification.md`](../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- The PR body gives the install order: the app on both devices. The helper doesn't change.
- **Gate, before any TestFlight upload:** `prepPlanSteps.completedAt` and its modification-time field are in
  Production. The architect imports them to Development with `cktool`, and Jon deploys in the Console.
- **Jon's device gate:** on the iPad, open Thanksgiving Week › **Prep** and check two of today's steps. On the iPhone,
  open **Prep** for the same menu and see them checked. Leave one of today's steps unchecked, and the next day find it
  under **Still open**. Swipe a step to **Tomorrow** and see it move. Tap a step and read its recipe in the pane. In
  the Prep Plan column, confirm the checked steps show checkmarks.
