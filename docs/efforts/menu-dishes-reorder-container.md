# Effort: menu Dishes drag-to-reorder on the sanctioned reorder container (2026-08-19)

**Type:** One probe dispatch (S0, ~30 min, mostly device) then one build dispatch (S1–S3, one PR).
**No schema. No new tables, no columns, nothing added to the promotion list.** One Info.plist addition,
one view restructure, two deletions.
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass — S0 is *his*, and it
gates nothing else).
**Status:** **S0 complete (Jon, 2026-08-19, beta 5) — root cause found and confirmed by inversion.** The
nine-month "blocked on the beta" park was covering a local bug: two `.dropDestination` modifiers stacked on
one view, the inner shadowing the outer. Drag-and-drop works on beta 5. **S1–S3 are dispatchable as one PR.**
The only live unknown is the sectioned `reorderContainer(for:in:)` (ADR-0055 OQ3), which S2 probes as it
builds.
**Summary:** A menu dish row lifts but shows the not-allowed badge on drop, on Xcode 27 beta 5. Three causes
are tangled: an Xcode 27 beta drag-and-drop defect both apps parked and never re-checked, two undeclared
`UTType`s in our own Info.plist, and a Dishes list that was never built on the SDK 27 reorder API at all.
Separate them, then put the Dishes list on `.reorderable(collectionID:)` + `.reorderContainer(for:in:)` like
the prep plan and Playbook already are.
**Related:** [ADR-0055](../decisions/ADR-0055-drag-and-drop-on-the-sanctioned-reorder-path.md) (this effort
*is* ADR-0055) · [ADR-0038 Amd 5](../decisions/ADR-0038-external-llm-handoff.md) (the reorder rule, and the
sparse-rank exception that does **not** apply here) · [ADR-0012](../decisions/ADR-0012-menu-actionable-chat.md)
(`dayOffset` + `mealSlot`) · [ADR-0039](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md) (the
Dishes body).

**Read before starting:** ADR-0055 in full, then the SDK 27 `reorderable` reference in the
`swiftui-whats-new-27` skill (`references/reorderable.md`) — **do not write `reorderContainer` code from
memory**; the sectioned overload and `DropSession.reorderDestination(for:)` both have close-named siblings
with different signatures. Then `CURRENT_HANDOFF.md` Verification Pattern.

---

## Where the code is

