# Effort — `stage_menu_day`: a chat replaces one day of an existing menu

Status: Ready
Summary: A new MCP staging tool, `stage_menu_day`, sends the whole of one day of a menu that already exists. The app opens it in a before-and-after review, and Apply replaces the day in one transaction. A dish that stays on the day keeps its row, along with its id, grocery sources and prep-step links. Dishes that aren't sent are deleted, as if Jon deleted them. No schema change, no export change.

Origin: Jon planning one dinner of the 7-day Thanksgiving Week menu with ChatGPT (2026-11-10). One dispatch, one PR.
**No schema change.**

Decisions: [ADR-0060 Amendment 3](../decisions/ADR-0060-chat-access-over-mcp.md#amendment-3--a-chat-can-replace-one-day-of-a-menu-that-already-exists-2026-11-10)
(D1–D5; read it first). Builds on Amd 2-D4 (`stage_menu`, the `ycmenu` inbox kind and its review). Related:
[archived `chat-started-returns-and-menus` brief](archive/chat-started-returns-and-menus.md) (S5 is the closest
precedent, and most of this slice copies its shape) · [`menu-row-note-on-recipe`](menu-row-note-on-recipe.md)
(independent; shows the row's note on the recipe screen).

## Where things are (architect, 2026-11-10, `origin/main` 9ac187a)

**Helper (`YesChefMCP/Sources/YesChefMCPServer/`)**
- `YesChefMCPServer.swift`:
  - `stagingTools` (about line 195) holds `stage_menu`'s schema (`itemProperties`, `itemSchema`).
  - `decodeAndStageMenu` (about line 238) has every item check. **Factor the per-item checks out** so both tools
    share them; don't copy them.
  - `StageContext.stageMenu` (about line 89) writes the `ycmenu` file. Copy it for `ycmenuday`.
- `ChatAccessReadTools.swift`:
  - `RefKind`, `resolveIndex` (about line 205), and `ChatAccessExportStore.resolveRecipes` (about line 80).
  - Add a menu resolver beside `resolveRecipes` that returns the export's `MenuRecord` (id, title, `dayCount`,
    items) for a `.m` ref, with the existing stale and wrong-kind messages.
- **Tests:** `YesChefMCP/Tests/YesChefMCPTests/YesChefMCPTests.swift`.
  - `stagingToolDescriptionsCarryTheHandoffRouting`: the descriptions carry the routing, because ChatGPT doesn't
    show the model the server instructions.
  - `containsUUID` asserts that no tool output leaks an id.

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `ChatAccessStagedItems.swift`: `ChatAccessStagedMenu` (the loud-decoding envelope, `format`/`version`) and
  `ChatMenuImport` (`resolve`, `create`). The day envelope and its import go beside them.
- `ChatAccessInbox.swift`: `menuRows(from:)` (about line 79) lists `ycmenu` files. Add `menuDayRows` beside it.
- `ChatAccessServerInstructions.swift`: the opening and the `stage_menu` paragraph.
- `ChatAccessExport.swift`: `MenuRecord` has `id`; `MenuItemRecord` has kind, title, recipe id, day, slot, note and
  scale. **No change here.**
- `MenuCore.swift`, `MenuRepository`:
  - `addRecipeItem`, `addNoteItem`, `updateRecipeItem`, `updateNoteItem`, `deleteItem`, `reorderItems`.
  - `validateDayOffset`, `nextSortOrder`.
  - `RecipeScaleRepository.setScale(_:for: .menuItem(id), in:)` (`RecipeScaleCore.swift`) sets a row's scale.
- `MealCalendarCore.swift`: `MenuPlacementDay.date(for:from:)` gives a placed menu's day its date.
- Rows other tables point at: `GroceryItemSource.menuItemID` and `PrepPlanStepRecord.sourceDish`
  (`MenuPrepPlan.swift`). **This is why matched rows must keep their ids.**

**App (`YesChefApp/`)**
- `ChatAccessInboxFileClient.swift` (about line 19): the `ycmenu` `ChatInboxItemKind`. Add `ycmenuday` with the same
  flags, and add it to `maintain` and `claim`.
- `ChatAccessInboxModel.swift`: `open(_ MenuRow)` and `createMenu(from:)` (about lines 219–285) are the model for
  open, review, write, then claim. Follow their order, including "close the review before claiming."
- `ChatMenuReviewSheet.swift`: `ChatMenuReviewModel` and the sheet. Follow its look for the day review.
- `ChatAccessInboxView.swift`: the **From Chat** list.

## The slice

### Core

- **The envelope.** Add `ChatAccessStagedMenuDay`, `Codable`, with loud decoding like `ChatAccessStagedMenu`:
  - `format` `"yc-menu-day"`, `version` 1;
  - `menuID`, `menuTitle`, `dayOffset`;
  - `items: [ChatAccessStagedMenu.Item]`, in the order sent (reuse the item type);
  - `dayAtStage`: an array of `{kind, title, recipeID?, slot, note?, scale}` taken from the export.
- **The plan, as a pure function.** Add `ChatMenuDayImport.plan(_ envelope:, in db:) throws -> MenuDayPlan`. It reads
  the live menu and that day's rows and runs Amd 3-D3's matching:
  - **Matching a recipe item:** a live `.recipe` row with the same `recipeID`, same slot first, then any slot.
    Each live row is matched at most once, in proposal order.
  - **Matching a dish without a ref:** a live `.note` or `.reservation` row whose title matches (trimmed,
    case-insensitive), same slot first.
  - **A recipe item whose recipe is missing or archived here** doesn't match a recipe row. It becomes a note-row
    proposal with its title and is flagged, as in `ChatMenuImport.resolve`.
  - **The output:**
    - one entry per proposed item: `.kept(row)`, `.changed(row, changes)` or `.new(resolution)`;
    - `removed`: the unmatched live rows;
    - `dayChangedSinceStage: Bool`, comparing the live day with `dayAtStage` as a multiset of
      (kind, title, recipe id, slot, trimmed note, scale).
  - **The changes on a matched row** are the slot, the note (set, changed, or removed) and the scale. "No `note`"
    means no note, and "no `scale`" means 1 (Amd 3-D2).
  - It throws a typed `menuUnavailable` if the menu is gone, and `dayOutOfRange` if the menu now has fewer days.
- **Apply.** Add `ChatMenuDayImport.apply(_ plan:, keeping:, in db:, now:, uuid:)`. `keeping` is the set of proposed
  entries Jon didn't drop. A dropped `.kept` or `.changed` entry's row is **removed**, because the day is replaced.
  In one transaction:
  1. Delete the removed rows with `MenuRepository.deleteItem`.
  2. Update the matched rows' slot and note through `updateRecipeItem` or `updateNoteItem` (keep the row's
     `recipeID` and title), and set their scale.
  3. Add the new rows with `addRecipeItem` or `addNoteItem`, then set their scale.
  4. Within each slot, set `sortOrder` in proposal order. Write only rows whose order actually changes.
  5. Touch the menu's `dateModified`.

  A matched row that doesn't change isn't written (guardrail #4).
- **The instructions.** Use Amd 3-D5's opening verbatim. Add the day sentence to the `stage_menu` paragraph. Update
  the 512-character opening test to require `stage_menu_day`.

### Helper

- **`stage_menu_day`.** Input `{menu: string, day: integer, items: [item]}`, all three required. The item schema is
  `stage_menu`'s without `day`, with `additionalProperties: false`. Annotations: `readOnly false, destructive false,
  openWorld false`. Nothing is written until Jon applies it.
  - **Description:** Amd 3-D5. It must say the items are the whole day; that anything not sent is removed,
    including a note or scale that isn't carried over; to read the menu with `get_menu` first; that a note is for
    this dish on this menu only; that a recipe change goes through `stage_recipe_return`; and that the day must
    exist.
  - **Checks,** all-or-nothing:
    - **The menu ref is stale, missing, or not a menu:** the read tools' messages.
    - **`day`** isn't a whole number from 0 to `dayCount - 1`: "day must be from 0 to N".
    - **`items`** has fewer than 1 or more than 40 entries.
    - **Each item:** the shared `stage_menu` item checks.
  - **File:** `HandoffInbox(root: inbox, fileExtension: "ycmenuday")`, slug from the menu title and day, and the
    encoded envelope. `dayAtStage` is the export menu's items with `dayOffset == day`.
  - **Result:** `{staged: "<menu title>, day N", dishes: <count>, next: "Jon reviews it in Yes Chef → From Chat."}`.
    **No id.**
- **`stage_menu`'s description:** Amd 3-D5's sentence.

### App

- **The inbox kind** `ycmenuday`. Its rows are `ChatAccessInbox.menuDayRows`, titled **"Menu day · <menu title>,
  <day>"**, where day is the placed date or "Day N+1".
  - **The menu isn't on this device:** the row reads **"Menu not found on this device"** and offers **Discard**
    only. It's never claimed automatically.
  - `inboxCount` includes openable rows.
- **Opening a row:** read and decode, run `ChatMenuDayImport.plan` in a `database.read`, and present the review. A
  decode or plan error shows on the row, and the file stays.
- **The review sheet** (`ChatMenuDayReviewSheet`, in the `ChatMenuReviewSheet` style):
  - The title is the menu and the day.
  - When `dayChangedSinceStage`, a banner (`.attentionCard()`) reads **"This day changed since Chat read it."**
  - **The day after Apply:** grouped by slot, one row per proposed entry, marked **Kept**, **Changed** (with each
    change spelled out, such as the new note, "Note removed", or "Scale 2× → 1×"), or **New** (**In your library** /
    **New dish**, with the missing-recipe flag). Each row has a keep toggle.
  - **"Removed"**: the live rows that will be deleted, plus any kept or changed row Jon toggled off.
  - **Apply** and **Cancel**. Apply runs `apply` in one `database.write`, posts "Day updated.", opens the menu,
    then claims the file. A failed write shows in the sheet, the same as `createMenu`.
- **Discard** claims the file.

### Out of scope

- Adding days, or several days per call (Amd 3 OQ7).
- Cleaning up grocery items or prep steps that pointed at a removed row. A removed row behaves exactly like one
  deleted in the app.
- Any write to a recipe.

### Tests

**Helper**
- Stage a day and decode the envelope. `dayAtStage` holds only that day's rows.
- Each check: a stale menu ref, a recipe ref passed as `menu`, `day` out of range, `day` not an integer, 0 items,
  41 items, and one bad item (an archived recipe). Any failure stages nothing.
- No ids in the result. The 512-character opening names `stage_menu_day`. `stage_menu`'s description names it.

**Core**
- **Matching:**
  - the same recipe stays, so the row keeps its id and its unchanged scale, and isn't written;
  - the same recipe moves from lunch to dinner, so the same row's slot changes;
  - the same recipe twice on the day, once each in two slots, so each proposal matches its own slot's row;
  - a note row matched by title, ignoring case and whitespace;
  - a reservation stays a reservation;
  - a recipe missing on this device becomes a flagged new note row.
- **Replacement:**
  - a live row not sent is removed;
  - a matched row with no `note` loses its note, and with no `scale` goes to 1;
  - a kept row Jon drops is removed;
  - rows take the proposal's order within each slot.
- **Identity:** a grocery source and a prep step pointing at a kept row still resolve after Apply.
- **Drift:** `dayChangedSinceStage` is false for an untouched day and true after a note edit.
- **Errors:** the menu deleted, or its day count lowered, throws the typed errors, and Apply writes nothing.
- **One transaction:** a failure partway leaves the day as it was.
- **Other days of the menu are untouched.**

**App (`YesChefTests`):** opening a `ycmenuday` row presents the review, and Apply updates the day and claims the
file. This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- `stage_menu_day` stages a checked, all-or-nothing envelope.
- The app's review shows Kept, Changed, New and Removed, plus the drift banner.
- Apply replaces the day in one transaction, and a dish that stays keeps its row.
- No ids in tool output. The opening is per Amd 3-D5.
- Tests above; verification per [`verification.md`](../verification.md), including the generic app build and
  `YesChefTests`; closeout (ADR-0005 D16). The PR body gives Jon the install order: the app on both devices
  first, then the helper.
- **Jon's device gate:** in ChatGPT, read Thanksgiving Week, then restage one day:
  - keep the souvlaki with a new note;
  - drop one dish and add one new dish.

  Check that the review shows those as Changed, Removed and New. After Apply, the souvlaki's grocery items still
  name it, and the calendar shows the new day.
