# Effort — A menu brings in its calendar days, and a multi-day prep plan runs by work day

Status: Ready
Summary: Placing a menu offers to bring in the calendar items and wholly-contained placed menus on its days, cooking history starts counting placed menus, and a multi-day menu's prep plan groups by the day the work happens, with today opening itself.

Jon asked on 2026-11-08 to plan days on the calendar, then define a menu over them and get one prep plan for the
result, and to pull Thanksgiving 2026 into Thanksgiving Week 2026. He accepted the design the same day.

Decisions: [ADR-0063](../decisions/ADR-0063-menus-absorb-calendar-days.md).
Related: [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) (prep plan, bands, the anchoring this
builds) · [ADR-0062 D8](../decisions/ADR-0062-serve-with-recipe-links.md) (the Production field gate copied in S3) ·
[standing guards](../standing-guards.md).

## Where things are (architect, 2026-11-08)

- Placement: `MenuLibraryModel.savePlacementButtonTapped` (`YesChefApp/MenuModels.swift`) saves `dayCount` and the
  placement in one write. `MenuRepository.placeMenu` / `updateMenuPlacement` / `updateMenuDayCount` are in
  `YesChefCore/MenuCore.swift`.
- Calendar projection: `MealCalendarRequest.projectedMenuRows` (`MealCalendarCore.swift`) adds `dayOffset` days to
  `placement.startDate` with a Gregorian calendar. Placement start dates are saved as
  `Calendar.autoupdatingCurrent.startOfDay`.
- History: `RecipeCookingHistory` (`MealCalendarCore.swift`) counts past recipe-kind `MealPlanItem` rows only. It's
  read by `RecipeBrowser` (whole library) and `RecipeLastCookedAtRequest` (one recipe).
- Grocery provenance: `GroceryItemSource` carries `mealPlanItemID`, `menuID`, `menuItemID` and `menuPlacementID`.
  `contributionID` and `groceryScale` (`GroceryCore.swift`) look these up.
- Prep plan: `PrepPlanStepRecord` / `PrepPlanStep` / `MenuPrepPlan` editable review text / `MenuPrepPlanClient` are in
  `MenuPrepPlan.swift`. Banding is `MenuPrepPlanSessionBand.grouping`, private in `YesChefApp/MenuViews.swift`. The step
  editor is `YesChefApp/MenuPrepPlanEditingViews.swift`. The day-scoped hand-off instruction is
  `MenuDayHandoffScope.prepInstruction` (`MenuChatContext.swift`). Today it says "weave into the existing horizon
  bands".

## S1 — Cooking history counts placed menus (ADR-0063 D4)

**Build.**
- Pull the projection's day arithmetic into one shared Core helper: a placement, a day offset, and the scheduled day.
  Also the inverse: a placement and a date give a day offset, for S2. `MealCalendarRequest`, grocery placement
  generation (`addMenuPlacement`), the history query and S2 all use it. Don't leave a second copy.
- `RecipeCookingHistory.lastCookedValues` and `lastCookedValue` add, for every placement, each recipe-kind `MenuItem`
  whose projected day is on or before `today`. Those join the existing `MealPlanItem` counts, so `timesCooked` sums
  both and `lastCookedAt` is the max. Do it with a scoped read of `menuPlacements` and recipe-kind `menuItems`, plus
  Swift arithmetic, not SQL date math. The single-recipe path filters `menuItems` by `recipeID`.

**Acceptance / tests (Core).**
- A recipe on a past placed menu counts, and on a future placed menu it doesn't.
- A menu placed twice in the past counts twice.
- Calendar and menu rows combine: the count is the sum, and the date is the latest.
- The shared helper gives `MealCalendarRequest` the same days as before. Include a placement that spans a DST change.

## S2 — Bring in calendar days (ADR-0063 D1, D2, D3 without work days)

**Build (Core).**
- `MenuRepository.bringInOffer(menuID:in:) -> MenuBringInOffer?` is a pure read. It returns `nil` unless the menu has
  exactly one placement and there's something to bring in. It reports:
  - the loose `MealPlanItem` rows in the range (count, and per day if useful for copy);
  - the menus whose placements lie wholly inside the range (title, dish count, prep-step count);
  - the menus whose placements partly overlap (title).
  A placement of the menu itself never counts.
