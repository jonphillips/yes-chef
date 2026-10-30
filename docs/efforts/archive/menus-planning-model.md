# Menus and the planning model — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** Menu vs meal plan vs cooking plan, and the 2026-07-02 dogfood asks: dated menus on the planner, searchable guests, multi-add groceries from a calendar day.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Menus / planning model

- Does the Menus subsystem need its own ADR, and what is the canonical provenance
  model linking recipe → menu → menu placement → calendar item → grocery source?
- Is "menu" vs "meal plan" vs "cooking plan" a clean three-concept split, or do two
  of them collapse?
- **Dated menus + upcoming/previous + on the planner (dogfood, 2026-07-02).** Jon wants to
  apply a **date** to a menu; the Menus list should split into **upcoming** vs **previous**;
  and dated menus should appear on the meal planner. Foundation partly exists — `menuPlacements`
  already put a menu on the calendar — but a first-class menu **date** field + list sectioning is
  net-new. Net-new feature, not designed yet.
- **Menu guests, searchable (dogfood, 2026-07-02).** Jon wants to record a menu's guests and
  have them searchable. Decision needed: a dedicated `guests` field (enables future guest
  search/reuse — favored) vs. stuffing it into free-text notes. Net-new, needs a small model
  decision.
- **Multi-add groceries by tapping a calendar day (dogfood, 2026-07-02).** Tap a day on the
  meal calendar and add *all* that day's items to the grocery list at once. **Verify against
  existing behavior first** — add-from-calendar-range/day generation already exists
  (`GroceryModels`/repository); this may be a UX-surfacing gap rather than net-new. Scope after
  confirming what the current add-from-calendar-day flow already does.
