# Effort — Groceries split into two trips

Status: Ready
Summary: The Add Ingredients sheet gets **Split into two trips** for menus and calendar days. Each ingredient goes to an **Advance** or a **Fresh** list by a fixed rule: produce that keeps, then store area, then Fresh. Switches you make are remembered in a new synced table, `groceryTripAssignments`, which needs a Production deploy. The sheet now skips only pantry items set to **Always have it**. The Groceries screen gets a **How Groceries Work** help page.

Origin: Jon, 2026-11-11, planning his two Thanksgiving shopping trips. One dispatch, one PR. **Persistent model change,
authorized by ADR-0068 D3.** **Deadline:** Jon's advance trip is around **Thu Nov 19**, so the device gate has to
pass before then.

Decisions: [ADR-0068](../../decisions/ADR-0068-two-trip-grocery-split.md) (D1–D6). Read it first. Patterns to copy:
[ADR-0052](../../decisions/ADR-0052-grocery-learned-area-table.md)'s learned table (`GroceryAreaAssignment`), and
[ADR-0066](../../decisions/ADR-0066-in-app-help-pages.md) with the archived
[`menu-help-and-add-menu`](menu-help-and-add-menu.md) brief for the help page.

## Where things are (architect, 2026-11-11, `origin/main` 69f73fe)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `GroceryAreaAssignment.swift`: the table to copy, minus `source` and `reviewedAt`.
- `GroceryStoreArea.swift`: `GroceryStoreAreaCache` and its private `GroceryAreaResolver` (around line 507), which
  resolves user fix, then built-in area list, then model area, all without calling a model. `seed(for:)` and
  `headNounSeed` show how canonical-name matching works.
- `GroceryPantryAssumptions.swift`: `isPantryStaple(_:pantryStaples:)` and the "salt and pepper" prefix.
- `GroceryIngredientChoice.swift`: the sheet's choices (`recipe`, `section`, `line`).
- `GroceryRepository+Generation.swift`: `addMenu` and `addMealPlanRows`, both of which take
  `includedIngredientLineIDs` and throw `noShoppableIngredients` on an empty subset.
- `GroceryCore.swift`: `GroceryRepository.addList(title:…)`.
- `DeterministicID.swift`: `pantryStaple(canonicalName:)`, the pattern for the new id.
- `AppHelp.swift`: `AppHelpPage` and `.menus`.
- `Schema.swift`: append the migration after the last one. `CloudSync.swift`: add the type to **both** table lists
  (around lines 76 and 362, next to `GroceryAreaAssignment`) and bump `declaredSchemaVersion` by one on top of
  whatever main has when you branch.

**App (`YesChefApp/`)**
- `GroceryViews.swift`: `GroceryIngredientSelectionView` (around line 867) is the sheet. It sets its initial
  selection from `pantryStaples`, and its sections are **Ingredients** and **Skipped Pantry Staples**.
  `GroceryListActionsMenu` (line 200) is the list's `⋯` **List Actions** menu.
- `GroceryIngredientChoiceViews.swift`: `GroceryIngredientChoiceSection` draws the rows.
- `GroceryModels.swift`: `pantryStapleNames` (line 85), `confirmIngredientSelectionButtonTapped` (line 432), and
  `GroceryIngredientSelectionContext` (around line 960).
- `AppHelpSheet.swift`: reuse as-is. `MenuViews.swift:233` shows how it's presented.

## The slice

### Core: trips (ADR-0068 D2, D3)
- `public enum GroceryTrip: String, CaseIterable, Codable, QueryBindable, QueryDecodable, Sendable { case advance, fresh }`,
  with `title` returning "Advance" or "Fresh".
- `@Table("groceryTripAssignments") GroceryTripAssignment`: `id`, `canonicalName`, `trip: GroceryTrip`,
  `dateModified`. Migration "Create grocery trip assignments" adds a `STRICT` table shaped like
  `groceryAreaAssignments` (id `TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())`, then
  `canonicalName TEXT NOT NULL`, `trip TEXT NOT NULL`, `dateModified TEXT NOT NULL`). Register it for sync.
- `DeterministicID.groceryTrip(canonicalName:)`, with the name `"groceryTrip:\(canonicalName)"`.
- `GroceryTripRule.defaultTrip(canonicalName:area:) -> GroceryTrip`, a pure function implementing D2 steps 2–4: the
  keeper set from the ADR, matched on the canonical name or its last word, with `green onion` and `spring onion`
  excluded; then the area mapping; then `.fresh`.
- `GroceryTripRepository`:
  - `trips(forCanonicalNames:in:) -> [String: GroceryTrip]`: your saved switch, else `defaultTrip` using the
    resolver's area. Make the resolver usable here, either by making `GroceryAreaResolver` internal or by adding a
    batch `resolvedAreas(for:in:)` to `GroceryStoreAreaCache`. Use whichever reads cleaner, but don't change what it
    resolves.
  - `recordSwitches(_ trips: [String: GroceryTrip], in:now:)`: an upsert by deterministic id.
- `GroceryRepository.tripListID(title:in:now:uuid:)`: returns the list whose title matches exactly, otherwise
  creates it through `addList`.

### Core: the pantry skip follows the setting (ADR-0068 D4)
- Add one Core helper, for example `GroceryPantryAssumptions.skippedStapleTitles(from: [PantryItem])`, that returns
  the titles of items whose `policy == .unlimited`. The App's `pantryStapleNames` uses it. The "salt and pepper"
  prefix stays.

### Core: the help page (ADR-0068 D6)
- `AppHelpPage.groceries`, using the copy below. Leave `RecipeChatContext.helpPage` alone, because there's no grocery
  chat.

### The Groceries page copy

