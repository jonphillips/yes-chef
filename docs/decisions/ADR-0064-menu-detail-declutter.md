# ADR-0064 — Menu detail: one AI menu, an Edit sheet, and rows without buttons

> **One-line:** The menu screen's three AI surfaces become the house **AI** toolbar menu. **Place** and the
> Calendar section become an **Edit Menu** sheet behind a pencil. Dish rows lose their trailing buttons. The
> Playbook toggle, the ChatGPT Project field and the large empty states go. Three custom SF Symbols give recipes and
> menus one glyph vocabulary.

Status: **Accepted** — 2026-11-10. Effort: [`efforts/menu-detail-declutter.md`](../efforts/menu-detail-declutter.md).
Origin: Jon's iPad pass on Thanksgiving Week 2026, 2026-11-10: *"There are so many buttons… I don't even remember
what that bullseye/target button does."* He approved a comp the same day. Two details differ from the comp because
of the house Controls rules (D2, D5).
Builds on: jon-platform `docs/ios/ui-and-platforms.md` § Controls (row actions, toolbars, the AI entry point) ·
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the Playbook column) ·
[ADR-0063](ADR-0063-menus-absorb-calendar-days.md) (placement and Bring In).
Re-applies: [ADR-0039 Amd 3](ADR-0039-playbook-column-thinking-vs-doing.md) (no menu Playbook toggle), reversing the
[2026-07-25 dogfood ferry](../efforts/archive/dogfood-ferry-2026-07-25.md) slice that brought it back for parity with
the recipe screen. The recipe screen dropped its own toggle on 2026-09-24.
Amends:
[ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd 1 (`Menu.externalProjectName` is no longer an
override, and nothing reads or writes it).

## Context

On a placed multi-day menu the screen shows these controls:

- **Toolbar:** Cook these, Browse Recipes (`book.badge.plus`), and Show/Hide Playbook (`sidebar.trailing`).
- **Body:** a ChatGPT Project field with Save Project, a **Place** button beside the Dishes heading, and a
  **Calendar** section at the bottom with Bring In and the placements.
- **Each day header:** an add button and a red **Hand off** text menu.
- **Each dish row:** up to three trailing buttons. **Make Recipe** (`book.badge.plus`, notes only), **Deposit target**
  (`target`) and **Edit Dish**, which uses a `calendar` icon.
- **Playbook column:** an **AI** menu (Hand off, Paste, Ask now) and **Regenerate whole plan** in a header row.
  Prep Plan's own `⋯` menu holds Copy Recipe Capture Request, Hand off · Prep, Hand off · Regenerate, Paste · Prep,
  and Clear. Then a large empty state for Prep Plan and another for Learnings.

Several of these duplicate each other or don't mean what they look like:

- **The two hand-offs are the same.** The column's *AI › Hand off* and Prep Plan's *⋯ › Hand off · Prep* both copy
  `HandoffExportSource.menu(menuID)`. The two Pastes route to the same source as well.
- **One glyph, two jobs.** `book.badge.plus` means both "browse recipes to add" in the toolbar and "make this note a
  recipe" on a row.
- **The bullseye only works while chat is open.** It marks the row that the in-app chat's *Add to recipe notes* and
  *Revise this note* write to (ADR-0027 Amd 1). With Ask closed it does nothing, but it still shows on every row.
- **Regenerate whole plan is the onboard model.** It sends a rebuild ask into the in-app chat. It doesn't hand off to
  ChatGPT, so it sits beside the hand-off menu without being one.
- **The Playbook toggle frees no space.** The menu body is capped at 900 pt, so hiding the column leaves the space
  empty. ADR-0039 Amd 3 removed this toggle once. The 2026-07-25 dogfood ferry restored it to match the recipe
  screen, and the recipe screen has since dropped its own.
- **The project field is obsolete.** ADR-0042 Amd 1 moved every hand-off into one shared Yes Chef ChatGPT project and
  kept `externalProjectName` as an override. Jon doesn't use the override.
- **Place is an edit.** The placement sheet is where a menu's length changes. Apart from that sheet, a menu's title
  and notes can't be edited after it's created.
- **The house rules already say otherwise.** Controls says every AI surface uses one trailing toolbar **AI** menu
  (Hand off, Paste, Ask now). It also says list rows carry no trailing action glyphs: actions go in the context menu
  and swipe, and a trailing glyph is only for status.

## Decisions

### D1 — One AI menu, in the toolbar

The menu screen gets the house `HandoffMenu` in its trailing toolbar group, after Cook these and Add Recipes. It
replaces the Playbook column's header row (the AI menu and Regenerate whole plan) and the hand-off half of Prep Plan's
`⋯`.

- **Hand off** opens a submenu, as the house rule allows when a screen has several hand-off purposes:
  - **Menu** — `.menu(menuID)`, today's *Hand off · Prep*.
  - **Fresh prep plan** — `.menu(menuID, prepPlanIntent: .regenerate)`, today's *Hand off · Regenerate*.
  - **Recipe capture request** — today's *Copy Recipe Capture Request*.
- **Paste** routes to `.menu(menuID)`, as both Pastes do today.
- **Ask now** toggles the in-app chat, as the column's AI menu does today.

Nothing else goes in this menu. The house rule fixes its three items and their order.

### D2 — Rebuilding with the onboard model moves into Prep Plan's `⋯`, below the fold

**Regenerate whole plan** stops being a visible button. It becomes **Rebuild with Yes Chef…** in Prep Plan's `⋯`
menu, above **Clear Prep Plan**. The behavior is unchanged: it opens Ask, sends the rebuild request, and nothing
replaces the plan until the cook approves it in the review. It's enabled under the same condition as today (the plan
has steps).

