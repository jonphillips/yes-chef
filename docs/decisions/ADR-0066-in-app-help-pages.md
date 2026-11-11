# ADR-0066 — A screen can carry a short help page, and the chat reads it too; menus gain Add Menu…

> **One-line:** A screen whose features you can't find by looking gets one bare-bones help page: a few sections of
> plain bullets, kept in Core, shown in a sheet from the toolbar `⋯`. The in-app chat on that screen gets the same
> text, so "how do I…?" is answered from the page instead of guessed. A PR that changes what a page describes updates
> the page. Menus come first, with a direct **Add Menu…** that copies one menu into another without going through the
> calendar.

Status: **Accepted** — 2026-11-11. Effort: [`efforts/menu-help-and-add-menu.md`](../efforts/menu-help-and-add-menu.md).
Origin: Jon, 2026-11-11, after needing the architect to explain Bring In: *"For the life of me, can't figure out how
to put one menu into another menu."* Then: *"I'm wondering if we need a help button on the menu with some of this
documentation. I know that's very non-iOS, but we are building a lot of capability here. Very simple bare-bones
instruction."* He approved this direction the same day.
Builds on: [ADR-0063](ADR-0063-menus-absorb-calendar-days.md) (Bring In, and its copy rules D1 and D3) ·
[ADR-0064](ADR-0064-menu-detail-declutter.md) (the menu toolbar) · [ADR-0043](ADR-0043-model-call-chokepoint.md)
(every model call declares its context layers) · jon-platform `docs/ios/ui-and-platforms.md` § Controls (toolbar
groups and overflow).

## Context

Bring In worked once Jon knew the recipe: place the outer menu once, place the inner menu wholly inside it, then
**Edit › Bring In Calendar Items…**, which only appears when all of that holds. Nothing on screen says any of this. The
same is true elsewhere. Work days on multi-day prep plans, the chat target, and the hand-off round trip are all real
features that are hard to find by looking.

The usual iOS answer is "make it obvious, don't document it." That's right for the basics, and the app should keep
doing it. But Yes Chef is a power tool for one cook, and some of its features take more than one step, so a short
written explanation is worth having. Apple's own pro apps ship help.

There are two failure modes to avoid: a manual nobody reads, and help pages that describe last month's app.

## Decisions

### D1 — One short page per screen, written only where it's earned

- A help page belongs to **one screen** (Menus first). It isn't a manual and doesn't have a table of contents.
- It's **a title and a few sections of plain bullets.** Each bullet says what something does and where to find it, in
  one or two sentences. No screenshots, no essays, no tips about the obvious.
- The rendered page is capped at **1,800 characters**, and a test enforces the cap. The cap keeps the pages
  bare-bones, and it keeps the chat prompt small (D4).
- A screen gets a page only when it has something that can't be found by looking. Most screens never will.

### D2 — Help is the last item in the toolbar `⋯`

- The screen's trailing toolbar gets an `ellipsis.circle` **More** menu if it doesn't already have one. **How Menus
  Work** (`AppSymbol.help`, `questionmark.circle`, a new ADR-0065 concept) is its last item, after a divider. The house Controls rule allows `⋯` in a toolbar
  for rarely used actions, and help is rarely used.
- It opens a sheet showing the page, with a **Done** button. Nothing is a link, and the sheet has no search.
- There's no `?` toolbar button. A dedicated button would be used a few times and then take up space for good.

### D3 — Pages live in Core as typed data

- Pages are values of `AppHelpPage` in `YesChefCore` (`AppHelp.swift`): a title, then sections, each with a heading
  and an array of bullet strings. A bullet may use inline Markdown (**bold**, *italics*) and nothing else.
- Pages live in Core, not in a resource file, because Core has no resource bundle today and the chat prompt is built
  in Core. A Swift literal is just as easy to edit, and tests can check it.
- Typed sections, not one Markdown string, because SwiftUI's `Text` doesn't render Markdown lists or headings. The
  sheet draws sections and bullets itself, and the chat gets a plain-text rendering of the same value
  (`AppHelpPage.plainText`).

