# ADR-0068 — Groceries split into two trips, your switches stick, and the Groceries screen gets a help page

> **One-line:** When you add a menu's or a calendar day's ingredients, you can split them into an **Advance** list
> and a **Fresh** list. A fixed rule picks each ingredient's trip: a short list of produce that keeps, then the store
> area, then Fresh. No model is involved. When you switch an ingredient to the other trip, the app remembers it in a
> small synced table. Separately, the add sheet now skips only pantry items set to **Always have it**, and the
> Groceries screen gets a **How Groceries Work** page.

Status: **Accepted** — 2026-11-11. Effort: [`efforts/grocery-two-trips.md`](../efforts/grocery-two-trips.md).
Origin: Jon, 2026-11-11: *"Stores get crowded at Thanksgiving, so I like to do two waves of shopping. The first is a
week before for staples, canned/jarred goods, and long keeping produce like onions/garlic."* He also said he
*"barely understand[s] how the corrective nature of grocery list items/pantry/etc. work."* The same day he decided
that switches stick, that Add Back stays unsaved, that the add sheet should respect each pantry setting, and that
the help page should be included.
Builds on: [ADR-0035](ADR-0035-grocery-store-area-grouping.md) and
[ADR-0052](ADR-0052-grocery-learned-area-table.md) (store areas and the learned-table pattern) ·
[ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) (grocery merging stays deterministic) ·
[ADR-0066](ADR-0066-in-app-help-pages.md) (help pages) · the Phase E pantry design
([archived milestone](../milestones/archive/grocery-consolidation-and-pantry.md)).

## Context

Today, adding ingredients puts everything on one list. Jon shops twice for a big event: a week ahead for staples,
cans and jars, and produce that keeps, then close to the day for everything perishable. Grocery lists are already
first-class (you can have several, and each one shares and exports on its own), so two trips can simply be two lists.
The open questions were how each ingredient gets its trip, and whether Jon has to teach the app.

Reading the grocery code turned up a second problem. Pantry rules apply in two places, and the two disagree:

1. **The add sheet** starts every line that matches *any* pantry item unchecked, under **Skipped Pantry Staples**.
2. **The list** applies each pantry item's setting. **Always have it** hides the item, **Remind me** hides small
   amounts and shows big ones under **You may need more**, and **Always confirm** always shows it.

Because the first step ignores the setting, a **Remind me** or **Always confirm** item from a menu never reaches the
list unless Jon re-checks it by hand. So the list-side rule never gets a chance to run.

## Decisions

### D1 — Split happens on the add sheet, into two lists

- The Add Ingredients sheet gets a **Split into two trips** toggle for **menu** and **calendar day** sources. A single
  recipe doesn't get it. The toggle is off by default.
- When it's on, the sheet shows an **Advance** section and a **Fresh** section in place of **Ingredients**.
  **Skipped Pantry Staples** stays as it is. Each line shows its trip as a tag, and tapping the tag moves the line.
  **All lines with the same ingredient (canonical name) move together.**
- **Add** writes the Advance lines to a list titled "*<source title>* — Advance" and the Fresh lines to
  "*<source title>* — Fresh". If a list with exactly that title already exists, it's reused, so adding a forgotten
  dish later lands on the same lists. A side with no lines doesn't create a list. The list selected on screen is
  ignored when splitting.
- Trips are assigned **per ingredient, not per line**, so each ingredient lands on exactly one list. That keeps
  merging working, and pantry thresholds are still checked against the full amount.

### D2 — A fixed rule picks the default trip; no model

For each ingredient, the first match wins:

1. **Your switch** (D3).
2. **Produce that keeps → Advance.** A short built-in list: onion, garlic, shallot, potato, sweet potato, yam, carrot,
   celery, beet, parsnip, turnip, rutabaga, cabbage, ginger, lemon, lime, orange, apple, cranberry, and the named
   winter squashes (butternut, acorn, kabocha, delicata, spaghetti squash, pumpkin). The match is on the canonical
   name or its last word, except green onion and spring onion, which wilt.
3. **Store area.** Advance: Canned & Dry, Condiments & Oils, Spices, Baking, Beverages, Dairy, Frozen, Household.
   Fresh: Produce, Bakery, Deli, Meat & Seafood, Other, any custom area. The area comes from the existing
   deterministic resolver (your area fix, then the built-in area list, then a model area already saved in the table).
   This step never makes a new model call.
