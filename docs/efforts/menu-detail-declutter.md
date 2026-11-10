# Effort — Menu detail declutter: one AI menu, an Edit sheet, and rows without buttons

Status: Ready
Summary: The menu screen's AI controls collapse into the house toolbar AI menu, Place and the Calendar section become an Edit Menu sheet, dish rows lose their trailing buttons, the Playbook toggle, project field and big empty states go, and three custom symbols replace `book.badge.plus` and `calendar.badge.plus`.

Jon's iPad pass on Thanksgiving Week 2026, 2026-11-10. He approved the comp the same day. One dispatch, one PR. No schema
change.

Decisions: [ADR-0064](../decisions/ADR-0064-menu-detail-declutter.md).
Related: jon-platform `docs/ios/ui-and-platforms.md` § Controls (read it first: row actions, toolbars, the AI
entry point) · [ADR-0063](../decisions/ADR-0063-menus-absorb-calendar-days.md) (placement and Bring In, unchanged in
behavior) · [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md) (the Playbook column) ·
[standing guards](../standing-guards.md).

## Where things are (architect, 2026-11-10)

- **Toolbar:** `MenuDetailView.toolbar` (`YesChefApp/MenuViews.swift`, about line 166) has Focus on the leading side,
  then Cook these and Browse Recipes. The Show/Hide Playbook item is added separately in `MenuDetailReader.body`
  (`YesChefApp/MenuPlaybookColumnView.swift`). The recipe screen's toolbar (`RecipeDetailView.recipeToolbar`) is the
  model to copy: a primary group ending in `HandoffMenu`, and Edit as `square.and.pencil`.
- **Playbook header:** `MenuDetailReader.menuPlaybookHeader` holds the column's `HandoffMenu` and Regenerate whole plan.
  The rebuild itself is `MenuDetailModel.regeneratePrepPlan()` (`MenuDetailModel+Chat.swift`).
- **Prep Plan section:** `MenuPrepPlanSection` (`MenuViews.swift`, about line 329) has the `⋯` menu, Add Step, the empty
  `ContentUnavailableView`, and the clear confirmation. Its `handoffSource` and `regenerateHandoffSource` are
  `.menu(id)` and `.menu(id, prepPlanIntent: .regenerate)`. Learnings: `LearningsSection`.
- **Body:** `MenuDetailReader.menuBody` lays out `MenuDetailHeader`, `MenuExternalProjectField`, `MenuDishList` and
  `MenuPlacementList`. The day header is `MenuDaySection`, the row is `MenuDishRowView`, and Place is `dishHeader`, all
  in `MenuDetailSections.swift`.
- **Chat target:** `MenuDetailModel.selectedTargetItemID` and `targetItemTapped(_:)` (`MenuModels.swift`). Whether
  Ask is open is `detailModel.tool` being `.chat`. The deposit actions read `selectedTargetItem`.
- **Menu sheets:** `MenuLibraryModel.Destination` has `addMenu` / `placeMenu` / `bringIn` / `deletePlacement` and
  others. The sheets are attached in `RecipeLibraryView.swift` (about line 113). `MenuEditorView` is the add-menu form,
  and `MenuPlacementEditorView` is start date plus days. `savePlacementButtonTapped` does the day-count and placement
  write, then the Bring In offer.
- **Project name:** `MenuExternalProjectField` (`MenuViews.swift`), `MenuDetailModel.updateExternalProjectName`,
  `MenuRepository.updateExternalProjectName` (`MenuCore.swift`), and the hand-off entity's `externalProjectName`
  `@Property` (`AppIntents/HandoffEntities.swift`, filled in `AppIntents/HandoffIntents.swift`).
- **Playbook toggle:** `MenuPlaybookColumnPreferences.visibilityStorageKey`, `MenuWideColumnLayout.isPlaybookVisible`
  (`RecipePlaybookColumnLayout.swift`) and `MenuWideColumnLayoutTests`.
- **Symbols:** the source templates are in `docs/design/symbols/`. The app's asset catalog is
  `YesChefApp/Assets.xcassets`, which holds no symbol sets yet.

## S1 — One toolbar AI menu; the Playbook column goes quiet (ADR-0064 D1, D2, D7)

