# ADR-0046 — The app shell becomes a **sidebar-adaptable `TabView`**: one taxonomy, one container, a user-switchable first column

Status: **Accepted** — opened 2026-07-25 from Jon's ferry dogfood pass ("like on Apple Music, let's have the
buttons so you can move the tab bar to the top and then back to the side"); **ratified 2026-08-08** after
[`efforts/dogfood-ferry-2026-07-25.md`](../efforts/dogfood-ferry-2026-07-25.md) Dispatch 1 landed (Slice A's
shared expand control shipped 2026-07-26), scoped against the real post-extraction code. The container rewrite,
the answered open questions, and the two-slice plan are in **Ratification** below. Governed by
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the sidebar-icon collision this must not reproduce).

## Context

**Nothing ever decided the current shell.** A `grep -ri` over `docs/` finds no ADR and no effort covering
app-level navigation. ADR-0039 touches sidebar *icons* — it records that the recipe playbook toggle
(`sidebar.trailing`) sits one glyph from the menu's Browse Recipes button (`sidebar.right`), "two
trailing-sidebar icons, one toggling a structural column, the other a panel" — but the three-column
`NavigationSplitView` container itself was never a considered choice. It is the default iPad idiom, arrived at
by inertia. **So this ADR is not overturning a decision; it is making one for the first time.**

**The taxonomy is encoded four times, in three incompatible partitions** (counts as of 2026-08-08 — ADR-0053
added `.createRecipe` after this ADR opened, which grew both the enums and the `body` fork).

| Encoding | Cases | Shape |
|---|---|---|
| `AppSection` ([`AppNavigationModels.swift:47`](../../YesChefApp/AppNavigationModels.swift)) | 8 | the actual source of truth |
| `AppCompactTab` ([`AppMainLayout.swift:269`](../../YesChefApp/AppMainLayout.swift)) | 5 | **lossy** — createRecipe/browser/workbenches/settings collapse to `.more`, whose `.section` returns `nil` |
| `AppMainColumnSection` ([`AppMainLayout.swift:148`](../../YesChefApp/AppMainLayout.swift)) | 5 | a **different** subset — `case .createRecipe, .browser, .mealCalendar: return nil` |
| `AppSidebar`'s `List` + **four** hand-written branches in `AppMainLayout.body` | — | createRecipe / browser / calendar / everything-else |

Two of those enums exist **only** because Browser, Calendar, and now Create Recipe don't fit the three-column
shape and need a `nil` escape hatch. Every new section must be threaded through all four.

## Decision

Replace the regular-width `NavigationSplitView` **and** the separate `AppCompactTabView` with **one**
`TabView` carrying `.tabViewStyle(.sidebarAdaptable)`, each `Tab` owning its own internal layout.

**What this buys, stated concretely:**

1. **The sidebar ⇄ top-tab-bar toggle Jon asked for is free** — it is what `.sidebarAdaptable` *is* on iPad,
   plus `TabViewCustomization` (reorder / hide / pin, persisted) that would otherwise be bespoke. Deployment
   target is iOS 27, so the API is available unconditionally.
2. **`AppCompactTab` and `AppMainColumnSection` both disappear.** With per-tab content, Browser and Calendar
   stop being special cases needing a `nil` partition — they simply have different tab bodies. The
   compact/regular fork in `AppMainLayout.body` collapses with them.
3. **The list/detail shape is not lost.** In sidebar mode the tab sidebar *becomes* the first column, so the
   familiar sidebar | list | detail persists; in tab-bar mode it drops to list | detail with the bar on top.
   Same information, switchable first column — which is exactly the Apple Music behavior being requested,
   and exactly why this is not a downgrade from three columns.

## What this costs — stated honestly, because it is the reason for the gate

**The code win is real but modest** (collapsing a four-way-duplicated taxonomy); the primary justification is
the user-facing affordance. Against that: this rewrites the top-level container of an app that is **currently
device-passing and syncing cleanly across two physical devices**, touching every surface at once, with no test
coverage — SwiftUI layout is verified only by Jon's device pass. That is a large blast radius for what began
as a navigation preference. **The mitigation is sequencing and isolation, not cleverness.**

## Sequencing (binding)

1. **[`efforts/dogfood-ferry-2026-07-25.md`](../efforts/dogfood-ferry-2026-07-25.md) Dispatch 1 lands first.**
   Its Slice A extracts the full-screen expand control into **one** definition. That control reads
   `columnVisibility`, whose ownership **moves** under this ADR — from one app-level split to one split per
   tab. Doing the extraction first means this ADR re-points a single call site instead of four.
