# ADR-0046 — The app shell becomes a **sidebar-adaptable `TabView`**: one taxonomy, one container, a user-switchable first column

Status: **Proposed** — opened 2026-07-25 from Jon's ferry dogfood pass ("like on Apple Music, let's have the
buttons so you can move the tab bar to the top and then back to the side"). **STUB: records the motivation,
the code argument, and the sequencing gate. Does not design the per-tab layouts.** Ratification and the slice
plan wait until [`efforts/dogfood-ferry-2026-07-25.md`](../efforts/dogfood-ferry-2026-07-25.md) Dispatch 1
lands — see Sequencing. Governed by [ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the
sidebar-icon collision this must not reproduce).

## Context

**Nothing ever decided the current shell.** A `grep -ri` over `docs/` finds no ADR and no effort covering
app-level navigation. ADR-0039 touches sidebar *icons* — it records that the recipe playbook toggle
(`sidebar.trailing`) sits one glyph from the menu's Browse Recipes button (`sidebar.right`), "two
trailing-sidebar icons, one toggling a structural column, the other a panel" — but the three-column
`NavigationSplitView` container itself was never a considered choice. It is the default iPad idiom, arrived at
by inertia. **So this ADR is not overturning a decision; it is making one for the first time.**

**The taxonomy is encoded four times, in three incompatible partitions.**

| Encoding | Cases | Shape |
|---|---|---|
| `AppSection` ([`AppNavigationModels.swift:47`](../../YesChefApp/AppNavigationModels.swift)) | 7 | the actual source of truth |
| `AppCompactTab` ([`AppMainLayout.swift:270`](../../YesChefApp/AppMainLayout.swift)) | 5 | **lossy** — browser/workbenches/settings collapse to `.more`, whose `.section` returns `nil` |
| `AppMainColumnSection` ([`AppMainLayout.swift:153`](../../YesChefApp/AppMainLayout.swift)) | 5 | a **different** subset — `case .browser, .mealCalendar: return nil` |
| `AppSidebar`'s `List` + three hand-written branches in `AppMainLayout.body` | — | browser / calendar / everything-else |

Two of those enums exist **only** because Browser and Calendar don't fit the three-column shape and need a
`nil` escape hatch. Every new section must be threaded through all four.

## Decision (proposed)

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

## Open questions (not answered here)

- **OQ1 — does each tab keep a two-column `NavigationSplitView`, or do Browser/Calendar go single-column?**
  They are the two sections that needed `nil` today; they are also the two most likely to want the full width.
- **OQ2 — where does the Focus/expand control point once `columnVisibility` is per-tab?** Related: whether
  "focus" should now mean *hide the tab sidebar* rather than *collapse the content column*, since in tab-bar
  mode the first column is already gone.
- **OQ3 — is `AppSection` still the right 7 given tabs can be user-hidden?** `TabViewCustomization` lets the
  user do what the `.more` collapse currently does by fiat; Settings in particular may want to stop being a
  tab.
- **OQ4 — does the ADR-0039 icon collision get worse?** Adding a system-provided sidebar toggle means a
  *third* sidebar-ish glyph on screen alongside the playbook toggle and Browse Recipes. Dispatch 1's Slice C
  is already required to resolve two of them; check the third against that resolution rather than separately.
