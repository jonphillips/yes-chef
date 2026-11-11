# Effort — Prep steps sort by approximate time, and a chat can restage the whole plan

Status: Ready
Summary: Prep steps gain an optional approximate time (`timeOfDay`). One Core placement rule uses it to keep a work day in time order on chat apply, weave, paste-back and editor saves, and Move Earlier/Later still overrides. `stage_prep_plan` gains a `wholePlan` mode that also removes steps no dish owns, and every Removed step in the review gets a keep toggle. One nullable synced column, with a Production deploy.

Origin: Thanksgiving Week, staged whole from ChatGPT on 2026-11-11. One dispatch, one PR. **Persistent model change,
authorized by ADR-0034 Amd 3.**

Decisions: [ADR-0034 Amendment 3](../decisions/ADR-0034-prep-plan-work-session-timeline.md#amendment-3--a-step-carries-an-approximate-time-and-time-sets-its-place-in-the-day-2026-11-11)
(C1, C2) and [ADR-0060 Amendment 6](../decisions/ADR-0060-chat-access-over-mcp.md#amendment-6--a-chat-can-restage-the-whole-prep-plan-2026-11-11)
(D1–D3). Read both first. Precedent for threading a new step field through every producer:
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
`ChatMenuReviewSheet.swift` (`ChatPrepPlanReviewModel`, its `keptIndices`, and `ChatPrepPlanReviewSheet`),
`ChatAccessInboxModel.applyPrepPlan`.

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
- Carry it like the window: `create`, `update`, `replace`, `Contents`, bring-in, export (`time` as `"HH:mm"`),
  `get_menu`, and a `  - Time: HH:mm` line in "Current prep plan".

### Placement (C2) — one Core function
Add `PrepPlanPlacement.insertionIndex(of step:, into steps: [PrepPlanStepRecord], dayCount:) -> Int` (or an
equivalent pure function), where `steps` is the menu's plan in order, without `step`:
- `dayCount > 1`, `step.workDayOffset != nil`, `step.timeOfDay != nil`: the index of the first step on the same work
  day whose `timeOfDay` is later. If none is later, the index after the last step on that day. If the day has no steps
  yet, keep today's behavior for a step on a new day.
- Anything else: today's behavior for that call site (append for `create`, the draft's position for `replace`).

Use it in:
- **`ChatPrepPlanImport.apply`:** replace the "same session, else same day" anchor with this rule, placing each kept
  New step in staged order.
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

### Whole-plan mode (Amd 6)
- **Envelope:** `ChatAccessStagedPrepPlan.wholePlan: Bool?`, decoded with `decodeIfPresent`, encoded only when true.
  Version stays 1.
- **Helper:** optional boolean `wholePlan` in the schema; a non-boolean is a problem. One description clause
  (Amd 6-D3): "Set `wholePlan` when you send every dish's steps; then anything not sent is removed, including steps not
  linked to a dish."
- **`ChatPrepPlanImport.plan`, when `wholePlan`:** after the named dishes, every owned step of a dish that wasn't
  named becomes a Removed entry under that dish (append the dish to `dishes`, with only Removed entries). Every step
  owned by no dish becomes a Removed entry in a new `Plan.unlinked: [PrepPlanStepRecord]`. Without `wholePlan`, both
  stay empty and nothing changes. `Plan.isWholePlan` records the mode.
- **Keep toggles (Amd 6-D2, both modes):** `keeping` already indexes the flattened entries. Extend the index space to
  `dishes`' entries, then `unlinked`, in that order. A Removed entry whose index is in `keeping` is left alone by
  `apply`. `ChatPrepPlanReviewModel` starts with New entries kept and Removed ones not.
- **Review sheet:** a keep toggle on every Removed row ("Keep"). In whole-plan mode, a banner ("This replaces the
  whole prep plan.") and a last section, **Not linked to a dish**, listing `unlinked` with the same toggles. Show each
  step's time beside its session (for example "Thu, Nov 26 · About 3 hours before dinner · 15:15").

### App
- **Editor:** an optional **Time** row: a toggle, and an hour-and-minute `DatePicker` when on. It's only offered when
  the step has a work day. Saving writes `timeOfDay`; changing it or the Day re-places the step (C2).
- **Step row:** unchanged. The session stays the label.

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
- **Identity:** a time change is Removed plus New in a stage, and a new id in `replace`.
- **Whole plan:** on a fixture shaped like Thanksgiving Week (a named dish, an unnamed dish with steps, and two
  unlinked steps serving "Thanksgiving dinner"), whole-plan mode removes the unnamed dish's steps and both unlinked
  ones; keeping one unlinked index leaves it untouched; without `wholePlan`, all of them stay.
- **Keep toggle, per-dish mode:** a kept Removed step survives Apply with its id.

**Helper:** `time` and `wholePlan` validation (a bad time, a non-boolean `wholePlan`, a null `time` accepted), and
the description carries the shared sentence and the `wholePlan` clause.

**App (`YesChefTests`):** the review model starts with Removed entries unkept, and a toggled Removed entry is passed in
`keeping`. Saving the editor with a time writes it.

## Done when

- A step stores an approximate time, and every producer fills it for work-day steps.
- A work day stays in time order through chat apply, weave, paste-back and editor saves; Move Earlier/Later still
  works.
- `wholePlan` restages remove unowned steps, and any Removed step can be kept in the review.
- Tests above. Verification per [`verification.md`](../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- The PR body gives the install order: **the app on both devices before the helper.** An older app ignores
  `wholePlan` and would apply a whole-plan file as a per-dish one.
- **Gate, before any TestFlight upload:** `prepPlanSteps.timeOfDay` (INT64) and its modification-time field are in
  Production. The architect imports them to Development with `cktool`; Jon deploys in the Console.
- **Jon's device gate:** in ChatGPT, read Thanksgiving Week and restage the whole plan with `wholePlan`. In the review,
  the old Thanksgiving steps appear under **Not linked to a dish**; keep the gluten-free stuffing ones. After Apply,
  there's no Flexible band of old steps, and Sunday, Tuesday and Thursday each read in time order. Change one step's
  time in the editor and see it move; Move Earlier on another and see it stay.
