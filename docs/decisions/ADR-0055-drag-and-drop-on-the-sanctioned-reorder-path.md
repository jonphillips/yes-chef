# ADR-0055 — Drag-and-drop belongs on the sanctioned reorder path, and beta parks belong in a standing file

> **Two apps independently parked drag-and-drop on the same Xcode 27 beta-1 bug, wrote the park in two
> different files, never linked them, and never re-checked.** Nine months and four betas later the feature
> is still dead in both, one app's stated fallback is disproven by the other app's code, and the surface
> that actually fails in Yes Chef was never built on the sanctioned API in the first place. This ADR
> separates the platform defect from our own defects, puts the menu Dishes list on `reorderContainer`, and
> gives Yes Chef the standing beta-issues file it has been missing.

Status: **Proposed** — 2026-08-19. Origin: Jon, on Xcode 27 beta 5 (`27A5237l`), reporting that a menu dish
row lifts but shows the not-allowed badge on drop. Binds
[ADR-0038 Amendment 5](ADR-0038-external-llm-handoff.md) (which already states the reorder rule, scoped to
Learnings) to every remaining drag surface. Touches
[ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) (the menu Dishes body) and
[ADR-0012](ADR-0012-menu-actionable-chat.md) (`dayOffset` + `mealSlot`, the structure being reordered).
Cross-repo: Galavant carries the same defect and the same park.

## Context — what was actually lost

Nothing was lost. Two separate things were confused into one, and the confusion is the finding.

**Both apps parked drag-and-drop on Xcode 27 beta 1, in files that do not know about each other.**

- Yes Chef — `docs/CURRENT_HANDOFF.md`: *"Drag recipes from Browse into a meal (BLOCKED on iPadOS Beta 4).
  The pipeline is already wired … drag-and-drop is not firing reliably in the current betas. Retry after
  Beta 4."*
- Galavant — `docs/KNOWN-ISSUES.md`, *"List drag-and-drop never lands a drop (Xcode 27 beta 1)"*: the row
  lifts, the drop never completes, console logs `Gesture: System gesture gate timed out`. Three drop
  surfaces were tried for "drag an itinerary stop between days" — section headers, the iOS 27 reorder
  container, and row `.dropDestination` + an empty-day placeholder. All three failed. Backed out; the
  `StopMenu`'s Move-to-Day covers it. Re-check on a later beta.

Neither re-check happened. We are on beta 5.

### Finding 1 — Galavant's stated fallback is disproven by Yes Chef's code

Galavant's entry hypothesizes `List` / `UICollectionView` interception and records the fallback: *"render
the itinerary as a `ScrollView`/`LazyVStack` (no `UICollectionView` interception) instead of `List`; row
`.draggable` / `.dropDestination` work reliably there."*

**RETRACTED 2026-08-19 — this finding was wrong, and the correction points the other way.** It read Yes
Chef's failing `VStack` surface (`MenuDetailSections.swift:228/316/262-270`) as evidence that a non-`List`
container fails identically. Jon's beta-5 probe (D1 Q3) then landed a **successful** drop from the Browse
Recipes panel onto that same `VStack` day container. The container was never the problem; the `MenuItem`
drag fails for an unrelated, local reason (**Finding 6**).

**So Galavant's fallback is live, not disproven — and Yes Chef is now positive evidence *for* it.** A
non-`List` container works as a drop destination on beta 5, verified. What Yes Chef's probe *does* narrow is
the direction: its working case is a **`List` source** → **non-`List` destination**, while all three of
Galavant's failures were **`List` destinations** (section headers, the reorder container inside a `List`, and
rows inside a `List`). The `List`-as-**source** hypothesis is dead; the `List`-as-**destination** hypothesis
survives untouched. That is the sharpened claim the two trees have for each other, and it is the opposite of
what this finding originally said.

### Finding 2 — the two symptoms are different, and collapsing them is why both stayed parked

Galavant: the lift succeeds and the drop **times out** (`System gesture gate timed out`) — a gesture-arbitration
failure. Yes Chef: the lift succeeds and the cursor shows **not-allowed** — no destination ever *claims* the
payload, which is a type-matching failure. These are not the same bug, and "it's the beta" is only an
explanation for one of them.

