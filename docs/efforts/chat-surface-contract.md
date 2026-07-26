# Effort: The chat panel gets a surface contract — one descriptor, no silent defaults

**Type:** App-layer structural refactor + one live defect. **No Core, no schema, no new UI.** The panel view
is already shared and stays exactly as it is; what changes is how a host *asks* for it.
**Status:** **Ready** — written 2026-07-26 from the architect review of PR
[#235](https://github.com/jonphillips/yes-chef/pull/235) (ferry Dispatch 1.5 Slice G5).
**Summary:** `RecipeChatPanel` is rendered by eight call sites across four surfaces. It takes eight
parameters, **six of them defaulted**, so a new surface opts out of every behavior by saying nothing — and
four of them have. Replace the loose argument list with one `ChatSurface` descriptor that forces each host to
answer the questions that have so far been answered by omission, and fix the dismiss defect that omission
already shipped.
**Related:** [ADR-0045](../decisions/ADR-0045-onboard-path-stays-viable.md) + its
[Amendment 3 codicil](../decisions/ADR-0045-onboard-path-stays-viable.md#codicil-to-amendment-3--the-embedded-panel-header-contract-2026-07-26)
(the header contract this makes portable) · [`dogfood-ferry-2026-07-25.md`](dogfood-ferry-2026-07-25.md)
Dispatch 1.5 (G1–G5 shared the header; this shares the contract around it) ·
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) (**the sequencing partner** — see Sequencing).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).

---

## The finding

Dispatch 1.5 did the hard half correctly. `RecipeChatPanel`
([`RecipeChatWorkspace.swift:226`](../../YesChefApp/RecipeChatWorkspace.swift)) is genuinely one view, and
G1–G5 settled its header once for everybody. That is why G5 was worth doing before the treatment spread.

The drift that remains is not in the panel. It is in the **eight argument lists** that construct it:

| Call site | embedded header | Discuss | dismiss | finalize | focus |
|---|---|---|---|---|---|
| [`RecipeDetailView.swift:256`](../../YesChefApp/RecipeDetailView.swift) — Recipe, iPhone sheet | — | ✓ | ✓ | ✓ | ✓ |
| [`RecipeDetailView.swift:282`](../../YesChefApp/RecipeDetailView.swift) — Recipe, iPad inspector | ✓ | ✓ | ✓ | ✓ | ✓ |
| [`MenuViews.swift:391`](../../YesChefApp/MenuViews.swift) — Menu, embedded tool | ✓ | — | ✓ | ✓ | — |
| [`RecipeChatWorkspace.swift:102`](../../YesChefApp/RecipeChatWorkspace.swift) — `ChatWorkspaceSplit` column (Calendar + Workbench ×2) | ✓ | — | — | — | — |
| [`MealCalendarViews.swift:51`](../../YesChefApp/MealCalendarViews.swift) — Calendar, iPhone sheet | — | — | — | — | — |
| [`MealCalendarViews.swift:156`](../../YesChefApp/MealCalendarViews.swift) — Calendar day, iPhone sheet | — | — | — | — | — |
| [`WorkbenchViews.swift:211`](../../YesChefApp/WorkbenchViews.swift) — Workbench, iPhone sheet | — | — | — | — | — |
| [`WorkbenchCompareView.swift:204`](../../YesChefApp/WorkbenchCompareView.swift) — Compare, sheet | — | — | — | — | — |

**Every defect the G5 review found is a row in that table, not a bug in the panel.**

1. **Four sheets have no dismiss control at all.** With `showsEmbeddedHeader: false` and `onDismiss: nil`,
   the embedded header's `✕` never renders *and* the toolbar's `if let onDismiss { Button("Done") }`
   ([`RecipeChatWorkspace.swift:416–420`](../../YesChefApp/RecipeChatWorkspace.swift)) never fires. Calendar,
   Calendar-day, Workbench and Compare on iPhone are **swipe-to-dismiss only**. Nobody decided that; it is
   what a defaulted `nil` does.
2. **Three surfaces inherit Recipe's copy.** `selectSection` is wired only from `RecipeDetailView`, but the
   shared `ChatEmptyState` tells all four *"choose a section from Discuss."* G5's fix #3 patches the string;
   it does not stop the next surface from inheriting the next Recipe-shaped assumption.
