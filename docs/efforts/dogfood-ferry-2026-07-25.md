# Effort: Dogfood ferry pass — 2026-07-25 (expand control, hand-off regrouping, workbench lifecycle)

**Status:** **Dispatches 1 and 1.5 have shipped** — 1 (commit `12a6612`, 2026-07-25), 1.5 (PRs
[#234](https://github.com/jonphillips/yes-chef/pull/234) + [#235](https://github.com/jonphillips/yes-chef/pull/235),
2026-07-26) → [`DONE-LOG`](../DONE-LOG.md). **Dispatch 2 is next**, then 3, one PR each.
**Summary:** Jon's 2026-07-25 ferry pass over Menu, Recipe, Calendar and Workbench. One shared full-screen
expand control replaces four drifted copies; the Menu grows the Recipe's pinned-Ask onboard treatment;
the embedded chat panel stops dumping its chrome into the host toolbar and learns to close itself;
prep-plan/complement hand-offs regroup from button rows into per-day and per-plan overflow menus with settled
vocabulary; the Workbench gains an Active/Completed lifecycle and edit-in-place; Menu learnings become
hand-authorable through the `.inApp` provenance that already exists.
**Related:** [ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md) (the woven prep plan this
effort must not fragment) · [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md) (the
playbook column and its sidebar-icon collision) · [ADR-0041](../decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md)
(scoped hand-off sources) · [ADR-0038](../decisions/ADR-0038-external-llm-handoff.md) (learnings + provenance)
· [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (the tab-bar shell — **gated behind
Dispatch 1**, not part of this effort).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

**Jon's decisions, ratified 2026-07-25 — do not re-litigate:**

1. **Per-day prep plan is a scoped *ask*, not scoped *storage*.** The master plan stays woven.
2. **The Calendar's verb is Make-ahead, not Prep Plan.** Already true in code; only labels change.
3. **There is no week-scoped hand-off.** Each day cell on the week grid gets its own menu for *that day*.
4. **Deleting a workbench leaves the un-promoted working recipe in the library.**
5. **Hand-authored menu learnings are Learnings, not notes** — distinguished by `provenance`, which is
   already modeled.

---

## The finding that shapes Dispatch 2

`PrepPlanStepRecord` ([`MenuPrepPlan.swift:10`](../../YesChefPackage/Sources/YesChefCore/MenuPrepPlan.swift))
has **no `dayOffset`**. Its only grouping axis is `session`, mapped onto the `PrepPlanSessionBand` horizon
bands (Flexible / Earlier in the week / The day before / The day of / At service). That is
[ADR-0034](../decisions/ADR-0034-prep-plan-work-session-timeline.md)'s decision, made deliberately on
2026-07-12: **one weaveable master plan per menu**, banded by horizon, so cross-dish work interleaves.

Adding `dayOffset` to the step record would fragment that plan into N per-day mini-plans and reverse
ADR-0034. So the per-day affordance is a **scoped ask with a woven return**: the day's menu builds a prompt
carrying only that day's dishes, and the return merges into the single master plan through the existing
`prepPlanPasted` reconciliation ([`MenuModels.swift:579`](../../YesChefApp/MenuModels.swift)). Steps land in
horizon bands as they do today.

This also fixes the ambiguity the per-day ask was reacting to: horizon bands are relative to **service**, and a
multi-day menu has several service dates, so "the day before" is already under-specified. Anchoring the *ask*
to a day resolves it without moving the storage.

**The asymmetry to expect:** `MenuComplement` already carries `dayOffset` on its suggestions
([`MenuComplement.swift:29`](../../YesChefPackage/Sources/YesChefCore/MenuComplement.swift)), so day-scoping
the complement is a prompt scope plus a fixed offset on the return. **Complement is cheap; prep plan is the
work.**

---

# DISPATCH 1 — the expand control and the onboard column (view layer only, no Core, no schema)

**Why these ship together:** all four surfaces' expand controls and the Menu's Ask placement are the same
class of drift — one interaction pattern, four independent implementations. Fixing them in one PR is what
stops a fifth copy appearing. **Nothing here touches `YesChefPackage`.**

**Read first:** [`RecipeDetailView.swift`](../../YesChefApp/RecipeDetailView.swift) (focus button ~141–155,
`primaryAction` group ~157–208, the reader's playbook toggle ~370–383),
[`MenuViews.swift`](../../YesChefApp/MenuViews.swift) (~216–224),
[`WorkbenchViews.swift`](../../YesChefApp/WorkbenchViews.swift) (~178–187),
[`AppMainLayout.swift`](../../YesChefApp/AppMainLayout.swift) (calendar branch ~46–56, focus wiring ~91–110),
[`RecipePlaybookView.swift`](../../YesChefApp/RecipePlaybookView.swift) (`playbookHeader` + `askButton`
~99–136 — the reference treatment),
[`MenuPlaybookColumnView.swift`](../../YesChefApp/MenuPlaybookColumnView.swift) (~61–65, ~159–185).

## SLICE A — one expand control, four surfaces

**Recipe is the reference and it is already correct** — `.topBarLeading`,
`arrow.up.left.and.arrow.down.right` becoming `….circle.fill` when active, `.tint(active ? .accentColor :
.primary)`, label `Focus` / `Exit Focus`, `.accessibilityValue("Focused" / "Split view")`.

1. **Extract it once.** A single `FocusToolbarButton` (or `ToolbarContent` helper) carrying icon, tint,
   label, and accessibility value. Every surface below uses it — no surface re-authors the glyph choice.
2. **Menu conforms.** Today `.primaryAction` with a `rectangle.expand` icon and no tint
   (`MenuViews.swift` ~216–224). Move to `.topBarLeading`, adopt the shared control.
3. **Workbench conforms.** Identical drift (`WorkbenchViews.swift` ~178–187). **Note for Jon's phrasing:**
   the "Focus" button is not being *removed* — it is the same control, non-conforming. After this slice it
   *is* the double-arrows.
4. **Calendar gains one.** It has none today. Its branch
   (`AppMainLayout.swift` ~46–56) is a two-column `NavigationSplitView` with **no `columnVisibility`
   binding** — add one, mirroring the wiring at ~91–110, so the control collapses to the detail column.

**Acceptance:** all four surfaces show the same glyph in the same place, highlight identically when active,
and exit with the same tap. Exactly one definition of the icon/tint pair exists in the codebase.

## SLICE B — Recipe toolbar: Edit right-most-but-visible

Edit is currently **first** in the trailing group (`RecipeDetailView.swift:158`), ahead of Groceries, Plan and
the Hand-off menu.

**The wrinkle that makes this more than a reorder:** the playbook show/hide button is contributed by
`RecipeReaderView`'s *own* `.toolbar` (~370–383), a different view. Toolbar order follows view-hierarchy
order, so anything in `RecipeDetailView`'s group renders **before** it — Edit can never become right-most by
reordering within its own group.

**Resolution:** hoist the playbook toggle into `RecipeDetailView`'s `primaryAction` group and place Edit last,
giving `Groceries · Plan · Hand off · Playbook · Edit · ⋯`. The toggle's `proxy.size.width >=
twoColumnThreshold` gate must travel with it (a width preference or a passed flag) — do not drop the gate, or
the toggle appears on iPhone where there is no second column.

**Acceptance:** Edit is the last visible trailing item, immediately left of the overflow `⋯`; the playbook
toggle still only appears at two-column width; the secondary-action overflow is unchanged.

## SLICE C — the Menu's onboard column echoes the Recipe's

1. **Pin Ask to the top of the playbook column.** Menu's Ask lives in the *toolbar* today
   (`MenuViews.swift` ~236–249). Move it into a `menuPlaybook` header matching
   `RecipePlaybookView.playbookHeader` (~99–103): trailing-aligned, `.bordered`, tinted stroke overlay while
   its panel is open, `.accessibilityValue("Panel open" / "Panel closed")`.
2. **The Ask dropdown carries Regenerate.** Recipe's Ask is a `Menu` over `PlaybookSectionKind.allCases`.
   Menu's list is **Prep Plan · Complement**, plus **Regenerate whole plan** as a distinct item —
   which retires the standalone `Regenerate` button now sitting inside the Prep Plan section
   (`MenuViews.swift` ~487–493).
3. **Give the column a show/hide toggle.** `MenuPlaybookColumnView` hardcodes `isPlaybookVisible: true`
   (~64). Adopt the Recipe's `@AppStorage`-backed visibility with the same `sidebar.trailing` toolbar button.
   **Heed [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md)'s recorded collision:** the
   Menu already has a *Browse Recipes* button using `sidebar.right`, one glyph away. Two trailing-sidebar
   icons on one toolbar is the exact confusion ADR-0039 flagged — resolve it in this slice (distinguish the
   panel toggle from the structural column toggle), do not ship both glyphs side by side.

**Acceptance:** Menu's Ask sits pinned at the top of the playbook column, lights up while its panel is open,
and offers Prep Plan / Complement / Regenerate; the column hides and shows; no two toolbar buttons read as
the same control.

## SLICE F1 — Calendar's onboard affordance

Calendar's onboard column is **not** the playbook pattern — it is `ChatWorkspaceSplit` with a persisted detent
([`MealCalendarViews.swift:268`](../../YesChefApp/MealCalendarViews.swift)), and `chatButtonTapped` only
*forces* `.balanced`, never collapses (~366–372).

**Do not converge the patterns in this slice.** Give the existing split a pinned Ask affordance and make the
button a real toggle (visible → collapse; hidden → `.balanced`), matching the fix already applied to the
recipe chat button in batch 5.

**Recorded, not scoped:** there are now **three** chat presentation patterns — inspector (Recipe),
`ChatWorkspaceSplit` (Calendar, Workbench compare), and sheet (compact). That convergence is a real question
and it is **explicitly out of scope here.**

**Acceptance:** the Calendar day's Chat button opens *and* closes the panel on repeated taps; the Ask
affordance is discoverable without selecting a day first.

**Dispatch 1 verification:** generic app build (elevated, no signing) + `scripts/check-drift.sh`. No package
tests — nothing here touches Core. Jon does the device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.

---

# DISPATCH 1.5 — the embedded chat panel owns its chrome, and the Calendar's chat is hoisted

> ### ✅ SHIPPED 2026-07-26 — do not re-implement.
> PRs [#234](https://github.com/jonphillips/yes-chef/pull/234) (G1–G4) + [#235](https://github.com/jonphillips/yes-chef/pull/235)
> (G5, the architect review, and the device-pass follow-ons) → [`DONE-LOG`](../DONE-LOG.md). The spec below is
> retained as the record of intent. **One deviation to know about:** it did not stay schema-free — assistant
> turns now record the tier that produced them (`chatMessages.resolvedTier`), a **local-only** column on an
> unsynced table, so nothing entered the prod-promotion list.

**Added 2026-07-26** from Jon's device pass on Dispatch 1. **View layer only — no Core, no schema.**

**Why this exists.** Dispatch 1 moved the Menu's Ask from the toolbar into the playbook column
(Slice C) and made the Calendar's chat button a real toggle (Slice F1). The device pass found the
Ask panel floating **over** the button that opens it on the Menu, and the Calendar's Ask still
arriving as a slide-up sheet. Chasing both found one cause and one scoping error — plus a third
thing: **Jon had only ever exercised the Recipe's Ask on iPhone**, which takes the `.sheet` path and
is correct. Every defect below is on the iPad path, and the Recipe has it too.

**The order is deliberate: fix the Recipe, then port.** The Recipe is the reference treatment every
other surface is being pulled toward; fixing the Menu first would mean porting from a surface that is
itself wrong.

## The finding that shapes this dispatch

`RecipeChatPanel` already carries the right concept. `showsEmbeddedHeader`
([`RecipeChatWorkspace.swift:233`](../../YesChefApp/RecipeChatWorkspace.swift)) renders the panel's
title, Clear and tier menu **inside** the panel and contributes **no** toolbar items. The doc comment
on `onDismiss` (~239) states the intent outright: *"`nil` for embedded panels that own their own
chrome."*

**Exactly one caller passes it** — `ChatWorkspaceSplit` (~105). The Recipe's `.inspector`
([`RecipeDetailView.swift:281`](../../YesChefApp/RecipeDetailView.swift)) and the Menu's trailing
overlay ([`MenuViews.swift:391`](../../YesChefApp/MenuViews.swift)) are equally embedded and both
leave it `false`, so they render *modal* chrome in a *non-modal* position: SwiftUI merges their
toolbar items into the **host's** navigation bar. That is the Clear (trash) and the tier menu Jon
found in the Recipe's main toolbar, and the stray `Done` next to the Focus glyph in the Menu.

**The precedent is already sitting in the same overlay slot.** `MenuRecipeBrowserPanel`
([`MenuDetailSections.swift:5`](../../YesChefApp/MenuDetailSections.swift)) renders its own
`Text("Recipes").font(.headline)` header with its Filter control beside it and declares no `.toolbar`
at all. The chat panel is the odd one out, not the pattern-setter.

**And a launcher cannot be the dismiss.** The Recipe's Ask ▾ is a `Menu` — a section picker, by
design ([ADR-0045](../decisions/ADR-0045-onboard-path-stays-viable.md) Amd 2) — so it cannot also be
a toggle, and it should not become one. **Launchers launch; panels close themselves.** Once the panel
owns a close control, the toggle semantics the Menu's Ask inherited stop mattering, and so does the
question of whether the Ask button is covered.

## SLICE G1 — the Recipe's inspector panel owns its chrome

1. **`askSlideOver` passes `showsEmbeddedHeader: true`**
   ([`RecipeDetailView.swift:280`](../../YesChefApp/RecipeDetailView.swift)). Title, Clear and tier
   stop leaking into the recipe's navigation bar.
2. **The embedded header gains a close** when `onDismiss` is set. Recommend an `xmark.circle.fill` at
   the header's **trailing** edge, not a `Done` — this panel commits through Finalize and the review
   sheet, so "Done" over-promises. `.accessibilityLabel("Close Ask")`.
3. **The embedded header's title slot becomes `ChatSectionMenu` when `selectSection` is non-nil.**
   Today the section switcher is a `.principal` toolbar item (~394), which on iPad **replaces the
   recipe's own navigation title with "Discuss ▾"** while the panel is open. Flipping the flag without
   this step would silently drop the switcher, which is an affordance, not chrome.
   `ChatSectionMenu`'s label is already `.font(.headline)`
   ([`ChatSectionMenu.swift:26`](../../YesChefApp/ChatSectionMenu.swift)), so it drops into the
   header's title slot as-is.
4. **Gate `.navigationTitle` / `.navigationBarTitleDisplayMode` behind `!showsEmbeddedHeader`** (~384–385).
   They are applied unconditionally today, *outside* the existing toolbar gate, so they fight the host
   title on the Calendar and Workbench splits as well — this is not Recipe-only.
5. **Rewrite the `onDismiss` doc comment** (~239–241). It currently reads *"`nil` for embedded panels
   that own their own chrome"* — after this slice embedded panels **do** take an `onDismiss`, and the
   comment becomes actively misleading.
6. **The `.sheet` path does not change**
   ([`RecipeDetailView.swift:254`](../../YesChefApp/RecipeDetailView.swift)). A sheet has its own bar,
   and `Done` there is correct. This is the iPhone behavior Jon has been living with, and it is the
   reason none of this surfaced until now.

**Acceptance:** with the Recipe Ask panel open on iPad, the recipe's navigation bar shows only the
recipe's own items — no trash, no tier menu, no stray `Done`, and the recipe title still reads the
recipe's title. The panel shows its own header with Discuss ▾, Clear, tier and a close. Closing it
takes one tap, in the panel. iPhone is unchanged.

## SLICE G2 — the same fix ports to the Menu

`menuToolContent`'s `.chat` case ([`MenuViews.swift:390`](../../YesChefApp/MenuViews.swift)) passes
`showsEmbeddedHeader: true` and keeps its `onDismiss: dismissTool`. Nothing else in the Menu changes.

This removes the dislocated `Done` and gives the Menu's Ask panel a close that does not depend on
reaching the button underneath it — which is the actual complaint. **`selectSection` is `nil` for the
menu context**, so its header keeps the plain title.

**Optional, while in the file:** give `MenuRecipeBrowserPanel` the same close control for symmetry. It
is not broken — its launcher is a plain toggle `Button`, so tapping Browse Recipes again already closes
it — so this is consistency, not a fix. Say in the PR which way you went.

**Deliberately NOT decided here — the Menu's panel *geometry*.** Whether the chat should keep floating
over, push like the Recipe's inspector, or take the playbook column's place is a real Menu-specific
question (it is the only surface with two body columns already), and the over-presentation is load-bearing
for the parked drag-from-Browse work — see the comment at
[`MenuViews.swift:191`](../../YesChefApp/MenuViews.swift). **A panel that covers a control you need is a
trap; a panel that covers content while open and closes on demand is just a panel.** G2 converts the
first into the second. Jon decides the geometry after feeling it, not before. **Do not change the
overlay to an inspector in this dispatch.**

**Acceptance:** the Menu's navigation bar shows only the Menu's own items while the Ask panel is open;
the panel closes from inside itself.

## SLICE G3 — hoist the Calendar's chat to the workspace

**Slice F1's premise was wrong and that is a spec error, not an implementation one.** F1 described the
Calendar as "`ChatWorkspaceSplit` with a persisted detent." That is true of **one of three**
`MealCalendarDayAgendaView` call sites. The other two pass `allowsChatWorkspace: false` — the wide-layout
agenda rail ([`MealCalendarViews.swift:219`](../../YesChefApp/MealCalendarViews.swift)) and the agenda
under the month/week grid (~167). The split is reachable **only** when `displayMode == .day`. In month
or week view — where Jon lives — `chatButtonTapped` falls to `compactChatModel` and presents a sheet.
Codex implemented F1 correctly (~376); it just only reaches a branch Jon was not standing in.

**Do not simply flip the flag.** Both `false` sites are inside a `ScrollView`, and `ChatWorkspaceSplit`
is a `GeometryReader` with fixed frames — nesting it in an unbounded-height scroll produces a collapsed
panel, not a column. The flag is defending something real.

**The fix is to raise the split one level.** `MealCalendarWorkspaceView`
([`MealCalendarViews.swift:23`](../../YesChefApp/MealCalendarViews.swift)) becomes the
`ChatWorkspaceSplit` host: its whole body — `MealCalendarWideWorkspace` **or**
`MealCalendarStackedContent` — is the **reader**, and chat is a sibling column beside the entire
calendar. Then:

1. The workspace builds `mealPlanChatContext` from `model` (it already holds `model`; the context is
   just `selectedDateTitle` / `selectedDate` / `selectedDayRows`).
2. `MealCalendarDayAgendaView` takes a passed-in `chatButtonTapped: (() -> Void)?` instead of owning
   the decision, and all three call sites route the day header's Ask up to the workspace's detent
   toggle. `allowsChatWorkspace` disappears with the local split.
3. **The compact path keeps its sheet.** `compactChatModel` stays for `horizontalSizeClass == .compact`
   — on iPhone a sheet is right.

> ⚠️ **Drop the `.id(chatContextIdentity)` on the split (~287) — do not carry it up.** Hoisted, that
> `.id` rebuilds the *entire calendar* every time the selected day changes. It is also **redundant**:
> `RecipeChatModel.updateContext`
> ([`RecipeChat.swift:797`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)) already
> persists the outgoing thread and loads the incoming one when the `persistenceSubject` changes, and
> the meal-plan subject is `.mealPlanDay(date)`
> ([`RecipeChatPersistence.swift:71`](../../YesChefPackage/Sources/YesChefCore/RecipeChatPersistence.swift))
> — per day. `ChatWorkspaceSplit` already calls `updateContext` from `.onChange(of: context)` (~114).
> So switching days swaps transcripts correctly **without** the `.id`, and dropping it is what makes
> the hoist safe rather than what makes it risky.

4. **Check day mode on device.** `displayMode == .day` routes through `MealCalendarStackedContent`,
   which means today's *working* split is **also** nested in a `ScrollView`. Suspect it is quietly
   degraded. The hoist should fix it by construction — confirm it does.

**Acceptance:** in month, week **and** day view on iPad, the day header's Ask opens a chat **column**
beside the calendar and the same button closes it; the transcript follows the selected day; changing the
selected day does not rebuild the calendar; iPhone still gets the sheet.

## SLICE G4 — Ask opens the panel (ADR-0045 Amendment 3)

**Added 2026-07-26, after G1–G3 were already submitted as PR [#234](https://github.com/jonphillips/yes-chef/pull/234) — folds into that PR.** Spec:
[ADR-0045 Amendment 3](../decisions/ADR-0045-onboard-path-stays-viable.md#amendment-3--ask-opens-the-panel-the-launcher-stops-picking-sections-2026-07-26).
Touches [`RecipePlaybookView.swift`](../../YesChefApp/RecipePlaybookView.swift), which G1–G3 do **not** touch —
no conflict with the submitted work.

**The defect:** `askButton` (~114) is a `Menu` over `PlaybookSectionKind.allCases`, so there is no way to open
the chat without first committing to a seeded section discussion. A cook who wants to type *"what's a good
substitution for buttermilk"* must first fake a scoped ask. **This is V1's defect mirrored** — V1 fixed "the
panel opens empty and looks broken" by refusing to open the panel without a seed.

1. **`askButton` becomes a plain `Button`.** It opens the panel unseeded and focuses the input. Keep the
   existing `.bordered` / radius-8 / `isAskActive` tinted-stroke treatment and the
   `.accessibilityValue("Panel open" / "Panel closed")` — only the `Menu` and its `ForEach` over sections go.
   The section list keeps its home in the panel's **Discuss ▾** (Amendment 2), which G1 moves into the embedded
   header — **so land G4 after G1**, not before.
2. **Route it through a no-section open path.** `RecipeDetailModel.askSection` is open-or-switch **scoped to a
   section**; the launcher now needs open-**unseeded**. Do not fake it by passing a default section — that is
   the exact behavior being removed. `seededAskSection` stays `nil`, which `Discuss ▾` already renders as its
   *"Discuss"* placeholder ([`ChatSectionMenu.swift:25`](../../YesChefApp/ChatSectionMenu.swift)).

> ⚠️ **The binding condition from the amendment — this slice is not done without it.** An unseeded panel today
> shows only `ChatContextHeader`'s one-line context footnote over an empty transcript, with the apply-verbs
> greyed and **unexplained**. That is precisely the screen that produced V1's *"the feature was removed"*
> conclusion, and shipping step 1 alone re-files that bug. So:
> **(a)** add an **empty state** in the transcript area when `chatModel.messages.isEmpty` — ask anything about
> this recipe, or pick a section from Discuss ▾ for a guided discussion; and
> **(b)** give the greyed apply-verbs a **stated reason** (they need a reply first). Greyed-with-a-reason is a
> working control; greyed-in-silence is a broken feature. **`requiresSubject` does not loosen** (D6) — the
> empty state explains the gate, it does not remove it.

3. **Do not touch the Menu's Ask ▾.** It lists *verbs* (Prep Plan · Complement · Regenerate), not sections, and
   has no in-panel equivalent to fall back on. Amendment 3 is explicit that it stays a menu.

**Acceptance:** one tap on the recipe's Ask opens the panel with the field ready and no seeded turn sent; the
empty panel states what it is for and why the apply-verbs are greyed; picking a section from Discuss ▾ still
seeds that section's opener into the open thread; the Menu's Ask ▾ is unchanged. **Testable on iPhone**, unlike
the rest of this dispatch.

## SLICE G5 — the panel header settles: one primary, one overflow, one dismiss

**Added 2026-07-26 from Jon's iPad pass on PR [#234](https://github.com/jonphillips/yes-chef/pull/234) — its own PR, after #234 merges.** Spec:
[ADR-0045 Amendment 3, codicil](../decisions/ADR-0045-onboard-path-stays-viable.md#codicil-to-amendment-3--the-embedded-panel-header-contract-2026-07-26).
**This is the slice that makes the panel treatment portable** — every embedded panel (Recipe, Menu, Calendar,
Workbench) renders the same `RecipeChatPanel` header, so settling it here settles it everywhere. That is
Jon's stated reason for doing it now rather than after it has spread.

**The observation:** G1 moved the chrome into the panel where it belongs, and that made visible how much of it
there is. An **empty** panel currently presents Discuss ▾, a trash, a tier chip, a close, a context line, an
empty state, a disabled Apply, an explanation of the disabled Apply, the input, and Send — ten elements to say
*"ask me something."*

> ⚠️ **Some of the items below may already be fixed** — Jon dispatched the review nits separately onto #234
> (the `ChatContextHeader` defect and the Ask-button toggle). **Check the merged state first and skip what is
> already done**; the acceptance criteria below are what matters, not the diff size.

**1. The header becomes `[ Discuss ▾ | title ] ……… [ ⋯ ] [ ✕ ]`.**
- **Primary slot** — `ChatSectionMenu` when `selectSection` is non-nil, otherwise the plain `Text(title)`.
  Unchanged from G1.
- **`⋯` overflow** — holds **Clear Chat** (destructive role, **keeping its existing `confirmingClearChat`
  alert**) and the **model/tier** picker (`ChatTierMenu`'s contents, inlined as a section of this menu rather
  than a nested menu). `.accessibilityLabel("Chat options")`.
- **`✕` close** — unchanged, and still rendered only when `onDismiss` is non-nil, so the `ChatWorkspaceSplit`
  surfaces (Calendar, Workbench) keep dismissal in their divider where it already lives.

**Why the overflow, stated as a rule and not a preference:** a **destructive** control must not sit one target
away from a **dismiss** control. `Clear Chat` already confirms, so a fat-finger costs a Cancel rather than a
transcript — but adjacency is the wrong shape regardless of the safety net. The tier picker joins it because
it is the least-used control on the surface (a per-conversation privacy override, not a per-question choice)
and it should not be paying for header width.

**2. The disabled-Apply explanation folds into the empty state.** Delete the standalone
`applyActionsNeedReply` footnote above the input; move its sentence into `ChatEmptyState`. The two currently
explain the same emptiness in two places, four inches apart — that redundancy was my binding condition on
Amendment 3 being satisfied twice, not a design. **Apply stays visible-but-disabled** (that teaches the
affordance exists); it just stops narrating. Once a reply exists, neither message renders.

**3. `ChatContextHeader` stops claiming a seed that did not happen** *(may already be fixed on #234)*. It
renders `seededContextDescription` unconditionally, and the recipe case is the hardcoded string **"Seeded with
the recipe on screen."** ([`RecipeChat.swift:116`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)).
Before Amendment 3 the panel was always seeded, so it was true; G4 made it false, and it now renders directly
above *"Ask anything about this recipe."* Suppress it when `chatModel.messages.isEmpty` — the empty state
covers the same ground — and **reword the seeded case out of internal vocabulary**: "seeded" is our word, and
what it means to a cook is *the model can see this recipe*.

**4. The Ask launcher toggles** *(may already be fixed on #234)*. `askButtonTapped` returns early when a chat
is already open, so the lit button is an indicator styled like a button. Amendment 2's never-close rule applied
to `askSection`, a **switcher**; the plain opener is not a switcher and closing is now safe. Make the tap close.

**5. Apply the same grouping to the modal sheet path.** The iPhone sheet keeps `Done` at `.topBarLeading` and
the section switcher at `.principal`, but its trailing `clearChatButton` + `ChatTierMenu` become the same
single `⋯`. One contract, both presentations — otherwise the iPhone and iPad panels drift apart again, which is
the class of problem this whole dispatch exists to close.

**Explicitly not in this slice:** `ChatWorkspaceDetent.storageKey` is a **single global key** shared by the
Calendar workspace ([`MealCalendarViews.swift:25`](../../YesChefApp/MealCalendarViews.swift)) and the Workbench
([`WorkbenchViews.swift:106`](../../YesChefApp/WorkbenchViews.swift)), so collapsing the chat column on one
collapses it on the other. **Pre-existing** — the pre-hoist day-agenda split used the same key — but G3 raised
its blast radius from one calendar mode to the whole surface. It wants a per-surface key; it is a different
concern from the header and should not ride here.

**Acceptance:** an empty panel presents **one** explanation of its emptiness, not two; the header carries three
targets (primary, `⋯`, close) with Clear Chat and the tier picker inside the overflow; Clear Chat still
confirms; no destructive control is adjacent to the close; the context line does not claim a seed on an
unseeded panel; tapping a lit Ask closes the panel; the iPhone sheet groups its trailing controls the same way.
**Verify on all four surfaces** — Recipe, Menu, Calendar, Workbench — since they share the header.

**Dispatch 1.5 verification:** generic app build (elevated, no signing) + `scripts/check-drift.sh`.
No package tests — nothing here touches Core. Jon does the device pass on `iPad Pro 13-inch (M5)` and
`iPhone 17 Pro`, **and the iPad pass is the point of this dispatch** — every defect it fixes is invisible
on iPhone.

**Sequencing note.** This lands **before** [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md).
That ADR's gate ("Dispatch 1 lands first") is already satisfied, but sending a broken panel affordance into a
container rewrite with no test coverage means you cannot tell which change broke what. Both fixes live inside
tab bodies and survive the container move.

---

# DISPATCH 2 — hand-off regrouping, scoped asks, and the vocabulary cleanup

**Why these ship together:** the regrouping and the renaming are the same edit to the same controls. Splitting
them means touching every hand-off button twice.

**Read first:** [`MenuDetailSections.swift`](../../YesChefApp/MenuDetailSections.swift) (`MenuDaySection`
~150–197, its Add button ~185–196), [`MenuViews.swift`](../../YesChefApp/MenuViews.swift) (prep-plan header
~450–502, `PrepPlanHandoffControls` ~593–628), [`MealCalendarViews.swift`](../../YesChefApp/MealCalendarViews.swift)
(`MealCalendarDayHeader` ~808–919, `MealCalendarWeekCell` ~734–777),
[`MealCalendarHandoffSource.swift`](../../YesChefApp/MealCalendarHandoffSource.swift),
[`MenuChatContext.swift`](../../YesChefPackage/Sources/YesChefCore/MenuChatContext.swift),
[`MenuComplement.swift`](../../YesChefPackage/Sources/YesChefCore/MenuComplement.swift).

## SLICE D1 — the Menu day overflow menu

Each `MenuDaySection` header gets a `⋯` menu **to the right of its existing Add button** (~185–196), holding
four items in this order:

> **Handoff Prep · Paste Prep · Handoff Complement · Paste Complement**

- **Complement is the cheap half** — scope the existing `.menuComplement` prompt to the day's dishes and fix
  the returned `dayOffset` to that day. `MenuComplement` already carries the field.
- **Prep is the scoped ask** — the prompt carries only that day's dishes and asks for steps for that day; the
  return merges into the one master plan via `prepPlanPasted`. **No `dayOffset` is added to
  `PrepPlanStepRecord`.** Steps continue to land in horizon bands.
- `PasteButton` does not render inside a `Menu`, so the Paste items read `UIPasteboard.general` directly and
  hand the empty case to the transport — copy the pattern at
  [`RecipeDetailView.swift:191`](../../YesChefApp/RecipeDetailView.swift), including the
  `.disabled(!UIPasteboard.general.hasStrings)` gate.

**This slice discharges a logged concern.** The PR #226 device pass noted the Prep Plan disclosure rendering
two Copy + two Paste buttons and the meal-plan day header four, with the note *"wants a feel on iPhone before
anyone adds a fifth."* Moving them into overflow menus **is** that fix — say so in the PR.

## SLICE D2 — the plan-level overflow menu and a Clear that asks

Right-align a `⋯` on the **Prep Plan title row** (`MenuViews.swift` ~452–469) holding the whole-plan actions:
**Handoff Prep · Paste Prep · Clear Prep Plan**. Retire the `PrepPlanHandoffControls` button row (~593–628)
and the standalone Clear button (~495–501).

**Clear currently fires immediately with no confirmation** — it calls `clearPrepPlan()` straight from the tap.
That is a destructive, un-undoable action on generated content. Add a `confirmationDialog` with a destructive
role, matching the section-clear pattern at
[`RecipePlaybookView.swift:89`](../../YesChefApp/RecipePlaybookView.swift).

## SLICE D3 — the Calendar day and week-cell menus

- **Day header** (`MealCalendarDayHeader` ~873–892): collapse the two `HandoffCopyPasteControls` into one `⋯`
  beside the Add menu, reading **Handoff Make-ahead · Paste Make-ahead · Handoff Complement · Paste
  Complement**. The sources already exist and are already per-day.
- **Week grid** (`MealCalendarWeekCell` ~734–777): each cell gets the same menu **for its own date**. The cell
  already receives a `summary` carrying `.date` and `.rows`, so it can build its own source — but today's
  `handoffAnchorItemID` reads `model.selectedDayRows`
  ([`MealCalendarHandoffSource.swift`](../../YesChefApp/MealCalendarHandoffSource.swift)), the **selected**
  day. **Parameterize the source by date** so a cell's menu acts on the cell you tapped, not on the selection.
- The cell is currently one large `Button`; place the menu in the header `HStack` where `Spacer(minLength: 0)`
  sits, and verify the nested control doesn't swallow the cell's own selection tap.

**There is no week-scoped hand-off.** Jon ruled this out explicitly — a week has no comprehensive ask.

## SLICE D4 — kill "Prep Plan" where it means Make-ahead

**Three concepts, deliberately distinct — only the leak is a bug:**

| Concept | Type / task | Correct name |
|---|---|---|
| Recipe → per-recipe make-ahead | `MakeAheadPlan`, `.recipeMakeAhead` | **Make-ahead** |
| Menu → woven, horizon-banded step rows | `PrepPlanStepRecord`, `.prepPlan` | **Prep Plan** |
| Calendar day → prose day strategy | `.mealPlanMakeAheadStrategy` | **Make-ahead Strategy** |

**Two sites leak "Prep Plan" onto the Recipe surface, and they are a coupled pair:**

1. [`RecipeDetailModel+Enrichment.swift:38`](../../YesChefApp/RecipeDetailModel+Enrichment.swift) —
   `ChatApplyAction<MakeAheadPlan>(title: "Create Prep Plan", …)`. Every *other* string in that same
   initializer already says make-ahead. → **`"Create Make-ahead"`**.
2. [`RecipeChatPanelSupport.swift:13`](../../YesChefApp/RecipeChatPanelSupport.swift) —
   `case .makeAhead: actionID = "Create Prep Plan"`.

> ⚠️ **`AnyChatApplyAction` defines `public var id: String { title }`**
> ([`RecipeChat.swift:604`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)). **The action's
> identity is its user-facing title.** `ChatFinalizeConfiguration` resolves Finalize by that string, so
> renaming one line without the other breaks Finalize on the recipe Make-ahead section **with no compile
> error**. Same family as the `editableSummary` no-op that bit ADR-0027 Amd-1
> ([[editable-summary-unchanged-commit-path]]). Change both in one commit and **extend the existing
> Finalize→action resolution test** (added in the PR #229 review) to cover the make-ahead section.

**Do not blanket-rename.** These stay as they are: the Menu section title, its alerts and empty state,
`MenuModels`' apply-action strings, `menuPrepPlanReviewItems`, `AIHandoffTaskType.prepPlan`,
`MenuChatContext`'s *"Current prep plan:"*, and every `PrepPlanStep` / `MenuPrepPlan` identifier. The Menu's
prep plan is a different artifact from a recipe's Make-ahead and is deliberately **composed from** it —
collapsing the words makes that relationship unsayable.

**Never touch:** the three `migrator.registerMigration` names containing "prep plan"
([`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) ~627, ~887, ~960). Migration
identifiers are frozen history.

**Also correct already, needing no change:** the Calendar's `"Copy Make-ahead Prompt"` and
`.mealPlanMakeAheadStrategy` → `"Make-ahead Strategy"`; and `AISettings`' **"Make-ahead & Prep Plans"**, whose
conjunction accurately covers both concepts.

**Dispatch 2 acceptance:** each Menu day and each Calendar day/week cell offers its four hand-off items scoped
to *that* day; a day-scoped prep ask returns steps that merge into the single master plan in horizon bands;
Clear asks first; the word "Prep Plan" no longer appears on any recipe surface; Finalize still resolves on the
recipe Make-ahead section (test).

**Dispatch 2 verification:** package `swift build` + Core tests for the scoped prompt construction and the
Finalize resolution test; then the generic app build + `scripts/check-drift.sh`.

---

# DISPATCH 3 — workbench lifecycle and hand-authored learnings

**Read first:** [`WorkbenchViews.swift`](../../YesChefApp/WorkbenchViews.swift) (list + swipe ~5–58,
title/notes editors ~334–372), [`WorkbenchModels.swift`](../../YesChefApp/WorkbenchModels.swift) (~66–86),
[`WorkbenchCore.swift`](../../YesChefPackage/Sources/YesChefCore/WorkbenchCore.swift) (`Workbench` ~5–31,
`updateWorkbenchTitle` ~400–413, `deleteWorkbench` ~415–421),
[`Schema.swift`](../../YesChefPackage/Sources/YesChefCore/Schema.swift) (~696–731),
[`MenuPrepPlanEditingViews.swift`](../../YesChefApp/MenuPrepPlanEditingViews.swift) (`LearningsSection`
~104–136), [`AIHandoff.swift`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift) (`Learning` ~136,
`LearningProvenance` ~170).

## SLICE E1 — edit-in-place title and notes

Drop the **Save Title** and **Save Notes** buttons (~348–372); commit on blur with a short debounce.

**Guard:** `updateWorkbenchTitle` throws on an empty title (~406). Edit-in-place must **revert to the last
good title** on empty rather than surfacing an error alert on every transient empty field during typing.
Notes have no such guard — empty is a legal value there (`nonEmptyWorkbenchText` maps it to `nil`).

## SLICE E2 — Active / Completed

**One nullable synced column: `workbenches.dateCompleted TEXT`.** A new synced table or column is cheap
([[synced-table-cost-calibration]]); register the change and **add it to the prod-promotion list in
`CURRENT_HANDOFF` in this same PR** ([[handoff-bump-rides-in-slice-pr]]).

1. A segmented **Active / Completed** control on `WorkbenchListView`, filtering on `dateCompleted == nil`.
2. **Search over the Completed list** (the Active list stays unfiltered — it is short by construction).
3. The swipe row gains **Mark Completed** alongside Delete; completing moves the row between lists.
4. **Decide and state in the PR:** whether a completed workbench still appears in the recipe detail's
   workbench picker and in chat context. Recommendation: **exclude from pickers, keep reachable by search** —
   completing is about clearing the working set, not hiding history.

## SLICE E3 — the delete confirmation tells the truth

**Deleting a workbench already does not delete recipes.** `workbenchCandidates.workbenchID … ON DELETE
CASCADE` drops only the join rows; `recipeID … ON DELETE SET NULL` points the other way
([`Schema.swift:711`](../../YesChefPackage/Sources/YesChefCore/Schema.swift)). The defect is the **copy**:
`deleteWorkbenchMessage` ([`AppMainLayout.swift:145`](../../YesChefApp/AppMainLayout.swift)) renders *"Delete
Braises and its 3 candidates?"*, which reads as deleting the recipes.

Rewrite it to say what happens — the workbench and its list go away, **the recipes stay in the library**.

**Jon's ruling on the adjacent case:** `workbenches.draftRecipeID → recipes ON DELETE SET NULL` means an
un-promoted working recipe outlives its workbench. **Leave it in the library.** No change; record the choice
in the PR so it is not "fixed" later by someone reading it as a leak.

## SLICE H — hand-authored menu learnings

Jon's want — *"6 lbs of chicken turned out to be the right amount and 2 pork shoulders was twice what we
needed"* — is distinguished from model output by **authorship**, and that is **already modeled**:
`LearningProvenance` has `.externalHandoff` and `.inApp`
([`AIHandoff.swift:170`](../../YesChefPackage/Sources/YesChefCore/AIHandoff.swift)).

**`.inApp` is constructed nowhere in the codebase.** It is an orphaned case with no producer, which is why
there is no way to write one. This is **not** a new table and **not** `Menu.notes` — dumping a new content
kind into a generic notes field is the thing [[decompose-notes-into-typed-homes]] forbids, and `Menu.notes` is
display-only today ([`MenuViews.swift:700`](../../YesChefApp/MenuViews.swift)).

1. **Add an Add affordance** to `LearningsSection`, writing `provenance: .inApp`. No schema change.
2. **Fix the empty state.** It currently reads *"Useful ideas returned from an AI handoff appear here"*
   (~114), which actively tells the cook this isn't a place they can write.
3. **Mark provenance in the row** so a hand-authored observation is distinguishable from a returned one.
4. **Feed them back out.** `knownLearningsBlock` exists only in the *recipe* hand-off context
   ([`AIHandoffContext.swift:76`](../../YesChefPackage/Sources/YesChefCore/AIHandoffContext.swift)) — menu
   learnings do **not** reach the menu's outbound ask. A quantity observation is precisely what should go out
   the next time that menu is planned, so wire menu learnings into `MenuChatContext`'s ask alongside the
   existing dedup instruction.

**Dispatch 3 acceptance:** title/notes commit without Save buttons and never clobber a good title with an
empty one; Active/Completed filters and searches, and the swipe completes; the delete dialog no longer implies
recipe deletion; a learning can be typed by hand on a Menu, is marked as hand-authored, survives sync, and
appears in the next outbound menu ask.

**Dispatch 3 verification:** package `swift build` + Core tests (the `dateCompleted` migration + filter, the
`.inApp` write path, the title-revert guard); then the generic app build + `scripts/check-drift.sh`.

---

## Explicitly out of scope

- **The sidebar-adaptable tab bar** — [ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md), its
  own decision and its own PR, **sequenced after Dispatch 1** so the shared expand control exists before the
  container moves underneath it.
- **Converging the chat presentation patterns.** Named in Slice F1 as three (inspector / `ChatWorkspaceSplit`
  / sheet); it is really **four** — the Menu's trailing overlay is a fourth. Dispatch 1.5 makes all of them
  share one *chrome* contract (`showsEmbeddedHeader`) without converging their *geometry*, which is the part
  that stays unscoped.
- **The Menu chat panel's geometry** — over vs. push vs. taking the playbook column. Deferred by Slice G2 on
  purpose; decide after the device pass on a panel that can close itself.
- **Any `dayOffset` on `PrepPlanStepRecord`.** Reverses ADR-0034; ruled out.
- **Week-scoped hand-off sources or contexts.** Ruled out.