**Build.**
- The trailing primary group becomes Cook these (when it applies), **Add Recipes**, **Edit** (S2), and the house
  `HandoffMenu`, in that order:
  - **Add Recipes** is today's Browse Recipes action, relabelled, with the `custom.richtext.page.badge.plus` symbol
    (S3).
  - In `HandoffMenu`, **Hand off** is a submenu with **Menu** (`.menu(id)`), **Fresh prep plan**
    (`.menu(id, prepPlanIntent: .regenerate)`) and **Recipe capture request** (`copyRecipeCaptureRequest()`).
  - **Paste** routes to `.menu(id)`.
  - **Ask now** binds to the same `isAskActive` / `askButtonTapped` pair the column uses today.
  - Use `LLMHandoffUI`'s menu-purposes initializer if it fits. If it can't take a submenu, extend `HandoffMenu` in
    jon-platform `LLMHandoffKit` rather than hand-rolling a lookalike, and say so in the PR.
- Delete `menuPlaybookHeader`, which removes the column's AI menu and Regenerate whole plan.
- In `MenuPrepPlanSection`:
  - The `⋯` menu becomes **Rebuild with Yes Chef…** (calls `regeneratePrepPlan`, disabled when the plan has no steps,
    as the button is today), a divider, then **Clear Prep Plan**. The hand-off and paste items and Copy Recipe Capture
    Request are removed. Drop the now-unused `handoffSource` and `regenerateHandoffSource` parameters, unless something
    else reads them.
  - **Add Step** becomes an icon-only `plus` button beside the heading, before `⋯`, keeping the label "Add Step".
  - The empty state becomes one `.tertiary` line, "No steps yet.".
- In `LearningsSection`, Add Learning becomes an icon-only `plus` beside the heading, and the empty state becomes "None
  yet.".
- Remove the Show/Hide Playbook toolbar item, the `@AppStorage` visibility property and
  `MenuPlaybookColumnPreferences.visibilityStorageKey`. `MenuWideColumnLayout` drops `isPlaybookVisible`, because the
  column is always visible. Update `MenuWideColumnLayoutTests`: drop the hidden case and keep the width cases.

**Acceptance.** The menu screen has one AI menu, in the toolbar, with Hand off (three purposes), Paste and Ask now. The
Playbook column has no AI controls. Every action removed above is still reachable from its new home.

## S2 — Edit Menu sheet replaces Place and the Calendar section (ADR-0064 D3, D4)

**Build (Core).**
- `MenuRepository.updateMenu(menuID:title:notes:in:now:)`. The title is required, after the same normalization as
  `addMenu` (empty title throws as `addMenu` does). Empty notes are stored as `nil`. It bumps `dateModified`.

**Build (App).**
- Add a `MenuLibraryModel.Destination.editMenu(MenuEditDraftContext)` case. The context carries the menu id, title,
  notes, `dayCount`, the minimum day count (the existing "occupied days" floor), and the placements as id plus start
  date.
- **Edit Menu** sheet (`MenuEditView`), opened by the toolbar pencil:
  - **Menu** section: Title, and Notes as a multi-line field.
  - **Days**: a stepper from the minimum to 14, as in the placement editor today.
  - **Calendar**: one `DatePicker` row per placement, then **Place on Calendar…**, which adds a draft start-date row
    defaulting to today. When `detail.bringInOffer` is non-nil, show **Bring In Calendar Items…** with the
    `custom.menucard.arrow.in` symbol. Each existing placement row has a **Remove from Calendar** swipe and context
    action.
  - Remove from Calendar and Bring In close the sheet without saving, then present their existing confirmations
    (`deletePlacementButtonTapped`, `bringInButtonTapped`). Name that behavior in a code comment.
  - **Save** calls a new `saveMenuEditsButtonTapped(context:)`. In **one** write it calls `updateMenu`,
    `updateMenuDayCount` (which already clears out-of-range work days), `updateMenuPlacement` for each moved date, and
    `placeMenu` for each new row. Normalize dates with `startOfDay` as `savePlacementButtonTapped` does.
  - After a successful save that added or moved a placement, compute and present the Bring In offer exactly as
    `savePlacementButtonTapped` does. Pull that tail into one private helper both paths use.
- Remove `MenuDishList.dishHeader`'s **Place** button. Keep the "Dishes" heading.
- Delete `MenuPlacementList`. Only Menu detail opens the placement editor today, through Place and the Calendar
  section's Change Start Date. So also delete `MenuPlacementEditorView`, `placeMenuButtonTapped`,
  `editPlacementButtonTapped`, `savePlacementButtonTapped` and the `placeMenu` destination. Move their tests to the
  edit path. `deletePlacementButtonTapped` and its confirmation stay.
