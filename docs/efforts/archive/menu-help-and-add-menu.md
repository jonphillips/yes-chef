# Effort — Menus get a help page and a direct Add Menu…

Status: Ready
Summary: The menu toolbar gains a `⋯` with **Add Menu…** (copy another menu's dishes and prep steps into this one, starting on a chosen day) and **How Menus Work** (a bare-bones help sheet). The menu chat reads the same page. No schema change.

Origin: Jon, 2026-11-11, after getting stuck putting Thanksgiving into Thanksgiving Week. One dispatch, one PR.

Decisions: [ADR-0066](../../decisions/ADR-0066-in-app-help-pages.md) (D1–D6; read it first). The copy rules are
[ADR-0063](../../decisions/ADR-0063-menus-absorb-calendar-days.md) D1 and D3, unchanged. Related:
[ADR-0064](../../decisions/ADR-0064-menu-detail-declutter.md) (the toolbar, the `custom.menucard.arrow.in` glyph).

## Where things are (architect, 2026-11-11, `origin/main` 22a578b)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `MenuBringIn.swift`: `bringIn(menuID:in:now:uuid:)`. The per-placement loop (about line 163) copies items with a
  day shift, then appends prep steps with `sourceDish` re-pointed and `workDayOffset` shifted or dated through
  `PrepPlanSessionBand(matching:)`. That loop is the code to share.
- `RecipeChat.swift`: `systemPrompt()` (about line 950), and the `contextLayers` built just before each model call
  (about line 894).
- `ModelCall.swift`: `ModelCallContextLayer` (about line 104).
- `MenuChatContext.swift`: the menu chat context. `RecipeChatContext.menu` wraps it.

**App (`YesChefApp/`)**
- `MenuViews.swift`: the detail toolbar's `ToolbarItemGroup(placement: .primaryAction)` (about line 176), holding
  Cook these, Add Recipes, Edit and `HandoffMenu`.
- `MenuModels.swift`: `MenuModel`'s `destination` enum and `bringInButtonTapped` / `confirmBringIn` (the pattern for a
  sheet plus a write).
- `AppSymbol.swift`: `.bringIntoMenu` is the `custom.menucard.arrow.in` symbol.
- `.swiftlint.yml`: the ADR-0065 D5 custom rule whose regex lists every concept glyph.

## The slice

### Core: share the copy (ADR-0066 D6)
- Pull the per-menu copy out of `bringIn` into one internal function. It copies a source menu's items and prep steps
  into a target menu with a given day shift and returns the old-to-new item id map. `bringIn` calls it per contained
  placement and keeps its grocery re-pointing and placement deletion. **Bring In's behavior doesn't change**, and its
  existing tests pass untouched.
- Add `MenuRepository.addMenuOffer(targetMenuID:in:)` (a pure read) and
  `MenuRepository.addMenu(sourceMenuID:into:startDayOffset:in:now:uuid:)`:
  - The offer lists every other menu with at least one item or step: id, title, `dayCount`, dish count, and whether
    it fits (`dayCount <= target.dayCount`). Sort by title, as Bring In does.
  - It also carries, per source, a calendar overlap note. The note is present when the target has exactly one
    placement and the source has a placement wholly inside the target's range: the source title and that
    placement's start date. Use the same range arithmetic as `bringInCandidates`.
  - The write re-reads inside its transaction. It throws if the source is gone or empty, if it's the target itself,
    or if `startDayOffset + source.dayCount > target.dayCount`. It touches no placement and no grocery source.

### Core: help pages (ADR-0066 D1, D3, D4)
- New `AppHelp.swift`: `public struct AppHelpPage` (`title`, `sections: [Section]`, where `Section` has a `heading` and
  `bullets: [String]`), `plainText` (the title, then each heading and its bullets as `- ` lines), and
  `public static let menus`, with the copy below.
- Add `case help` to `ModelCallContextLayer`.
- `RecipeChatContext` gains `helpPage: AppHelpPage?`: `.menus` for `.menu`, nil for every other case.
  `systemPrompt()` appends, when non-nil, a blank line, then *"How this screen works. Answer questions about using the
  app from this. If it doesn't cover something, say so instead of guessing."*, then `plainText`. The call sites add
  `.help` to the included layers when the page is non-nil. The page sits outside `serialized(for:)`'s budget.

### The Menus page copy

The architect wrote this. **Check each sentence against the app as built, after your changes.** Fix a label that
doesn't match what's on screen, and list each fix in the PR body. Don't add bullets.

