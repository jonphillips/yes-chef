# ADR-0065 — One glyph per concept, owned by `AppSymbol`

> **One-line:** An app-layer `AppSymbol` type owns the glyph for each Yes Chef concept. Views name the concept,
> never an SF Symbol string, and a SwiftLint rule enforces it. A recipe is `richtext.page` everywhere, `book` means a
> source, and there are two Edit glyphs. There's no separate glyph for a collection of recipes.

Status: **Accepted** — 2026-11-10. Effort: [`efforts/archive/app-symbol-vocabulary.md`](../efforts/archive/app-symbol-vocabulary.md).
Origin: Jon, 2026-11-10: *"Do we have an Icon struct nicely abstracted here so we can make sure we are properly using
our Icons across the app?"* He chose `richtext.page` for recipes and two Edit glyphs the same day.
Builds on: [ADR-0064 D8](ADR-0064-menu-detail-declutter.md) (the custom symbols and the overlay vocabulary) ·
jon-platform `docs/ios/ui-and-platforms.md` (§ Visual craft: prove in one app, then extract · § Controls).

## Context

No type owns icons. The one shared piece is `HandoffSymbol` (`LLMHandoffKit`), which holds the four AI-menu glyphs.
Everywhere else a glyph is a string at its use site: 393 `systemImage:` / `systemName:` literals in `YesChefApp`,
plus `systemImage` properties on about 15 enums, some of them in `YesChefCore`. The same concept has drifted to
different glyphs:

- **Recipe** is `book.closed` (the Recipes tab, "No Recipes", recipe-kind menu and calendar items, grocery sources)
  and `fork.knife` ("Select a Recipe", "Recipe Not Found"). The ADR-0064 symbols build on `richtext.page`.
- **`book`** also means a recipe's **source**, in list rows, the filter bar, presets and the Power Browser.
- **`fork.knife`** also means course, dinner, and a menu's dish count.
- **Edit** is `pencil` nine times and `square.and.pencil` on the Recipe and Menu toolbars.
- **Category** is `folder`, except "New Category", which uses `tag`.
- **Workbench** is `hammer`, except one "Workbench These", which uses `checklist`.

Galavant has no icon type either, so there's nothing to lift yet. The house rule is to prove a pattern in one app
before extracting it.

## Decisions

### D1 — `AppSymbol` owns concept glyphs

`YesChefApp/AppSymbol.swift` defines a small value type:
- Each value is either a system symbol name or a custom symbol's generated `ImageResource`.
- It has an `image` accessor.
- `Label` gets an `init(_:symbol:)` overload, for both `LocalizedStringKey` and `String` titles.

Each concept is one `static let`. Views use `Label("Edit", symbol: .edit)`, not a string. Custom symbols use Xcode's
generated asset symbols, so a misspelled name fails to compile.

The type lives in the app target, and `YesChefCore` stays free of glyph names (D4).

### D2 — The vocabulary

| Concept | `AppSymbol` | Glyph |
|---|---|---|
| A recipe | `.recipe` | `richtext.page` |
| Add recipes here, or create one (the Create Recipe tab) | `.addRecipes` | `custom.richtext.page.badge.plus` |
| Make this into a recipe | `.makeRecipe` | `custom.richtext.page.arrow.in` |
| A menu | `.menu` | `menucard` |
| Bring into this menu | `.bringIntoMenu` | `custom.menucard.arrow.in` |
| A recipe's source | `.source` | `book` |
| Library and Reference shelves | `.libraryShelf` | `books.vertical` |
| Category | `.category` | `folder` |
| New category | `.addCategory` | `folder.badge.plus` |
| Tag or facet | `.tag` | `tag` |
| A dish, course or meal (food served) | `.dish` | `fork.knife` |
| Edit the whole thing, in a sheet | `.edit` | `square.and.pencil` |
| Edit this row or field | `.editRow` | `pencil` |
| Delete | `.delete` | `trash` |
| Calendar | `.calendar` | `calendar` |
| Put on the calendar | `.plan` | `calendar.badge.plus` |
| Groceries | `.groceries` | `cart` |
| Add to groceries | `.addToGroceries` | `cart.badge.plus` |
| Workbench | `.workbench` | `hammer` |
| Chat target | `.chatTarget` | `target` |
| How this screen works (help page, [ADR-0066](ADR-0066-in-app-help-pages.md)) | `.help` | `questionmark.circle` |

The rules behind the table:
- **Plus means add, and an arrow in from the left means "make into" or "bring into"** (ADR-0064 D8). An overlay
  modifies the concept's base glyph.
