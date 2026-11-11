# Effort — `stage_prep_plan`: a chat replaces the prep plan for the dishes it names

Status: Ready
Summary: A new MCP staging tool, `stage_prep_plan`, sends the whole prep plan for some of a menu's dishes. The app reviews it per dish (New, Kept, Removed) and Apply replaces only those dishes' steps in one transaction, linking each new step to its dish. `get_menu` now shows the menu's current plan. No schema change; the export gains an optional `prepPlan` on menus.

Origin: the S6 device pass (2026-11-10). The chat that planned Thanksgiving Week's Day 3 dinner also wrote its prep
plan and, with no tool for it, offered to put the schedule in the dish notes. One dispatch, one PR. **No schema
change.**

Decisions: [ADR-0060 Amendment 5](../decisions/ADR-0060-chat-access-over-mcp.md#amendment-5--a-chat-can-replace-the-prep-plan-for-the-dishes-it-names-2026-11-10)
(D1–D6; read it first). Builds on Amd 3 (the closest precedent: a staged replacement, matched rows keep their ids,
a drift banner) and Amd 2-D1 (refs resolved at staging). Related: [archived `stage-menu-day`](archive/stage-menu-day.md)
(copy its shape) · [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) and
[ADR-0063](../decisions/ADR-0063-menus-absorb-calendar-days.md) (the plan's sessions and work days) ·
[`from-chat-destination`](archive/from-chat-destination.md) (moves the From Chat list; if it merges first, this row and
sheet live there, unchanged).

## Where things are (architect, 2026-11-10, `origin/main` 5153ee0)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `MenuPrepPlan.swift`:
  - `PrepPlanStepRecord`, with `session`, `task`, `serves`, `sourceDish`, `workDayOffset`.
  - `PrepPlanStepRepository`: `replace` (whole plan, keeps ids by `Contents`), `steps(for:)`, and the private
    `writeSortOrder`.
  - `PrepPlanDishMatcher.suggestedSourceDish(serves:among:)` — D2's rule 2. It returns a match only when exactly one
    dish matches.
  - `MenuPrepPlan.parse` shows the existing `workDay` convention (1-based, −6 to `dayCount`, stored as
    `workDayOffset = workDay − 1`, and nil on a one-day menu). This tool's `workDay` is **0-based**, so it maps
    straight onto `workDayOffset` (−7 to `dayCount − 1`).
- `MenuPrepPlanBands.swift`: how the plan groups by work day and session. Use it to check the D5 ordering rule.
- `ChatAccessExport.swift`: `MenuRecord` (about line 36) and where it's built (about line 172). Add
  `prepPlan: [PrepStepRecord]?` with `workDayOffset`, `session`, `task`, `serves` and `dishIndex: Int?` (the
  linked row's index in that menu's `items`). Keep `version` at 1; the field is optional.
- `ChatAccessStagedItems.swift`: `ChatAccessStagedMenuDay` and `ChatMenuDayImport`. Copy both shapes for
  `ChatAccessStagedPrepPlan` and `ChatPrepPlanImport`. Amd 3-D3's row matching is in `ChatMenuDayImport.plan`;
  factor it out rather than copy it.
- `ChatAccessInbox.swift`: `menuDayRows` and `menuDayMetadata`. Add `prepPlanRows` beside them.
- `ChatAccessServerInstructions.swift`: the opening.

**Helper (`YesChefMCP/Sources/YesChefMCPServer/`)**
- `YesChefMCPServer.swift`: `stage_menu_day`'s tool, `decodeAndStageMenuDay`, and `StageContext.stageMenuDay`.
- `ChatAccessReadTools.swift`: `get_menu` (about line 168), and `ChatAccessExportStore.resolveMenu` /
  `resolveRecipes`.

**App (`YesChefApp/`)**
- `ChatAccessInboxFileClient.swift`: the kinds list. Add `ycprepplan` with the same flags as `ycmenuday`.
- `ChatAccessInboxModel.swift`: `open(_ MenuDayRow)`, `applyMenuDay`, `discard(_ MenuDayRow)`, and the
  `ChatAccessInboxReview` enum. Follow them.
- `ChatMenuReviewSheet.swift`: `ChatMenuDayReviewSheet`. Follow its look.
- `ChatAccessInboxView.swift`: the menu-day rows and the `.sheet(item: $model.review)` switch.

## The slice

### Core

- **The envelope.** Add `ChatAccessStagedPrepPlan`, with loud decoding like `ChatAccessStagedMenuDay`:
  - `format` `"yc-prep-plan"`, `version` 1;
  - `menuID`, `menuTitle`;
  - `dishes: [Dish]`, where a dish has `dayOffset`, `recipeID?`, `title` and `steps: [{workDayOffset?, session,
    task}]`;
  - `planAtStage: [PrepStepRecord]?` (nil when the export had none).
- **The plan.** Add `ChatPrepPlanImport.plan(_ envelope:, in db:) throws -> Plan`, as a pure function:
  - **Resolve each dish to its row** with Amd 3-D3's matching on that day. If the menu is gone, throw
    `menuUnavailable`; if a dish is no longer on the menu, throw `dishUnavailable(title)`.
  - **For each dish, find the steps it owns** (Amd 5-D2): `sourceDish` is the row, or `sourceDish` is nil and
    `PrepPlanDishMatcher` picks this row among **all** the menu's rows. Mark the second kind `matchedByName`.
  - **Match staged steps to owned steps** on (work day, session, task), trimmed. A match is **Kept**; unmatched
    staged steps are **New**; unmatched owned steps are **Removed**.
  - **Set `planChangedSinceStage`:** the menu's live plan against `planAtStage`, as a multiset of (work day,
    session, task, serves). Nil when `planAtStage` is nil.
- **Apply.** Add `ChatPrepPlanImport.apply(_ plan:, keeping:, in db:, now:, uuid:)`, where `keeping` is the set of
  New steps Jon left on. In one transaction:
  1. Delete the Removed steps.
  2. Insert each kept New step with `sourceDish` set to its dish's row and `serves` set to the row's title.
  3. Leave Kept steps and every step outside the named dishes alone. A Kept step that was matched by name gets its
     `sourceDish` set, which is the only write to it.
  4. Order the inserts by Amd 5-D5's rule, then renumber `sortOrder`, writing only the rows that change.
  5. Touch the menu's `dateModified`.
- **The export.** Fill `MenuRecord.prepPlan` from `PrepPlanStepRepository.steps(for:)`.
- **The opening** (Amd 5-D6), within 512 characters:

  > These are Yes Chef's recipe tools. Read with `search_recipes`, `get_recipe`, `list_menus`, `get_menu`,
  > `get_meal_plan`. In a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`. Without
  > one, stage a new recipe (`stage_recipe`), changes to a recipe (`stage_recipe_return`), a new menu
  > (`stage_menu`), one day of a menu (`stage_menu_day`), or the prep plan for some of a menu's dishes
  > (`stage_prep_plan`). Nothing is saved until Jon reviews it in the app.

  Add one sentence after the `stage_menu_day` paragraph: for `stage_prep_plan`, read the menu with `get_menu`
  first, send every step for each dish you name, and keep the steps to tasks.

### Helper

- **`get_menu`** adds `prepPlan`: an array of `{workDay, session, task, dish}`, where `dish` is the linked item's
  `"<title>, day N"`, or else its `serves` text. Omit `workDay` on a one-day menu. No ids.
- **`stage_prep_plan`**, input per Amd 5-D3, all three levels with `additionalProperties: false`.
  - **Description:** per Amd 5-D6, all four points, plus "Nothing is saved until Jon reviews it."
  - **Checks,** all-or-nothing:
    - the menu ref (the read tools' messages);
    - 1 to 20 dishes, at most 80 steps in all, and at most 40 per dish;
    - each dish: `day` in range, and exactly one of `ref` or `title`;
    - each dish exists on that day in the export: a `ref` names a recipe row with that recipe on that day, and a
      `title` names a note or reservation row on that day;
    - each step: `workDay` is a whole number from −7 to `dayCount − 1` (and absent or 0 on a one-day menu), and
      `session` and `task` are non-empty, with `task` at most 500 characters.
  - **File:** `HandoffInbox(root: inbox, fileExtension: "ycprepplan")`, with the slug from the menu title.
    `planAtStage` is the export menu's `prepPlan`.
  - **Result:** `{staged: "<menu title> prep plan", dishes: N, steps: N, next: "Jon reviews it in Yes Chef → From
    Chat."}`.
- **`stage_menu_day`'s description** gains: "To stage its prep plan, use `stage_prep_plan`."

### App

- **The inbox kind** `ycprepplan`:
  - Rows titled **"Prep plan · <menu title>"**. If the menu isn't on this device, the row reads **"Menu not found
    on this device"** and offers Discard only, as `ycmenuday` does.
  - `inboxCount` counts openable rows.
- **Opening a row:** read, decode, and run `plan` in a `database.read`. A decode or plan error shows on the row, and
  the file stays.
- **The review sheet** (`ChatPrepPlanReviewSheet`, in the day review's style):
  - The title is the menu.
  - **The drift banner** (`.attentionCard()`): "This plan changed since Chat read it." when
    `planChangedSinceStage` is true; "Chat couldn't see the current plan." when it's nil.
  - **One section per dish:**
    - **New**, each step with a keep toggle;
    - **Kept**;
    - **Removed**, with "Matched by name" on those steps.

    Each step shows its work day (as the day's date when the menu is placed, else "Day N"), its session and its
    task.
  - **Apply** and **Cancel**. Apply runs `apply` in one `database.write`, posts "Prep plan updated.", opens the menu,
    then claims the file. A failed write shows in the sheet.
- **Discard** claims the file.

### Out of scope

- Steps that serve no dish (Amd 5 OQ8).
- Any change to the hand-off prep plan, or to `PrepPlanStepRepository.replace`.
- Writing to a recipe or a menu row.

## Tests

**Helper**
- Staging decodes into the envelope, and `planAtStage` is that menu's plan only.
- `get_menu` returns `prepPlan` with dish titles and no ids, and omits it for an export without one.
- Each check rejects and stages nothing:
  - a stale ref, or a recipe ref passed as `menu`;
  - 0 dishes, or 21 dishes;
  - 81 steps in all;
  - a dish not on that day, and a dish with both `ref` and `title`;
  - `workDay` out of range, or not an integer;
  - an empty `task`.
- No ids in the result. The opening is at most 512 characters and names `stage_prep_plan`.

**Core**
- **Ownership:**
  - a linked step is owned;
  - an unlinked step whose `serves` names the dish is owned and marked matched by name;
  - an unlinked step whose `serves` matches two dishes is not owned;
  - a linked step for another dish is untouched.
- **Replacement:**
  - an identical staged step is Kept with its id, and isn't written;
  - a missing one is Removed;
  - a new one is inserted, linked, with `serves` set to the row's title;
  - a dish with no steps has all of its steps removed;
  - a dropped New step isn't inserted.
- **Scope:** steps for unnamed dishes, and steps with no dish, are unchanged after Apply, ids and order included.
- **Order:** a new step lands after the last step with its work day and session, or else the last on its work day.
- **Drift:** false for an untouched plan, true after a step edit, nil without `planAtStage`.
- **Errors:** a deleted menu, or a dish deleted from the menu, throws the typed error, and Apply writes nothing.
- **Export:** `prepPlan` carries `dishIndex` for linked steps, and an export without the field decodes.

**App (`YesChefTests`):** opening a `ycprepplan` row presents the review, and Apply writes and claims the file.
This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- `stage_prep_plan` stages a checked, all-or-nothing envelope, and `get_menu` shows the plan.
- The review shows New, Kept and Removed per dish, with the drift banner.
- Apply replaces only the named dishes' steps, in one transaction, and the new steps are linked.
- No ids in tool output. The opening is per Amd 5-D6.
- Tests above. Verification per [`verification.md`](../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- The PR body gives Jon the install order: the app on both devices first (it writes the new export field), then the
  helper.
- **Jon's device gate:** in ChatGPT, read Thanksgiving Week, then stage the prep plan for Day 3's dinner dishes.
  - In the review, the steps are grouped under their dishes.
  - After Apply, the plan shows them in the right work days, and a step opened in the editor shows its dish linked.
  - Then restage one dish with one step changed: the review shows one New, one Removed, and the rest Kept, and the
    other dishes' steps are untouched.