The architect wrote this. **Check each sentence against the app as built, after your changes.** Fix a label that
doesn't match what's on screen, and list each fix in the PR body. Don't add bullets.

> **How Groceries Work**
>
> **Adding ingredients**
> - **Add Ingredients** adds a calendar day or a menu to this list. You pick which lines to add first.
> - Lines matching a pantry item set to **Always have it** start unchecked under **Skipped Pantry Staples**. Check
>   one to buy it anyway.
> - Turn on **Split into two trips** to send each line to an **Advance** list or a **Fresh** list. Tap a line's
>   **Advance** or **Fresh** tag to switch it. The app remembers your switch next time.
>
> **Merging**
> - The same ingredient from different recipes becomes one item with the amounts added up, when the units can be
>   added (cups with cups, grams with grams). Otherwise it stays a separate item.
> - Long-press an item to see where it came from, or remove one recipe's share.
>
> **Pantry**
> - Pantry items say what you usually have. Set each one in **Pantry**: **Always have it** hides it from the list,
>   **Remind me** hides small amounts and shows big ones under **You may need more**, **Always confirm** always shows
>   it.
> - Hidden items sit under **Assumed in pantry**. **Add Back** puts one on the list for now.
> - Swipe an item right and tap **Add to Pantry** to stop buying it.
>
> **Store areas**
> - Items are grouped by store area. Change one with **Edit Item › Aisle**. The app remembers your change for that
>   ingredient from then on.

### App
- **Toggle:** when `context.source` is `.menu` or `.mealPlanRows`, the sheet's `List` starts with a section holding a
  `Toggle("Split into two trips")`, off by default. When it's on, the sheet loads trips once through
  `GroceryTripRepository.trips(forCanonicalNames:)` for the choices' canonical names and keeps them in sheet state,
  along with the set of canonical names you switched.
- **Sections:** when the toggle is on, **Ingredients** is replaced by **Advance** and **Fresh**, built from the
  regular choices. **Skipped Pantry Staples** stays, and a staple you check goes to its trip's list. Each row gets a
  trailing borderless tag with its trip's title. Tapping it flips the trip for **every choice with that canonical
  name** and adds the name to the switched set. Checkmarks don't change when a row moves. A line with no canonical
  name goes to Fresh and has no tag.
- **Add:** with the toggle on, `confirmIngredientSelectionButtonTapped` does everything in **one write**:
  1. Split the selected line ids by trip.
  2. For each side that has lines, call `tripListID(title: "\(context.title) — \(trip.title)")`, then
     `addMenu` or `addMealPlanRows` with that side's ids.
  3. `recordSwitches` for the switched names, using their final trips.

  Then select the Advance list, or the Fresh list if Advance is empty, and post one toast: "Added N to *Advance list*
  and M to *Fresh list*" (one clause if a side was empty). Then `scheduleCategorization()`. With the toggle off,
  nothing changes.
- **Pantry skip:** `pantryStapleNames` uses the Core helper.
- **Help:** append a `Divider` and **How Groceries Work** (`AppSymbol.help`) as the last item of
  `GroceryListActionsMenu`. It presents `AppHelpSheet(page: .groceries)` through the grocery model's existing sheet
  pattern.

## Tests

**Core**
- `defaultTrip`: onion, yellow onion, garlic, butternut squash and cranberry go to Advance. Green onion, cilantro,
  turkey and baguette go to Fresh. Canned tomatoes, butter, flour and frozen peas go to Advance by area. An unknown
  name with no area goes to Fresh.
- `trips(forCanonicalNames:)`: a saved switch beats the keeper list and the area. A user area fix (an ADR-0052 row)
  changes the area-based default.
- `recordSwitches` twice for the same name leaves one row with the latest trip, and its id is
  `DeterministicID.groceryTrip`.
- `tripListID`: reuses a list with exactly that title and creates one otherwise.
- With a menu where onion appears in two recipes and cilantro in one, splitting puts one onion item (amounts merged)
  on Advance and cilantro on Fresh. A side with nothing selected creates no list.
- `skippedStapleTitles`: includes **Always have it** items only.
- `AppHelpPage.groceries.plainText.count <= 1_800`, and it contains "How Groceries Work" (ADR-0066 D5's tested label).
- The migration: the table exists after migrating, and the sync table list includes it. Follow the existing schema
  tests.

**App (`YesChefTests`)**
- A split add through `GroceryLibraryModel` writes both lists, records only the switched names, and selects the
  Advance list.
- With the toggle off, the add is unchanged.
- `pantryStapleNames` leaves out **Remind me** items.

This touches `YesChefApp/` model code, so the target runs (guardrail #9).

## Done when

- **Split into two trips** fills an Advance list and a Fresh list from a menu or a calendar day. A switch you make is
  the default next time, on both devices.
- Only **Always have it** pantry items start skipped.
- **⋯ › How Groceries Work** shows the page, and the page matches the app as built. Any label fixes are listed in the
  PR body (ADR-0066 D5).
- Tests above. Verification per [`verification.md`](../../verification.md), including the generic app build and
  `YesChefTests`. Then closeout (ADR-0005 D16).
- **Gate, before any TestFlight upload:** the `groceryTripAssignments` record type and its fields are in Production.
  The architect imports them to Development with `cktool`, and Jon deploys in the Console.
- **Jon's device gate (before Nov 19):** on the iPad, go to **Groceries › Add Ingredients › Thanksgiving** and turn on
  **Split into two trips**. Check the Advance and Fresh sections, and switch one item (say, celery). Add. Two lists
  appear, with onions and canned goods on Advance and herbs and the turkey on Fresh. Open the sheet again and confirm
  the switched item stays where you put it. Set butter to **Remind me** in **Pantry** and confirm it now starts
  checked. Open **⋯ › How Groceries Work** and read it.
