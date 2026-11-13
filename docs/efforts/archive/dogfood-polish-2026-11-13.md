# Effort — Dogfood polish, November 13

Status: Ready
Summary: Seven fixes: Menus Dated / Undated; menu title in the content; Same As… drops twins; grocery Add Item in the list; amounts as fractions; AppSymbol rendering modes; Share Recipe… as text. No schema change.

Origin: Jon, 2026-11-12 and 2026-11-13, dogfooding the Thanksgiving Week menu and its Advance / Fresh lists on the iPad
and iPhone. One dispatch, one PR. Items 1–5 are layout and display fixes inside existing decisions. Item 6 is
[ADR-0065 Amendment 1](../../decisions/ADR-0065-one-glyph-per-concept.md#amendment-1--a-concept-can-carry-a-rendering-mode-color-stays-at-the-call-site-2026-11-13).
Item 7 is a readable text copy, not ADR-0003's `.yeschef` transfer.

## Where things are (architect, 2026-11-13, `origin/main` 01c3b1c)

**Core (`YesChefPackage/Sources/YesChefCore/`)**
- `MenuCore.swift`: `MenuRowData` (line 4) and `MenuListRequest` (line 122). The request already loads every
  `MenuPlacement` and sorts by title.
- `Models.swift`: `MenuPlacement` (line 407), with `startDate`. A menu is **dated** when it has at least one placement.
- `GroceryRepository+Editing.swift`: `formatGroceryQuantity` (line 4) formats with `%g`, which makes `1.08333`. It
  writes `GroceryItem.quantityText` at its five call sites (merge, generation, recalculation, drafts).
- `RecipeCore.swift`: `IngredientScaler.formattedQuantity` (line 826) and `commonFractions` (line 897, which has every
  eighth plus thirds, fifths and sixths).
- `GroceryRepository+Editing.swift`: `sameAs(itemID:targetItemID:in:now:)` (line 175) shows how the item's and the
  target's fixed names resolve: `fixes.canonicalName(item.canonicalName ?? item.title)`.

**App (`YesChefApp/`)**
- `MenuViews.swift`: `MenuListView` (line 6). `MenuDetailView` sets `.navigationTitle(detail.menu.title)` (about line
  144). `MenuDetailHeader` (line 619) shows only the date range, day and dish counts, and notes.
- `MenuModels.swift`: `MenuLibraryModel` (line 13) with `@Fetch(MenuListRequest())`. Adding a menu selects it (about
  line 139).
- `MenuPlaybookColumnView.swift`: `MenuDetailReader`. On a wide layout it's an `HStack` of two `ScrollView`s
  (dishes, then Prep Plan and Learnings), so the large navigation title belongs to neither and never collapses.
- `RecipeDetailView.swift` (line 66): the precedent for item 3. It sets `.navigationTitle("")` and
  `.navigationBarTitleDisplayMode(.inline)`, and the recipe title is drawn in the content.
- `GroceryViews.swift`: `GroceryDetailView` (line 44) puts `GroceryRapidAddField` (line 730) in
  `.safeAreaInset(edge: .top)` (line 103). On iOS 27 the large title scrolls with the content, so the inset sits on top
  of it (Jon's screenshots: "Thanksgiving Week 2026 — Fresh" is only visible after pulling down).
- `IngredientNameFixViews.swift`: `SameAsPickerSheet` (line 114). It already drops the item's own row by id, and it
  shows only each row's title and area. `AppDestinationPresentation.swift` (about line 138) passes it
  `groceryModel.selectedItemRows`.
- `AppSymbol.swift`: the concept vocabulary (ADR-0065). `.swiftlint.yml` `concept_glyph_literal` lists the concept
  glyph names five times; a new concept goes in each.
- `RecipeDetailView.swift` (about line 207): the `.secondaryAction` overflow (Edit, Workbench, View Original, Archive,
  Delete…). `RecipeDetailModel` (`RecipeModels.swift`, line 695) observes `detail: RecipeDetailData?`.
- `GroceryListPlainTextRenderer.swift` (Core) and `GroceryViews.swift` (line 210, **Share List**) are the precedent
  for item 7.
- `WorkbenchViews.swift` (line 44) has a segmented control in a top `safeAreaInset`. **Don't copy it**: it's the same
  shape as the grocery bug.

## 1. Menus list: Dated / Undated

**Build.**
- **Core.** `MenuRowData` gains `latestPlacementDate: Date?`, the latest `startDate` among the menu's placements
  (nil when there are none). `MenuListRequest` fills it from the placements it already loads. It's a read-model field,
  not a column.
- **Core.** A `MenuListSegment` enum (`dated`, `undated`) with a pure function that filters and sorts rows:
  - **Dated:** rows with a `latestPlacementDate`, newest first; ties by title (`localizedStandardCompare`), then id.
  - **Undated:** rows without one, by title (`localizedStandardCompare`), then id.
- **App.** `MenuLibraryModel` holds `menuListSegment`, default `.dated`, not persisted. `MenuListView` shows the
  model's filtered rows.
- **App.** A segmented `Picker` ("Dated" / "Undated") is the first thing in the list, under the large title, and
  scrolls with it. It's not a top `safeAreaInset` (see item 4). It isn't selectable as a row.
- **App.** Adding a menu switches the segment to **Undated**, since a new menu has no placement, so the new
  menu's selected row is visible.
- **App.** An empty segment shows a `ContentUnavailableView`. Dated: "No Dated Menus", "Put a menu on the calendar to
  date it." Undated: "No Undated Menus".
- **Keep:** the selection. Switching segments, or placing / unplacing the selected menu, doesn't clear
  `selectedMenuID`. The detail column stays on that menu even when its row is in the other segment.

## 2. Menu detail: the title stops floating over the dishes

**Build.** Follow the recipe detail precedent. `MenuDetailView` sets `.navigationTitle("")` and
`.navigationBarTitleDisplayMode(.inline)`. `MenuDetailHeader` draws `detail.menu.title` first, in `.largeTitle` bold,
above the metadata line. On the wide layout the title then scrolls with the dishes column. On iPhone it scrolls with
the single column.

**Keep:** the toolbar, the Focus button, and the tool overlay as they are. If an empty title breaks something the
recipe detail doesn't hit (the iPhone back button, the app switcher), say so in the PR body rather than invent a
different fix.

## 3. Same As… shows what you're matching

**Build.**
- **Core.** A pure function returns the Same As candidates for an item from the list's rows and the current
  `IngredientNameFixes`. It leaves out the item itself and every row whose fixed name equals the item's fixed name
  (the same resolution `sameAs` uses). Picking one of those twins can't teach a fix; it only renames. The other rows keep
  their display order.
- **App.** `SameAsPickerSheet` takes the candidates from that function rather than filtering by id itself.
- **App.** The sheet opens with a non-tappable section headed **Matching**. It shows the item's title and its amount
  and area line, the same text `GroceryItemRowView` shows under the title (`1 ⅛ cup · Produce`). The candidates follow
  in a section headed **Same As**, and each one shows that amount and area line too, so two rows with the same title
  can be told apart.
- **App.** No candidates gives a `ContentUnavailableView`: "Nothing Else to Match".

## 4. Groceries: Add Item stops covering the list name

**Build.** Remove the top `safeAreaInset` from `GroceryDetailView`. `GroceryRapidAddField` becomes its own `Section`
in the `List`. It sits right after the list `Picker` section (when `showsListPicker`) and before the items, so the large
title sits above it and it scrolls with the list. Keep `.attentionCard()` on it. Give the row a clear background so
the card doesn't draw on top of a cell background. Fix the same view on iPad and iPhone.

**Keep:**
- Rapid entry: after an add, the field keeps focus and the text clears.
- The fraction pill row while focused, and the keyboard's **Done**.
- `.scrollDismissesKeyboard(.immediately)`.
- The toolbar's **Add Item** button, which opens the full editor.

If the field loses focus when its own section re-renders after an insert, fix that in this PR. Don't move the field
somewhere else.

## 5. Grocery amounts read as kitchen fractions

Found in the same screenshots: summed amounts show `1.08333 cup` and `0.4375 cup`.

**Build.** `formatGroceryQuantity` changes. A whole number stays whole. A value within 0.01 of a whole plus a common
fraction uses `IngredientScaler`'s rendering (so ⅓ and ⅔ survive). Anything else rounds **up** to the next eighth and
renders the same way. Shopping for a little more beats a little less. `1.08333` → `1 ⅛`, `0.4375` → `½`, `1.5` →
`1 ½`, `0.333…` → `⅓`. Reuse `IngredientScaler.formattedQuantity` for the rendering; don't copy the fraction table.

**Keep:** `GroceryItem.quantity`, the number merges add up, which stays exact. Only `quantityText` changes, and only
on rows written from now on. Existing rows keep their stored text until they're merged into or rebuilt. There's no
data pass.

## 6. AppSymbol carries a rendering mode (ADR-0065 Amendment 1)

**Build.**
- `AppSymbol` gains an optional rendering mode, given in its initializers (`AppSymbol("cart", rendering:
  .hierarchical)`) and defaulting to none. Use a small `Sendable, Hashable` enum of the modes that need no colors
  (monochrome, hierarchical, multicolor) mapped to `SymbolRenderingMode`, rather than storing `SymbolRenderingMode`.
- `image` applies it with `Image.symbolRenderingMode(_:)`, so it stays an `Image`, and `Label(_:symbol:)` picks it up.
- `func rendering(_:) -> AppSymbol` returns a copy with the mode replaced, for call sites:
  `Image(symbol: .menu.rendering(.hierarchical)).foregroundStyle(.blue)`.
- No concept gets a mode in this PR. Jon sets them, one line each. The custom symbols are layered (#509), so
  `.hierarchical` draws them two-tone.
- Add `.share` → `square.and.arrow.up` (A5). Add it to the lint regex, and convert **Share List** in
  `GroceryViews.swift` to `Label("Share List", symbol: .share)`.

**Keep:** `systemName` and `systemNameForIntents` as they are; a rendering mode doesn't reach App Intents.

## 7. Share Recipe… as text

**Build.**
- **Core.** `RecipePlainTextRenderer.render(_ detail: RecipeDetailData) -> String`, beside
  `GroceryListPlainTextRenderer`. It renders the **base recipe at its own yield**, ignoring the active variation and
  the on-screen scale, in this order:
  - the title;
  - the source name and URL, when there are any;
  - the yield and times, when present;
  - **Ingredients**, by section, with a section's name as a heading when it has one, and each line's display text at
    scale 1;
  - **Directions**, by section, steps numbered within each section;
  - **Notes**, the recipe's notes, when there are any.

  It leaves out learnings, the playbook, variations, Serve With, rating, tags and categories, which are your own
  notes about the recipe, not the recipe. Blank parts produce no heading.
- **App.** **Share Recipe…** in the recipe detail `.secondaryAction` overflow, after **Workbench**, as a
  `ShareLink(item: text, subject: Text(title))` with `Label("Share Recipe…", symbol: .share)`. The text comes from
  `RecipeDetailModel`, built from `detail`. Hide the item while `detail` is nil.

**Keep:** no file, no photo and no new document type. ADR-0003's `.yeschef` transfer is a separate effort.

## Tests

`YesChefCoreTests`:
- **Menu segments:** three dated menus (one with two placements, ordered by its later one) come out newest first. Two
  undated menus come out by title. A menu is in exactly one segment. `MenuListRequest` fills `latestPlacementDate`.
- **Same As candidates:** the item itself and a second item with the same fixed name (for example, two `unsalted
  butter` rows whose units can't add) are left out. A name fix makes `fresh mint leaves` a twin of `mint`, so it's
  left out too. Other rows keep their order.
- **Recipe text:** a two-section recipe renders section headings for ingredients and directions; an untitled
  single section renders none; an active variation and a scale on the model don't change the text; learnings and
  tags don't appear; a recipe with no source or notes has no Source or Notes lines.
- **Formatting:** `1.08333` → `1 ⅛`, `0.4375` → `½`, `1/3` → `⅓`, `2/3` → `⅔`, `1.5` → `1 ½`, `3` → `3`. A
  consolidation of ¼ cup + ½ cup + ⅓ cup stores `quantityText` `1 ⅛` and `quantity` exactly 13/12.

`YesChefTests` (app target), because `MenuLibraryModel` changes:
- The default segment is `.dated`. Adding a menu switches to `.undated` and selects the new menu.
- `AppSymbol`: a concept's rendering mode survives into `image`; `rendering(_:)` overrides it without changing the
  static value.

## Verify

`scripts/check-drift.sh`, the generic iOS build, and `YesChefTests` on a simulator, because `MenuLibraryModel` changes
(AGENTS.md #9). No simulator installs or screenshots; Jon checks the layout on device.

## Done when

- The tests above pass, and check-drift, the generic build and `YesChefTests` are green.
- Closeout per ADR-0005 D16 (DONE-LOG, archive this brief, advance NEXT_UP per D12).
- Gate line appended to `device-passes.md`: on the iPad and the iPhone:
  - Menus opens on **Dated**, newest first. **Undated** is alphabetical. A new menu lands in Undated, selected.
  - Thanksgiving Week's title sits above Day 1 and scrolls away with the dishes. Nothing draws under the toolbar.
  - On the Fresh list, the list name shows without pulling down. Rapid-add three items in a row.
  - Same As… on minced fresh mint shows it under Matching and not in the list.
  - Rebuild the Fresh list and confirm parsley reads `1 ⅛ cup` and mint `½ cup`.
  - On the souvlaki, ⋯ › Share Recipe… to Messages and Notes; the text reads cleanly with sections and steps.