2. **This ADR ships alone, in its own PR.** It rides with nothing.
3. Ratification + slice plan are written **after** step 1, against the real post-extraction code.

## Ratification (2026-08-08)

Ratified after Dispatch 1 landed, scoped against the real post-extraction code. Deployment target is **iOS 27.0**,
so `.tabViewStyle(.sidebarAdaptable)` + `TabViewCustomization` are available unconditionally, and the new
`Tab(value:)` API is already in use in the compact path. **Two product calls from Jon (2026-08-08):** ship as
**two slices** (below), and **Settings stays a customizable tab** — not demoted out of the taxonomy.

### The open questions, now answered

- **OQ1 — per-tab column shape.** Content sections (recipes/menus/workbenches/groceries) **keep a two-column
  `NavigationSplitView` (list | detail)** inside their `Tab`; the tab sidebar supplies the first column, so
  sidebar mode still reads sidebar | list | detail. **Browser and Create Recipe are single-column** (they are
  detail-only today). **Calendar** stays one `Tab` owning its existing workspace + Focus split. Settings is
  two-column (pane list | detail).
- **OQ2 — Focus control.** **Unchanged meaning: collapse the list column to `.detailOnly`.** Each two-column
  tab owns its **own** `columnVisibility` `@State` (cleaner than today's two shared states). Focus stays
  **orthogonal** to the system sidebar/tab-bar toggle — do *not* overload Focus to hide the tab sidebar; the
  extracted [`FocusToolbarButton`](../../YesChefApp/FocusToolbarButton.swift) keeps its semantics.
- **OQ3 — is `AppSection` still right?** Yes — **all 8 cases become tabs; `AppCompactTab` and
  `AppMainColumnSection` are deleted.** Today's "primary 4 + More" is replicated with
  `defaultVisibility(.hidden, for: .tabBar)` on the secondary sections (browser/workbench/createRecipe/settings)
  plus persisted `TabViewCustomization`. **Settings stays a tab** (Jon, 2026-08-08) — customizable and
  user-hideable, not moved out of the taxonomy.
- **OQ4 — ADR-0039 icon collision.** The system sidebar toggle is a third sidebar-ish glyph; **verify it against
  Dispatch 1 Slice C's resolution in the device pass**, not separately. Visual polish, not a blocker.

### Slice plan

**S1 — the container rewrite (ships alone, its own PR).** The structural piece.
- Build each section's body as a standalone view; each two-column tab owns its own `columnVisibility` `@State`
  and `FocusToolbarButton`.
- Replace `AppMainLayout.body` (**both** the compact and regular forks) with **one**
  `TabView(selection: $selectedSection).tabViewStyle(.sidebarAdaptable)` over `AppSection.allCases`.
- Add persisted `TabViewCustomization` (stable `AppStorage` key) with `defaultVisibility(.hidden, for: .tabBar)`
  on the four secondary sections.
- **Delete** `AppCompactTabView`, `AppCompactTab`, `AppMainColumnSection`, `AppMoreStack`; retire the workbench
  `navigationPath` More-stack in favor of the two-column split.
- Untouched by design: `AppContainer`'s full-screen covers (`presentedRecipe`/`presentedCookSession`) sit
  *above* the layout; `openMenuFromCalendar` and the `.recipes` reset keep writing `selectedSection`.

**S2 — the chat presentation merge (the deferred half; separate PR, after S1 device-passes).** Reconcile the
Calendar/Workbench **detent-sheet** chat vs the Recipe **inspector** chat now that all eight sites live in
per-tab layouts. This is the deferred half [`efforts/chat-ask-uniformity.md`](../efforts/chat-ask-uniformity.md)
hands off — the *contract* is already unified (PR #244); only presentation remains. It genuinely needs S1's
shell to exist, and it is product polish rather than structure, so it must **not** ride in S1.

### Verification & blast radius

No automated coverage exists for top-level SwiftUI layout — this rewrites the container of an app that is
device-passing and syncing cleanly across two physical devices, so the mitigation is **isolation (two slices) +
Jon's device pass**, not tests. S1's pass must cover **both physical devices × both orientations × both sidebar
and tab-bar modes**, plus `TabViewCustomization` persistence across launches. Watch: the full-screen covers
presenting over the `TabView`, the cross-tab `openMenuFromCalendar` jump, and workbench navigation collapsing
from two modes to one. `YesChefTests` certifies the models, not the shell.
