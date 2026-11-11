# ADR-0067 — Today's Prep: a view for doing the prep plan, with checks that sync

> **One-line:** A **Prep** button beside **Cook these** opens a full-screen checklist of the prep steps due now: today's
> work day, anything left over from earlier days, and an optional look ahead. You check steps off as you go. Each check
> is a synced `completedAt` date on the step, so it survives the night and shows on the other device. Tapping a step
> shows its dish's recipe alongside. Editing the plan stays in the Prep Plan column.

Status: **Accepted** — 2026-11-11 (Proposed the same day). Brief: [`today-prep`](../efforts/archive/today-prep.md). Origin: Jon, 2026-11-11: *"The prep plan UI we have today is fine for
designing/editing. It's much less fun for actually doing the prep work. Just as we have a 'Cook These' flame icon in the
toolbar, I wonder if you could brainstorm what a 'Today's Prep' view would look like."* He chose a synced done date
(option 3 of three) the same day.
Builds on: [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) (one prep plan per menu; its deferred **Cook mode**,
which this decides) · [ADR-0063](ADR-0063-menus-absorb-calendar-days.md) D5–D7 (work days, day bands, today opening by
itself) · [ADR-0016](ADR-0016-multi-recipe-cook-session.md) (Cook these: a full-screen cover, kept-alive Readers,
session-only done) · [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (steps are rows) ·
[ADR-0062 D8](ADR-0062-serve-with-recipe-links.md) (a new field reaches Production before the build does) ·
[ADR-0065](ADR-0065-one-glyph-per-concept.md) (glyphs) · [ADR-0066](ADR-0066-in-app-help-pages.md) (help pages).
Lands after: ADR-0034 Amendment 3 (`timeOfDay`, PR #490), which touches the same repository functions.

## Context

The prep plan has a good home for **designing**. The menu-detail Prep Plan column groups steps by work day, opens today's
band by itself on a placed menu, and edits each step in a sheet. The weave, the hand-off and `stage_prep_plan` all write
into it.

It's a poor surface for **doing** the work. Standing at the counter on Tuesday night, Jon wants three things the column
doesn't give:

- **What's left, and only that.** The column shows the whole week, and nothing records that the chiles are already
  toasted.
- **Memory across the night and across devices.** Prep spans days. Whether the turkey got salted has to be on the
  iPad on Wednesday morning and on the iPhone at the store.
- **The recipe within reach.** "Make salsa verde" needs the salsa recipe open beside the list.

ADR-0034 saw this coming and parked a **Cook mode**: one band filling the screen, big checkable steps, keep-awake, a
countdown, and "next up". Two things have changed since. Steps are rows with work days (ADR-0040, ADR-0063), so "today"
is computable. And Cook these (ADR-0016) has shown the shape of a full-screen working surface: a cover, keep-awake, and
kept-alive Readers.

The one real decision is where "done" lives. Cook these keeps it in memory for the session (ADR-0016 D3), which suits a
recipe you finish within the hour. Prep doesn't fit that, and Jon chose a synced field.

## Decisions

### D1 — A Prep button opens a full-screen view

The menu toolbar gains **Prep** beside **Cook these**, shown when the menu's plan has at least one step. It opens a
full-screen cover (`TodayPrepView`), presented the way the cook session is, with `.keepsScreenAwakeWhilePresented()` and
a **Close** button, as the cook session's cover has.

The glyph is a literal `checklist`. Under ADR-0065 D3 a glyph joins `AppSymbol` when its concept first appears on a
second surface, and this is one surface. If a second entry point arrives (see Deferred), it joins the table then.

### D2 — "Today" when the menu has a date, a band picker when it doesn't

**Dated mode.** The menu is longer than one day, and exactly one of its placements has a work range containing today.
The work range runs from 7 days before the start date (the earliest work day ADR-0063 D5 allows) to the menu's last day.
This generalizes ADR-0063 D7, whose "one placement" condition is the common case. The view reads, top to bottom:

1. **Still open**: unchecked steps from earlier work days in this run, under their day's header. It's left out when there
   are none. Nothing is moved or rescheduled; the steps are just shown.
2. **Today**: today's work day, titled like D6 ("Today · Wed, Nov 25 · 1 day before Day 1").
3. **Get ahead** (the Flexible band) and **Tomorrow**, collapsed, with counts. Checking one of these early just marks it
   done. It isn't rescheduled.

**Manual mode.** The menu is unplaced, is one day long, or doesn't have exactly one placement covering today. The title
is plain **Prep**. A picker at the top lists the bands `MenuPrepPlanBanding` already returns (Flexible and day bands, or
the session bands of a one-day menu). The view opens on the first band with an unchecked step. The choice isn't saved.

This follows the house rule for modes: key off a date when the artifact has one, and use a manual toggle otherwise.
Mapping a one-day menu's "The day before" onto a calendar date would be a heuristic, so it isn't done. Bring-in's
one-time, exact mapping (ADR-0063 D3) is a different case.

The sectioning is a pure Core function over steps, `dayCount`, the anchoring placement and today, next to
`MenuPrepPlanBanding`, and it's tested there.

### D3 — A row is a task you check off

Each row shows a large check control and the task. Under the task are the `serves` chip and the make-ahead window, as
in the Prep Plan column. Session labels appear as sub-headers wherever they change (ADR-0063 D6). Rows keep plan order,
which after ADR-0034 Amd 3 is time order within a day. The approximate time isn't shown, because the session stays the
label people read.

Tapping the check marks the step done; tapping again clears it. A done row stays in place, dimmed with a checkmark, so
the list doesn't reshuffle under your hand. Each section's footer reads "3 of 5 done".

**No timers, countdowns or "next up" clock.** This withdraws that part of ADR-0034's deferred Cook mode. A prep plan
holds tasks, never choreography, and session labels such as "~3 hrs out" stay text.

### D4 — The dish's recipe sits beside the list

Tapping a row's body selects it. On regular width, a trailing pane shows the selected step's `sourceDish` recipe in the
Reader, scaled from its menu item's `ScaleContext` (`.menuItem`). Readers stay alive per dish across selection changes
as in ADR-0016 D4, so scroll position and ingredient checks survive. A step with no `sourceDish` leaves the pane as it
was. On compact width, selecting a step pushes the Reader.

The pane adds nothing beyond the Reader. Recipe edits go through the Reader's own toolbar, as in a cook session.

### D5 — Done is a synced date on the step

`prepPlanSteps` gains `completedAt TEXT`, nullable, holding a date the way `dateModified` does. Checking writes now, and
unchecking writes nil. SQLiteData's per-field last-writer-wins settles two devices checking the same step.

`completedAt` exists **only on `PrepPlanStepRecord`**. `PrepPlanStep` (the draft and wire type), the editable review
text, `ChatAccessExport`, `get_menu`, the prep prompt and the weave don't carry it. So no prompt changes, and checking a
step never trips the chat drift banner (`ChatPrepPlanImport.multiset` compares the export fields).

Every writer of `prepPlanSteps` either keeps the date or starts it at nil, and each gets a test:

| Writer | `completedAt` |
|---|---|
| `PrepPlanStepRepository.replace` (weave, paste-back) | A survivor matched by `Contents` **carries `existing.completedAt`**: the upsert writes a freshly built record, so the date has to be copied in. `Contents` doesn't gain it. New steps start nil. |
| `PrepPlanStepRepository.update` (editor save) | Untouched. It's a column-targeted update. Editing a done step leaves it done. |
| `PrepPlanStepRepository.create` | nil. |
| `ChatPrepPlanImport.apply` | Kept rows are untouched (column-targeted updates); new rows start nil. |
| Bring-in and Add Menu (`MenuBringIn`) | Copies start nil. A copied menu is a new run. |
| `reorder`, `writeSortOrder` | Untouched. |

With ADR-0034 Amd 3, a re-weave or restage that changes only a step's time or window keeps its id, and now its check.
A step whose task text changes is a new step and starts unchecked, which is honest: it's different work.

### D6 — A check belongs to one run of the menu

A menu can be placed more than once (Thanksgiving, again next year), but its steps are shared rows. So "done" is
judged against the menu's **current run**:

- **The current run** is the placement whose work range (D2) contains today. If none does, it's the next placement to
  start, and if none is upcoming, the latest one.
- **A step is done** when `completedAt` is later than the end of the **previous run**: the placement that started
  latest before the current run, through its last day. If there's no previous run, or the menu is unplaced, any
  `completedAt` counts.

So a menu placed again starts unchecked, with no reset to remember, and last year's dates stay as harmless history.
Early prep still counts: a Flexible step checked ten days before the work range is done, because it's after last
year's run. The view's `⋯` menu has **Uncheck All** for reusing an unplaced menu, after a confirmation. It writes nil
to every step of the menu.

The rule is one Core function, used by both this view and D8.

*Refined at acceptance (2026-11-11). The Proposed D6 counted checks only from the run's work-range start in dated mode,
and any check otherwise. That dropped early prep, and it showed last year's checks before this year's range began.*

### D7 — Only light edits happen here

- **Move to tomorrow.** Swipe, or the context menu on an unchecked dated step. It sets `workDayOffset` to today + 1
  (manual mode: **Next Day**, the selected band's day + 1) through `PrepPlanStepRepository.update`, so the step is
  re-placed by time (ADR-0034 Amd 3). It's hidden on the menu's last day, on Flexible steps and on one-day menus. This is
  for "ran out of time tonight".
- **Add Step.** At the foot of Today, or of the selected band, **Add Step** opens the existing step editor
  (`PrepPlanStepEditorSheet`) with that day filled in.
- **Edit Step…** in the context menu opens the same editor.

Deleting, reordering, re-weaving and hand-offs stay in the Prep Plan column. This view doesn't become a second editor.

### D8 — The Prep Plan column shows checks but can't change them

In the menu-detail Prep Plan column, a step that counts as done (D6) shows a small checkmark and dims. There's no toggle
there: the column is for designing the plan, and Prep is for doing it. This keeps the column from showing work as
outstanding when it's finished.

### D9 — The help page says how it works

The Menus help page's "Prep plan" section (`AppHelp.swift`, ADR-0066) gains a bullet: "**Prep** opens the steps due now
as a checklist, with each dish's recipe beside it. Checks sync to your other devices. Swipe a step to move it to
tomorrow."

### D10 — The field reaches Production before the build does

As in ADR-0062 D8 and ADR-0063 D8: `prepPlanSteps.completedAt` and
`sqlitedata_icloud_userModificationTime_completedAt` go into `cloudkit-expected-fields.txt`. Before the first TestFlight
build containing D5, Jon creates them in Development, confirms the export differs only by those fields, and deploys. If
ADR-0034 Amd 3's `timeOfDay` hasn't deployed by then, both go in the same deploy.

## Rejected

- **Session-only done, like Cook these.** Checks vanish when the app is killed or the cover closes, so Tuesday's work
  is forgotten by Wednesday and "Still open" can't exist. That's fine for an hour of cooking and wrong for a week of
  prep.
- **A local-only done table.** The iPad and the iPhone would disagree about what's done. A local table keyed by synced
  ids also leaves orphan rows behind when steps are deleted on the other device.
- **A Bool instead of a date.** It costs the same and can't support D6, so a re-placed menu would need a manual reset.
- **A reset action when a menu is placed again.** That's a write somebody has to remember. D6 gets the same result from
  data already stored.
- **Rolling unchecked steps forward automatically.** It's a silent edit to the plan. "Still open" shows them, and Move to
  Tomorrow is the explicit version.
- **Timers, countdowns and a "next up" clock** (ADR-0034's Cook mode). That's choreography near the stove (D3).
- **A second plan editor in this view.** D7 keeps it to check, defer, add, and the existing editor sheet.

## Deferred

- **Today across menus.** A sidebar or calendar entry that gathers today's work from every placed menu, grouped by menu.
  Its Core function can be built on D2's. Not until two placed menus actually overlap in use.
- **Calendar days.** When ADR-0034 Amendment 1's date-keyed calendar plan is built, its rows get `completedAt` and join
  this view the same way.
- **The chat reading what's done** ("what's left for tonight?"). `get_menu` could carry a done flag later. The drift
  multiset would then have to leave it out.

## Consequences

- One more field in CloudKit Production, permanently.
- Done state syncs, and it survives re-weaves and restages for every step whose task text is unchanged.
- A reused unplaced menu needs **Uncheck All**. A reused placed menu doesn't.
- ADR-0034's Deferred **Cook mode** bullet points here.

## Cost and slice plan

There's one schema change, and the rest reuses existing parts: banding, the step editor, the cook session's cover,
keep-awake and kept-alive Readers. One effort, one dispatch, after PR #490 merges:

- **Core:** the migration and `completedAt` on `PrepPlanStepRecord`; the D5 writer table, each with a test; the D2
  sectioning function and the D6 done rule, both pure and tested; `cloudkit-expected-fields.txt`.
- **App:** `TodayPrepView` with its sections, check rows, the Reader pane and the band picker; the toolbar entry; Move to
  Tomorrow, Add Step and Edit Step; Uncheck All; the D8 checkmark in the Prep Plan column; the D9 help bullet.
  `YesChefTests` cover checking, Move to Tomorrow and Uncheck All.
- **Gates:** D10 before TestFlight. Jon's device pass checks a step on the iPad and sees it checked on the iPhone, leaves
  one unchecked overnight and finds it under Still open, and moves one to tomorrow.
