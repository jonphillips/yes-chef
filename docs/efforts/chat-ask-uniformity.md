# Effort: One Ask — the same entry point and the same panel on every surface

**Type:** App-layer product change. **No Core, no schema, no sync.** One enabling type change in
`ChatSurface`, then four call sites stop being special.
**Status:** **Ready** — written 2026-07-27 from Jon's dogfood read of PR
[#243](https://github.com/jonphillips/yes-chef/pull/243).
**Summary:** [#243](https://github.com/jonphillips/yes-chef/pull/243) unified the chat panel's
*contract*; it deliberately did not touch the *experience*, and said so twice. This is the follow-on
that spends what #243 bought. Two complaints, one root cause: `ChatSurface.Sections` is typed to
`PlaybookSectionKind`, so only the Recipe can express "here are things you can start a discussion
about." The Menu, unable to use it, grew a pre-flight verb menu that **cannot open the panel without
paying for an LLM call**. Generalize `Sections` and both defects close together.
**Related:** [`chat-surface-contract.md`](chat-surface-contract.md) (**the predecessor** — this
answers its Open Question 1) · [ADR-0045](../decisions/ADR-0045-onboard-path-stays-viable.md)
Amendment 3 codicil (the header contract) ·
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (**owns the deferred half** — see
Sequencing).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

---

## The finding

### 1. Six Ask buttons, three different behaviors

| Surface | Control | Toggles closed? | Opens free? | Label |
|---|---|---|---|---|
| Recipe playbook — [`RecipePlaybookView.swift:115`](../../YesChefApp/RecipePlaybookView.swift) → [`RecipeModels.swift:941`](../../YesChefApp/RecipeModels.swift) | `Button` | ✅ | ✅ | Ask |
| **Menu playbook** — [`MenuPlaybookColumnView.swift:215`](../../YesChefApp/MenuPlaybookColumnView.swift) | **`Menu`, 3 verbs** | ❌ | ❌ **seeds a call** | Ask |
| Calendar workspace — [`MealCalendarViews.swift:113`](../../YesChefApp/MealCalendarViews.swift) | `Button` → detent toggle | ✅ | ✅ | Ask |
| Calendar day — [`MealCalendarDayHeader.swift:60`](../../YesChefApp/MealCalendarDayHeader.swift) | `Button` | ❌ open-only | ✅ | Ask |
| Workbench detail — [`WorkbenchViews.swift:239`](../../YesChefApp/WorkbenchViews.swift) | `Button` | ❌ open-only, rebuilds the model | ✅ | **Chat** |
| Workbench Compare — [`WorkbenchCompareView.swift:123`](../../YesChefApp/WorkbenchCompareView.swift) | `Button` | ❌ open-only, rebuilds the model | ✅ | **Chat** |

**Only one row is a live defect, and it is the Menu's.** The three open-only rows present the panel
as a *modal sheet* that covers the button, so a second tap is unreachable and the missing toggle
never bites. The Menu's panel is an **embedded tool rendered alongside its button**
([`MenuViews.swift:390`](../../YesChefApp/MenuViews.swift)), so both halves bite — and the expensive
half is the real one: `askPrepPlan` goes straight to `seedIfCold(context.discussAsk())` and may
`send()` on top ([`MenuViews.swift:314`](../../YesChefApp/MenuViews.swift)), `presentComplementAsk`
builds a handoff prompt ([`:323`](../../YesChefApp/MenuViews.swift)). **There is no way to look at the
Menu's chat without buying a discussion first.**

The two `Chat` labels are not a defect, just drift. They are the cheapest possible "relearn the
interface" tax and they go in the same pass.

### 2. Four things move inside the panel

The panel is genuinely one view, so this list is short — and every entry is driven by a `ChatSurface`
field, which is why #243 had to land first:

1. **The title slot changes control type.** `ChatSectionMenu` — a dropdown — on the Recipe; a static
   `Text(context.title)` on the other five
   ([`RecipeChatWorkspace.swift:216`](../../YesChefApp/RecipeChatWorkspace.swift)). Same position,
   different affordance, no signal to the cook which surface gives them which.
2. **The header's location flips with presentation.** Embedded row for column/inspector/Menu
   ([`:214`](../../YesChefApp/RecipeChatWorkspace.swift)); nav-bar toolbar for every modal sheet
   ([`:374`](../../YesChefApp/RecipeChatWorkspace.swift)). **Out of scope — see the decision below.**
3. **The finalize button appears and disappears** ([`:294`](../../YesChefApp/RecipeChatWorkspace.swift)),
   shifting the whole bottom action stack. Recipe (seeded) and Menu only.
4. **The empty state has three copy variants**
   ([`RecipeChatPanelSupport.swift:83`](../../YesChefApp/RecipeChatPanelSupport.swift)), one of which
   names a control — *"choose a section from Discuss"* — that four of six surfaces do not have.

**The root cause, stated once:** `Sections` is
`case switchable(select: (PlaybookSectionKind) -> Void, active: PlaybookSectionKind?)`. A playbook
section is a Recipe concept. The Menu's starters are not sections and never will be, so the Menu could
not answer the question the descriptor asked — and a surface that cannot say "I have starters" grows
its own control outside the panel. That is defect 1 and divergence 1 in one sentence.

---

## Decision recorded (Jon, 2026-07-27)

**Uniformity is cross-surface, not cross-device.** Every surface gets identical panel internals, and
modal sheets keep the iOS nav bar (`Done` top-left) while embedded and column presentations keep the
in-panel header row. Recipe → Menu → Calendar match each other on a given device; iPhone and iPad
still differ, which is what the platform sheet idiom asks for. **Divergence 2 above is therefore
closed as intended behavior, not deferred.**

Jon is also content to live with the Calendar's detent split vs. the Recipe's inspector for now — see
Sequencing.

## What this effort is *not*

- **Not the presentation merge.** The Calendar/Workbench detent split and the Recipe inspector stay
  as they are. That is a genuine product decision and it belongs to
  [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md), which moves all eight call sites
  anyway. Doing it here means rewriting the same code twice.
- **Not a merge of the apply-action catalogs.** Still correctly per-host, exactly as #243 said. The
  verbs differ per surface *on purpose*; only the control that starts a discussion is being unified.
- **Not a change to `RecipeChatContext`.** Leave it alone.
- **Not Core, not schema, not sync.**

---

## S1 — `Sections` carries starters, not playbook sections

The enabling change; everything else depends on it. Names are a proposal, not a mandate:

```swift
struct ChatStarter: Identifiable {          // app layer, alongside ChatSurface
  let id: String
  let title: String
}

enum Sections {
  case none
  case starters(_ starters: [ChatStarter], active: ChatStarter.ID?, select: (ChatStarter.ID) -> Void)
}
```

- **Recipe supplies `PlaybookSectionKind.allCases` mapped to starters**, `select` routing to the
  existing [`askSection`](../../YesChefApp/RecipeModels.swift). Its behavior must not change by a
  pixel — it is the reference implementation and the regression canary.
- **`.none` still renders `Text(context.title)`**, exactly as today. Calendar and Workbench pass
  `.none` and are untouched by this slice.
- **`ChatSectionMenu` becomes starter-generic** and keeps its **Discuss ▾** label. The label is
  established and the cook already knows it.
- **`ChatEmptyState` stops naming a control it may not have.** Drive the clause off the starter list
  rather than a `hasSectionMenu` bool, and drop the Recipe-shaped copy for wording that reads on all
  six surfaces.

**Acceptance:** the Recipe's Discuss ▾ behaves identically to today; the other five surfaces render
byte-identically; the empty state never names a control the surface lacks.

## S2 — The Menu's Ask becomes a toggle

Depends on S1.

- Replace the `Menu { … }` at
  [`MenuPlaybookColumnView.swift:215`](../../YesChefApp/MenuPlaybookColumnView.swift) with a plain
  `Button` calling a new `MenuDetailModel.askButtonTapped()` that **mirrors
  [`RecipeModels.swift:941`](../../YesChefApp/RecipeModels.swift) exactly**: open if closed, close if
  open, seed nothing, and set `focusesInputOnAppear` when unseeded.
- **Prep Plan and Complement move into the Discuss ▾ starters.** `askPrepPlan` and
  `presentComplementAsk` become the `select` targets rather than entry points.
- **They must reuse an already-open chat model, not build a new one.** The Recipe solved this at
  [`RecipeModels.swift:962–967`](../../YesChefApp/RecipeModels.swift) — *"a freshly-opened panel may
  restore a warm thread from an earlier section"*. The Menu will hit the identical trap the moment
  the panel is open before a starter is picked, which after this slice is the normal case. Port the
  guard; do not re-derive it.
- **"Regenerate whole plan" is not a starter** — it regenerates an existing artifact rather than
  opening a discussion. It stays on the playbook header as its own control.

**Acceptance:** tapping **Ask** on a Menu opens an empty, focused panel and costs nothing. Tapping it
again closes it. Prep Plan and Complement still work, from inside the panel, and reuse the open
thread.

## S3 — Entry-point drift

Small, mechanical, same mental model:

- **`Chat` → `Ask`** at [`WorkbenchViews.swift:242`](../../YesChefApp/WorkbenchViews.swift) and
  [`WorkbenchCompareView.swift:126`](../../YesChefApp/WorkbenchCompareView.swift).
- **Give the three open-only entry points the same close-if-open guard** as the Recipe. It is
  unreachable behind a modal today, so this is not a bug fix — it is removing the last reason for
  these call sites to read differently from each other, and ADR-0046 may well un-modal them.

**Acceptance:** all six entry points are a `Button` labelled **Ask** that toggles a free, unseeded
panel. No surface has a pre-flight menu.

## S4 — Tests

Extend `YesChefAppTests/ChatSurfaceTests.swift` with the starter contract: each host's factory
resolves to the starter list it claims, `.none` surfaces expose no starter control, and no factory
seeds on construction.

> ⚠️ **This slice is blocked and the effort must not pretend otherwise.** `YesChefAppTests` does not
> currently build: `xcodebuild build-for-testing` fails linking `CloudSyncKit.framework` on missing
> GRDB / StructuredQueriesCore symbols, reproducibly **and identically on `main`**. So #243's
> `ChatSurfaceTests.swift` has never executed, and neither will this. `check-drift.sh` runs only the
> package suite, so nothing in the standard verification reveals it. Write S4 anyway — it is cheap
> and it is correct the day the target builds — but **do not report it as passing**, and see Open for
> Jon 2.

---

## Sequencing

**After [#243](https://github.com/jonphillips/yes-chef/pull/243) merges. Before
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md).**

- **After #243**, because `Sections` only exists as a stated field because of it. Before #243 this
  effort would have been six argument-list edits with no shared shape to change.
- **Before ADR-0046**, for the same reason #243 was: that ADR moves every one of these call sites,
  and it should inherit one Ask, not six.

**Batching:** S1–S4 are one dispatch, one PR. They share files and a single mental model, and S2/S3
are near-certainly right once S1 lands (AGENTS.md rule 5).

## Verification

Generic app build (elevated, no signing) + `scripts/check-drift.sh`. **No simulator installs.** S4
compiles but cannot run — say so in the PR body rather than claiming a green test pass.

Jon device-passes on `iPad Pro 13-inch (M5)` (both orientations) + `iPhone 17 Pro`:

1. **Menu** — Ask opens an empty panel with no network call; Discuss ▾ lists Prep Plan and
   Complement; picking one seeds into the *open* thread; Ask again closes it.
2. **Recipe** — completely unchanged, both presentations. This is the canary.
3. **Calendar + Workbench** — unchanged apart from the `Ask` label, and the empty state no longer
   mentions a Discuss control they do not have.

## Open for Jon

1. **Do the Calendar and Workbench want starters of their own?** S1 gives them the capability and
   they pass `.none`, which is now an explicit answer rather than an omission. "Plan this week" or
   "What should I prep tonight?" would be the obvious candidates — worth knowing whether you want
   them before ADR-0046 rearranges these surfaces.
2. **The app test target has been dark for some time.** All eight files in `YesChefAppTests` are
   unbuildable behind the CloudSyncKit link failure, and `check-drift.sh` reports green without them,
   which is how it stayed invisible. Fixing it is a jon-platform effort, not this one — but until it
   lands, "add a test" is not a real acceptance criterion anywhere in this repo's app layer, and this
   effort's S4 is the second brief in a row to write a test that cannot run.