4. **Otherwise Fresh.**

When the rule is unsure, it picks Fresh, because the two mistakes don't cost the same. Something wrongly put on Fresh
is just bought on the second trip, which is what you'd do without this feature. Something wrongly put on Advance, like
herbs, sits for a week. So Jon doesn't have to teach the app anything up front. He switches the few it gets wrong.

### D3 — Your switches stick, in a small synced table

- New table `groceryTripAssignments`: `id`, `canonicalName`, `trip` (a real enum: `advance` | `fresh`),
  `dateModified`. It only holds your switches. The built-in keeper list and the area rule stay in code, the same split
  ADR-0052 made (design B).
- The `id` is a fixed UUIDv5 made from the canonical name (`DeterministicID.groceryTrip(canonicalName:)`), so both
  devices produce the same row for the same ingredient, and an upsert replaces it. That avoids the duplicate-row
  handling ADR-0052's table needs.
- Rows are written when you tap **Add**, one for each ingredient you switched on the sheet. **Cancel** writes
  nothing. To change a remembered trip, switch it again. There's no screen for managing these rows.
- **Persistent model change** (AGENTS.md rule): it's one new table with an append-only migration, and no existing
  data changes. It syncs, so it needs a Production schema deploy. The simpler option was not remembering switches,
  and Jon turned that down: switches should stick.

### D4 — The add sheet respects each pantry setting

- Only pantry items set to **Always have it** start unchecked under **Skipped Pantry Staples**. Items set to
  **Remind me** or **Always confirm** start checked. Once on the list, the list-side rule handles them, so a big
  butter amount shows under **You may need more**.
- The built-in "salt and pepper" match still skips as before.
- No schema change.

### D5 — Add Back stays unsaved

**Add Back** keeps an item on the list only until the app relaunches. Jon decided it doesn't need saving. If he wants
an item for good, he can change its pantry setting.

### D6 — How Groceries Work

- A help page per ADR-0066. It goes last in the Groceries list's existing `⋯` (**List Actions**) menu, after a
  divider, and explains adding, splitting, merging, pantry settings, and store-area fixes.
- There's no grocery chat, so ADR-0066 D4 (the chat reads the page) doesn't apply. The standing guard (ADR-0066 D5)
  does apply: this page's labels are now covered by it.

## Later, not decided here

- **Make-ahead dishes.** A dish whose prep starts before the Fresh trip needs its perishables on the Advance trip
  (pie, stock). The prep plan already knows each dish's work days, so a rule could move those dishes' lines to
  Advance. That rule needs a date for the Fresh trip.
- **Scheduling trips.** Jon asked whether to schedule the trips. Not for this ADR: with no make-ahead rule, a trip
  date changes nothing. When the make-ahead rule comes, the date should come from the menu's calendar placement,
  with a "Fresh trip: N days before" setting on the split, following the date-over-toggle rule in
  [ADR-0039 Amd 1](ADR-0039-playbook-column-thinking-vs-doing.md). Trips don't become calendar entries.

## Rejected

- **A model deciding what keeps.** The rule above covers the common cases, the safe default absorbs the rest, and
  switches stick. If misses pile up, the ADR-0052 pattern (a model fills misses and loses to you) can be added
  without changing this design.
- **One list with trip sections.** Two trips are two outings, and lists already share, export and get checked off
  one at a time. Sections would need new grouping and share logic for the same result.
- **A trip column on `groceryItems`.** That would apply to one item on one list only, and the next menu would forget
  it. Where the item sits is the trip; the table remembers your switches.
- **Splitting by line instead of by ingredient.** That puts the same ingredient on both lists and breaks the threshold
  total.

## Consequences

- One new synced table, which needs a Production deploy before any TestFlight build that includes it.
- The keeper list in code is Jon's to tune. A missing keeper costs one switch, once.
- The add sheet gains a toggle and a per-line tag, shown only for menu and calendar-day sources.
- A **Remind me** or **Always confirm** pantry item now reaches the list, where its rule applies. That's the
  intended behavior, but Jon will see items he used to have to re-check by hand.
