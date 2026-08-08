# Effort: Sidebar-adaptable app shell — ADR-0046

**Type:** App-layer view/model rewrite. **No Core, no schema, no sync, no LLM.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Governing decision:** [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (Accepted 2026-08-08) —
read its **Ratification** section first; this effort is its S1, and S2 is stubbed at the bottom.
**Status:** S1 **shipped** 2026-08-08 (PR [#297](https://github.com/jonphillips/yes-chef/pull/297)), under Jon's
dogfood; device pass owed. S2 (chat presentation merge) is briefed below and dispatches **after** S1's pass —
its one open product decision (inspector vs. detent split) is Jon's to lock first.

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

## Shipped 2026-08-08 (PR #297) — review-caught fixes folded in

Architect review before the device pass caught three defects of one class — **single-column tabs had no
navigation container** — and one dead-code sweep. All fixed in the S1 PR:

- **Calendar** was wrapped in `NavigationSplitView { EmptyView() } detail:`; the empty root column rendered as a
  blank leading pane on iPad and, because a collapsed split shows its *root* first, a **fully blank screen on
  iPhone**. Rewritten to a single-column `NavigationStack { MealCalendarWorkspaceView }` — the workspace already
  adapts to width on its own (calendar + agenda rail + chat when wide, stacked when compact).
- **Create Recipe** and **Browser** were bare tab children; their `.navigationTitle`/`.toolbar` had no host, so
  Create Recipe lost its title **and its Clear/Save buttons** (no way to save). Both now wrapped in `NavigationStack`.
- **Calendar loses Focus.** The single-column calendar has no list to focus, so its `FocusToolbarButton` is gone.
  This deviates from the "calendar keeps Focus" line above — Jon's product call, live-with-it for now; a real
  calendar focus (e.g. collapse the agenda rail) would be its own feature, not this.
- **Dead code removed:** orphaned `MealCalendarPlannerView` and the now-unused `AppSection.label`. Left in place:
  `ChatSurface.calendarDayCompactSheet` (production-dead after the planner deletion but still test-covered — fold
  into S2's calendar pass rather than dragging `ChatSurface` + its test into S1).

Verified: elevated generic build green, `YesChefTests` 40/40 green. (`check-drift` shows one **pre-existing**
red Core test — `DatabaseBackupTests…NMinusOneBackup`, red on `main`, unrelated migration-fixture drift, spun off
as its own task.)

---

# S2 — chat presentation merge (its own PR, after S1's device pass)

## Goal

All eight chat call sites now live in per-tab `NavigationStack`/`NavigationSplitView` shells (S1). Reconcile the
**three** wide-width chat presentations that survived into those shells down to **one**, so the cook meets the
same Ask surface everywhere on a given device. The chat *contract* is already unified (PR #244,
[`chat-ask-uniformity.md`](chat-ask-uniformity.md)) and the panel internals are one view — **only the container
differs**. Compact (iPhone) presentation is **out of scope and stays a modal `.sheet`** (cross-device divergence
is intended and closed — see Guardrails).

## The one product decision — Jon locks this before dispatch

Codex cannot choose this; it is the whole slice. Today's wide-width presentations:

| Surface | Wide presentation | Where |
|---|---|---|
| Recipe detail | SwiftUI **`.inspector`** (trailing panel, toggles closed) | [`RecipeDetailView.swift:260`](../../YesChefApp/RecipeDetailView.swift) (`RecipeAskPresentationModifier`) |
| Calendar workspace | **`ChatWorkspaceSplit`** (custom drag-divider, named detents, persisted width) | [`MealCalendarViews.swift:18`](../../YesChefApp/MealCalendarViews.swift) |
| Workbench detail + Compare | **`ChatWorkspaceSplit`** | [`WorkbenchViews.swift:163`](../../YesChefApp/WorkbenchViews.swift), [`:319`](../../YesChefApp/WorkbenchViews.swift) |
| Menu playbook | **embedded tool** (`menuTool`, alongside the playbook column) | [`MenuViews.swift:271`](../../YesChefApp/MenuViews.swift) |

**Options:**
- **A — inspector everywhere (architect's lean).** Retire `ChatWorkspaceSplit`; Calendar/Workbench adopt
  `.inspector`. It is the system idiom, it toggles/dismisses for free, and it composes with the per-tab
  `NavigationSplitView` detail columns S1 just established. **Risk to prototype first:** the Calendar wide
  workspace already carries an internal agenda rail (`MealCalendarWideWorkspace`), so calendar | agenda |
  inspector can get tight — confirm it breathes before committing.
- **B — detent split everywhere.** Recipe adopts `ChatWorkspaceSplit`; keeps drag-resize + detents. Cost: a
  custom split (more upkeep, no free compact adaptation) competing with Recipe's own playbook-column layout.
- **C — don't merge; close S2.** The ADR explicitly left this "content to live with for now." A legitimate
  outcome if S1's shell makes the divergence feel fine in the dogfood — record it and stop.

**Menu's embedded tool is out of scope** unless Jon folds it in — it is a playbook-column affordance, a different
concept from the inspector/split question, and #244 already settled its behavior.

## Adjacent decision to settle in the same pass (ADR-0045 leftovers)

The meal-calendar **day-header Chat** and the **Workbench Chat** pass `.none` starters today — an explicit answer,
not an omission. Since S2 rearranges exactly these surfaces, decide now whether they want their own cold-start
starters ("Plan this week", "What should I prep tonight?") or stay starterless. Do not silently change it.

## Guardrails

- **View-layer only.** No `YesChefPackage`, no schema, no sync, no LLM, **no `ChatSurface` contract change** and
  **no apply-action catalog merge** (still per-host, #243). If you're editing Core, stop.
- **Do NOT reopen cross-device divergence.** Modal sheets keep the iOS nav bar (`Done` top-left); embedded/column
  presentations keep the in-panel header row. Uniformity is **cross-surface, not cross-device** — intended and
  closed ([`chat-ask-uniformity.md`](chat-ask-uniformity.md) decision, 2026-07-27). Compact stays `.sheet`.
- **Fold in the S1 leftover:** if the chosen path touches the calendar chat, retire the now-dead
  `ChatSurface.calendarDayCompactSheet` (and its test) here rather than leaving it orphaned.

## Verification

- `xcodegen generate` if any `YesChefApp/` files are added/removed.
- Elevated generic build + `scripts/check-drift.sh`.
- **`YesChefTests`** — the chat presentation is driven by model/binding state; run the target elevated on the
  first attempt (see the handoff Verification Pattern).
- No simulator install; Jon owns the device pass.

## Acceptance criteria

1. Every **wide-width** chat surface uses the single chosen presentation (or, under Option C, the divergence is
   recorded as accepted and nothing changes).
2. Compact presentation is untouched — still a modal `.sheet` with the nav-bar header.
3. Toggle/dismiss behavior reads the same across surfaces on a given device.
4. No `ChatSurface` contract, apply-action catalog, schema, or sync change; Menu untouched (unless Jon folded it in).
5. Green: generic build + `check-drift.sh` + `YesChefTests`.

## Device pass (Jon)

Both physical devices × both orientations × sidebar and tab-bar modes. Open Ask on Recipe, Calendar (workspace
+ day header), Workbench (detail + Compare): confirm one consistent presentation wide, the sheet unchanged on
iPhone, and that toggling Ask closed and switching tabs never strands a panel.
