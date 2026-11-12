# ADR-0069 — Ingredient name fixes: say once that two names are the same ingredient, and it holds everywhere

> **One-line:** A small synced table of **name fixes** (`flat leaf parsley → parsley`). Each row maps one ingredient
> key to another. Every place that compares ingredient keys (grocery merging, store areas, trips, pantry, the Compare
> matrix) applies the fixes after the built-in rules. Nobody adds built-in aliases by hand any more: your fixes get
> promoted into the built-in list on a schedule ([ADR-0070](ADR-0070-what-you-teach-reaches-everyone.md)), so
> everyone who uses the app gets them. You add a fix from a grocery item (**Same As…**) or from **Groceries › ⋯ › Name Fixes**, and you edit or delete it there.

Status: **Accepted** — 2026-11-12 (Jon). Effort: [`efforts/archive/ingredient-name-fixes.md`](../efforts/archive/ingredient-name-fixes.md).
Amended: [Amendment 1](#amendment-1--notes-and-store-areas-dont-block-a-merge-consolidate-list-2026-11-12) (2026-11-12): notes and store areas no longer block a merge; **Consolidate List**; items sort by name within an area.
Origin: Jon, 2026-11-12, graduating the [Tandoor idea harvest](../efforts/archive/tandoor-idea-harvest.md): *"this is
the 'same misses over and over' trigger: a table of editable name fixes using the ADR-0052 shape. You'd add
'flat-leaf parsley → parsley' once and it would apply everywhere, instead of relying on a growing hardcoded list. The
bigger {base, form, prep} model can stay deferred."* The trigger is #499 (2026-11-11), which added three parsley
spellings and six prep adverbs to `CanonicalIngredient` in code, after #484 and earlier dogfood passes did the same.
Builds on: [ADR-0052](ADR-0052-grocery-learned-area-table.md) (the learned-table pattern; this closes its OQ2) ·
[ADR-0068](ADR-0068-two-trip-grocery-split.md) D3 (the fixed-UUID row id) ·
[ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) (grocery merging stays deterministic) ·
[ADR-0066](ADR-0066-in-app-help-pages.md) (the Groceries help page) ·
[ADR-0070](ADR-0070-what-you-teach-reaches-everyone.md) (how your fixes reach everyone else).

## Context

Every ingredient line and grocery item gets a **key** from `CanonicalIngredient.canonicalName`: lowercased, a few
leading prep words stripped, lightly singularized, then a small built-in alias list. Two lines merge on the grocery
list only when their keys match, and the store-area table, the trip table, pantry matching and the Compare matrix all
look things up by the same key.

When two spellings of one ingredient get different keys, the only fix today is a code change: add an alias or a prep
word, ship a build, and run a data pass to refresh cached keys (#499 added that pass). Each miss costs a dispatch, so
misses pile up. That's the same bottleneck ADR-0052 found for store areas, where a fix meant hand-editing Swift.

Tandoor fixes the same problem with a table of user-editable alias rows. ADR-0052 already built that shape for one
target (store areas). This ADR is its second target: the key itself.

**Not in scope:** a structured `{base, form, prep}` ingredient model, Tandoor's other rule types (never-unit,
transpose-words, site-scoped regex), and any model-suggested fixes. The harvest notes stay in the archive for those.

## Decisions

### D1 — A synced `ingredientNameFixes` table: one row per "from" key

```swift
@Table("ingredientNameFixes")
struct IngredientNameFix: Identifiable, Sendable {
  let id: UUID          // DeterministicID.ingredientNameFix(fromName:)
  var fromName: String  // a base key (D2), e.g. "flat leaf parsley"
  var toName: String    // a base key, e.g. "parsley"
  var dateModified: Date
}
```

- The `id` is a fixed UUIDv5 made from `fromName`, as ADR-0068 D3 does for trips. Both devices produce the same row
  for the same "from" key, an upsert replaces it, and there's no duplicate-row handling.
- **No `source` column.** Every row is one you wrote; nothing else writes them. If a model ever proposes fixes, that
  change adds `source` with ADR-0052's precedence. Shipping the column now would be schema with no writer.
- **Persistent model change** (AGENTS.md rule): one new table, an append-only migration that writes no data, and no
  change to existing rows. It syncs, so it needs a Production schema deploy. The simpler option is to keep adding
  aliases in code, which is the cost this ADR removes.

### D2 — Stored keys stay the built-in key; fixes apply when keys are compared

There are two kinds of key from now on:

- The **base key** is what the code rules produce from text alone, as `canonicalName` does today. The cached
  `canonicalName` columns on `IngredientLine` and `GroceryItem` keep holding the base key. The parser keeps computing
  it with no database access.
- The **fixed key** is the base key after one more step: look it up in the name fixes and use the "to" name if there
  is one. All key comparisons use the fixed key: grocery consolidation, the store-area ladder (ADR-0052 D2), trip
  assignment, pantry matching and pantry dedup, the add sheet's pantry skip, and the Compare matrix's alignment key.

Applying the fixes at compare time means adding, editing or deleting a fix **rewrites no rows**. That keeps sync
quiet, a fix that arrives from the other device works on the next comparison, and the #499 data pass stays tied to
code changes only. The cost is that every compare site must use the fixed key; D6 makes the compiler find them.

Fixes are loaded once per operation (one generation pass, one add, one edit) into a value type, the way ADR-0052's
area resolver loads its table once per pass.

### D3 — The built-in rules run first; your fixes run last and win

The order is: normalize, strip leading prep words, singularize, built-in alias, **then your fix**. A fix's "from" is
the base key the built-in rules already produce, so a fix can't be shadowed by them. It can also point a built-in
result somewhere else (`green onions → scallions`). That gives ADR-0052's precedence, you over the built-in list,
without a precedence field.

When you type a fix, both sides are run through the base-key rules before saving, so "Flat-leaf Parsley" saves as
`flat leaf parsley`. A fix whose two sides have the same base key isn't saved: the built-in rules already merge them,
and the sheet says so.

### D4 — One hop, kept flat on write

The table never chains. When you save `A → B`:

- If `B` is itself fixed (`B → C`), the row saves as `A → C`.
- Rows that point at `A` (`X → A`) are re-pointed to the new target.
- If the new target is `A` itself (you saved `B → A` earlier and now save `A → B`), the older reverse row is deleted,
  so the last thing you said wins.

Two devices editing at once can still sync a chain into the table, so the lookup follows chains with a cycle guard.
It doesn't rely on writes keeping the table flat.

### D5 — Two ways to add a fix; one sheet to manage them

- **Same As… on a grocery item.** This is where you notice a miss: two lines on the list that should be one. Pick
  the item that's the real name. The app saves the fix (this item's base key → that item's fixed key) and updates the
  current list as if the two items had been added after the fix existed. If generation would merge them (same notes,
  quantities that combine), they merge into one item and the sources move with it. If not, the moved item takes the
  target's title and store area and stays its own line.
- **Groceries › ⋯ › Name Fixes.** A sheet listing every fix as "from → to", with add, edit and swipe-to-delete. This
  is the editable home Jon asked for. It goes in the Groceries **List Actions** menu next to **How Groceries Work**,
  not in Settings, where the store-area review sits under **Developer**: fixes are an everyday tool, used from the
  list.

Adding or deleting a fix from that sheet doesn't change lists that already exist, the same as ADR-0052. Lists you build
after that use it. Only **Same As…** changes the current list, and only the two items involved.

Recipe text never changes. A fix changes keys and grocery titles, never an ingredient line's text or the original
snapshot.

### D6 — The code-only function is renamed, so the compiler finds every site

`CanonicalIngredient.canonicalName(_:)` is renamed `baseName(_:)`. The fixed key comes only from the loaded fixes
(`fixes.canonicalName(_:)`). Every current caller stops compiling and has to pick one: storing a key uses `baseName`,
comparing keys uses the fixes. `comparisonKey` and `displayName` take the fixes too. A missed site is the bug to watch
for here, and the rename turns it into a compile error.

### D7 — Built-in aliases aren't added by hand; your fixes get promoted into them

`CanonicalIngredient`'s `aliases` dictionary stays the built-in layer (design B, as in ADR-0052 D6). Nothing moves
into the table, so no migration writes data. Nobody adds entries to it by hand any more: a new spelling miss becomes
a row, added from the app, and it works for you right away. Your table is private to your iCloud (ADR-0003), so the
row alone never reaches Wendy. [ADR-0070](ADR-0070-what-you-teach-reaches-everyone.md) moves the built-in aliases
into a data file and promotes your rows into it on a schedule, so everyone gets them in the next build. Until
ADR-0070 ships, your rows wait in your table and lose nothing.

The prep-word list is different. A prep word that blocks a merge in only a few ingredients gets fixes. A word that
should be stripped from *every* ingredient is still a code change, because it's a rule, not a name. This joins
`standing-guards.md`.

### D8 — What a fix does to rows already keyed by the "from" name

Store-area rows, trip rows and pantry items keyed by the "from" name stop matching, because lookups now use the
fixed key. The area and trip rows are left in place, not deleted. If you delete the fix, they match again, so
deleting a fix puts things back the way they were. Pantry items are the exception. The existing pantry dedup
(`canonicalPantryItem`) folds two items that now share a key into one the next time either is touched, and keeps the
older item's notes. You've said they're the same ingredient, so that's intended, but deleting the fix doesn't bring
the second pantry item back.

### D9 — The Groceries help page explains fixes

**How Groceries Work** (ADR-0066/0068 D6) gets a short paragraph: two lines merge when they're the same ingredient,
and **Same As…** teaches the app that two names are one, from then on.

## What this costs

- A new synced table and a Production schema deploy.
- About thirty call sites touched by the rename (D6). The change is mechanical, but it touches every grocery path,
  so the tests have to cover each compare site.
- A wrong fix merges two different things on every future list until you delete it. Name Fixes shows every fix,
  so it's easy to spot and undo.
- Pantry items folded by a fix (D8) don't come back if you delete the fix.

## Open questions

- **OQ1 — show the built-in aliases in Name Fixes?** A read-only "Built in" section would show why `scallion` already
  merges with `green onions`. Leave it out until it would have helped.
- **OQ2 — a "From the Compare matrix" entry point.** The matrix is the other place two spellings show up as two rows.
  Same As… there would be cheap once D5 exists. Wait for a real miss.

## Amendment 1 — Notes and store areas don't block a merge; Consolidate List (2026-11-12)

Status: **Accepted** — 2026-11-12 (Jon). Effort: [`efforts/archive/grocery-consolidate-list.md`](../efforts/archive/grocery-consolidate-list.md).
Origin: Jon, 2026-11-12, on the Thanksgiving Advance list, with three **unsalted butter** lines (2, 6 and 6
tablespoons): *"So why aren't these unsalted butters merging?"* All three had the same key, area and unit. They stayed
apart because their recipe notes differed ("or about 5 tablespoons for 3½ cups strained stock", a pie's slicing
note, and none), and the merge rule (`canConsolidate`, since commit 484d90d, 2026-07-03) requires equal notes. **Same As…**
couldn't help: it uses the same rule. Jon then: *"Items in different store areas should merge, and then if I need to
correct the store area, that's fine."* He named the action **Consolidate List**.

### A1 — The merge test is the fixed key and the units, nothing else

Two items merge when they have the same fixed key (D2) and their amounts can be added (`Measure.merged`), or both
have no amount. **Notes and store area no longer count.** This one rule applies everywhere items merge: adding
ingredients (generation), **Same As…** (D5), and Consolidate List (A3). Checked-off items still never merge.

A recipe's prep note ("beaten lightly", "cut into slices") doesn't change what you buy. Merging loses nothing, because
each recipe's share keeps its own `GroceryItemSource` with the original line text, which long-press already shows.

### A2 — What the merged item keeps

- **The surviving item keeps its id, title and store area.** In generation that's the existing item; in Same As it's
  the item you picked as the real name; in Consolidate List it's the earliest item on the list (lowest `sortOrder`,
  then id). Stable ids, per guardrail #4. If the area is wrong, you correct it with **Edit Item › Aisle**, which
  also teaches the area table (ADR-0052).