> **How Menus Work**
>
> **A menu**
> - A menu plans an event: one dinner or a whole week. Dishes sit on Day 1, Day 2 and so on, not on dates.
> - Tap **+** on a day to add a dish. Long-press a dish to edit it, move it to another day, or make a note into a
>   recipe.
>
> **Dates**
> - To give a menu real dates, tap **Edit** (the pencil), then **Place on Calendar…**. Its dishes then show on the
>   Calendar.
> - A menu can be placed more than once, such as the same dinner party twice.
>
> **Combining menus**
> - **⋯ › Add Menu…** copies another menu's dishes and prep steps into this one, starting on the day you pick. The
>   other menu doesn't change.
> - **Edit › Bring In Calendar Items…** moves what's already on the calendar during this menu's dates into it,
>   including any menu placed wholly inside them. It shows only when this menu is on the calendar once and there's
>   something to bring in.
>
> **Prep plan**
> - The **Prep Plan** column lists work to do ahead. Build it from the **AI** menu: **Ask now** to work with the
>   in-app chat, or **Hand off** to ChatGPT and **Paste** the reply. Tap a step to edit it.
> - On a menu longer than one day, steps are grouped by the day you do the work.
>
> **Cooking**
> - **Cook these** opens the menu's recipes together for cooking.

### App
- **Toolbar:** append a `Menu` labeled **More** (`ellipsis.circle`) to the existing primary-action group, after
  `HandoffMenu`. It holds **Add Menu…** (`AppSymbol.bringIntoMenu`), a `Divider`, and **How Menus Work**
  (`AppSymbol.help`).
- **`AppSymbol.help`:** a new concept, `questionmark.circle`, already in ADR-0065's D2 table. Add the `static let` and
  add `questionmark.circle` to the lint rule's regex (ADR-0065 D5).
- **Add Menu sheet:** a new `MenuModel` destination case. It's a `NavigationStack` with a `List` of the offer's menus,
  each showing title and "N days · M dishes", disabled with "Needs N days" when it doesn't fit. Selecting one shows a
  **Start on** picker (Day 1 … last fitting day, with the real date when this menu has one placement) only when the
  target has more than one day. It shows the overlap note when present: *"Thanksgiving is also on the calendar on Thu,
  Nov 26. Its dishes will show twice there. To move it in instead, use Edit › Bring In Calendar Items…"* It has
  **Cancel** and **Add**. Add writes through the model, dismisses, and surfaces errors through the model's existing
  error alert.
- **Help sheet:** a new destination case showing `AppHelpPage.menus`: the title as the navigation title, each section
  as a `Section` with its heading, and bullets as `Text(LocalizedStringKey(bullet))` rows, so inline bold renders.
  **Done** dismisses it. Put the view in its own small file (`AppHelpSheet.swift`), taking an `AppHelpPage`, so later
  screens reuse it.

### Standing guard
Already in this plan: `docs/standing-guards.md` carries ADR-0066 D5. This brief's own Done-when applies it.

## Tests

**Core**
- The shared copy: after the extraction, the existing Bring In tests pass unchanged.
- `addMenu` on a 7-day target with a 1-day source at start day 4: items land on day offset 3, prep steps keep their
  order after the target's own, `sourceDish` points at the copies, *The day before* lands on offset 2, and *Flexible*
  stays nil. The source's items, steps and placements are unchanged.
- `addMenu` with a multi-day source whose steps have `workDayOffset`: shifted by the start day.
- `addMenu` throws on the target itself, on an empty source, and on a source that doesn't fit at the requested start.
- `addMenuOffer`: excludes the target and empty menus, marks a too-long menu as not fitting, and carries the overlap
  note only when the target has one placement and the source's placement is wholly inside it.
- `AppHelpPage.menus.plainText.count <= 1_800`. It contains "Add Menu…" (ADR-0066 D5's one tested label).
- The menu chat's `systemPrompt()` contains the framing line and the page's plain text. A recipe chat's doesn't. The
  menu chat call's context layers include `.help`.

**App (`YesChefTests`):** Add Menu through `MenuModel` writes the copy and clears the destination. This touches
`YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- **⋯ › Add Menu…** copies a menu in at a chosen day and leaves the source alone. **⋯ › How Menus Work** shows the page.
  The menu chat answers "how do I put one menu into another?" from the page.
- Bring In's behavior is unchanged.
- The help page matches the app as built, and any label fixes are listed in the PR body (ADR-0066 D5).
- Tests above. Verification per [`verification.md`](../../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- **Jon's device gate:** on an iPad, open **⋯ › How Menus Work** and read it. Then make a scratch 3-day menu and
  **⋯ › Add Menu…** Thanksgiving at Day 2: its dishes land on Day 2, its prep steps follow, and Thanksgiving itself is
  unchanged. Ask the menu chat how to combine two menus, and check that it describes Add Menu… and Bring In.