| Thing | Location |
|---|---|
| Day section + row list (the `VStack` that fails) | `YesChefApp/MenuDetailSections.swift:154` (`MenuDaySection`), rows at `:228` |
| Interim Move Up/Down (to be retired) | `:229-236` (adjacency computation), `:322-345` (the swipe buttons) |
| Row `.draggable` (to be deleted) | `:316` |
| Stacked `dropDestination` pair | `:262` (recipe), `:270` (menu item) |
| Container that will host the reorder container | `YesChefApp/MenuDetailSections.swift:82` (`MenuDishList`'s `VStack`) |
| Payload types + `UTType`s | `:531-551` |
| Missing declarations | `YesChefApp/Info.plist:31` (`UTExportedTypeDeclarations`) |
| **The working precedent — read this first** | `YesChefApp/EditableRowsSection.swift:155-166` |
| Its call sites | `YesChefApp/MenuPrepPlanEditingViews.swift:204`, `YesChefApp/RecipePlaybookView.swift:284` |

---

## S0 — the discriminating probe (Jon, on device, beta 5)

**Not a build slice.** Three questions, each changing one variable. Record answers — with the beta build
number `27A5237l` — in the new `docs/KNOWN-ISSUES.md` created by S1.

1. ~~**Does an existing `reorderable()` surface still reorder?**~~ **ANSWERED YES — Jon, 2026-08-19, beta 5
   (`27A5237l`).** The reorder container works on beta 5.
   **Read it precisely: this proves the *single-collection* overload only.** Every `reorderContainer` in
   both repos is `for:` / `for:itemID:` with **no `in:`** — `EditableRowsSection.swift:162`,
   galavant `TripsScreen.swift:96` and `TripIdeasView.swift:163`. There is **no sectioned
   `reorderContainer` anywhere in either app**, and the sectioned overload is exactly what galavant's
   KNOWN-ISSUES listed as flaky and what **D3 depends on**. So: single-collection is healthy, sectioned is
   still unproven on beta 5, and the `.draggable`/`.dropDestination` path is still the prime suspect for
   the not-allowed badge. See S2's first checkpoint.
2. ~~**Does the Info.plist declaration alone fix the drop?**~~ **MOOT — answered sideways by Q3.**
   `MenuDraggedRecipe` is equally undeclared and drops fine, so the missing declaration cannot be what
   breaks the other type. **Consequence for sequencing: S1 no longer needs to ship isolated** (isolating
   this variable was its only reason to) — fold it into the S2/S3 PR per the batching rule.
3. **ANSWERED — Jon, 2026-08-19, beta 5, iPad: the Browse Recipes panel → day drop WORKS.**
   (*"Browse Recipes"* = the toolbar button of that name on menu detail, `MenuViews.swift:182`, and the
   panel it opens — **not** the in-app WebKit browser of ADR-0009.)
   - **Drag-and-drop is not broken on beta 5 in this app.** The platform lands drops. The nine-month beta
     park was covering a local bug.
   - **The `VStack` day container is a working drop destination.** ADR-0055 Finding 1 is **retracted**, and
     Galavant's `LazyVStack` fallback is live rather than disproven.
   - **The dish-row drag fails alone, for a local reason** — ADR-0055 **Finding 6**: `MenuDaySection` stacks
     two `dropDestination` modifiers on one view (`:262` inner, `:270` outer); the inner one works and the
     outer one is dead, so a `MenuDraggedMenuItem` finds no acceptor → not-allowed badge.
   - Jon also confirmed the dish row cannot be dragged **within** a day either — expected, that drag was
     never built (Finding 4).

4. **ANSWERED — Jon, 2026-08-19, beta 5, on device. The symptom inverted cleanly.** With `:262` and `:270`
   exchanged: a dish row now drags **between days**, and the Browse Recipes → day drop now **fails**. No
   residue either way. **ADR-0055 Finding 6 is confirmed as the mechanism**; the beta explanation is retired
   for this app; the rule is lifted to `jon-platform/docs/ios/ui-and-platforms.md`
   (*"Stacked `dropDestination` trap"*).
   - **The swap is not a fix and must not ship** — it trades one broken drag for the other. Both
     destinations are needed; the answer is **one** destination on the container (S3).
   - **Within-day reorder stayed dead, as predicted** (Finding 4 — no within-day drop target exists in the
     code). Independent of the stacked pair. **S2 is the only thing that delivers it.**
   - **Working-tree note for Codex:** Jon's swap may still be in the tree. **Check `git diff` on
     `MenuDetailSections.swift` and revert it before starting** — S2/S3 delete both of those modifiers
     anyway, and building on top of a hand-swapped pair invites a confusing merge.

---

## S1 — declare the UTTypes and stand up `KNOWN-ISSUES.md`

**Now bundles with S2/S3 into one PR.** It was held separate only to isolate S0 question 2, which Q3 made
moot. The Info.plist fix is demoted from prime suspect to **hygiene** — real (an `exportedAs` promise the
plist doesn't keep), but not the cause and not gating.

- Add a `UTExportedTypeDeclarations` entry to `YesChefApp/Info.plist` for `com.jon.yeschef.menu-recipe`
  (`UTTypeConformsTo` `public.data`, plus a `UTTypeDescription`). **`com.jon.yeschef.menu-item` does not need
  one — S2 deletes that type outright.** While here, note the prefix inconsistency against the existing
  `com.jonphillips.yeschef.database-backup` declaration; **do not renormalize it in this PR** (it is a
  separate, wider question and this PR should not carry it).
- Mirror the addition in `project.yml` (the Info.plist is generated — check `project.yml:84`, which already
  carries a `UTExportedTypeDeclarations` block) and run `xcodegen generate`.
- Create `docs/KNOWN-ISSUES.md`, header adopted from `galavant/docs/KNOWN-ISSUES.md` ("re-verify each on
  every new Xcode 27 beta; delete an entry when it's fixed upstream or we work around it"). Seed it with the
  drag-and-drop entry, **moved verbatim-in-substance out of** `docs/CURRENT_HANDOFF.md:161` (delete it there),
  restated with: both symptoms (ours = not-allowed, Galavant's = `System gesture gate timed out`), the
  cross-repo pointer to `galavant/docs/KNOWN-ISSUES.md`, and the explicit note that **Galavant's
  `LazyVStack` fallback is disproven** by our `VStack` surface failing the same way.

## S2 — Dishes on the reorder container

**Two checkpoints before writing anything else. Report both before continuing; do not improvise past
either.** S2 is now the first sectioned `reorderContainer` in either codebase, so it is also the probe S0
could not be.

**Checkpoint A (ADR-0055 OQ1) — does the container cross the child-struct boundary?** Does
`.reorderContainer` on `MenuDishList`'s `VStack` (`:82`) resolve a `.reorderable(collectionID:)` attached to
a `ForEach` inside the child `MenuDaySection` struct (`:154`)? Apple's sectioned example keeps both in one
view builder. If it does not cross, **stop and report** — the fix is inlining `MenuDaySection`'s body into
the container or having it vend its rows' `ForEach`, and that is a view-structure decision the architect
makes.

**Checkpoint B (new, from S0) — does the *sectioned* overload actually deliver moves on beta 5?** S0 Q1
proved only the single-collection overload healthy. Galavant tried
`.reorderable(collectionID:)` + `.reorderContainer(for:in:)` on beta 1 for this exact use case
(cross-section day move) and recorded it as flaky. Once the wiring compiles, confirm the `move` closure is
actually **called** with a sane `ReorderDifference` on a cross-day drag before building the write-back on
top of it. If it never fires, **report and stop at that point** — D7 still says ship the structural work,
but the architect decides how much of S2/S3 is worth completing blind.

Assuming it resolves:

- `.reorderable(collectionID: dayOffset)` on each day's rows `ForEach`.
- `.reorderContainer(for: MenuItemRowData.self, in: Int.self)` on `MenuDishList`'s `VStack`, keyed by
  `dayOffset`. Use the `itemID:` keypath overload if `MenuItemRowData`'s `Identifiable` conformance does not
  key on the `MenuItem` id you need to write back.
- In the `move` closure: `difference.sources` are the moved rows, `difference.destination.collectionID` is
  the destination day, `difference.destination.position` is `.before(id)` or `.end`.
- **Meal slot (ADR-0055 D4):** the moved item adopts the `mealSlot` of the row it lands next to — for
  `.before(id)`, that row's slot; for `.end`, the last row's slot; on an empty day, `.dinner`. Crossing a slot
  boundary is now **allowed** and is the intended behavior change.
- **`sortOrder` (ADR-0055 D6):** stays **contiguous** per `(dayOffset, mealSlot)`, rewritten as a generated
  collection. A cross-day move rewrites the source day's run and the destination day's run. **Do not** adopt
  ADR-0038 Amd 5's sparse 1024-stride ranks — that rule is for `Learning`'s grain, not this one.
- Delete: `.draggable(MenuDraggedMenuItem…)` (`:316`), the `MenuDraggedMenuItem` type and
  `UTType.yesChefMenuItem` (`:539-546`, `:550`) and its Info.plist entry from S1, the
  `.dropDestination(for: MenuDraggedMenuItem.self)` at `:270`, the `canMoveUp`/`canMoveDown` computation
  (`:232-236`) and the Move Up/Move Down swipe buttons (`:322-345`).
- Keep `model.reorderMenuItemWithinDay(itemID:direction:)` in the repository **only if** another caller
  exists; grep first, delete if the menu was its only consumer.

## S3 — the Browse Recipes panel → day drop lands where it was dropped

- Move `.dropDestination(for: MenuDraggedRecipe.self)` off `MenuDaySection` (`:262`) onto `MenuDishList`'s
  reorder container, and resolve placement with `DropSession.reorderDestination(for:)` (iOS 27) rather than
  appending at `.dinner`. `nil` from `reorderDestination` means the drop didn't hover a specific row —
  append to the day's end.
- Use the **`DropSession` overload**, not the legacy `(items, location: CGPoint) -> Bool` one both current
  destinations use.
- `MenuDraggedRecipe` and `UTType.yesChefMenuRecipe` **survive** and keep their S1 Info.plist declaration.
- This removes the stacked-`dropDestination` pair; after S2 and S3 there is exactly one drop destination on
  the container.

---

## Verification

Per `CURRENT_HANDOFF.md` Verification Pattern, plus:

- `xcodegen generate` is **required** — S1 touches `project.yml`/Info.plist and S2/S3 may add no new `.swift`
  files, but the Info.plist regeneration is not optional.
- Run the **`YesChefTests` app target** if any model/repository code changes (the `sortOrder` write-back
  does). Note the standing Codex-env gotcha: that target cannot run in Codex's sandbox; say so plainly rather
  than claiming a pass, and the architect runs it locally.
- **No simulator installs.** Jon does the device pass.

## For Jon's device pass

1. Drag a dish **within** a day → order persists across app relaunch.
2. Drag a dish **to another day** → lands at the drop point, not appended.
3. Drag a dish **across a meal-slot boundary** within a day (ADR-0055 D4 — the one deliberate behavior
   change). Does adopting the neighbor's slot read right, or does it need to be visible/confirmable?
4. **Swipe-to-Delete still works on a dish row** (ADR-0055 OQ2 — `reorderContainer` and
   `swipeActionsContainer()` arbitrate the same horizontal drag outside a `List`).
5. Drag a recipe from the **Browse Recipes** panel into a specific position in a day (iPad/wide layout).