- `MenuRepository.bringIn(menuID:in:now:uuid:) -> MenuBringInResult` runs in the caller's write transaction and
  **recomputes the range itself**. It never trusts an offer. It throws if the menu no longer has exactly one placement.
  - Each loose item becomes a `MenuItem` with a fresh id and `dayOffset` from the S1 helper. Kind, `recipeID`, title,
    slot, notes and scale carry over. A recipe-kind item without a `recipeID` becomes `.note`. Then the `MealPlanItem` is
    deleted. Items whose recipe is archived still move.
  - Each wholly-contained menu: its items are copied with fresh ids and `dayOffset + shift`, where `shift` is the
    contained placement's start minus this placement's start. Its `prepPlanSteps` are appended after this menu's steps,
    in order, with `sourceDish` mapped to the new item ids (`nil` stays `nil`; an id that doesn't resolve becomes `nil`)
    and `session`, `task` and `serves` unchanged. Then that placement is deleted. The source menu, its items and its
    steps are untouched.
  - `sortOrder`: incoming items are appended after existing items in the same day and slot, keeping their relative
    order. Use the existing `nextSortOrder` logic.
  - Grocery sources are re-pointed in the same transaction. Rows with `mealPlanItemID` of a moved item, and rows with
    `menuPlacementID` of a deleted contained placement, get `origin = .menuPlacement`, `menuID` / `menuItemID` /
    `menuPlacementID` of the new row, and `mealPlanItemID = nil`. `scheduledDate`, `mealSlot`, titles and text stay.
  - `updateMenuDayCount` already refuses to shrink past occupied days. After bring-in, the moved items occupy those days
    too, which is correct.

**Build (App).**
- After `savePlacementButtonTapped` succeeds, new or edited, compute the offer. If there is one, present a confirmation
  through the model's `Destination`, not a boolean. It shows:
  - Title: "Bring Calendar Items into <menu>?"
  - Message: one line per part, such as "5 calendar items", "Thanksgiving 2026 — 4 dishes, 6 prep steps", and "Beach
    Brunch overlaps these days but runs past them, so it stays as is."
  - Buttons: **Bring In** and **Not Now**.
- Menu detail gets **Bring In Calendar Items…** wherever the placement actions already live. It's shown when the offer
  is non-nil and uses the same confirmation. Follow `ui-and-platforms.md` § Controls for placement.
- After bring-in, nothing navigates. The menu's rows update by observation.

**Acceptance / tests.**
- Core: offer `nil` with zero or two placements, and with nothing in range. Partly overlapping menus are listed and
  untouched. Loose items move with the right day, slot, kind, notes and scale. A recipe-kind item without a recipe
  becomes a note. A contained menu is copied with the shift, and its placement is deleted while the menu survives. Prep
  steps are appended with remapped `sourceDish`. Grocery sources are re-pointed, and `contributionID` and
  `groceryScale` still resolve. Every moved and copied item projects to the same calendar day and slot it showed before,
  so the calendar is unchanged apart from row identity. Bring-in recomputes rather than using a stale offer: add a
  calendar item between offer and write, and it moves too.
- App model (`YesChefTests`): saving a placement with candidates presents the offer. Saving with none, or on a menu
  with two placements, doesn't. Bring In writes, and Not Now writes nothing.

**Not in scope.** No undo or dissolve. No de-duplication. No work days on copied steps yet: S5 adds that. Until
Dispatch 2 lands, a copied plan keeps its session labels. Note this in the PR.

## S3 — A prep step carries a work day: schema, weave, review text (ADR-0063 D5, D8)

**Persistent model change (authorized by ADR-0063).**
- Append a migration: `ALTER TABLE "prepPlanSteps" ADD COLUMN "workDayOffset" INTEGER`. Never edit a shipped migration.
  Add `workDayOffset: Int?` to `PrepPlanStepRecord`, and `workDay`-backed `workDayOffset` to `PrepPlanStep` (Codable
  key `workDay`, 1-based, decoded with `decodeIfPresent`; old JSON decodes to `nil`).
- Existing rows start `nil`. Nothing is backfilled.
- Confirm a backup → restore round trip keeps the field, with a test if the backup path has table-level coverage
  today.

**Build.**
- `MenuPrepPlanClient.instructions`: on a menu with more than one day, emit `"workDay"`, the 1-based day the work happens
  (0 or below for days before Day 1, at most 7 before), or `null` for flexible work. Make `session` the time within that
  day. One-day menus don't emit it. Pass the menu's `dayCount` (and real dates when placed once) where the prompt is
  built, if the context doesn't already make it plain.
- `MenuPrepPlan` editable review text takes the menu's `dayCount`. When it's greater than 1:
  - Render headers as `Day N · <session>:` for dated steps, and plain `<session>:` for undated ones.
  - Parse `Day N` with an optional separator (`·`, `—`, `–`, `-` or `:`) and an optional session. With no session,
    store "Any time".
  - A day outside `[−6, dayCount]` (1-based) keeps the step undated and is counted in the parse result, which the
    review shows.
  - When `dayCount` is 1, rendering and parsing are unchanged.
- The hand-off copy-out prompt and `MenuDayHandoffScope.prepInstruction` ask for that format on multi-day menus, and
  "weave into the existing horizon bands" becomes "into the existing work days".
- `MenuPrepPlanRepository` create, update and replace carry `workDayOffset`. Apply (`applyPrepPlan` / `replace`) stores
  what the weave or the parsed text returned.
- `updateMenuDayCount` clears `workDayOffset` on this menu's steps with an offset at or past the new `dayCount`, in the
  same transaction.

**Acceptance / tests (Core).**
- Old JSON and old rows decode with no work day.
- Weave JSON with `workDay` stores the offset.
- Review text round-trips dated and undated steps on a 3-day menu, and is byte-identical to today on a 1-day menu.
- An out-of-range day keeps the step undated and is counted.
- "Day 2 prep:" on a 1-day menu stays a session label.
- Shrinking a menu clears steps past the end and keeps their text.
- The migration adds the column to an existing database with rows in it.

## S4 — Day bands, the Day picker, and today (ADR-0063 D6, D7)

**Build.**
- Move banding into Core as a pure function. It takes steps, `dayCount`, an optional single placement start, and
  `today`, and returns ordered bands.
  - `dayCount == 1`: today's session banding, unchanged (Flexible first).
  - `dayCount > 1`: *Flexible* (undated) first, then one band per work day in ascending order, negative days first.
    Steps keep plan order within a band, and each step carries its session sub-label only where it changes.
  - Each band has a title: with one placement, "Tue, Nov 24 · Day 2", or "Today" for today's band. Without one, "Day
    2", or "2 days before Day 1". It also has a step count and an `isToday` flag.
- `MenuViews.swift` renders the Core bands. The band whose `isToday` is set starts expanded, and the rest start
  collapsed. Expansion is view state, not persisted.
- `PrepPlanStepEditorSheet` adds a **Day** picker on multi-day menus. Its options are Flexible, then 7 days before Day 1
  up to the last day, labelled with real dates when placed once. New steps default to Flexible. The session picker is
  unchanged.
- Reorder stays within a band. Moving a step to another day goes through the editor.

**Acceptance / tests.**
- Core banding: one-day output equals today's. Multi-day bands are in order with Flexible first. Session sub-labels
  appear only on change. Titles are right with and without a placement, and the today flag is set only with one
  placement.
- App model: saving the editor with a Day writes `workDayOffset`.

## S5 — Copied prep steps get work days (ADR-0063 D3)

**Build.** In S2's `bringIn`, each copied step also gets a work day:
- A step that has `workDayOffset` gets `+ shift`.
- An undated step from a one-day source menu is dated through `PrepPlanSessionBand(matching:)`. `.dayOf` and
  `.atService` get the dish's day: that is, `shift`, since a one-day menu's dishes sit at offset 0. `.dayBefore` gets
  `shift − 1`. Anything else, or no match, stays `nil`.
- The bring-in confirmation's prep-step line is unchanged.

**Acceptance / tests (Core).** A one-day Thanksgiving menu with "The day before", "The day of", "At service" and
"Flexible" steps, brought into a 7-day week menu at offset 3, lands on 2, 3, 3 and `nil`. A dated multi-day source is
shifted. Session labels are unchanged.

## Verification and completion

- S1 and S2 change no schema. S3 adds one nullable column to a synced table, authorized by ADR-0063 D5/D8.
- Run focused tests, then `scripts/check-drift.sh`, the generic device build, and the `YesChefTests` app target per
  [verification.md](../verification.md). Every dispatch touches `YesChefApp/` model code.
- Closeout per ADR-0005 D16. Dispatch 2 archives this brief.
- Gate lines (Jon, iPad + iPhone):
  - **Dispatch 1:** Put two dishes and a note on the calendar across three days, and place Thanksgiving 2026 on one of
    them. Create a three-day menu over those days and Bring In. The calendar looks the same and the rows open the
    menu. Thanksgiving 2026 is unplaced with its plan intact, and its steps are in the new menu. Grocery items for moved
    dishes still group and remove correctly. A past placed menu's recipe shows a last-cooked date.
  - **Dispatch 2, before any TestFlight upload:** Create `prepPlanSteps.workDayOffset` (INT64) in Development, confirm
    the schema export differs from Production only by that field, and deploy. The `testflight` expected-fields gate
    blocks the upload until then.
  - **Dispatch 2, on device:** Weave a plan on a multi-day placed menu. It bands by day with real dates, and today
    opens itself. Edit a step's Day. Round-trip a Copy Prep Prompt hand-off through ChatGPT. Re-run the Dispatch 1
    bring-in with a Thanksgiving copy and check the steps land on Wednesday and Thursday.

## Dispatch ledger

- [ ] Dispatch 1 — S1 + S2 (history counts placed menus; bring-in), one PR. No schema.
- [ ] Dispatch 2 — S3 + S4 + S5 (work-day column, weave and text, day bands and picker, copied-step dating), one PR.
  Schema: escalate to Jon at review.