- **Notes:** a recipe's notes stay on the merged item only when every merged part has the same notes. Otherwise the
  recipe notes are dropped from the row; each source still has its original line. **Notes you typed are never
  dropped.** An item's notes count as typed when they match none of its sources' ingredient lines' grocery notes
  (or it has no recipe sources). Typed notes from every merged part are kept, distinct ones joined with "; ".
- Amounts add up as they do now.

### A3 — Consolidate List re-runs the merge on the list you're looking at

**Groceries › List Actions › Consolidate List** merges the current list's unchecked items under A1 and A2. It
amends D5's "Only Same As… changes the current list": fixes added in **Name Fixes**, fixes synced from your other
device, promoted fixes in a new build (ADR-0070) and this amendment's looser rule reach an existing list when you
tap it. It never rebuilds the list from its recipes, because that would lose checkmarks, items you typed, edits,
removed shares and **Add Back**.

- One list at a time. With **Split into two trips**, Advance and Fresh are separate lists, and items never merge
  across them.
- Items are folded in list order: each item merges into the first earlier survivor it can merge with, or becomes a
  survivor itself. So "1 cup" and "2 sticks" stay two items if their units can't be added.
- No confirmation dialog and no undo, like Same As. Long-press › remove one recipe's share is the way back for a wrong
  merge.
- No schema change. The merge writes only rows that change: survivors' amounts and notes, moved sources, deleted
  merged-away items.

### A4 — Items sort by name within each store area

Unchecked items sort by title (`localizedStandardCompare`), then the order they were added, then id. Duplicates whose
units can't be added then sit next to each other, where you can see them. Nobody reorders grocery items by hand, so
there's no order to protect.

### A5 — The help page says so

How Groceries Work's **Merging** section says notes and areas don't keep items apart and names **Consolidate
List**. The brief carries the exact text, which fits the 1,800-character cap (ADR-0066 D1).

### Rejected

- **A "Redo grocery list" that rebuilds from the recipes.** It would lose checkmarks, typed items, edits, removed
  shares and Add Back. Consolidate List gets the merge without the loss.
- **Keeping store area in the merge test.** The same ingredient sits in different areas only after a correction or a
  fix. Jon would rather merge and fix the area once.
- **Joining every recipe's notes on a merged item.** Three prep notes on one row is unreadable, and the sources keep
  them anyway.