- **The section tabs use the singular glyph:** Recipes is `.recipe`, Menus is `.menu`, Calendar is `.calendar`.
  Create Recipe is `.addRecipes`, not `square.and.pencil`, which is now Edit.
- **The two Edit glyphs differ in scope.** `.edit` opens a sheet that edits the whole recipe or menu. `.editRow`
  edits one row or field in place or in a small editor.
- **`fork.knife` never means "recipe" again.** Recipe states ("Select a Recipe", "Recipe Not Found") use `.recipe`.
- **`book.closed` is retired.**
- The AI-menu glyphs stay in `HandoffSymbol`. `AppSymbol` doesn't copy them.

### D3 — Only concepts go through `AppSymbol`

Chevrons, checkmarks, warnings, sort arrows, photos and other glyphs that don't name a Yes Chef concept stay as
literals. Converting them would add indirection with nothing to keep consistent.

A new concept joins the table when it first appears on two surfaces, or when it gets a custom symbol.

### D4 — Core enums stop naming glyphs for concepts

`YesChefCore` enums that map a case to a concept glyph lose that mapping, and the app gains an extension that
returns an `AppSymbol`. Today these are `MenuItem`/`MealPlanItem` kind and `GroceryItemSource` origin. Cases that
aren't concepts, such as meal slots, keep their Core strings.

This follows the repo rule that model and UI stay separate. A glyph name is presentation.

### D5 — A lint rule keeps it that way

A SwiftLint custom rule fails on any concept glyph spelled as a string literal outside `AppSymbol.swift`. "Concept
glyph" means each system name in D2, plus any `"custom.` asset name. The rule's regex is the enforcement list, so
adding a concept means updating both the table and the rule.

## Rejected

- **A glyph for a collection of recipes.** Every grouping of recipes already has its own concept:
  - the Recipes section uses the singular glyph, as Menus, Calendar and Groceries do;
  - the Library and Reference shelves are `books.vertical`;
  - categories are `folder`;
  - a Workbench is `hammer`;
  - the Power Browser is `square.grid.2x2`.

  A stacked-page glyph would be a sixth name for "some recipes" with nothing of its own to mark. At toolbar size it
  would also read as `doc.on.doc`, which already means Copy. If a named recipe collection is ever built, its glyph
  can come with it, as an overlay on `richtext.page`.
- **Converting all 393 literals.** See D3.
- **A shared jon-platform icon package.** No second app has the pattern yet. Prove it here first.
- **String constants instead of a type.** Constants can't hold a custom symbol's `ImageResource`, and they don't
  stop a view from passing any string.

## Consequences

- One file says what each concept looks like. Changing a concept's glyph is a one-line edit.
- Adding a concept takes an `AppSymbol` entry and a lint-regex entry.
- The Recipes tab, recipe-kind items, grocery sources and the recipe empty states change glyph on device, from
  `book.closed` / `fork.knife` to `richtext.page`.
- Core enums lose some `systemImage` cases. The app owns that presentation.

## Amendment 1 — A concept can carry a rendering mode; color stays at the call site (2026-11-13)

Origin: Jon, 2026-11-13. He wanted to give a concept a treatment like `.symbolRenderingMode(.hierarchical)` in
`AppSymbol` itself, since that's the one place that names each concept's look. He chose rendering mode only.

- **A1 — Rendering mode belongs to the concept.** An `AppSymbol` can carry a rendering mode, and `image` applies it,
  so `Label(_:symbol:)` and `Image(symbol:)` get it without call-site changes. The default is none, which keeps the
  system's mode. Setting a concept's mode is a one-line edit to its `static let`.
- **A2 — A call site can override it** with `symbol.rendering(_:)`, which returns a copy. `image` stays an `Image`,
  because `Image.symbolRenderingMode(_:)` returns an `Image`.
- **A3 — Color is not part of a concept.** A baked color would override system tinting: a selected sidebar row, a
  disabled button and the toolbar tint would all keep it. It would also make `image` a `View`, which `Label`'s icon
  slot can't take. Color stays a modifier at the call site.
- **A4 — Custom symbols are layered like Apple's.** The page or menu card is the secondary layer, and the badge or
  arrow is primary, as in `cart.badge.plus` ([#509](https://github.com/jonphillips/yes-chef/pull/509)). A new custom
  symbol follows the same split.
- **A5 — Share joins the vocabulary** as `.share` → `square.and.arrow.up`. It now appears on two surfaces: Share List
  on groceries and Share Recipe… on recipe detail (D3's rule). The lint regex gains it.
