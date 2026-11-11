# Effort — Prep steps sort by approximate time

Status: Ready
Summary: Prep steps gain an optional approximate time (`timeOfDay`). One Core placement rule uses it to keep a work day in time order on chat apply, weave, paste-back and editor saves, and Move Earlier/Later still overrides. Matching ignores time and window, so restaging a day to add times re-sorts its steps instead of replacing them. One nullable synced column, with a Production deploy.

Origin: Thanksgiving Week, staged from ChatGPT on 2026-11-11. One dispatch, one PR. **Persistent model change,
authorized by ADR-0034 Amd 3.**

Decisions: [ADR-0034 Amendment 3](../decisions/ADR-0034-prep-plan-work-session-timeline.md#amendment-3--a-step-carries-an-approximate-time-and-time-sets-its-place-in-the-day-2026-11-11)
(C1–C3). Read it first. Precedent for threading a new step field through every producer:
[archived `prep-step-make-ahead-window`](archive/prep-step-make-ahead-window.md), which did exactly this for
`makeAheadWindow` (#486). Copy its shape; every file it touched is touched again here.

## Where things are (architect, 2026-11-11, `origin/main` 54b47d8)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `Schema.swift`: append after "Add prep plan make-ahead window".
- `CloudSync.swift`: `declaredSchemaVersion` (59 now).
- `MenuPrepPlan.swift`: `PrepPlanStepRecord`, `PrepPlanStep` (Codable), the editable review text (the `Keeps:` line
  is the model for a `Time:` line), `MenuPrepPlanClient.instructions` and `parse`, and `PrepPlanStepRepository`
  (`create` uses `nextSortOrder`; `update`; `replace` and `Contents`; `writeSortOrder`; `reorder`).
- `ChatPrepPlanImport.swift`: the envelope, `plan` (ownership, Kept/New/Removed), `apply` (the insertion loop at the
  bottom is Amd 5-D5's rule, which C2 replaces), and `same`.
- `MenuChatContext.swift`: `prepPrompt` and the "Current prep plan" lines.
- `MenuBringIn.swift`, `ChatAccessExport.swift`: copy and export, as for the window.

**Helper:** `YesChefMCPServer.swift` (`stage_prep_plan`'s description, schema, `decodeAndStagePrepPlan`) and
`ChatAccessReadTools.swift` (`get_menu`).

**App:** `MenuPrepPlanEditingViews.swift` (the editor), `MenuDetailModel+PrepPlanEditing.swift`,
`ChatMenuReviewSheet.swift` (`ChatPrepPlanReviewSheet`).

**Repo root:** `cloudkit-expected-fields.txt`.

## The slice

### Schema (C1)
- Append `ALTER TABLE "prepPlanSteps" ADD COLUMN "timeOfDay" INTEGER`. Bump `declaredSchemaVersion`.
- `timeOfDay: Int?` (minutes after midnight, 0…1439) on `PrepPlanStepRecord` and `PrepPlanStep`. `PrepPlanStep`'s
  Codable key is `time`, as `"HH:mm"`. Decode with `decodeIfPresent`; a malformed string decodes to nil in the weave
  JSON path (tolerant, like `serves`), and is a stage error in the helper (below).
- One Core helper converts both ways: `"HH:mm"` ⇄ minutes. Accept `H:mm` too. Reject anything else.
- Add `prepPlanSteps timeOfDay` and its `sqlitedata_icloud_userModificationTime_timeOfDay` line to
  `cloudkit-expected-fields.txt`.
- Carry it like the window: `create`, `update`, `replace`, bring-in, export (`time` as `"HH:mm"`), `get_menu`, and a
  `  - Time: HH:mm` line in "Current prep plan".

### Matching (C3)
- **`Contents`** (in `replace`) drops `makeAheadWindow` and doesn't gain `timeOfDay`. A survivor keeps its id and is
  written with the draft's time and window (the upsert already writes the draft's values).
- **`ChatPrepPlanImport.same`** drops the window comparison and doesn't compare time.
- **`Entry.kept`** carries the staged step too (or its time and window), so the review and Apply see what changed.
  Apply writes a Kept row's time and window when they differ, and re-places it (C2) when its time changed.
- **Drift** (`multiset`) keeps comparing every field, window and time included: a change since the chat read the plan
  should still show the banner.

### Placement (C2) — one Core function
Add `PrepPlanPlacement.insertionIndex(of step:, into steps: [PrepPlanStepRecord], dayCount:) -> Int` (or an
equivalent pure function), where `steps` is the menu's plan in order, without `step`:
- `dayCount > 1`, `step.workDayOffset != nil`, `step.timeOfDay != nil`: the index of the first step on the same work
  day whose `timeOfDay` is later. If none is later, the index after the last step on that day. If the day has no steps
  yet, keep today's behavior for a step on a new day.
- Anything else: today's behavior for that call site (append for `create`, the draft's position for `replace`).

Use it in:
- **`ChatPrepPlanImport.apply`:** replace the "same session, else same day" anchor with this rule. Place each kept
  New step, and each Kept step whose time changed (removed from the list first), in staged order.
- **`PrepPlanStepRepository.replace`** (the weave and paste-back): build the plan by placing each draft in turn into
  an empty list. A day's timed steps come out sorted; untimed steps keep their relative order.
- **`create`**, and **`update` when `timeOfDay` or `workDayOffset` changes:** remove the step, place it, then
  renumber with `writeSortOrder`.
- **Not `reorder`.** Move Earlier/Later never touches `timeOfDay`.

### Producers (C1)
Add one shared Core sentence, used by all three like `makeAheadAndLeftoversGuidance`:

> Give every step on a work day an approximate start time, "HH:mm" in 24-hour time, for sorting the day; estimate
> from the meal's time when the menu doesn't state one. Keep the session as the label people read. Flexible steps
> get no time.

- **Weave:** the JSON step gains `"time":"HH:mm or null"`; add the sentence.
- **Copy Prep Prompt and the review text:** a step with a time renders `  Time: HH:mm` under its bullet, after
  `Keeps:` when both are present. Parse it the way `Keeps:` is parsed, in either order. A plan with no times renders
  byte-identical to today. Ask for the line and add the sentence in `prepPrompt`.
- **`stage_prep_plan`:** optional `time` string per step. Null means absent. Not `H:mm`/`HH:mm`, or out of range, is
  a problem: `"<label>, step N: time must be HH:mm"`. A `time` on a step with no `workDay` on a multi-day menu is
  dropped silently. Add the sentence to the description.

### App
- **Editor:** an optional **Time** row: a toggle, and an hour-and-minute `DatePicker` when on. It's only offered when
  the step has a work day. Saving writes `timeOfDay`; changing it or the Day re-places the step (C2).
- **Step row:** unchanged. The session stays the label.
- **Chat review:** show each step's time beside its session (for example "Thu, Nov 26 · About 3 hours before dinner ·
  15:15"). A Kept step whose time or window changes says "time updated" or "window updated".

## Tests

**Core**
- Old rows and JSON decode with no time; the migration adds the column to a database with rows.
- `"HH:mm"` round-trips; `"7:05"` parses; `"24:00"`, `"9am"` and `"12:5"` don't.
- **Placement:** into Tuesday's real 11-11 order (6:57 PM, 6:43 PM, 10:00 AM, untimed), a 3:15 PM step lands before
  the first later step; a step later than all lands after the day's last step; another day's steps never move.
- **Apply:** Tuesday's steps staged in dish order (souvlaki 18:47, 18:57; köfte 18:43; tzatziki 10:00) come out
  10:00, 18:43, 18:47, 18:57.
- **Replace:** a weave whose drafts are out of time order stores each day sorted, untimed steps in their relative
  order, Flexible unchanged.
- **Editor:** changing a step's time moves it; Move Earlier/Later keeps the time and moves the step.
- **Review text:** `Time:` and `Keeps:` round-trip in either order; a plan with neither is byte-identical.
- **Matching:** restaging Tuesday's untimed steps with times gives all Kept, no Removed or New; Apply keeps every id
  and leaves the day in time order. A window-only change is Kept with the new window (this reverses #486's
  Removed-plus-New test). In `replace`, a time or window change keeps the id.
- **Drift:** a time edit after the chat read the plan still raises the banner.

**Helper:** `time` validation (a bad time rejected, a null `time` accepted), and the description carries the shared
sentence.

**App (`YesChefTests`):** saving the editor with a time writes it, and changing it moves the step.

## Done when

- A step stores an approximate time, and every producer fills it for work-day steps.
- A work day stays in time order through chat apply, weave, paste-back and editor saves; Move Earlier/Later still
  works.
- Restaging a day to add times re-sorts its existing steps without new ids.
- Tests above. Verification per [`verification.md`](../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- The PR body gives the install order: the app on both devices, then the helper.
- **Gate, before any TestFlight upload:** `prepPlanSteps.timeOfDay` (INT64) and its modification-time field are in
  Production. The architect imports them to Development with `cktool`; Jon deploys in the Console.
- **Jon's device gate:** in ChatGPT, read Thanksgiving Week and restage Tuesday's dinner dishes with times. The review
  shows Kept steps with "time updated", not Removed and New. After Apply, Tuesday reads in time order. Then restage
  Thursday's dishes and check the same. Change one step's time in the editor and see it move; Move Earlier on another
  and see it stay.
