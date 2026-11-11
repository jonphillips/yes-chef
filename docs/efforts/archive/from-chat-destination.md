# Effort — From Chat gets its own sidebar destination

Status: Ready
Summary: The From Chat list moves out of Create Recipe into its own sidebar destination, **From Chat**, which carries the inbox badge and shows an empty state when nothing is staged. Create Recipe goes back to the compose box and the draft. Every row opens exactly as it does today. View and navigation only: no schema, no tool, no change to how items open or are claimed.

Origin: Jon, during the S6 device pass (2026-11-10): "Create Recipe is becoming more and more of a lie." Four of the
five inbox kinds don't end in Create Recipe, and a staged menu day sat in a list hidden inside another
destination's screen. One dispatch, one PR. **No schema change.**

Decisions: [ADR-0060 Amendment 4](../../decisions/ADR-0060-chat-access-over-mcp.md#amendment-4--from-chat-is-its-own-sidebar-destination-2026-11-10)
(D1–D3). Related: [ADR-0053](../../decisions/ADR-0053-create-recipe-destination.md) (Create Recipe is compose plus
draft; unchanged) · [ADR-0046](../../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (the sidebar-adaptable shell) ·
[archived `stage-menu-day`](stage-menu-day.md) (the latest kind added to the list).

## Where things are (architect, 2026-11-10, `origin/main` 5153ee0)

- **`AppNavigationModels.swift`:** `AppSection` (about line 50), with `title` and `symbol`.
- **`AppMainLayout.swift`:**
  - `body` (about line 29) lists the tabs in two orders, iPhone and iPad.
  - `createRecipeTab` (about line 111) passes `chatAccessInboxModel` into `CreateRecipeView` and carries
    `.badge(chatAccessInboxModel.inboxCount)` and `.defaultVisibility(.hidden, for: .tabBar)`.
- **`CreateRecipeView.swift`:** `ChatAccessInboxSection(model: chatAccessInboxModel)` is the first thing in the
  `Form` (about line 25), and the view's `chatAccessInboxModel` property exists only for it.
- **`ChatAccessInboxView.swift`:** `ChatAccessInboxSection`. Its outer `if` (about line 9) hides the whole section
  when there's nothing to show. The menu and menu-day review sheets hang off it with `.sheet(item: $model.review)`.
- **`ChatAccessInboxModel`:** owned by `RecipeLibraryView` (about line 39), which also sets `onMenuSelected` to
  select Menus. The model is already app-wide: `prepare()` runs from the library's `.task`, not from Create
  Recipe.
- **Routing that already works and doesn't change:**
  - a staged recipe → `createRecipeCoordinator.stage(text:)`, which selects Create Recipe;
  - handoff and recipe returns → `handoffReviewCoordinator.presentStaged`;
  - a menu or menu day → its review sheet, then `onMenuSelected`.
- **`SettingsViews.swift`** (about line 95): `LabeledContent("Inbox", value: …inboxCount)`.
- **`AppSymbol.swift`:** the glyph vocabulary.

## The slice

- **`AppSection.fromChat`:**
  - title **From Chat**;
  - a new `AppSymbol.fromChat` = `tray.and.arrow.down`.
- **`fromChatTab` in `AppMainLayout`:**
  - It sits directly above `createRecipeTab` in both the iPhone and the iPad orders.
  - It moves `.badge(chatAccessInboxModel.inboxCount)` here from Create Recipe, and keeps
    `.defaultVisibility(.hidden, for: .tabBar)`.
  - Its content is a `NavigationStack` around a new `FromChatView`.
- **`FromChatView`:**
  - A `Form` holding `ChatAccessInboxSection`, so the rows, the review sheets and the footer are reused as they are.
  - When the section would hide itself, show
    `ContentUnavailableView("Nothing from Chat", systemImage: …, description: Text("Recipes, returns and menus
    that ChatGPT stages show up here for you to review."))`.
  - Put the section's visibility condition on the model (e.g. `hasContent`), so the section and the empty state use
    the same rule instead of two copies.
  - Navigation title **From Chat**.
- **`CreateRecipeView`:** remove the section and the `chatAccessInboxModel` property, along with the plumbing that
  only fed it.
- **Settings:** relabel the count **From Chat**.
- **Out of scope:**
  - any change to how a row opens, claims or discards;
  - the review sheets' content;
  - the toast "New recipe sent to Create Recipe." (still true);
  - the compact tab bar's contents beyond keeping From Chat hidden there, like Create Recipe.

## Tests

None new. This is view and navigation wiring, and the model's behavior is unchanged and already covered by
`ChatAccessInboxModelTests`. If you add `hasContent` to the model, add one test for it: empty, and then one menu-day
row whose menu is missing, which is visible but not counted.

## Done when

- **From Chat** is in the sidebar on iPad and iPhone, directly above Create Recipe. It carries the badge and shows
  the empty state when nothing is staged.
- Create Recipe shows only Source and the draft, with no badge.
- Verification per [`verification.md`](../../verification.md): `check-drift.sh` and the generic app build. Run
  `YesChefTests` only if you changed `ChatAccessInboxModel`. Then closeout (ADR-0005 D16).
- **Jon's device gate** (iPad, then iPhone):
  - From Chat shows the badge and the staged items;
  - opening a staged recipe lands in Create Recipe's draft;
  - opening a menu day shows its review, and Apply lands on the menu;
  - with the inbox empty, From Chat shows the empty state and Create Recipe has no list.