### Finding 3 — Yes Chef has an independent, non-beta defect that produces exactly the not-allowed symptom

`MenuDetailSections.swift:548-551` declares both drag payload types with `UTType(exportedAs:)`:

```swift
static let yesChefMenuRecipe = UTType(exportedAs: "com.jon.yeschef.menu-recipe")
static let yesChefMenuItem = UTType(exportedAs: "com.jon.yeschef.menu-item")
```

Neither appears in `UTExportedTypeDeclarations` in `YesChefApp/Info.plist:31`, which declares exactly one
type: `com.jonphillips.yeschef.database-backup`. Note the **different bundle prefix** — this is not a typo in
an existing declaration, it is an absent one. `exportedAs` is a promise that the Info.plist declares the
type; when it doesn't, the type is never registered with the system.

**DEMOTED 2026-08-19 — a real defect, but not the cause.** `MenuDraggedRecipe` is *equally* undeclared and
its drop **works** (D1 Q3). Since both types are undeclared and only one fails, undeclared-ness cannot be
what distinguishes them. This stays a latent correctness bug worth fixing on hygiene grounds — an
`exportedAs` promise the Info.plist doesn't keep — but it is no longer a suspect, no longer gating, and no
longer needs to ship in isolation.

### Finding 4 — the menu never had drag-reorder to lose

Within-day ordering is swipe **Move Up / Move Down**, explicitly labelled *"Interim within-day reorder"*
(`:229-231`). The only `MenuDraggedMenuItem` drop target is the **day** container (`:270`), which performs a
cross-day `moveMenuItem`. Over the row list itself there is nothing that accepts the payload, so "I can pick
it up but can't drop it" is the code behaving as written. Jon's memory of working drag-and-drop is accurate
and points elsewhere (Finding 5), not at this surface.

### Finding 5 — the sanctioned API is already load-bearing in both apps

`YesChefApp/EditableRowsSection.swift:155-166` drives menu prep-plan steps and recipe Playbook rows with
`ForEach { … }.reorderable()` inside a plain `VStack` plus `.reorderContainer(for:itemID:)`. Galavant drives
`TripsScreen.swift:94` and `TripIdeasView.swift:87/149` off the same pair, with a shared
`ReorderDifference+Apply.swift`. Apple's SDK 27 guidance states the rule directly: **"A standalone
`.draggable` does not customize the reorder container; provide a `dragContainer` instead."** The menu Dishes
list is the one drag surface in Yes Chef still on the unsanctioned path, and it is the one that fails.

### Finding 6 — the stacked `dropDestination` pair shadows, and it explains the symptom exactly

`MenuDaySection` applies **two** drop destinations to one view (`:262-275`):

```swift
.dropDestination(for: MenuDraggedRecipe.self)   { … }   // applied first  → inner
.dropDestination(for: MenuDraggedMenuItem.self) { … }   // applied second → outer
```

The **inner** one works. The **outer** one is dead. That is precisely the not-allowed badge: a
`MenuDraggedMenuItem` payload hit-tests into a destination that only accepts `MenuDraggedRecipe`, finds no
acceptor anywhere in the tree, and the system reports "nothing here takes this."

This is a **local code bug** — not the beta, not the UTTypes, not the container type, not the `.draggable`
call. It also explains why the symptom differs from Galavant's (**Finding 2**): ours was never a gesture
failure at all.

**CONFIRMED by inversion — Jon, 2026-08-19, beta 5, on device.** Swapping the two modifier lines swapped
which drag works: the dish row now moves **between days**, and the Browse Recipes panel drop now **fails**.
Clean inversion, no residue. Promoted from hypothesis to mechanism, and lifted to the house rules
(`jon-platform/docs/ios/ui-and-platforms.md`, *"Stacked `dropDestination` trap"*).

**Do not ship the swap.** It is a strict trade — it moves the breakage from one drag to the other, and both
destinations are needed. The fix is **one** destination on the container (D5), which is what D3 and D5
deliver together.

**Within-day reorder remains dead after the swap, and that is expected, not residue.** There is no
within-day drop target in the code at all (**Finding 4**); the stacked pair was only ever about *cross-day*
move. The two defects are independent, and **D3 is the only thing that delivers within-day reorder** — the
one behavior in this whole investigation that has never existed.