The comp put this item in the AI menu. It moves to Prep Plan's `⋯` because the house AI menu holds only its three
verbs, and because the rebuild belongs to the prep plan.

### D3 — Edit Menu replaces Place and the Calendar section

A pencil (`square.and.pencil`, the same Edit glyph the recipe screen uses) joins the trailing toolbar group. It opens
an **Edit Menu** sheet:

- **Title** and **Notes**. These are new: no menu field is editable after creation today.
- **Days.** The stepper and its floor are today's, and shrinking clears work days past the end (ADR-0063 D5).
- **Calendar.** One row per placement with its start date. Each row can change the date or **Remove from Calendar**.
  **Place on Calendar…** adds a placement. **Bring In Calendar Items…** shows when ADR-0063's offer is non-nil.

The **Place** button, the bottom **Calendar** section and the placement sheet's role as the length editor all go. The
post-save Bring In offer (ADR-0063 D2) fires after this sheet saves a new or moved placement, just as it does after
the placement sheet today.

No schema change. Title and notes are existing columns.

### D4 — The header carries the dates; the project field goes

- With exactly one placement, the header's metadata line leads with the date range ("Sun, Nov 22 – Sun, Nov 29") and
  then the day and dish counts. With several placements it says how many ("On the calendar 2 times"). With none it
  shows only the counts.
- The **ChatGPT Project** field and Save Project are removed. So is the hand-off entity's `externalProjectName`
  property (the "ChatGPT Project" value in Shortcuts).
- `Menu.externalProjectName` stays in the schema: Production fields are permanent (ADR-0056). Nothing reads or
  writes it, and existing values stay where they are.

### D5 — Dish rows carry no action buttons

This follows the house row-actions rule:

- **Tap** opens the recipe, or a note's editor, as today.
- **Context menu (long-press):** Edit, Move to Day, **Make Recipe** (notes only), **Set as Chat Target** / **Clear
  Chat Target** (only while Ask is open), and Delete.
- **Swipe:** trailing Delete and Move to Day, as today. Leading **Make Recipe** on notes, and Edit on recipes.
- **The chat target is status.** While Ask is open, the targeted row shows a trailing `target` glyph and today's
  accent tint, and no other row does. With Ask closed, no row shows either. The selection survives closing and
  reopening the chat, as it does today.

The comp kept a visible Make Recipe button on note rows. The house rule moves it into the context menu and swipe,
where it uses the new glyph (D8).

### D6 — Day headers are quieter, and empty days are one line

- The title reads "Sunday, Nov 22 · Day 1" when the menu is placed once, and "Day 1" otherwise.
- The add button and the hand-off menu are icon-only. Their accessibility labels and the hand-off menu's items are
  unchanged.
- A day with no dishes is one line ("Tuesday, Nov 24 · Day 3 — no dishes") with no chevron and no "No dishes" body
  row. Its add and hand-off buttons stay.

### D7 — The Playbook column is always there, and quiet when empty

- The Show/Hide Playbook toggle is removed, and so is its stored preference. On wide layouts the column always shows.
  The resize handle and the per-menu widths are unchanged.
- An empty Prep Plan shows one tertiary line, "No steps yet.", and so does an empty Learnings section. The
  `ContentUnavailableView` cards go.
- **Add Step** and **Add Learning** become `plus` icon buttons beside their headings, with their accessibility labels
  kept. Prep Plan's `⋯` holds Rebuild with Yes Chef… and Clear Prep Plan.

### D8 — Three custom symbols: plus means add, an arrow in means "make into" or "bring into"

Recipes are `richtext.page` and menus are `menucard`. Overlays have one meaning each:

| Symbol | Meaning | First use |
|---|---|---|
| `custom.richtext.page.badge.plus` | add recipes | the menu toolbar's **Add Recipes** (today *Browse Recipes*, `book.badge.plus`) |
| `custom.richtext.page.arrow.in` | make this into a recipe | **Make Recipe** on a note row |
| `custom.menucard.arrow.in` | bring into this menu | **Bring In Calendar Items…** |

`book.badge.plus` is retired from the menu screen. The architect authored the templates from Jon's SF Symbols exports
(`docs/design/symbols/`). They're Regular-weight static templates: the arrow and badge cut-outs can't be made
interpolation-compatible with Ultralight and Black, so every weight draws the Regular design. That's fine for toolbar
and menu icons. A `custom.menucard.badge.plus` template exists in Jon's iCloud folder but ships only when something
needs it.

## Rejected

- **Keeping a scoped AI menu in the Playbook column.** The house rule allows one, but here it would duplicate the
  toolbar menu verb for verb. The column holds no hand-off of its own.
- **A visible Make Recipe button on note rows.** This was in the approved comp. It's an action, and rows carry status
  glyphs only (D5).
- **Composing overlays in SwiftUI** (`Image` plus `.overlay`). That can't cut a gap in the page outline where the arrow
  crosses it, and it doesn't scale with the text. Custom symbols do both.
- **Dropping the `externalProjectName` column.** Production schema is additive-only (ADR-0056).

## Consequences

- One toolbar AI menu on Menu, the same as Recipe and Calendar. The Playbook column has no AI controls.
- Rarer actions are a long-press away: Edit Dish, Make Recipe, chat target, and the onboard rebuild.
- A menu can be renamed and its notes edited for the first time.
- `Menu.externalProjectName` stays in the schema with nothing reading it. A Shortcut that reads the hand-off entity's
  "ChatGPT Project" property loses that value. Jon confirmed on 2026-11-10 that his flow uses one shared project.
- The three symbols live in the app's asset catalog as `.symbolset`s. Their source templates are in
  `docs/design/symbols/`.