### D4 — The in-app chat on that screen reads the page

- The in-app chat's system prompt for that screen's context (`RecipeChatContext.menu` first) appends the page's plain
  text after the subject context, under one framing line: *"How this screen works. Answer questions about using the
  app from this. If it doesn't cover something, say so instead of guessing."*
- It's included on every tier. 1,800 characters fits the on-device budget, and the page is outside the context's
  `serializedCharacterBudget`, so menu content isn't trimmed to make room.
- A new context layer, `ModelCallContextLayer.help`, is declared on those calls (ADR-0043).
- **Not in the outboard hand-off.** ChatGPT plans the food, not the app's controls. **Not in chat access (MCP) yet.**
  Add a `get_help` read when Jon asks ChatGPT how to use the app and it can't answer.

### D5 — A change to what a page describes updates the page in the same PR

- A PR that adds, removes, renames or moves something a help page mentions updates that page in the same PR. A brief
  that touches a screen with a page says so in its Done-when, and the architect's review checks it.
- The rule is a ⚠️ standing guard (`docs/standing-guards.md`), so it applies to every dispatch that touches such a
  screen.
- Each page's sentences name controls by their on-screen labels. A test asserts that each page names its own screen's
  `⋯` entry title, so renaming that entry fails the test. The other labels are checked in review, not by tests.

### D6 — Add Menu… copies one menu into another, from the menu itself

ADR-0063 rejected nesting, and that stands. A menu doesn't contain another menu. But copying in a menu shouldn't
require placing both on the calendar first.

- The menu screen's `⋯` gets **Add Menu…** (`custom.menucard.arrow.in`, the "bring into this menu" glyph from ADR-0064
  D8) as its first item.
- It opens a sheet listing every other menu that has dishes or prep steps, each showing its day count and dish count.
  This menu isn't listed. Choosing one shows **Start on** (Day 1 … the last day it fits) when this menu has more than
  one day. A menu longer than this one is listed but disabled, with "Needs N days." **Add** commits.
- The copy follows ADR-0063's rules exactly. Items keep their content and get a fresh id, with `dayOffset` shifted by
  the chosen start day. Prep steps are appended, with `sourceDish` re-pointed and work days shifted or dated from
  their session label (D3). Nothing is de-duplicated. Core shares the copy code with Bring In, so the two paths can't
  drift.
- **The source menu is untouched**, including its calendar placements. This is the difference from Bring In, which
  *moves* calendar content. If the source is placed on the calendar inside this menu's dates, the sheet says so in one
  line: its dishes will show twice there, and Bring In is the way to move it instead.
- No schema change.

## Rejected

- **A `?` toolbar button.** It would be permanent clutter for an occasional action (D2).
- **TipKit.** Tips show once and then they're gone, which makes them useless as reference. Also, a single user sees
  every tip on the first day.
- **One global help screen or manual.** It would be harder to find than a page on the screen you're stuck on, and it
  would grow into a manual.
- **A Markdown resource file.** It would need resource-bundle plumbing in Core, and `Text` can't render its lists
  anyway (D3).
- **Feeding help to the outboard hand-off.** It's the wrong audience (D4).
- **Nesting, again.** ADR-0063's reasons hold. Add Menu… copies.
- **Add Menu… unplacing the source** the way Bring In does. The source may be a template that isn't on the calendar at
  all, and silently changing another menu's dates would surprise you. Bring In stays the tool for moving.

## Consequences

- Each page adds about 1,800 characters to every chat turn on its screen.
- Every PR touching a screen with a page carries a small extra review item (D5). Pages will still drift between
  reviews, and the chat repeating stale help is how that drift gets noticed.
- Add Menu… can't be undone, just as Bring In can't. Wrongly added dishes are deleted one by one, and the source menu
  is unchanged.
- If the source is also placed inside this menu's dates, its dishes show twice on the calendar and in that range's
  groceries until one placement is removed. The sheet warns about this case.