## Decisions

**D1 — S0 is a discriminating probe, not a build slice.** Before any rewrite, answer three cheap questions on
beta 5 hardware, because each one splits "the beta" from "our code":

1. **ANSWERED YES — Jon, 2026-08-19, beta 5 (`27A5237l`).** An existing `reorderable()` surface still
   reorders, so the reorder container is healthy on beta 5 and the `.draggable`/`.dropDestination` path is
   the prime suspect. **But the question was under-specified and the answer is narrower than it reads:**
   every `reorderContainer` in Yes Chef *and* Galavant is the **single-collection** overload
   (`EditableRowsSection.swift:162`, `TripsScreen.swift:96`, `TripIdeasView.swift:163` — all `for:` with no
   `in:`). There is **no sectioned `reorderContainer` anywhere in either app.** The sectioned overload is
   precisely what Galavant recorded as flaky on beta 1 and precisely what **D3 depends on**, so it remains
   unproven. Consequence: **S2 is itself the sectioned probe** (see its Checkpoint B), and D7's pessimistic
   branch is narrowed but not closed.
2. Does declaring the two UTTypes in `Info.plist` (Finding 3), **and nothing else**, turn not-allowed into an
   accepted drop?
3. **ANSWERED — Jon, 2026-08-19, beta 5, iPad. The Browse Recipes panel → day drop WORKS.** Three
   consequences, all large: (a) **drag-and-drop is not broken on beta 5 in this app** — the platform lands
   drops, so the nine-month beta park was covering a local bug for at least the last several betas;
   (b) **Finding 3 is demoted** — the working payload type is equally undeclared; (c) **Finding 1 is
   retracted** — the `VStack` day container is a working drop destination, so Galavant's `LazyVStack`
   fallback is live rather than disproven. What remains is why the *dish-row* drag alone fails, which
   **Finding 6** answers.
4. **ANSWERED — Jon, 2026-08-19, beta 5. The symptom inverted cleanly.** Swapping `:262` and `:270` made
   cross-day dish drags work and broke the Browse Recipes drop. **Finding 6 is confirmed as the mechanism**,
   the beta explanation is fully retired for this app, and the rule is now in the house docs. Within-day
   reorder stayed dead, as predicted by Finding 4 — a separate defect that only D3 addresses.

**D2 — Yes Chef gets `docs/KNOWN-ISSUES.md`, and beta parks live there, not in `CURRENT_HANDOFF.md`.** This is
the process half of the ADR and it is not incidental. A beta park is a **standing condition with a re-check
trigger** — the same shape as a seam-ledger row — while `CURRENT_HANDOFF.md` is the dispatcher: swept for
completed work, read fresh on every dispatch, and deliberately lean. A standing condition parked in the
dispatcher gets skimmed past forever, which is precisely what happened. Move the drag entry
(`CURRENT_HANDOFF.md:161`) out, adopt Galavant's file header verbatim (*"re-verify each on every new Xcode 27
beta; delete an entry when it's fixed upstream or we work around it"*), and record every beta build number an
entry was re-checked against.

**D3 — the menu Dishes reorder is rebuilt on `reorderContainer`, regardless of what the probe says.** Sectioned
form: `.reorderable(collectionID: dayOffset)` on each day's rows `ForEach`, and
`.reorderContainer(for: MenuItemRowData.self, in: Int.self)` on `MenuDishList`'s `VStack`;
`difference.destination.collectionID` is the destination day. This collapses **within-day reorder and
cross-day move into one write path**, retires `MenuDraggedMenuItem` and the interim Move Up/Down swipe
buttons, and puts the menu on the same API as the prep plan, the Playbook, and Galavant's two reorder
surfaces.

**D4 — `collectionID` is the day, not day + meal slot; meal slot is inferred from the landing neighbor.** The
dropped item adopts the `mealSlot` of the row it lands next to; on an empty day, `.dinner`. Rationale: the
current "can't move past a slot boundary" constraint is an artifact of how Move Up/Down was implemented
(`:232-236` walks adjacent same-slot siblings), **not a product rule**. A composite `(day, mealSlot)`
collection key would freeze that artifact into the shape of the interaction and make dragging a dish from
lunch to dinner permanently impossible. This is the one place the fix **changes behavior**, so it is a named
decision rather than an implementation detail — and it is the item for Jon's device pass to judge.