3. **Three split sites share one detent identity.** `ChatWorkspaceDetent.storageKey`
   ([`RecipeChatWorkspace.swift:8`](../../YesChefApp/RecipeChatWorkspace.swift)) is a single `@AppStorage`
   string read at [`MealCalendarViews.swift:25`](../../YesChefApp/MealCalendarViews.swift) and
   [`WorkbenchViews.swift:106`](../../YesChefApp/WorkbenchViews.swift), while `ChatWorkspaceSplit` is
   instantiated **three** times ([`MealCalendarViews.swift:38`](../../YesChefApp/MealCalendarViews.swift),
   [`WorkbenchViews.swift:143`](../../YesChefApp/WorkbenchViews.swift) and
   [`:283`](../../YesChefApp/WorkbenchViews.swift)). Collapsing the chat column in the Workbench collapses it
   in the Calendar. The ferry doc logged this as pre-existing and out of G5's scope — **this is its home**,
   because it is an identity question, and identity is what a descriptor carries.
4. **Tier propagation is implemented twice.** `ChatWorkspaceSplit` takes an `activeTierChanged` closure and
   wires it internally ([`RecipeChatWorkspace.swift:116–122`](../../YesChefApp/RecipeChatWorkspace.swift));
   `WorkbenchCompareChatSheet` hand-rolls the identical `.onAppear` + `.onChange(of: chatModel.activeTier)`
   pair at its own call site ([`WorkbenchCompareView.swift:199–211`](../../YesChefApp/WorkbenchCompareView.swift)).
   The Calendar sheets do neither. One behavior, two implementations, one omission.

**The shape of the problem, stated once:** a defaulted parameter is a decision made by whoever *doesn't* type
it. Six of them means a new surface is silently wrong in six ways on the day it is added, and the wrongness
surfaces months later as "the Calendar's chat is different." That is the same disease
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md) opens by naming one level up — *"the taxonomy
is encoded four times, in three incompatible partitions"* — and it wants the same cure: one encoding that
callers cannot route around.

---

## What this effort is *not*

- **Not a redesign.** No pixel moves except S1's four new dismiss controls. If a device pass shows any
  surface looking different other than gaining a `Done`, that is a regression, not a win.
- **Not a merge of the apply-action catalogs.** `applyActionCatalog(for:)` is correctly per-model — the verbs
  genuinely differ per surface, and their `requiresSubject` asymmetry is exactly what G5's fix #1 had to
  untangle. Collapsing them would rebuild that confusion. They stay per-host; the descriptor only *carries*
  them.
- **Not a change to `RecipeChatContext`.** It is already the right shape: a closed enum whose `switch` sites
  fail to compile when a case is added ([`RecipeChat.swift:113`](../../YesChefPackage/Sources/YesChefCore/RecipeChat.swift)).
  Leave it alone. It is the model-side proof that this pattern works.
- **Not Core, not schema, not sync.** Nothing here enters `YesChefPackage`.

---

## S1 — The four sheets get a dismiss control

**Ship this first and independently of the rest.** It is a live defect on three surfaces and it does not
depend on the descriptor landing.

Give [`MealCalendarViews.swift:51`](../../YesChefApp/MealCalendarViews.swift),
[`:156`](../../YesChefApp/MealCalendarViews.swift), [`WorkbenchViews.swift:211`](../../YesChefApp/WorkbenchViews.swift)
and [`WorkbenchCompareView.swift:204`](../../YesChefApp/WorkbenchCompareView.swift) an `onDismiss` that clears
the presenting `item:` binding, so the existing `Done` at `.topBarLeading` renders. Do **not** invent a new
control — the modal contract already exists in the panel and Recipe already uses it; these four call sites
simply never opted in.

**Acceptance:** every modal presentation of the panel has a visible, labelled dismiss. Swipe-down keeps
working. No embedded/column presentation changes.

## S2 — `ChatSurface`: one descriptor, no defaults on decided questions

Introduce an app-layer `ChatSurface` value that every host constructs, and reduce `RecipeChatPanel` to
`RecipeChatPanel(chatModel:surface:)`. Shape (names are a proposal, not a mandate — the constraint is what
must be *answerable*, not what it is called):

```swift
struct ChatSurface {
  var applyActions: [AnyChatApplyAction]
  var sections: Sections            // .none | .switchable(select:active:)
  var dismissal: Dismissal          // .hostOwned | .panelOwned(() -> Void)
  var presentation: Presentation    // .modalSheet | .embeddedHeader | .column(detent: DetentIdentity)
  var finalization: ChatFinalizeConfiguration?
  var focusesInputOnAppear: Bool
  var activeTierChanged: (ModelTier) -> Void
}
```

**The rules that make this worth doing** — without them it is a rename:

- **`sections`, `dismissal` and `presentation` take no default.** These are the three that have been answered
  by omission. A new surface must state them. Everything else may default, because a wrong default there is
  visible immediately rather than months later.
- **`presentation` replaces the `showsEmbeddedHeader` + `onDismiss` pair**, which currently encode the same
  question twice and can disagree — the disagreement *is* defect 1. Make the illegal combination
  unrepresentable rather than documented.
- **`sections` carries `select` and `active` together.** They are one fact; today they are two optionals that
  can be set independently.
- **Fold the tier propagation in.** `ChatWorkspaceSplit`'s `activeTierChanged` and
  `WorkbenchCompareChatSheet`'s hand-rolled `.onAppear`/`.onChange` pair become one field the panel honors,
  and the duplicate at [`WorkbenchCompareView.swift:199–211`](../../YesChefApp/WorkbenchCompareView.swift)
  is deleted.
- **`ChatWorkspaceSplit` builds its own `ChatSurface`** for the column it owns, so its three hosts keep
  passing it a reader and apply-actions and nothing more.

**Acceptance:** eight call sites each construct a `ChatSurface`; `RecipeChatPanel` has two parameters; adding
a hypothetical ninth surface fails to compile until dismissal, sections and presentation are stated.

## S3 — The detent gets a per-surface identity

`ChatWorkspaceDetent.storageKey` becomes a `DetentIdentity` carried on `ChatSurface.presentation.column`,
so the Calendar and each Workbench split persist independently. Migrate the existing
`"recipeChatWorkspaceDetent"` value forward as the Calendar's key so a dogfood device does not reset to
`.balanced` on first launch; the Workbench sites may start fresh.

**Do this in the same PR as S2, not before it** — the identity has nowhere to live until the descriptor
exists, and doing it standalone means touching the same three call sites twice.

## S4 — A per-surface resolution test

This is the slice that makes the refactor safe, and it is the reason the effort is worth more than its diff.

Add a test in `YesChefAppTests` that constructs each surface's `ChatSurface` and asserts the resolved
contract — for each of the eight, that dismissal is stated, that `sections` matches whether the host actually
provides a switcher, and that column presentations carry distinct detent identities.

**This is the artifact that would have caught defect 1 on the day it appeared.** The panel currently has no
direct coverage: `ChatAssistantSelectionTests` and `OnboardChatFinalizationTests` touch chat obliquely, and
nothing asserts what any surface resolves to. **A refactor across eight call sites with no tests is how a
silent regression ships** — do not land S2 without S4.

---

## Sequencing

**This lands after ferry Dispatch 1.5 (PR #235) and before
[ADR-0046](../decisions/ADR-0046-sidebar-adaptable-app-shell.md).** That window is not arbitrary:

- **After 1.5**, because G1–G5 are what made the header worth sharing. Refactoring the contract around a
  header that was still leaking chrome into host toolbars would have hardened the wrong shape.
- **Before ADR-0046**, because that ADR moves every one of these eight call sites. Doing the descriptor first
  means the container rewrite relocates **one type** instead of eight argument lists; doing it after means
  the new shell inherits the same defaulted-omission shape and reproduces the drift inside a rewrite with no
  test coverage to catch it. This is the same argument the ferry doc makes for landing G5 before ADR-0046,
  applied one layer out.

It does **not** block Dispatch 2 or 3, and it shares no files with either (2 is hand-off controls, 3 is
workbench lifecycle). If appetite favors the ferry track continuing, S1 can ship alone as a fast-follow on
#235's heels and S2–S4 hold their slot ahead of ADR-0046.

**No ADR.** This makes no product decision — it enforces one already made (ADR-0045 Amendment 3's codicil:
*one contract, both presentations*) across the surfaces that were never asked to honor it.

## Verification

Generic app build (elevated, no signing) + `scripts/check-drift.sh` — which now covers S4. No package tests;
nothing touches Core. **No simulator installs.** Jon device-passes on `iPad Pro 13-inch (M5)` (both
orientations) + `iPhone 17 Pro`, checking all four surfaces in both presentations: the four new dismiss
controls, and that nothing else moved.

## Open for Jon

1. **Does the Menu's chat want a Discuss switcher?** Once `sections` is a stated field, "Menu has no
   sections" becomes an explicit answer rather than an omission — and it is worth confirming that is the
   answer you want, since the Menu is the surface closest to Recipe in shape.
2. **Do the two Workbench splits share a detent, or is that three independent identities?** S3 assumes three.
   Sharing between the Workbench detail and Compare is defensible; sharing with the Calendar is not.
