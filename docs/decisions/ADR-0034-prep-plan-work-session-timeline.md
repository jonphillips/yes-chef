# ADR-0034 — The prep plan is one weaveable, work-session timeline

> **Vocabulary:** a *menu prep plan* is the staged, editable make-ahead document for one multi-day menu
> ([ADR-0012](ADR-0012-menu-actionable-chat.md)'s "Build prep plan" verb), stored as a JSON blob on
> `Menu.prepPlan` and shown in the **Prep Plan** section of the menu detail screen. A *step* today is
> `PrepPlanStep{when, task, sourceDish}`. This ADR reshapes that step and the verb behind it: from a
> **strict roll-up** of per-recipe Make-Ahead notes, sliced by *how far ahead of service*, into a
> **weaveable work-session timeline** — grouped by *when you're in the kitchen*, with every task tagged by
> the meal it feeds.

Status: **Accepted** — 2026-07-12 (Proposed 2026-07-12). Origin: Jon's 2026-07-12 dogfood conversation. **Supersedes the
"prep-plan stays strict" disposition** from [[menu-planner-dogfood-2026-07-09]] (the roll-up-only,
"do not invent" contract). Design capture: [[prep-plan-horizon-redesign]]. **Extends
[ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](ADR-0012-menu-actionable-chat.md)** (the
`(extract → review → commit)` apply-action and the menu prep-plan verb) and rides
[ADR-0026](ADR-0026-review-collection-sheet.md)'s review sheet unchanged. Holds the
[[llm-vs-determinism-surface-boundary]] line: prep is **advisory**, read-only guidance a human edits
before it matters, so LLM invention is appropriate here (unlike the deterministic grocery merge).
Sync-safe by construction — the blob already syncs ([[sqlitedata-blob-cloudkit-asset]];
[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

Three observations from the dogfood pass, in Jon's words:

1. **The roll-up is tedious and it errors.** "Build prep plan" composes only from each dish's *stored*
   Make-Ahead field and is forbidden to invent (`MenuPrepPlan.instructions`: "Do not invent or rewrite
   per-dish make-ahead prose"). When no dish has a Make-Ahead note the model correctly returns
   `{"steps":[]}` and the app raises "No prep steps to build." So the plan is only as good as prior
   per-dish authoring, and the failure mode is an error. Meanwhile, **ignoring the verb and just asking
   the chat "make a plan for this day" works beautifully** — because free chat is unconstrained. Jon wants
   that inventive plan *as the verb*.

2. **He couldn't find where the plan "shows up."** It has a real home — the Prep Plan section on menu
   detail (`MenuViews.swift`, gated `if !steps.isEmpty`) — but between the strict verb erroring (section
   stays empty → hidden) and Jon living in the meal *calendar* (where the parallel
   `MealPlanMakeAheadStrategy` verb dumps its output as a **note item mixed into the day's dish list**,
   with no pane at all), he'd never seen it populated.

3. **"How far ahead of service" is the wrong axis for a multi-day menu.** A menu has many dishes across
   many meals, so every dish has its own service moment; "2 days before" is "2 days before *which* meal?"
   Bands measured against a single service force the human to visit each day and mentally interleave.
   What Jon actually wants: *"Wednesday evening: roast tonight's cauliflower, salt tomorrow's beef, make
   Friday's salsa."* One work session, tasks spanning several future meals, the interleaving done **for**
   him. Notably this is exactly how the LLM's own free-chat plan organized itself (by working day, each
   task noting what it feeds).

The prep plan is therefore **one document per menu** (never one-per-day), and its natural spine is the
**work session**, not the service horizon.

> The meal-calendar per-day `MealPlanMakeAheadStrategy` note verb is the wrong-shaped twin of this feature
> (per-day, dissolves into the dish list). This ADR makes the **menu** the home; realigning or retiring
> the calendar note verb is noted as deferred cleanup, not built here.

## Decisions

### D1 — One plan per menu, home is the menu-detail Prep Plan section

The prep plan stays a single blob on `Menu.prepPlan`, rendered in the existing Prep Plan section. Not
per-day, not on the calendar. Jon's "prep tomorrow's meat today" observation is the proof: tasks are
relative to future *meals*, not to the wall-clock day you do them, so a per-day home is structurally
wrong. The human authors, reads, and executes from this one surface.
[Amendment 1](#amendment-1--a-calendar-day-gets-a-real-plan-2026-11-05) narrows "not on the calendar" for days outside a menu.

### D2 — The step is reshaped: `session` + `serves` + tappable link

`PrepPlanStep` moves from `{when, task, sourceDish}` to:

- **`session: String`** (replaces `when`) — the work block: "Anytime, get ahead", "Sunday–Monday",
  "Wednesday evening", "Saturday · ~3 hrs out", "At service". Free-form label, **not a fixed enum** — the
  earlier "7 horizon bands" idea is retired here because real session labels ("Saturday ~3 hrs out")
  don't fit a fixed vocabulary. A sub-timing can live inside the label ("~3 hrs out", "25 min out").
- **`task: String`** — unchanged, the concrete kitchen task.
- **`serves: String?`** — new. The human-readable meal/day this task feeds ("tomorrow's beef", "Fri taco
  night"). This is the annotation that kills the mental interleaving — a mixed-meal work session reads
  cleanly because each line says what it's for.
- **`sourceDish: MenuItem.ID?`** — unchanged in the model, **newly load-bearing in the UI** (see D4): when
  present it makes the `serves` tag a live link to that dish's recipe. When null (a step spanning dishes),
  the `serves` label renders as plain text.

Steps are grouped into bands by `session`, in **plan-emitted order** (the array order the weave returns),
grouping consecutive same-session steps. A session labeled "Anytime"/"Flexible"/"Get ahead" sorts to the
top by convention. No chronological sort key is stored — order is the LLM's, editable by the human.

### D3 — The verb becomes a weave, not a roll-up (retires "do not invent")

Loosen the prompt: compose from stored per-recipe Make-Ahead notes **when present, and invent sequencing,
work sessions, and new prep steps** grounded in the menu's dishes and the conversation — emitting
`session` and `serves` for each step. Keep [ADR-0012](ADR-0012-menu-actionable-chat.md)'s
"current plan is the artifact being edited → return the full proposed replacement" contract, which is what
makes **incremental, day-by-day authoring** work: plan Wednesday → save → plan Thursday → the weave merges
it into the existing plan. This reverses the 2026-07-09 strict call deliberately; prep is advisory, and an
inventive editable plan beats a reproducible-but-empty one.

The empty-result path stays (a genuinely empty plan is still valid), but it stops being the *common* case,
so the "add Make-Ahead detail to the dishes" empty message is no longer the primary story.

### D4 — Banded, collapsible display; tappable `serves`; timing in the sub-labels

The flat checklist becomes **collapsible session bands** — all collapsed by default, a per-band step
count on the right, tap to open one. This is the reconciliation of the two modes in one surface:

- **Bird's-eye:** all bands collapsed = the whole arc at a glance.
- **"The heat is on":** collapse to the session you're in (e.g. "Saturday · ~3 hrs out") and it fills the
  screen as a countdown checklist — *provided* the weave (D3) orders that final session's steps by
  descending time and puts the minutes in each sub-label. That ordering is free from the prompt/array
  order; no new machinery.
- **No scrolling to piece it together:** the `serves` tag is a **live link** — tap
  `→ chicken fajitas` and you're in that recipe. This is the specific answer to "is go-time close enough
  to my menu items" — one tap from a prep step to the dish, no hunting between "the plan" and "the
  recipes." Data's already there (`sourceDish`); D4 just wires the tap.

### D5 — Clipboard both ways (the ChatGPT escape hatch)

- **Copy dish context out:** a button that dumps the already-built serialized `MenuChatContext`
  (`MenuChatContext.serialized`) to the clipboard, so the human can paste it into an external LLM and
  spend *those* tokens instead of ours.
- **Paste free text in:** the Prep Plan pane accepts a pasted free-text plan as its body. Because the plan
  already round-trips through editable review text (`MenuPrepPlan.editableReviewText` /
  `applyingEditableReviewText`), an imported plan can seed the document; the weave verb (D3) can then sort
  it into sessions / add `serves` tags on a later pass.

**Amendment 1 (2026-07-12) — the copy-out is a complete, _frontier_-budget prompt.** Dogfooding D5
surfaced that "Copy dish context" reused `MenuChatContext.serialized()` at the **on-device 12k-char budget**
(~3k tokens), whose degradation ladder trims ingredients to zero, truncates make-ahead notes, and finally
**drops whole dishes** — so on a real menu the pasted plan referenced dishes the external LLM never saw.
Three further gaps: recipe **method was never in the context**; the ingredient list is capped at a hard
**8** even when budget is plentiful (`defaultIngredientLimit` is the _start_ of the trim ladder, which only
walks down — an arbitrary "key ingredients" heuristic from the tiny-budget era, not a real limit); and the
copied blob is bare context with **no instruction prompt**, so it doesn't read as something you can paste
and run. Since the entire point of the escape hatch is to spend _their_ tokens (a full menu with method is
only ~2–18k tokens, well under the 120k-char frontier budget), S3c makes the copy-out a self-contained
prompt. Four moves, **export-path only — the on-device weave verb (D3) is untouched:**

1. **Frontier budget.** Copy-out serializes at `serialized(for: .frontier)` (was the defaulted on-device
   budget), so ingredients/make-ahead stop trimming and no dishes drop.
2. **Full method.** Serialization carries recipe method (fetched via `InstructionStep`, section-then-step
   order, `InstructionSection.name` as a sub-header when a recipe has >1 section), as a per-dish `Method:`
   block behind a **new trim rung cut _first_** in `budgetedSerialization` — so the _shared_ on-device path
   is essentially unchanged (method drops immediately under 12k) while frontier keeps everything.
3. **Uncap ingredients on the frontier path.** The ingredient-limit ladder starts from the full list length
   at the frontier budget (keeping 8 only as the on-device starting ceiling); `keyIngredients` already holds
   the complete list, so this is a tier-aware starting bound, not new data.
4. **A real intro prompt, tuned from AI settings.** Prepend an adapted form of `MenuPrepPlanClient.instructions`
   (the weave's own system prompt) plus the user's `tasteProfile` and `makeAheadPrepPlanPreference` (via
   `aiPromptPreferences` / `AISettingsRepository`). Critically, the exported prompt asks for the
   **review-text output format** (`Session:` headers + `- task → serves` bullets that
   `applyingEditableReviewText` re-imports), **not** the internal strict-JSON/UUID contract — otherwise the
   paste-in round-trip breaks on ChatGPT's answer.

Because the clipboard now carries a runnable prompt rather than raw context, the button is renamed
**"Copy Dish Context" → "Copy Prep Prompt."**

## Deferred (on the record, explicitly not built here)

- **Calendar real-date anchoring.** Pin a menu to actual dates → resolve free-form session labels
  ("Wednesday evening") to real weekdays, and make "collapse to now" *automatic* (the app knows which
  session is current). Pre-anchoring, sessions are labels and there is no auto-"now" — all bands start
  collapsed, the human taps the one they want. This is the same deferral flagged throughout the design.
  **Decided for multi-day menus in [ADR-0063](ADR-0063-menus-absorb-calendar-days.md) D5–D7** (2026-11-08): a
  nullable `workDayOffset` on each step, day bands, and today opening itself. One-day menus keep session bands.
- **Cook mode.** A dedicated single-session execution surface: one band filling the screen, giant
  checkable steps, keep-awake, a live countdown ticking against the sub-label times, "next up" peeking at
  the bottom. The banded reader + ordered timing + tappable serves (D4) delivers ~80% of that feeling with
  zero new surface; cook mode is the last 20% and its own milestone.
- **Retire/realign the meal-calendar per-day make-ahead note verb** now that the menu owns the prep-plan
  home. Decided in [Amendment 1](#amendment-1--a-calendar-day-gets-a-real-plan-2026-11-05): realign.

## Storage sketch

**No schema change.** `Menu.prepPlan` stays a BLOB holding JSON-encoded `[PrepPlanStep]`
(`MenuPrepPlanCoding`). The reshape (D2) is a **JSON-key** change inside the blob:

- Encode the new keys `session` / `serves` (keep `sourceDish`).
- **Back-compat decode:** existing blobs carry `when` and no `session`/`serves`. Decode reads `session`
  falling back to `when`; missing `serves` decodes to nil. Old plans render as single-step-per-band lists
  with no serves tags until re-woven — no data loss, no migration.
- BLOB syncs unchanged as a CKAsset; sync-safe by construction, no CloudKit concern
  ([[sqlitedata-blob-cloudkit-asset]]).

## Cost, honestly — and the slice plan

The verb, storage, review sheet, and Prep Plan section all exist. What's new is the step reshape, the
prompt loosening, the band grouping, the tappable tag, and the two clipboard affordances. Batched:

- **S1 — model + weave (first dispatch, part 1).** Reshape `PrepPlanStep` (`when`→`session`, add `serves`;
  keep `sourceDish`) with back-compat decode. Loosen `MenuPrepPlanClient` instructions to the D3 weave and
  emit `session`/`serves`/`sourceDish`. Update `editableReviewText`/`applyingEditableReviewText` round-trip
  and tests. Nothing visible yet, but everything rides on it.
- **S2 — banded UI + tappable serves (first dispatch, part 2).** `MenuPrepPlanSection` renders collapsible
  session bands (collapsed default, per-band count, plan-emitted order, "anytime" first). `serves` renders
  as a chip; tappable → navigate to `sourceDish`'s recipe when present, plain text when null. This is the
  display that makes S1 legible; bundle S1+S2 as one dispatch (the author-and-read pass).
- **S3 — clipboard (follow-up dispatch).** "Copy dish context" out + free-text paste-in. Small,
  independent; rides after S1+S2. **Shipped** in [#164](https://github.com/jonphillips/yes-chef/pull/164)
  (also folded in the parse-robustness `session`←`when` fallback).
- **S3c — the copy-out becomes a complete frontier prompt (Amendment 1, follow-up dispatch).** Four moves:
  (1) frontier budget (`.serialized(for: .frontier)`); (2) full method — `MenuDetailRequest` fetch of
  `InstructionStep`/`InstructionSection`, new `recipeMethodLines` on `MenuItemRowData`, `method` on
  `MenuChatItemContext`, per-dish `Method:` render + method-first trim rung in `budgetedSerialization`;
  (3) uncap ingredients on the frontier path (tier-aware start of the ingredient ladder, keeping 8 on-device);
  (4) prepend an adapted intro prompt from `MenuPrepPlanClient.instructions` + the user's `tasteProfile` /
  `makeAheadPrepPlanPreference` (`aiPromptPreferences`), asking for the **review-text** output format the
  paste-in path re-imports. Follows S3.

Follow the [[batch-slices-and-lean-handoff]] default: S1+S2 is one Codex dispatch; S3 follows. Build brief
to live at `efforts/adr-0034-prep-plan-work-session-timeline.md` when dispatched.

## Open questions

- **OQ1 — session grouping when the human hand-edits.** Editable review text is line-based
  (`applyingEditableReviewText`). How does a hand-edited plan re-associate lines to sessions — a
  `session:` header line per band, or a per-line prefix? *Lean:* header line per band (mirrors how the
  bands read), parsed back on commit. Confirm during S1.
- **OQ2 — `serves` when `sourceDish` is null.** Plenty of steps span dishes or feed a meal generally. The
  chip is then a plain non-tappable label. Confirm that reads fine (no dangling link affordance) and that
  the weave is comfortable emitting `serves` prose without a dish ID.
- **OQ3 — does the weave need the stored per-recipe Make-Ahead at all now?** D3 says "compose when
  present, else invent." Confirm we still pass the per-dish Make-Ahead notes in context (we do, via
  `MenuChatContext`) so the weave *prefers* the human's authored notes over inventing from scratch —
  invention is the floor, not the default.

## Related

- ADR-0011/0012 (the apply-action + menu prep-plan verb this reshapes), ADR-0026 (the review sheet it
  rides), ADR-0002 (sync-by-blob), ADR-0022 (the determinism boundary this stays on the advisory side of).
- Memory: [[prep-plan-horizon-redesign]] (the design capture), [[menu-planner-dogfood-2026-07-09]] (the
  superseded strict call), [[llm-vs-determinism-surface-boundary]], [[llm-curation-not-synthesis]],
  [[batch-slices-and-lean-handoff]], [[sqlitedata-blob-cloudkit-asset]].

## Amendment 1 — A calendar day gets a real plan (2026-11-05)

Accepted 2026-11-05 by Jon, during the `handoff-menu` device pass. Not scheduled: there's no brief yet, and Jon expects
light use, so this should stay cheap. It settles the deferred "retire or realign" item above in favor of realign.

**The problem.** The calendar's make-ahead verb saves its whole strategy as one `.note` row
(`MealCalendarRepository.addMakeAheadStrategyNote`). In Jon's words, it's "a huge block of text that I lose myself
through halfway down". It can't be navigated, and it can't be edited step by step
([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)'s grain rule).

**What changes in D1.** D1 stays true for a menu: a menu has one plan, in its Prep Plan section. D1's "not on the
calendar" no longer holds for a day that isn't part of a menu. Its reasoning still does: a task belongs to the meal it
feeds, not the day you do it. So a calendar plan belongs to the **service date**, and a task done on Friday for Saturday's
dinner sits in Saturday's plan, under a band such as "The day before". A view of what's due today stays deferred, with
real-date anchoring.

### A1 — Storage: a new date-keyed synced table

Add a table with the same step fields as `prepPlanSteps`, with `scheduledDate` in place of `menuID`. It has no parent FK,
and `sourceDish` stays a loose ID, here to a `MealPlanItem`.

- **Why not reuse `prepPlanSteps`:** every row there requires `menuID`, and that's the row's one CloudKit parent.
- **Why not turn the day into a one-day menu:** it needs no schema, but menu rows are read-only on the calendar, and the
  Menus list would fill with small one-day menus.
- **Cost:** additive, and it needs a CloudKit Production schema deploy. The consumer ships in the same change.

### A2 — One plan surface, shared with Menu

The day shows Menu's plan UI: collapsible session bands, and step add, edit, reorder, and clear. Share
`MenuPrepPlanSection` and its step views rather than copying them. They're written against `PrepPlanStepRecord` and
`MenuItemRowData` today, so the brief must size that separation. The size is unknown.

### A3 — The verb writes steps

The calendar make-ahead verb commits steps to this table, through Ask now and through Hand off and Paste. It stops
creating a note. Its review should follow Menu's prep-plan review rather than today's editable text block. When a plan
already exists, the verb replaces it with a full plan, as Menu's weave does.

### A4 — Existing notes stay

Make-ahead notes already on the calendar stay as ordinary notes, with no conversion or backfill. Parsing them would be a
data pass for little value. Jon can delete any he doesn't want.

### Questions for the brief

- **Days with a placed menu.** The menu already has a plan, so the day probably links to it and doesn't offer a second
  one. Decide what happens when the same day also has its own items. Since [ADR-0063](ADR-0063-menus-absorb-calendar-days.md), such items can
  be brought into the menu, and bring-in must move this table's steps for the range too.
- **Moved or deleted dishes.** Steps stay on their date when a dish moves or is deleted, unless the brief adds handling.
  *Lean:* leave them, and keep the text readable if `sourceDish` no longer resolves. Decide what happens to a plan when
  the day's last dish goes ([[no-dead-data]]).
- **Conflicts across devices.** A full-replacement write from each of two devices could mix steps from both plans. Check
  how Menu's plan behaves before copying it.
- **Check-off.** Steps have no completion state, in Menu either. Try bands alone first. If Jon still loses his place while
  cooking, a check-off is the next step, and it should cover both plans. This doesn't change the cook-mode deferral above.

## Amendment 2 — A step shows its make-ahead window, and plans leave room for leftovers (2026-11-11)

Accepted 2026-11-11 by Jon, while dogfooding Thanksgiving Week. Brief:
[`prep-step-make-ahead-window`](../efforts/archive/prep-step-make-ahead-window.md).

**The problem.** A step says when to do the work but not how far ahead the recipe allows it. Jon wants the step itself
to say "No more than 24 hours ahead", "8–18 hours" or "Up to 3 days ahead". Placement also ignores leftovers. A sauce
that keeps a week shouldn't be made 7 days ahead when the family eats the leftovers for 3 days after the meal; 4 days
ahead is right.

### B1 — A step stores its make-ahead window

`prepPlanSteps` gains `makeAheadWindow TEXT`, nullable: the recipe's own limit, in short words. It's a separate field
and not folded into `task`, so it can be shown, edited and copied on its own
([ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)). Existing rows stay nil, with no backfill. The step
editor edits it, and the step shows it on its own line above the task. A nil window shows nothing.

- **Source.** Each producer fills it from the dish's Make-Ahead note when one exists, else from what the recipe says.
  The producers are the in-app weave, the Copy Prep Prompt round trip, and `stage_prep_plan`
  ([ADR-0060](ADR-0060-chat-access-over-mcp.md) Amd 5). When nothing grounds it, it's left out, never guessed.
- **Identity.** The window is part of a step's contents wherever steps are matched: `replace` keeps an id only when the
  window matches too, and `stage_prep_plan` shows a changed window as Removed plus New. That needs no new review state.
- **Cost.** One nullable column on a synced table, so a CloudKit Production deploy before any TestFlight upload. Its
  consumer ships with it.

### B2 — Plans leave about 3 days for leftovers, as a rule and not a calculation

Every producer's instructions carry the same rule: when a dish keeps for days, schedule it so about 3 days of keeping
remain after the meal it feeds. A sauce that keeps a week is made no more than 4 days before. A window in hours, or a
limit of a few days or less, is followed as written. The user's make-ahead preferences can override the allowance.

- **Why a rule:** windows are free text from notes, so calculating from them would need the text turned into exact
  durations, which would break easily. The plan is advisory and Jon reviews it, so an instruction to the producer is
  enough (the [[llm-vs-determinism-surface-boundary]] line D1 already holds).
- **Not built:** a setting for the allowance. Add one only if a dinner party and a week of family meals need different
  numbers.

## Amendment 3 — A step carries an approximate time, and time sets its place in the day (2026-11-11)

Accepted 2026-11-11 by Jon, after staging Thanksgiving Week's whole plan from ChatGPT. Brief:
[`prep-plan-time-order`](../efforts/archive/prep-plan-time-order.md). Replaces [ADR-0060](ADR-0060-chat-access-over-mcp.md)
Amd 5-D5's ordering rule, and narrows Amd 2-B1's identity rule.

**The problem.** Within a work day, steps sit in the order they arrived. A chat stages dish by dish, so a day reads by
dish, not by time: Tuesday went 6:57 PM, 6:43 PM, 10:00 AM. The session text can't be the sort key, because most of
Thursday's labels have no time in them ("About 45 minutes into roast", "After turkey is removed"). The 11-10 dogfood
found this and parked it; staging 49 steps at once made it the main problem.

### C1 — An optional approximate time, kept apart from the session label

`prepPlanSteps` gains `timeOfDay INTEGER`, nullable: minutes after midnight, the approximate time the step starts on
its work day. It's a sort key, not a promise. The session stays the label and keeps Jon's preference: approximate
in the run-up, specific on the day. Nil means any time that day. Existing rows stay nil, with no backfill.

- **Wire format:** `"HH:mm"`, 24-hour, wherever a producer or the export carries it.
- **Producers:** the in-app weave, the Copy Prep Prompt round trip, and `stage_prep_plan` each give every step on a
  work day an approximate time, estimated from the meal's time when the menu doesn't state one. Flexible steps send
  none.
- **Shown:** in the step editor (an optional time) and in the chat review. The step row shows only the session.
- **Cost:** one nullable column on a synced table, so another CloudKit Production deploy before any TestFlight
  upload. Its consumer ships with it.

### C2 — Time sets a step's place within its day; Move Earlier/Later still overrides

One placement rule, used wherever a step is placed on a multi-day menu: a step with a time and a work day goes
**before the first step on that day with a later time**, or after the day's last step if none is later. A step with
no time goes where it goes today. The rule runs when:

- a chat's staged steps are applied, for New steps and for Kept steps whose time changed (replacing Amd 5-D5's "after
  the last step with the same session");
- the weave or a paste-back replaces the plan (each step placed in turn, so a day comes out in time order);
- a step is created, or saved with a changed time or work day, in the editor.

Move Earlier/Later changes only `sortOrder`, never the time, so a manual order holds until that step's time or day
changes. Nothing re-sorts on display. Flexible steps and one-day menus are unchanged.

### C3 — Matching ignores the time and the window; a matched step takes the new ones

A step is the same step when its work day, session and task match (and, in `replace`, its serves and dish). Time and
make-ahead window are attributes, not identity. This narrows Amd 2-B1, which made the window part of identity.

- **Chat apply:** a Kept step takes the staged time and window when they differ, keeps its id, and is re-placed if its
  time changed. The review marks it "time updated" or "window updated". This is the only other write Apply makes to a
  Kept step, beside Amd 5-D2's dish link.
- **`replace`:** a surviving step keeps its id and takes the draft's time and window.

**Why:** today's steps have no time. If time were identity, restaging a day just to add times would show every step
as Removed plus New and give each a new id. With C3 it shows only real changes, and the existing steps move into time
order.

### Rejected

- **Parse the session text:** fails on relative labels, which are most of a dinner day.
- **Sort on display:** it would undo Move Earlier/Later.
- **A whole-plan restage mode** (drafted and withdrawn the same day). It would make the chat copy back every step it
  isn't changing, which is where a long plan drifts, and one stage holds at most 20 dishes. Jon restages chosen meal
  days, which the per-dish mode already covers, and deletes leftover steps that belong to no dish by hand.