**D5 — the Browse Recipes panel → day drop stays a drop, and moves onto the reorder container.** Keep
`.dropDestination(for: MenuDraggedRecipe.self)` but attach it to `MenuDishList`'s container and use
`DropSession.reorderDestination(for:)` (iOS 27) for placement, so a dragged recipe lands **where it was
dropped** instead of being appended at `.dinner`. This also removes two smells the rewrite should not
preserve: the **stacked pair** of `dropDestination` modifiers on one view (`:262` + `:270` — two destinations
on a single view is under-defined and should not survive), and the **legacy Bool/`CGPoint` overload** both
currently use.

**D6 — `MenuItem.sortOrder` stays contiguous. Do not harmonize it with ADR-0038 Amd 5's sparse ranks.**
Learnings use a sparse 1024 stride because a learning is a human move on a live two-device synced list where
an N-row rewrite is a real sync cost. `MenuItem.sortOrder` is already contiguous per `(dayOffset, mealSlot)`
and rewritten as a generated collection; a cross-day move rewrites the source day's run and the destination
day's run. Stated explicitly because the two rules now sit one ADR apart and the sparse one reads like the
"newer, better" pattern. It is not — it is the pattern for a different storage grain.

**D7 — if the probe says beta 5 still refuses drops, ship the structural rewrite anyway and gate only the
device pass.** *(Largely spent: D1 Q3 shows beta 5 lands drops. Retained for the one branch still open —
the sectioned `reorderContainer(for:in:)` of OQ3, which nothing in either codebase has yet exercised.)* The rewrite is correct code on a broken platform, and it removes three of our own defects
(Findings 3, 4, 5) that are currently hiding behind the platform's. Parking it a second time is exactly how
we arrived here with two divergent notes and a disproven fallback. No feature flag; record the outcome and
the beta build number in the new `KNOWN-ISSUES.md`.

## Consequences

- The interim Move Up/Down swipe buttons and `reorderMenuItemWithinDay(itemID:direction:)`'s
  `.earlier`/`.later` call site go away with D3. Keep the repository method if the meal-planner uses it;
  delete the menu's use of it.
- `MenuDraggedMenuItem` and `UTType.yesChefMenuItem` are deleted by D3. `MenuDraggedRecipe` and
  `UTType.yesChefMenuRecipe` survive (D5) and **must** gain their `UTExportedTypeDeclarations` entry.
- Schema-free. No migration, no new table, no sync surface.
- **Not in scope:** the Learnings reorder (already correct per ADR-0038 Amd 5), the recipe editor's
  ingredient/instruction ordering, and the meal-planner calendar.

## Open questions

**OQ1 — does `reorderContainer` reach a `ForEach` that lives inside a child `View` struct?** Apple's sectioned
example keeps the `ForEach`es and the container in one view builder. Ours does not: `MenuDishList`'s `VStack`
would hold the container while each `.reorderable(collectionID:)` sits inside a separate `MenuDaySection`
struct (`:154`). If SwiftUI's reorder container does not resolve across that boundary, `MenuDaySection` must
be inlined into the container or restructured to expose its rows' `ForEach`. **This is the first thing the
slice resolves** — it decides whether D3 is a 60-line change or a view-structure refactor, and everything
else waits on the answer.

**OQ3 — is the sectioned `reorderContainer(for:in:)` sound on beta 5?** Opened by D1's answer: nothing in
either codebase exercises it, and the only data point we have is Galavant's beta-1 "flaky." This is not
resolvable by probe — the cheapest way to answer it *is* to build D3, which is why S2 carries it as an
explicit checkpoint rather than an assumption. If it turns out unsound, D7 governs: the structural work
still ships, and how much of S3 is worth completing blind is an architect call at that moment.

**OQ2 — does a `reorderContainer` compose with `swipeActionsContainer()`?** `MenuPlaybookColumnView.swift:53`
already marks the enclosing scroll view for swipe actions, and the dish rows carry `.swipeActions` for
Delete. Both features arbitrate the same horizontal-drag gesture outside a `List`. Verify Delete still swipes
after D3, on device.