- `MenuDetailHeader`'s metadata line:
  - With one placement: the date range, then the counts ("Sun, Nov 22 – Sun, Nov 29 · 8 days · 4 dishes").
  - With several: "On the calendar N times · …".
  - With none: the counts only.
  - Use the shared ADR-0063 day-arithmetic helper for the end date. Don't add a second copy.
- **Project name:** delete `MenuExternalProjectField`, `MenuDetailModel.updateExternalProjectName`,
  `MenuRepository.updateExternalProjectName`, and the hand-off entity's `externalProjectName` property and the code
  that fills it. Leave the `Menu.externalProjectName` column, its `Schema.swift` definition and any migration
  untouched (ADR-0056). Remove tests that cover only the deleted repository function.

**Acceptance / tests.**
- Core: `updateMenu` saves the title and notes, normalizes empty notes to `nil`, and throws on an empty title.
- App model (`YesChefTests`):
  - Saving the edit context writes the title, notes, day count, a moved placement and a new placement in one save.
  - A save that adds a placement with something to bring in presents the offer.
  - A save that only renames presents nothing.
  - Shrinking the days below occupied days is blocked by the existing floor.

## S3 — Rows, day headers and symbols (ADR-0064 D5, D6, D8)

**Build.**
- **Symbols:**
  - Add three symbol image sets to `YesChefApp/Assets.xcassets`: `custom.richtext.page.badge.plus`,
    `custom.richtext.page.arrow.in` and `custom.menucard.arrow.in`. Each is a `.symbolset` holding the matching
    template from `docs/design/symbols/` and a `Contents.json` like the one Xcode writes when a symbol is dragged in.
  - Use them through generated asset symbols or `Label(_:image:)` / `Image(_:)`, never `systemImage:`.
  - Build once and confirm the asset catalog compiles them with no warnings.
- **`MenuDishRowView`:**
  - Remove the three trailing buttons: Make Recipe, Deposit target and Edit Dish.
  - Context menu, in order: **Edit**; **Move to Day** (existing); **Make Recipe** (notes only, the arrow-in symbol);
    **Set as Chat Target** / **Clear Chat Target** (only while Ask is open, calling `targetItemTapped`); then
    **Delete**.
  - Trailing swipe: unchanged (Delete, Move to Day).
  - Leading swipe: **Make Recipe** on notes and **Edit** on recipes.
  - While Ask is open, the target row shows a trailing `target` glyph (accessibility label "Chat target") and today's
    accent tint. With Ask closed, show neither and leave `selectedTargetItemID` as it is.
- **`MenuDaySection`:**
  - The title is "Sunday, Nov 22 · Day 1" when placed once, and "Day 1" otherwise. Drop the year and the parenthesized
    day.
  - The add button and the hand-off menu are icon-only. Keep the hand-off menu's `Label("Hand off", …)` with
    `.labelStyle(.iconOnly)` and its existing accessibility labels.
  - An empty day renders its header only: no chevron, a `.tertiary` "— no dishes" after the title, and no "No dishes"
    body row. The toggle does nothing for an empty day.

**Acceptance.** No dish row has a trailing action button. Every removed button's action is reachable from the context
menu, and the most common ones from swipe. `book.badge.plus` and `calendar.badge.plus` no longer appear on the menu
screen.

## Verification and completion

- No schema, sync or migration change. `externalProjectName` stays in the schema and becomes unused.
- Run focused tests, `scripts/check-drift.sh`, the generic device build and the `YesChefTests` app target per
  [verification.md](../verification.md). This touches `YesChefApp/` model code.
- Check `LLMHandoffKit` too if S1 extends `HandoffMenu`: its package tests, and confirm Galavant still builds against
  the change or doesn't consume the new API.
- Closeout per ADR-0005 D16. This dispatch archives the brief.
- **Gate (Jon, iPad, then iPhone):** On Thanksgiving Week 2026:
  - The toolbar reads Cook these · Add Recipes · Edit · AI. Hand off › Menu copies a prompt, and Paste routes the
    reply.
  - Ask now opens chat. Long-press a dish to set the chat target, and the ◎ appears on that row only. Close chat and
    the ◎ is gone.
  - Prep Plan's ⋯ › Rebuild with Yes Chef… runs the rebuild through review.
  - Edit renames the menu and changes a date, and the Bring In offer appears when it should.
  - Long-press a note row and Make Recipe works.
  - Empty days and empty Prep Plan and Learnings read quietly.
  - The three new symbols render crisply at toolbar and menu size, in light and dark.

## Dispatch ledger

- [ ] Dispatch 1 — S1 + S2 + S3, one PR. No schema.
