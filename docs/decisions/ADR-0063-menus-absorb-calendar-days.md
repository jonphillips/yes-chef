# ADR-0063 — A menu takes in the calendar days it covers, and a multi-day prep plan runs by work day

> **One-line:** Placing a menu offers to **bring in** what the calendar already has on those days. Loose calendar
> items move into the menu, and another menu placed wholly inside the range is copied in and unplaced. A menu longer
> than one day groups its prep plan **by the day you do the work**, using a new nullable `workDayOffset` on each step.
> Cooking history starts counting dishes on placed menus.

Status: **Accepted** — 2026-11-08. Effort:
[`efforts/menu-absorbs-calendar-days.md`](../efforts/menu-absorbs-calendar-days.md).
Origin: Jon, 2026-11-08: *"plan some things on a calendar and then, if I define a menu over a few days, it will pull in
things from the calendar. Then I'll want to be able to come up with a prep plan from the resulting set of days."* And:
*"pull a menu (Thanksgiving 2026) into another menu (Thanksgiving Week 2026)."* He accepted this direction the same day.
Builds on: [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) (one prep plan per menu, session bands, the
deferred real-date anchoring this decides) · [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (steps are rows)
· [ADR-0056](ADR-0056-move-to-production-and-data-carry.md) (Production schema is additive-only) ·
[ADR-0062 D8](ADR-0062-serve-with-recipe-links.md) (a new field reaches Production before the build does).
Adjacent, unchanged: [ADR-0034 Amendment 1](ADR-0034-prep-plan-work-session-timeline.md#amendment-1--a-calendar-day-gets-a-real-plan-2026-11-05)
(a calendar day's own plan, not built).

## Context

The Calendar plans ordinary life: what gets cooked on which day. A Menu plans an event as a unit, first a dinner party
and now a week at the beach. It has scale, a prep-plan weave, grocery generation and hand-offs. The prep plan is the
Menu's real advantage, and it should stay on the Menu.

Today the data only flows one way. A `Menu` is a template in relative days: `MenuItem.dayOffset`, not a date. A
`MenuPlacement` pins it to a `startDate`, and a menu can have several placements. `MealCalendarRequest` shows placed
menus as read-only calendar rows next to the calendar's own `MealPlanItem` rows. Nothing moves calendar rows into a
menu, so a week planned on the calendar can't get a prep plan.

Two more facts shape the decision:

- **Cooking history ignores menus.** `RecipeCookingHistory` counts only past `MealPlanItem` rows. A dish served from a
  placed menu has never counted as cooked, so last year's Thanksgiving turkey has no history.
- **The prep bands assume one service.** `PrepPlanSessionBand` (*Flexible*, *Earlier in the week*, *The day before*,
  *The day of*, *At service*) works for one dinner. Across a week, every dinner has its own "day before", and the bands
  stop meaning anything. ADR-0034 deferred anchoring steps to real days. A multi-day menu is the case that needs it.

## Decisions

### D1 — Bring in, don't reference

A menu takes in calendar content by **moving** it, not by pointing at it. A calendar row that a menu referenced would
have two owners, two editors, and two answers to "what's on Tuesday".

Bring-in is a single write transaction over the days of the menu's one placement (`startDate` through
`startDate + dayCount − 1`):

- **Loose calendar items move.** Each `MealPlanItem` in the range, of any kind, becomes a `MenuItem` with a fresh id.
  It keeps its kind, recipe, title, slot, notes and scale, and gets `dayOffset = day − startDate`. The calendar row is
  deleted. A recipe-kind row without a `recipeID` becomes a note, because a recipe-kind menu item must have a recipe.
- **A placed menu wholly inside the range is copied in.** Its items are copied with their offset shifted by where the
  placement falls, and that placement is deleted. The source menu survives unplaced, as a template for next year. Its
  prep steps are copied too (D3).
- **A placed menu that only partly overlaps the range is left alone.** Copying part of it and unplacing it would drop
  its other days off the calendar. The confirmation names it.
- **Grocery sources follow.** `groceryItemSources` rows that point at a moved calendar item, or at a copied menu's
  deleted placement, are re-pointed to the new menu item and this menu's placement (`origin = .menuPlacement`). The
  grocery list keeps its grouping and scale lookups. Nothing on the list changes.
- **No de-duplication.** If the menu already has the same recipe on the same day and slot, both rows stay. Guessing
  which one is the duplicate is a heuristic, and deleting one is a tap.

After bring-in the calendar shows the same dishes on the same days. They're now menu rows, so they're edited in the
Menu.

### D2 — Offered when a menu is placed, and on demand

- **After a placement is saved**, new or moved, the app offers bring-in if the menu has exactly one placement and the
  range holds anything to bring in. The confirmation counts what comes in, names each menu being copied, and names each
  partly overlapping menu left alone. **Bring In** or **Not Now**.
- **On demand:** the menu detail has **Bring In Calendar Items…**, available on the same conditions.
- **Only with one placement.** A menu placed on two different weeks can't take in one week's rows. The prep-plan
  context already uses real dates only with one placement (`MenuChatContext`), so this is the same rule.
- The offer is computed by a pure read. The write re-reads the range inside its transaction and acts on what's there
  then, not on the offer it showed.

There's no reverse ("dissolve this menu back into the calendar"). Add it if Jon misses it.

### D3 — A copied menu's prep steps come with it

The source menu's `prepPlanSteps` are appended after the target's own, with `sourceDish` re-pointed to the copied
items. The session label is kept word for word. Once steps carry a work day (D5), the copy also dates them:

- A step with a `workDayOffset` gets the same placement shift as the items.
- A step from a one-day menu without one is dated from its session label through the existing
  `PrepPlanSessionBand(matching:)` matcher. *The day of* and *At service* land on the dish's day, and *The day before*
  lands on the day before it. Everything else stays undated (*Flexible*).

The weave already reads the current plan and keeps it (`MenuPrepPlanClient.instructions`), so re-weaving the combined
menu starts from the copied steps rather than from nothing.

### D4 — Cooking history counts placed menus

`RecipeCookingHistory` counts a recipe-kind `MenuItem` once per placement whose projected day is on or before today.
That's in addition to past `MealPlanItem` rows. It uses the same day arithmetic as `MealCalendarRequest`'s projection,
pulled out into one shared helper, so the calendar and history can't disagree about which day a dish falls on.

This ships with bring-in, or before it. Without it, every dish that bring-in moves would drop out of history.

### D5 — A prep step can carry a work day

`prepPlanSteps` gains `workDayOffset INTEGER`, nullable. It's the day the work happens, counted like
`MenuItem.dayOffset`: 0 is the menu's first day, and a negative value is a day before the menu starts. `nil` means
unscheduled, shown as *Flexible*. `session` stays as the free-text label within the day ("Morning", "Two hours before
dinner").

- **Model and text use 1-based day numbers**, matching the "Day 2" labels the context already carries. The weave's JSON
  gains `"workDay": <int or null>`. In the editable review text, a multi-day menu's band header is
  `Day N · <session>:`, where `Day 0` and below are days before Day 1. The hand-off copy-out asks for the same syntax.
  Storage converts with `workDayOffset = workDay − 1`.
- **Out-of-range days aren't dropped.** A returned day outside the menu (or more than 7 days before it) keeps its step
  and its text, with the step left unscheduled. The review says how many.
- **Only multi-day menus parse days.** On a one-day menu, a header such as "Day 2 prep:" is still a session label. The
  rule is the menu's `dayCount`, not a guess about the text.
- **Shrinking a menu** clears `workDayOffset` on steps past its new last day, in the same transaction. The text stays.
  Menu items already block shrinking past them. Steps don't need to.
- **Moving or deleting a dish doesn't move its steps.** This is the same rule as ADR-0034 Amendment 1.

### D6 — A multi-day plan reads by work day

A menu with `dayCount > 1` groups its plan into one band per work day, after a *Flexible* band for undated steps.
Within a day, steps keep plan order, and the session label shows as a sub-label wherever it changes. With one placement,
the header shows the real date ("Tue, Nov 24 · Day 2"). Without one, it shows "Day 2", or "2 days before Day 1".

A one-day menu keeps today's session bands unchanged.

The step editor gains a **Day** picker on multi-day menus: Flexible, up to 7 days before Day 1, then Day 1 through the
last day, with dates when placed. The session picker is unchanged.

The banding moves out of the view (`MenuPrepPlanSessionBand` in `MenuViews.swift`) into Core, so it's a tested pure
function.

### D7 — With one placement, today opens itself

When a multi-day menu has one placement and today is one of its work days, that band starts expanded and reads
**Today**. The others start collapsed, as they do now. This is the automatic "now" ADR-0034 deferred until steps were
anchored. Expansion isn't persisted.

### D8 — The field reaches Production before the build does

`workDayOffset` is a field on a synced table, and a Production schema deploy is one-way. As in ADR-0062 D8, Jon creates
it in Development, confirms the export differs only by that field, and deploys before the first TestFlight build
containing D5. Bring-in (D1–D4) changes no schema and isn't held by this.

## Rejected

- **A menu references calendar rows.** Two owners for one dish (D1).
- **Nesting: a menu that contains another menu.** Two prep plans would weave the same dishes, placements would recurse,
  and a synced row would need a second parent. Copying in (D1) gets the same result and keeps the source as a template.
- **A read-only "prep for these days" view across menus and calendar days.** It needs no data change, but it shows
  separate plans side by side, and nothing notices that three meals need the same stock. One menu, one weave.
- **Work days parsed out of the session label.** "Wednesday evening" isn't reliably one day. Using the session matcher
  once, at copy time, on its fixed vocabulary is different, because it's exact and never re-runs (D3).
- **Turning calendar days into one-day menus.** ADR-0034 Amendment 1 already rejected it: the Menus list fills with
  small menus.

## Consequences

- One more field in CloudKit Production, permanently.
- Moved calendar items become read-only on the calendar, and they're edited in the Menu.
- Bring-in can't be undone. It loses nothing, because every row's content survives in the menu, and a copied source
  menu survives as a template.
- A peer device editing a calendar item while another device brings it in could restore the deleted row. That shows up
  as a visible duplicate on the calendar, not as lost data.
- Past placed menus start counting as cooked, so last-cooked dates and counts move for those recipes. This is the
  intended change.
- When ADR-0034 Amendment 1's date-keyed calendar plan is built, bring-in must move that table's steps for the range
  too. That's its brief's job, and it's noted there.
- A pending calendar make-ahead or complement hand-off whose item has moved can't find its source on return.
  `AIHandoffIntentImport` already throws when the item is missing (today as `wrongTask`), so it fails loudly, not
  silently.
