# Effort: Sidebar-adaptable app shell — ADR-0046

**Type:** App-layer view/model rewrite. **No Core, no schema, no sync, no LLM.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Governing decision:** [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (Accepted 2026-08-08) —
read its **Ratification** section first; this effort is its S1, and S2 is stubbed at the bottom.
**Status:** S1 dispatched 2026-08-08. S2 (chat presentation merge) is queued **behind S1's device pass**.

> ⚠️ **Sequencing:** S1 depends on the ADR-0046 ratification (Accepted status + slice plan) being on `main`.
> They land together. Do not dispatch against the old *Proposed* stub.

---

# S1 — the container rewrite (ships alone, its own PR)

## Goal

Replace the size-class fork in `AppMainLayout.body` — the compact `AppCompactTabView` **and** the four
regular-width `NavigationSplitView` branches — with **one** `TabView(selection: $selectedSection)` carrying
`.tabViewStyle(.sidebarAdaptable)`, one `Tab` per `AppSection`, each owning its own internal layout. This
collapses the four-way-duplicated taxonomy (`AppSection` / `AppCompactTab` / `AppMainColumnSection` / the hand
branches) down to the single `AppSection` source of truth, and gives Jon the free sidebar ⇄ top-tab-bar toggle.

`AppMainLayout` is the whole surface here; `AppContainer` ([`RecipeLibraryView.swift`](../../YesChefApp/RecipeLibraryView.swift))
above it — which owns the models, `selectedSection`, and the full-screen covers — does **not** change shape.

## Target structure

One `TabView(selection: $selectedSection).tabViewStyle(.sidebarAdaptable)`, with
`Tab(section.title, systemImage: section.systemImage, value: section)` for each `AppSection`. Per-tab bodies:

| Section(s) | Body |
|---|---|
| `recipes`, `menus`, `workbenches`, `groceries` | two-column `NavigationSplitView(columnVisibility:)` — list (**`.selection` style**) \| detail column. Each tab owns its **own** `@State columnVisibility`. |
| `settings` | two-column `NavigationSplitView` — pane list \| `SettingsDetailPane`, driven by `$selectedSettingsPane` (unchanged). |
| `browser`, `createRecipe` | **single-column** (detail-only): `BrowserWorkspaceView` / `CreateRecipeView`. No split, no `columnVisibility`. |
| `mealCalendar` | its existing `MealCalendarWorkspaceView` with its own Focus split — self-contained; keep its own `@State`. |

**Focus (unchanged meaning).** The tab's `FocusToolbarButton` toggles that tab's `columnVisibility` between
`.doubleColumn` and `.detailOnly`. Sections that have Focus today keep it (recipes, workbenches, menus,
calendar); groceries, settings, browser, createRecipe do **not**. Do not overload Focus to hide the tab
sidebar — that is the system toggle's job; keep them orthogonal.

**TabViewCustomization.** Add an `@AppStorage`-backed `TabViewCustomization` (stable key
`"app-shell-tab-customization"`) applied with `.tabViewCustomization($customization)`. Give the four secondary
sections `.defaultVisibility(.hidden, for: .tabBar)` — `browser`, `workbenches`, `createRecipe`, `settings` —
so the compact tab bar shows the primary set and the rest live in the sidebar / overflow. This replicates
today's "primary 4 + More" **without** a lossy enum.

## Delete

- `AppCompactTabView`, `AppCompactTab`, `AppMainColumnSection`, `AppMoreStack`.
- The compact `NavigationStack` bodies the split now replaces: `RecipesStack`, `MenusStack`,
  `MealCalendarStack`, `GroceriesStack`, and the `.navigation`-style list usage. (The regular-width detail
  helpers — `RecipeDetailColumn`, `WorkbenchDetailColumn`, `MenuDetailColumn`, `GroceryDetailColumn`,
  `SettingsDetailPane` — stay; they become each tab's detail column.)

## Migration points — get these exactly right

1. **Deep-links repoint from `navigationPath` to split selection.** The compact/More `NavigationStack` paths
   are gone, so the two `navigationPath = [id]` writers must instead drive the split's selection:
   - [`MenuModels.swift:65`](../../YesChefApp/MenuModels.swift) (`navigationPath = [menuID]`) → select the menu row.
   - [`WorkbenchModels.swift:43`](../../YesChefApp/WorkbenchModels.swift) (`navigationPath = [workbenchID]`) → select the workbench row.
   Audit every reader of `navigationPath`; if nothing else uses it after this, remove the property.
2. **`openMenuFromCalendar`** must still land on the Menus tab with that menu selected
   (`selectedSection = .menus` + menu selection).
3. **Full-screen covers stay put.** `presentedRecipe` / `presentedCookSession` live in `AppContainer` above the
   layout — leave them; just confirm they present over the `TabView`.
4. **Compact behavior now comes from `NavigationSplitView`'s automatic collapse** (list → push detail), not the
   old `.navigation` stacks. This is the highest-risk UX change; it is why the device pass is mandatory.

## Guardrails

- **View/model layer only.** No `YesChefPackage` edits, no schema, no sync, no LLM. If you're touching Core, stop.
- **Do NOT touch chat presentation** (the Calendar/Workbench detent sheet vs the Recipe inspector) — that is
  **S2**, a separate PR after S1 device-passes. Chat call sites keep their current presentation in S1.
- **`AppSection` stays the single source of truth** — do not introduce a replacement enum. **Settings stays a
  tab** (customizable/hideable), not demoted out of the taxonomy.
- Keep `FocusToolbarButton` and its semantics exactly as extracted (Dispatch 1 Slice A).

## Verification

- `xcodegen generate` — this adds/removes `YesChefApp/` files, so regenerate the pbxproj (a build that omits
  new files is proof it was never run — see the handoff Verification Pattern).
- Elevated generic app build:
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- `scripts/check-drift.sh`.
- **`YesChefTests`** (app-layer models/bindings are touched) — run the target elevated on the first attempt:
  `udid=$(xcrun simctl list devices available | grep -oE '[0-9A-Fa-f-]{36}' | head -1); scripts/xcodebuild-summary.sh -scheme YesChef -destination "platform=iOS Simulator,id=$udid" -skipMacroValidation test`.
- No simulator install; Jon owns the device pass.

## Acceptance criteria

1. One `TabView(.sidebarAdaptable)`; the compact/regular fork, `AppCompactTab`, and `AppMainColumnSection` are gone.
2. Sidebar mode reads sidebar \| list \| detail for content sections; tab-bar mode drops to list \| detail with
   the bar on top; the system sidebar ⇄ tab-bar toggle works.
3. Browser and Create Recipe are single-column; Calendar keeps its Focus split.
4. Per-tab Focus toggles that tab's **own** `columnVisibility`; switching tabs never carries another tab's focus state.
5. Tab reorder / hide / pin persists across launches (`TabViewCustomization`).
6. Menu/workbench deep-links and `openMenuFromCalendar` land correctly; the full-screen cook/recipe covers still present.
7. Green: `xcodegen generate` + generic build + `check-drift.sh` + `YesChefTests`.

## Device pass (Jon)

Both physical devices × both orientations × sidebar **and** tab-bar modes; `TabViewCustomization` persistence
across launches; the ADR-0039 third-glyph check — the system sidebar toggle alongside the playbook toggle and
Browse Recipes, against Dispatch 1 Slice C's resolution, not separately.

---

# S2 — chat presentation merge (queued, NOT in S1)

After S1 device-passes: reconcile the Calendar/Workbench **detent-sheet** chat vs the Recipe **inspector** chat
now that all eight call sites live in per-tab layouts. The chat *contract* is already unified (PR #244,
[`chat-ask-uniformity.md`](chat-ask-uniformity.md)); only presentation remains. Own PR. See ADR-0046 Ratification.
