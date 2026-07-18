# Done Log

Archive of completed efforts, the implemented-behavior checkpoint, and strategic
background. **Read-rarely, append-on-approval.** No dispatch instruction should ever
point the coding agent (or the architect during a dispatch) at this file — it is a
human-reference archive, not a working-context source. `docs/CURRENT_HANDOFF.md` stays
lean precisely because this history lives here instead.

Newest first.

---
## ADR-0041 Slice 1 — per-section Playbook toolbar + edit sheet · recipe Learnings loop · hand-off regenerates fresh + learning dedup

**✅ Merged to main — PRs [#199](https://github.com/jonphillips/yes-chef/pull/199), [#200](https://github.com/jonphillips/yes-chef/pull/200), [#202](https://github.com/jonphillips/yes-chef/pull/202) (+ [#201](https://github.com/jonphillips/yes-chef/pull/201) doc, [#203](https://github.com/jonphillips/yes-chef/pull/203) recovery), 2026-07-18. App-build gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED); core tests green. Device pass owed (Jon).** App-layer + Core; **no schema / migration** (reuses the existing enrichment content, the ADR-0024 review sheet, and the already-synced ADR-0038 `learnings` table). A dogfood arc off ADR-0041's acceptance — four efforts:

1. **ADR-0041 S1 — section-scoped Playbook controls (PR #199).** State-aware per-section toolbar (D2) rendered in the expanded content (collapsed = title + fill-dot + chevron only); per-section **Edit** sheet (D4) lifted off the monolithic `RecipeEditorView`; **Clear** relocated to overflow + sheet. Make-ahead's existing external hand-off moved into its section (empty → Hand off · Paste; filled → Edit · **Hand off again**); the column-top duplicate retired. Chef It Up + Serve With stay free of external controls until S2. Brand-free copy (D7). Architect review folded three fixes into the branch: Serve-With writes moved into `RecipeRepository` (out of the app layer) with an ID-preservation test; make-ahead/chef-it-up rendered as bullets when multi-line; "Redo" → "Hand off again".
2. **Recipe Learnings full loop (PR #200).** ADR-0038 Amd 1's two-part return had a write path but **no recipe display** — learnings were write-only-into-the-void. Added `LearningRepository.learnings(sourceType:sourceID:)`, `RecipeDetailData.learnings` on the observed `RecipeDetailRequest`, and a shared `LearningsSection`/`LearningRow` (generalized from the menu's `MenuLearningsSection`, now used by both). Gated off on recipes when empty so the column stays calm ([[automation-decays-near-the-stove]]).
3. **ADR-0038 Amendment 4 — Learning ingest append-only, curation deferred (PR #201, doc).** Records the dogfood finding: learnings append with no dedup/merge, and the outbound context omits existing learnings so the model re-derives them. Near-term mitigation shipped (below); the smart LLM curation pass (reconcile incoming-vs-existing, review sheet surfaces existing) is on the record as **deferred** — the exact-dedup floor "must not become the reason the smart pass never gets scheduled."
4. **Hand-off regenerates fresh + learning dedup (PR #202).** Jon's dogfood: "Hand off again" was feeding the current make-ahead back into its own prompt (a refine, not a regenerate) and learnings duplicated. Fix: `RecipeChatRecipeContext.serialized(includingCurrentMakeAhead:)` (default `true` for in-app chat; the hand-off passes `false`) so a re-hand-off regenerates **fresh** — refinement belongs in the live ChatGPT thread, not a re-export. Plus `LearningRepository.insertNew` deterministic exact-match dedup on ingest (against stored + within batch; source-agnostic, so menu/meal-plan benefit too) and an outbound "return only new learnings" instruction. See [[handoff-stateless-both-directions]].

**⚠️ Stacked-merge recovery (PR #203).** #200 and #202 were stacked PRs, each **based on the branch below rather than main** — so merging them landed their commits in the intermediate branches, not main. GitHub marked them "merged," but only #199/#201 actually reached main; the Learnings loop + fresh-regen/dedup code was absent (main still had the old `MenuLearningsSection`, no `insertNew`). PR #203 3-way-merged the full stacked branch onto main, **preserving ADR-0038 Amd 4** (the raw diff's −37 was an artifact of the branch predating #201). Lesson: **base stacked PRs on main, or confirm the merge commit is an ancestor of main before treating it as shipped** ([[verify-local-fix-reached-merge]]). Stale branches `codex/recipe-learnings-full-loop` + `codex/adr-0041-s1-playbook-section-toolbar` to be deleted.

---
## Dogfood polish batch — yield-fraction scaling · scalar→30 · grocery aisle picker · Workbench→Reference

**✅ Merged to main — yes-chef PR [#198](https://github.com/jonphillips/yes-chef/pull/198), 2026-07-17. App-build gate green (`generic/platform=iOS` → BUILD SUCCEEDED) + `check-drift` green (SwiftLint; 358 package tests). Device pass owed (Jon).** App-layer + Core; **no schema / migration** (every field/table/placement pre-existed). From Jon's 2026-07-16 device pass — four unrelated small fixes in one PR.

1. **Vulgar/mixed-fraction yield scaling (Core).** The fraction/mixed-number parse was extracted from `IngredientParser` into a shared Core helper both parsers call, and a pure `YesChefPackage` function scales the leading quantity **in place**, preserving trailing unit words and ranges ("2½ cups" → "5 cups"; "4–6 servings" → "8–12 servings"). Also kept the `ServingParser` Double fix. Fixes existing recipes with **no migration** (stored `Recipe.servings` stays nil).
2. **Scale multiplier range 10 → 30 (app).** One shared `maximumWholeMultiplier` now drives both the wheel `ForEach` and `ScaleFraction.nearestSelection`, so a >10× scale no longer snaps back on reopen; covers recipe / menu-item / meal-plan via `ScaleContext`.
3. **Grocery aisle → Picker (app).** The free-text Aisle field became a picker over `GroceryStoreArea.canonicalAreas`, preserving any existing non-canonical value as a selectable custom row.
4. **Workbench "Archive All candidates" → "Move to Reference" (Core + app).** Curated-out candidates now land as Reference (`setLibraryPlacement(.reference…)`) instead of archived; candidate links still cleared; button / case / confirmation copy renamed. Replaces Archive (Jon's call — not both). Note-only candidates skip, as before.

---
## ADR-0039 — Amendment 2 / Slice D + Amendment 3, menu adopts the Playbook column (permanent; tools slide over)

**✅ architect-approved + Jon device-confirmed + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-16.** yes-chef PR [#197](https://github.com/jonphillips/yes-chef/pull/197). **This closes ADR-0039 Amendment 2 — all four slices (A–D) shipped — under the Amendment 3 correction.** **App-layer only — no schema / migration** (view composition + local `@AppStorage`; prep-plan/learnings/handoff data all pre-existed).

**The menu now shares the recipe's grammar.** `MenuDetailReader` splits (≥ 820pt) into **Body** = `MenuDetailHeader` + `MenuExternalProjectField` + `MenuDishList` + `MenuPlacementList` (always in view) and a **Playbook companion** = `MenuPrepPlanSection` + `MenuLearningsSection` (the ChatGPT handoff rides inside the prep-plan section). `MenuWideColumnLayout` does the 2-region width math (Body 0.30 floor + detent-driven Playbook remainder) over the *shared* `RecipePlaybookColumnDetent`/`RecipePlaybookResizeHandle`/`RecipeWideColumnMetrics` — no fork. Compact is one scroll, Body then Playbook, unchanged.

**Amendment 3 corrections (the reason this isn't a plain "Slice D").** Slice D first shipped as a toggle build (PR #197's first commit) whose device pass exposed two structural problems: two look-alike trailing-sidebar toolbar buttons (Show/Hide Playbook vs. Browse Recipes), and `.inspector` **pushing** rather than overlaying — opening Browse squeezed Body + Playbook + Browse into three cramped columns. [ADR-0039 Amendment 3](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-3--2026-07-16-the-menu-playbook-is-permanent-and-transient-tools-go-over-it-not-beside-it) resolved both:

- **D6 — the menu Playbook is permanent.** No toggle, no `isPlaybookColumnVisible`; always co-visible on wide, sized only by drag + the Comfortable/Wide detents. The recipe keeps its toggle (deliberate asymmetry — the Dishes body gains nothing from full width, the recipe body can). Threshold raised 640→**820** (`MenuPlaybookColumnMetrics.twoColumnThreshold`) so a ~700pt multitasking pane falls back to compact instead of a cramped permanent two-column.
- **D6 — width persists per-menu; service date seeds only the first open.** Replaced the single global detent key with a `[menuID: detent]` JSON map in one `@AppStorage`; `currentPlaybookDetent` reads `map[menu.id] ?? (isServiceDateTodayOrPast ? .comfortable : .wide)`, so the service date sets the initial detent only until the first drag on that menu, after which the stored width wins and the heuristic never overrides it. This resolves the global-vs-per-menu sub-decision the Slice D dispatch had flagged (first-review finding #1).
- **D7 — transient tools slide *over*, not *in*.** Browse Recipes + Ask moved off `.inspector` onto a trailing `.overlay` above a stable Body + Playbook layout (`.move(edge: .trailing)` transition; `menuToolContent` builder shared by the overlay and the compact `.sheet`). The reader underneath never reflows. The recipe's Ask stays on `.inspector` for now (noted follow-up — no Browse collision there).
- VoiceOver label parameterized on the shared handle (menu reads "Dishes and Playbook split").

**Scrim removed to keep the body interactive (Jon's edit, `ac7629f`).** The overlay initially had a tap-to-dismiss scrim; Jon removed it because the whole point of the *over* presentation is to let recipes be **dragged from Browse into a meal**. Discovery during review: that pipeline is **already wired end-to-end** — `MenuDishDayList` carries `.dropDestination(for: MenuDraggedRecipe.self) { model.addRecipesToMenu(…) }` and the browser rows are `.draggable(MenuDraggedRecipe(…))` — so removing the scrim unblocks a working drag-recipe-into-a-day flow, not just a future one. Dismissal is now via the toolbar toggle (or selecting a recipe).

**Architect review (PR #197) — approve; build green; device-confirmed.** Amendment 3 landed faithfully; the per-menu detent + service-date seed resolves first-review finding #1 cleanly; the scrim removal is correct and better-motivated than "future." Three minor follow-ups Jon dispatched to Codex, **folded into this same PR**: (2) gate the trailing overlay on `usesToolOverlay` (not just `toolOverlay != nil`) so a size-class flip to compact can't strand a 380pt panel; (3) drop the redundant `.regularMaterial` under the opaque browser panel, add a leading separator/shadow so it reads as floating; (4) delete the now-unused `MenuDetailInspector.title` (only the removed scrim referenced it). Non-blocking, cosmetic/robustness only — no behavior-affecting logic. First-review findings #2 (compact prep-plan expansion) left as a device-pass knob; #3 (VoiceOver label) fixed in the Amendment 3 pass.

**Follow-on left on the board (Jon's to pick).** Drag-recipe-into-a-meal is now functional; the remaining work is confirming/polishing the E2E interaction and any meal-planner integration — queued in CURRENT_HANDOFF Ready Efforts, not inferred as Next Up.

---
## ADR-0039 — Amendment 2, Playbook Peek detent dropped (two detents)

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon device-confirmed (handle cycles Comfortable ↔ Wide, no sliver, toolbar Hide restores) — 2026-07-16.** yes-chef PR [#196](https://github.com/jonphillips/yes-chef/pull/196). A small follow-up off Slice C's device pass — **not** its own Amendment slice. **App-layer only — no schema / migration** (view + local `@AppStorage` state; **D = menu adopts the Playbook column, still parked**).

**Why Peek went.** Slice C's device pass surfaced a pre-existing Slice B detent-math gap: **Peek** = ⅓ of an already-small remaining width, with no content floor mirroring the Directions floor, so at its minimum it rendered a degenerate sliver (the Playbook header wrapped one char per line, Ask clipped). The resize handle was deliberately built *not* to hide the column (drag-to-zero is "fiddly and easy to do by accident"); the **toolbar Show/Hide button is the honest hide**, so a near-hide detent was both redundant and broken. Two detents + binary toolbar-hide is the Xcode/VS Code grammar without the broken corner.

**The change (2 lines, one file).** `case peek` removed from `RecipePlaybookColumnDetent` (`RecipePlaybookColumnLayout.swift`); the enum is now `comfortable · wide`, both `switch` bodies updated, and the resize-handle VoiceOver hint changed to "Cycles between comfortable and wide Playbook widths." No width constants touched: `playbookWidth(for:)` derives its fraction from `(index+1)/count`, so with two cases it auto-rebalances — **Comfortable → ½ max, Wide → full max** — and `next`/`previous`/`nearestDetent` keep working over `allCases`.

**No migration.** `currentPlaybookDetent`'s getter (`RecipeDetailView.swift:650`) reads through `RecipePlaybookColumnDetent(rawValue:) ?? .comfortable`, so any device with `"peek"` persisted from Slice B falls back to Comfortable on next open — confirmed intact. Grep found zero remaining `.peek` / `"peek"` references in Swift.

**Architect review (PR #196) — approve, no on-branch code changes.** Enum-count-driven math self-adjusts correctly; the persisted-`"peek"` fallback holds; VoiceOver hint updated; clean removal. Two notes: (1) **non-blocking doc nit fixed in this PR** — ADR-0039 §D4's detent example still listed "(e.g. Peek / Comfortable / Wide)"; struck to `(Comfortable / Wide)` with an Amendment 2 note. (2) **Pre-existing, not this PR** — the `accessibilityAdjustableAction` wraps around (increment from Wide → Comfortable) rather than clamping at ends; benign with two detents, left for parity with the chat-workspace precedent. **Device-pass watch (Jon):** Comfortable is now ½-max (was ⅓-max under three detents, i.e. it *grows*), so confirm it still clears the Playbook-header content floor on the smallest target; handle cycles only Comfortable ↔ Wide with no sliver reachable; toolbar Hide fully collapses and restores the last detent.

---
## ADR-0039 — Amendment 2 / Slice C, recipe header nests beside Ingredients

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon device-confirmed running (3 detents exercised on `iPad Pro 13-inch (M5)`, screenshots) — 2026-07-16.** yes-chef PR [#195](https://github.com/jonphillips/yes-chef/pull/195) (Codex branch/PR title says "A2 S3" — same slice; the doc series calls it **Slice C**).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): **third of four** Amendment 2 slices — corrects Slice A's full-width header band to the real Paprika **column-scoped** composition. **App-layer only — no schema / migration** (pure view composition; Slice B's `@AppStorage` keys untouched). **D = menu adopts the column, still parked.**

**The full-width band + divider are gone.** `RecipeReaderView.body`'s two-column branch is now just the three columns filling full height (`.frame(width:height:alignment: .topLeading)`); the outer `VStack`/`header`/`metadata`/`Divider` strip that spent the whole recipe's top edge on identity is deleted. Ingredients and Playbook both rise to the top edge — the vertical reclaim the band only half-delivered.

**Header nests at the top of the Directions column only.** A new `wideColumnHeader(_:)` puts `header` + a 96 pt cover photo side-by-side, stacked above `metadata(_:showsPhoto: false)` + `directionsColumn` inside the Directions `ScrollView` — spanning Directions' width and scrolling with it. Directions-only (not Directions + Playbook) keeps identity + method together and lets the Playbook stay **top-anchored** (Ask · Make-ahead · Notes rise to the ceiling) — Jon's chosen fork. `metadata` gained a `showsPhoto` flag so the compact reader keeps its 72 pt band thumbnail (`compactThumbnailSideLength`) while the wide header owns the photo (`wideColumnPhotoSideLength` = 96, a **deliberate** grow past Paprika's stamp, recorded so it doesn't read as drift).

**Ingredients cheated narrower; the three columns still reconcile.** `RecipeWideColumnLayout` split its single `contentColumnFraction` (⅓) into `ingredientsColumnFraction` = **0.27** and `directionsMinimumFraction` = **0.30**. The narrower Ingredients widens both the Directions floor and the Playbook max; the math reconciles exactly (at Wide, Directions lands back on `0.30w`).

**Slice B review finding closed here (same region).** The Show/Hide Playbook toolbar toggle moved out of the parent's `isSplitEnabled` gate into the reader's own `proxy.size.width >= twoColumnThreshold` gate — so the button now appears **iff** the three-column layout actually renders, killing the dead-control state on a sidebar-narrowed pane. `isSplitEnabled` remains used elsewhere (not dead).

**Architect review (PR #195) — approve, no on-branch changes required.** Composition matches the ADR intent exactly (confirmed against on-device screenshots); layout math reconciles precisely; the toolbar re-gate is a genuine improvement, not just a relocation. One **non-blocking** nit: `metadata(showsPhoto: false)`'s `ViewThatFits` collapses to two near-identical candidates on the wide path (the `VStack` branch is dead there) — cosmetic, deferred. **Device-pass discovery → next slice:** the **Peek** detent renders a degenerate sliver at its minimum width ("Hand off to ChatGPT" wraps one char per line, Ask clipped) — a pre-existing Slice B detent-math gap (Peek = ⅓ of an already-small max, with no content floor mirroring the Directions floor), surfaced now, **not caused by Slice C**. Jon's call: **drop Peek to two detents** (see CURRENT_HANDOFF Next Up).

---
## ADR-0039 — Amendment 2 / Slice B, resizable recipe Playbook column

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-16. Jon device-pass pending.** yes-chef PR [#194](https://github.com/jonphillips/yes-chef/pull/194).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): **second of what is now four** Amendment 2 slices — the arc grew from three when the header-nesting correction was inserted. A (header band) shipped; **C = the header nests beside Ingredients (Paprika composition), next**; **D = menu adopts the column, parked** (D is the *old* "Slice C," renumbered). **App-layer only — no schema / migration** (Playbook width persists via local `@AppStorage`, not synced — it's view state).

**Wide iPad is now three co-visible columns, no mode.** `wideRecipeSection`'s Cook/Plan segmented toggle is gone; a new `wideRecipeColumns(in:)` lays out Ingredients + Directions + Playbook simultaneously. `WideSection`/`wideSection` deleted as dead. Directions never leaves the screen to plan — Amendment 1's wide toggle is reversed.

**Playbook width — show/hide + drag-snap + persist.** New `RecipePlaybookColumnLayout.swift`: a `RecipeWideColumnLayout` value type does the width math (Ingredients pinned at ⅓, a matching ⅓ Directions floor, three detents — **Peek / Comfortable / Wide** — evenly dividing only the *remaining* width, so no device-point widths are baked in), a `RecipePlaybookResizeHandle` (draggable + VoiceOver-adjustable, tap-to-cycle), and a `RecipePlaybookColumnDetent` enum. Visibility + detent persist in local `@AppStorage`; a toolbar **Show/Hide Playbook** button preserves the last detent. Structurally a faithful clone of the shipped `RecipeChatWorkspace` resize affordance (same `@GestureState` drag + `.simultaneousGesture`, `proposed…Width`/`nearestDetent`, `.snappy(0.22)`, wrapping detents) — deliberate reuse, the two resize surfaces stay consistent.

**Compact untouched** — the segmented `Ingredients · Directions · Playbook` picker stays, one region at a time. Ask + Browse remain `.inspector` slide-overs over the top.

**Architect review (PR #194) — one coherence finding, carried into Slice C (not fixed on-branch).** The Show/Hide Playbook toolbar button is gated on `isSplitEnabled` (`RecipeDetailView.swift:137` — iPad + non-compact size class) while the three-column layout is gated on `isTwoColumn` (`RecipeDetailView.swift:267` — detail-pane width ≥ 640). On an iPad whose detail pane is < 640 (sidebar showing), the button appears but the Playbook column doesn't render — toggling is a **dead control**, and that's a common everyday state, not an edge case. **Folded into Slice C's task list** (which rebuilds that exact wide-layout + toolbar region): re-gate the toggle on the real two-column width signal. Two non-blocking device-pass notes: the Directions readability floor is a pure `w/3` fraction (watch it at the narrowest Directions width on 13"); the detents wrap (Wide→Peek), consistent with the chat-workspace precedent, left for parity. Architect local build → **BUILD SUCCEEDED**.

---
## ADR-0039 — Amendment 2 / Slice A, compact recipe header + Start Cooking burial

**✅ architect-approved + app-build-gate green (architect local `generic/platform=iOS` → BUILD SUCCEEDED, run against the post-review fix tip) — 2026-07-16. Jon device-pass pending.** yes-chef PR [#193](https://github.com/jonphillips/yes-chef/pull/193).
[ADR-0039 Amendment 2](decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column): first of **three** Amendment 2 slices (B = resizable Playbook column + recipe adoption; C = menu adopts it — both still ahead). **App-layer only — no schema / migration.**

**Recipe header compacted to a Paprika-style band.** `header(_:)` is now a tight title/subtitle/summary stack (summary `lineLimit(2)`); `metadata(_:)` is a dense stats · source · thumbnail band. The cover thumbnail dropped 112→72 pt so it no longer dictates header height (`HeaderMetrics.thumbnailSideLength`), and `SourceMetadataView` collapsed from a multi-line block to a single `lineLimit(1)` `.caption` line (displayName + one `compactDetail` field). Directions climbs up the page — the point, now that it's a co-visible column whose vertical space is precious.

**`View Original` → toolbar.** Moved out of the `metadata(_:)` stack into a `.secondaryAction` toolbar item, gated on `originalSnapshot != nil`.

**Recipe "Start Cooking" entry point removed (surgical).** Deleted `startCookingButton`, the `showsStartCookingButton` param threaded through `RecipeDetailView`/`RecipeReaderView` (and its `CookSessionView` call site), the recipe-library `cookButtonTapped` + `.cookingMode` destination, the `CookingModeView` screen, its `.sheet` in `AppDestinationPresentation`, and the `CookingModeModel`. Confirmed **zero** dangling references and the pbxproj no longer lists the deleted file. **`CookSessionView` and the Menu/Calendar "Cook these" flows are untouched** — the recipe opened that shared `TabView` with one item (the 40 pt step-by-step Jon won't use); Menu/Calendar open the *same* view with many (kept). Git is the archive ([[automation-decays-near-the-stove]]).

**Folded-in D4 fix — menu Ask toggle.** The merged D4 menu Ask already uses a toggle action for the toolbar and an ensure-open action for Regenerate, preserving a live transcript — the PR #192 finding is closed here.

**Architect review (PR #193) — two follow-ups, both fixed on-branch.** (1) The new `compactDetail` silently dropped `sourceNotes` from every reader surface (it stayed editable + searchable, so it became write-only). Restored as a capped secondary caption (`.caption`, `lineLimit(2)`) below the metadata band — a **temporary** read surface so Jon can dogfood and decide its fate; the ADR trajectory still points source notes into the Playbook ([[decompose-notes-into-typed-homes]]), not this line. (2) The metadata `ViewThatFits` narrow fallback omitted the thumbnail, which is the **sole** `isPhotoGalleryPresented` entry point — so on narrow width the recipe's photos went unreachable. Fixed by adding the 72 pt thumbnail to the fallback branch too. Architect local build (post-fix) → **BUILD SUCCEEDED**.

---
## ADR-0039 — D4 / OQ3, the Menu launcher mode

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED; `MenuServiceDateTests` green) — 2026-07-16. Jon device approved.** yes-chef PR [#192](https://github.com/jonphillips/yes-chef/pull/192).
[ADR-0039 §D4 + OQ3](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): a menu is a *thinking* artifact you don't execute (you execute its recipes), so its planning→launcher shift is **temporal, not spatial** — keyed off the **service date** ([[mode-trigger-date-vs-toggle]]). **App-layer + one Core helper — no schema / migration.**

**Date-driven mode, one pure Core helper.** New `MenuServiceDate.hasArrived(placements:now:calendar:)` (`YesChefCore`) — the earliest placement `startDate` compared to `now` at **day** granularity — is the single mode switch, unit-tested (`MenuServiceDateTests`: empty / future / later-today / mixed-past). Keeping the date logic in Core (not the App layer) is what let it be tested at all.

**Planning vs. launcher, over time.** *Far from service:* the **prep plan is foregrounded and expanded**, the dish list sits at the bottom. *On/after the service date:* the **dish list jumps to the top with all days collapsed** (`isInitiallyExpanded: false`) and the **prep plan collapses** — day-of, the job is *get me into the right recipe fast*. Both `MenuDishList` day headers and the `MenuPrepPlanSection` header gain **chevron toggles** with accessibility labels; OQ3's collapsible days land here.

**The menu's standing AI third column is deleted.** The always-on `ChatWorkspaceSplit` chat pane is removed from the menu detail; the reader is now a single pane. Ask + Browse Recipes become a **unified `.inspector`** (a private `MenuDetailInspector` enum, `recipeBrowser | chat`, with an `Optional.isPresented` binding) on wide iPad; Ask stays a `.sheet` on compact — echoing the recipe-side D3 demotion.

**Architect review (PR #192) — Ask-toggle finding fixed in Amendment 2 Slice A (PR #193)..** The menu's `chatButtonTapped` (`MenuViews.swift:317`) is a pure setter: on wide iPad, re-tapping the live **Ask** toolbar trigger rebuilds the `RecipeChatModel` and **silently discards the in-progress transcript**, with **no toolbar close path** — the *identical* defect the D3 follow-on (PR #191, entry above) just fixed on the recipe side, where `RecipeModels.swift:915` now toggles and its comment even points here ("See the Menu recipe-browser toggle for the pattern"). Fix: make the menu Ask **toggle closed** on re-tap, mirroring the sibling `recipeBrowserButtonTapped` — but `chatButtonTapped` doubles as `regeneratePrepPlan`, so split the intents (a toggling Ask path + an ensure-open path for Regenerate that doesn't rebuild an existing chat). Two minor notes, non-blocking: the menu Ask trigger lacks the recipe's active-state ring, and `dayAccessibilityTitle` duplicates `dayTitle`'s date formatting. Architect local build (pre-fix) → **BUILD SUCCEEDED**.

## ADR-0039 — D3 follow-on, the true "Ask" slide-over + Playbook-header polish

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED) + Jon
device-pass done — 2026-07-15. Merge pending.** yes-chef PR
[#191](https://github.com/jonphillips/yes-chef/pull/191).
[ADR-0039 §D3 + Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): delivers the *true*
slide-over Amendment 1 specified ("a true slide-over, decoupled from any resize bar") to replace D3's reused
modal sheet. **App-layer only — no schema / migration.**

**Ask is now a native trailing inspector on wide iPad**, a non-modal companion that doesn't dim/steal the
reader; it reuses the established Menu recipe-browser inspector width range (320 / 380 / 480 pt). **Compact keeps
the plain sheet** (no room for a side companion). The dual `.inspector`/`.sheet` with mirrored `.constant`
bindings migrates an open chat inspector↔sheet across size-class changes without losing `destination`.

**Architect review (PR #191) fixes — one real interaction bug + polish.** The non-modal companion left the
Playbook-header **Ask** trigger live beside the open panel, but `chatButtonTapped` was a pure setter: re-tapping
rebuilt the `RecipeChatModel` and **silently discarded the scratch transcript**, and there was **no close path**
(the panel has no dismiss control and `@Environment(\.dismiss)` can't close an inspector). Fixed by making
`chatButtonTapped` **toggle** (re-tap closes), mirroring the Menu recipe-browser toggle
(`RecipeModels.swift:915`). Both folded-in cosmetic notes landed (PasteButton `.bordered`; redundant in-view
"Playbook" title removed). Architect local build → **BUILD SUCCEEDED**.

**Jon UI request, same slice.** The Playbook header now **separates the two AI tiers**: the ChatGPT copy/paste
round-trip (Hand off + Paste) clusters at the leading edge, **Ask sits apart on the trailing edge**, out of that
workflow. While its panel is open, Ask carries a **3 pt tint-colored active ring** so the trigger reads as lit.

---
## ADR-0039 — D3, the "Ask" chat demotion + retiring the wide chat split

**✅ architect-approved + app-build-gate green (local `generic/platform=iOS` → BUILD SUCCEEDED) — 2026-07-15.
Jon device-pass done, merged.** yes-chef PR [#190](https://github.com/jonphillips/yes-chef/pull/190).
[ADR-0039 §D3 + Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): collapses the
transitional AI-in-two-places state D1/D2 left behind. The always-on `ChatWorkspaceSplit` + draggable
`ChatWorkspaceDivider` is **removed from the recipe detail** (still live in Menu/Calendar/Workbench); the
Playbook header now **owns both tiers** — **Hand off to ChatGPT** (`.borderedProminent`, primary) and **Ask**
(`.bordered`, secondary), plus the return-paste `PasteButton`. The toolbar "Chat" entry point and the Cook/Plan
detent-toggle logic (`wideSectionChanged`, `chatWorkspaceDetentRaw`) are deleted. **App-layer only — no schema /
migration.**

**Ask reuses the existing recipe-scoped `.sheet` for now** (`model.chatButtonTapped` →
`.sheet(item: $model.destination.chat)`); the **true slide-over presentation** Amendment 1 specifies ("a true
slide-over, decoupled from any resize bar") is a **deliberate follow-on**, not a miss — see the D3-follow-on
Next Up. D3 delivers the *demotion + divider retirement*; the slide-over *styling* is the next slice.

**Architect review (PR #190) — verified clean.** No orphaned code: `ChatWorkspaceSplit`/`ChatWorkspaceDetent`
stay in use across Menu/Calendar/Workbench. The Focus toolbar button is untouched — it drives
`NavigationSplitView` column visibility (`AppMainLayout.swift`), not the retired chat split. Confining
Ask/handoff to the Playbook is **per-spec** ("the Playbook column header owns both"), not a reachability
regression. Two cosmetic notes (PasteButton styling; "Playbook" vs "Plan" heading) were **folded forward** into
the D3-follow-on slice rather than blocking merge. Architect local build → **BUILD SUCCEEDED**.

---
## ADR-0039 — D1/D2 + OQ1/OQ2, the Recipe Playbook region

**✅ architect-approved + app-build-gate green + Jon device-pass done — 2026-07-15. Merge pending.** yes-chef
PR [#189](https://github.com/jonphillips/yes-chef/pull/189).
[ADR-0039 §D1/D2, Amendment 1](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): the anchor UI slice —
the recipe gains a **third peer region, Ingredients · Directions · Playbook**, and the "thinking" content leaves
the cook body. **App-layer only — no schema / migration; `Recipe.makeAhead` (`String?`) stays canonical.** New
file `YesChefApp/RecipePlaybookView.swift`.

**Both device renderings (Amendment 1).** Compact adds a **third `.segmented` case** (`Ingredients · Directions
· Playbook`). Wide iPad **pins Ingredients as a ⅓ anchor** and a **Cook / Plan toggle** swaps the other ⅔
between Directions (Cook) and Playbook (Plan), setting preset `ChatWorkspaceDetent` detents (Cook → `readerOnly`,
Plan → `balanced`).

**Full content move (OQ1 — body shows nothing).** Make-ahead, Notes (reader feedback + other `RecipeNote`),
Chef It Up, and Serve With cut from `directionsColumn` into the Playbook; each section is **collapsible** with a
**filled/empty header indicator**. Stays in Directions: Instructions, the active-variation method note, Workbench
candidate links. All existing edit/clear actions and the canonical make-ahead store preserved.

**Architect app-build gate earned its keep — four App-target compile errors that `check-drift.sh` structurally
cannot see** (it compiles only `YesChefPackage`; all four were pure SwiftUI in `YesChefApp/`). Round 1: a
`let … = nil` binding excluded from the memberwise init, and `.padding()/.frame()` chained onto a bare `switch`.
Round 2 (surfaced only by the local `generic/platform=iOS` build): a `.tint`/`.secondary` ShapeStyle ternary
needing `AnyShapeStyle`, and a non-`@escaping` `@ViewBuilder` closure captured by `DisclosureGroup`. The last two
fixed + committed by the architect (a3e5011); build → **BUILD SUCCEEDED**. Reinforces
[[codex-build-excuse-reproduce]]. Codex's cited `swiftc -parse` cannot catch any of these (parse skips
type-checking).

**Intentional intermediate state (device-confirmed).** The `ChatWorkspaceDivider` / in-app chat column is **not**
retired here — deferred to **D3**. So on wide iPad, Plan re-expands the old chat column via the `balanced` detent,
and the AI appears in two places at once (the standing column + the Playbook's Copy-Prompt handoff). That
doubling is transitional and collapses in D3.

---
## ADR-0039 — D5, prep plans emit tasks, not choreography

**✅ architect-approved + package tests green (18/18) — 2026-07-15. Jon device-pass + merge pending.** yes-chef
PR [#188](https://github.com/jonphillips/yes-chef/pull/188).
[ADR-0039 §D5](decisions/ADR-0039-playbook-column-thinking-vs-doing.md): the smallest-first opening slice of
the Playbook milestone — both prep-plan prompt contracts now emit **separable, atomic, context-free tasks** and
are explicitly forbidden from **choreography** (interleaving recipe instructions, coordinating concurrent
cooking, or turning the plan into a merged mega-recipe). "The recipes hold the cooking." **Core-only — no app /
schema / migration.**

**Both contracts constrained.** `MenuPrepPlan.instructions` (`MenuPrepPlan.swift:293`) and the sibling
`MealPlanMakeAheadStrategy.instructions` (`MealPlanMakeAheadStrategy.swift:183`) both drop the invitation to
"invent grounded sequencing" and gain the tasks-never-choreography constraint plus grounded example tasks
("Salt the chicken Wednesday", "Pull the beef to temp at 4"). Existing JSON shapes
(`session`/`task`/`serves`/`sourceDish`) and the compose-from-stored-Make-Ahead behavior are preserved; the
horizon-band session grouping (temporal bucketing, not step interleaving) stays. Realizes
[[automation-decays-near-the-stove]].

**Tested in Core.** Both package suites assert the positive constraint (`separable, atomic, context-free
tasks`, `Do not generate choreography`, `The recipes hold the cooking`) and the menu suite pins the negative
(`invent grounded sequencing` == false). `swift test` MenuPrepPlanTests + MealPlanMakeAheadStrategyTests, 18
passed. Prompt-only steer — no schema/storage change, so a phrasing that underperforms is a regeneration away
from reversible.

---
## ADR-0040 — Editable-at-the-grain, S3 (surface menu edit outcomes / lossless-or-**loud**)

**✅ architect-approved + app-build-gate green — 2026-07-15. Jon device-pass + merge pending.** yes-chef PR
[#187](https://github.com/jonphillips/yes-chef/pull/187).
[ADR-0040 S3](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md): the **silent-success** half of the
lossless-or-loud pass — every direct menu edit path now ends in a visible outcome. **App-layer only — no core /
schema / migration.**

**Direct edits confirm.** Prep-step create/edit/delete/reorder and learning edit/delete now post a transient
success toast via the shared `AppToastCenter` (threaded into `MenuLibraryModel` + `MenuDetailModel`); failures
keep the standard error surface (`MenuDetailModel+PrepPlanEditing.swift`).

**No-ops go loud.** A reorder that can't move (`PrepPlanStepRepository.reorder` → `false`) now raises "already at
the beginning/end of the plan" instead of silently accepting it; a blank learning edit raises an error instead
of silently returning; empty/whitespace handoff-result and recipe-URL pastes (`HandoffInAppTransport`,
`RecipeCaptureModel.pastedText`) become visible errors instead of `guard let … else { return }` invisibility —
the S3a device-pass failure mode where "did nothing," "worked invisibly," and "wrong build" were
indistinguishable.

**Build note.** Codex's one generic-build attempt caught a real `toastCenter` `private`-protection error, which
was fixed; the architect re-ran the generic app build locally (`generic/platform=iOS`, `BUILD SUCCEEDED`, 0
errors) as the approval gate.

---
## ADR-0038 — External-LLM handoff, S3c (in-app door) + Amendment 2

**✅ DONE — architect-approved + Jon device-passed 2026-07-15.** yes-chef PR
[#186](https://github.com/jonphillips/yes-chef/pull/186).
[ADR-0038 Amendment 2](decisions/ADR-0038-external-llm-handoff.md): Recipe + MealPlan get an in-app
**Copy-Prompt / Paste-Result** door (discuss-first) as the **primary** path; the App Intent stays the
hands-free bonus. **App-layer only — no core / schema / migration.**

**In-app transport (`HandoffInAppTransport`).** Copy emits the S3b tokenized prompt (`YC-HANDOFF:` + the
source's `DeliverableFormat`) via shared `HandoffAppOperations.export`; Paste routes through
`AIHandoffIntentImport.stageReview` → the review sheet (editable-at-grain, Learnings ride along). Menu's manual
Copy/Paste moved onto the same review-routed transport, retiring its direct-write paste path. Controls live on
a **persistent Make-ahead header** in the recipe Playbook column (a first ADR-0039 brick, fixing the
`PasteButton`-in-overflow-menu bug) and on the meal-plan day header; custom copy icon
(`sparkles.square.filled.on.square`), `PasteButton` kept for paste (privacy, no per-paste prompt).

**Unmatched-result guard.** The in-app paste checks the pasted result against the surface it was tapped on: a
missing token, a handoff not found locally (incl. cross-device, since `AIHandoff` is device-local), or a token
resolving to a **different** source each raise a **Review Anyway / Cancel** alert. Proceed stages against the
current surface via `stageReviewForKnownSource` (mints a device-local handoff + stages atomically in one
write). Restores the token-less fallback **safely** — never a direct write, always the review sheet, with an
explicit "check this" gate; also makes a cross-device return route to the same synced recipe/day.

**App Shortcuts.** Export/Import registered as `AppShortcut`s for Spotlight / Siri / Action Button discovery;
the intents refactored onto the shared `HandoffAppOperations`. Follow-up commits `a4ea289` (controls fix) +
`da07b47` (unmatched guard) landed the device-pass findings.

---
## ADR-0038 — External-LLM handoff, S3b (Recipe + Meal Plan)

**✅ DONE — architect-approved; build fix landed as `3999bf2`. Jon device pass: _pending_ — flip this line to
`+ Jon device-passed 2026-07-14` on pass.** yes-chef PR
[#185](https://github.com/jonphillips/yes-chef/pull/185).
[ADR-0038](decisions/ADR-0038-external-llm-handoff.md): the two-part return contract — proven on **Menu only**
because Menu's context serializer already existed (S3a + ADR-0040 S1/S2) — now covers **Recipe** and **Meal
Plan**. It **inherits** editable-at-grain rather than adding new BLOBs ([[editable-at-the-grain-stored]]).

**Context builders (Core, `AIHandoffContext.swift`).** `RecipeHandoffContext` and `MealPlanHandoffContext` on
the `MenuChatContext` pattern — shared frontier character budget, full recipe methods, uncapped ingredients
within budget, intro prompts tuned from `tasteProfile` / `makeAheadPrepPlan` AI settings, asking for
paste-ready **review text, not JSON**. `AIHandoffToken.DeliverableFormat` (`menuPrepPlan` / `recipeMakeAhead` /
`mealPlanMakeAheadStrategy`) shapes the export prompt per source; the export intent passes the right one
(default stays `menuPrepPlan`).

**Generalized return routing.** `AIHandoffReview` enum + `AIHandoffIntentImport.stageReview` dispatch by
`sourceType`; `AIHandoffReturn.plainText(from:)` splits deliverable/learnings for the non-Menu sources.
`HandoffReviewCoordinator` routes source-specific review items and reusable, **source-typed** `Learning` rows
off the same S3a machinery — the reason the handoff is worth doing on a source with no structured deliverable
field at all.

**Commit shape per source ([[chat-verb-commit-shapes]]).** Recipe → `Recipe.makeAhead` (verbatim prose at its
own grain), via a distinct **local-only** `recipeMakeAhead` handoff task — **no synced table or column, no
migration**. Meal Plan → a day-scoped make-ahead strategy through the existing
`MealCalendarRepository.addMakeAheadStrategyNote` (PR #91), no new synced schema either. **No additions to the
prod-schema promotion list.**

**Lossless-or-loud, at the boundary not just the UI (ADR-0040 D3).** `MealPlanMakeAheadStrategy
.parsingEditableReviewText` returns `unparsedLines`; the review sheet **surfaces** them ("Couldn't parse — fix
or remove these lines before saving") and `commitMealPlanMakeAhead` **re-parses and hard-rejects** any unparsed
line (`unparsedStrategyText`) before writing. Human edits are never silently dropped.

**Meal-plan Learnings hand-cascade** on source-item delete (`LearningRepository.deleteAll` in
`MealCalendarRepository.delete`) — no orphaned synced ghosts. (Menu already did; recipe learnings live on an
archive-not-delete source.)

**Tests.** `AIHandoffRecipeMealPlanTests` — prompts, full meal-plan context, Recipe staging, Meal Plan staging,
visible unparsed lines. Full `AIHandoffTests` suite green (15).

**Review finding, fixed post-push (`3999bf2`).** The app target **did not compile** — `HandoffIntents.swift`
used `date: .full`, invalid for `Date.FormatStyle.DateStyle` (valid: `.omitted/.numeric/.abbreviated/.long/
.complete`; `.full` is old `DateFormatter.Style` only). Codex's package `swift build` + tests were green and
its own generic app build **SIGTERM'd (exit 143, "CoreSimulator unavailable")** — the **third** PR (after #183,
#184) to slip an uncompiled app target through on that excuse. Architect-caught by running the generic build
locally (exit 65, real compile error); one-line fix `.full → .complete`.

**Process fix (real this time).** The #184 "just mandate the generic build" fix did not hold — Codex **can't
execute** that build (no working CoreSimulator subsystem / cold-build timeout → SIGTERM). The Verification
Pattern in `CURRENT_HANDOFF.md` now makes the app-target build the **architect's gate**, treats a green package
build as *not* evidence the app compiles, and adds the corollary: keep pure formatting/serialization logic in
`YesChefPackage`, not the App layer (the `.full` call belonged in `MealPlanHandoffContext` in Core, where the
package build would have caught it). See [[codex-build-excuse-reproduce]].

**Dogfood finding → [Amendment 2](decisions/ADR-0038-external-llm-handoff.md) + queued S3c.** The recipe/
meal-plan handoffs shipped **intent-only** — no in-app door — so the sole entry point is a hand-built Shortcut
running the *Immediate* autopilot, which discards the discussion that is the point of a make-ahead hand-off.
Amendment 2 makes an **in-app Copy-Prompt / Paste-Result** affordance (discuss-first, paste routed through the
review sheet) the *primary* door for these two sources; the App Intent stays the hands-free/cross-device bonus.
Filed as **S3c** (app-layer only) in the Ready Efforts queue.

**Known edges (deferred to the ADR-0040 S3 lossless pass).** In meal-plan strategy parsing the **title (first)
line is not checked for parseability** — a mangled header silently falls back to the existing title/slot rather
than surfacing in `unparsedLines`. And an import returning **only unparseable lines with no learnings** throws
`emptyPlan`, losing those lines before they reach a review sheet. Both mirror the existing Menu path, so
neither is an S3b regression — fold into the same lossless-or-loud sweep.

---
## ADR-0040 — LLM-populated content is editable at the grain it is stored, S1 + S2 (on Menu)

**✅ DONE — architect-approved + Jon device-passed 2026-07-14.** yes-chef PR
[#184](https://github.com/jonphillips/yes-chef/pull/184).
[ADR-0040](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md): the prep plan stopped being an
**all-or-nothing BLOB** the human could only regenerate through the LLM, and the `learnings` table (ADR-0038
S3a) got a reader. Two rules proven on Menu: **store LLM output at the grain the human manipulates** (a row
with an id) and **the human never authors the wire format** (structured fields, lossless-or-loud parsing).

**S1 — the Learnings surface.** A **Learnings** section on the menu detail (`MenuLearningsSection`), this
menu's learnings newest-first, read through the existing **per-menu** `MenuDetailRequest` (no whole-library
`@Fetch` — [[sqlitedata-fetch-writer-convoy]]). Inline edit (writes `dateModified`, leaves `provenance`),
swipe-to-delete a single row via `LearningRepository.delete(id:)` — `swipeActionsContainer()` on the
`ScrollView`, the iOS 27 way to swipe outside a `List`. Also exposed the **Handoff ID** as an `@Property` on
`HandoffExport` so a Shortcut can wire Export → Import directly instead of trusting ChatGPT to echo the token
UUID.

**S2 — prep plan → step rows.** `Menu.prepPlan` BLOB migrated into a synced **`prepPlanSteps`** table
(`id`, `menuID`, `sortOrder`, `session`, `task`, `serves`, `sourceDish`) — a real child of `Menu` with a
**FK + `ON DELETE CASCADE`** (no hand-cascade; multi-FK does not block sync). `PrepPlanStepRepository` does
add / edit / delete / **reorder**; the detail section edits **fields + a session picker** (six-band vocabulary
with an `.other` free-text escape), not the `session:` / `→` wire DSL. The BLOB is retained one release as a
**frozen snapshot, not a rollback mirror** (nothing writes it). Both `learnings` and `prepPlanSteps` joined the
prod-schema promotion list; the restructure landed **before the prod cut locks the record type**.

**Silent-loss paths killed (ADR-0040 D3).** `sourceDish` is no longer re-derived by matching task prose — it
rides on row identity, so a text import with no link intentionally drops the recipe chip rather than guessing
(pinned by test + documented). The parser now routes unparseable lines to `unparsedLines` instead of
`continue`-ing them away.

**Review findings, fixed in-PR** (PR #184 review + `076eb11`). (1) App target **did not compile** and the
suite was **red** as first pushed — an if-let-shorthand typo and a stale BLOB-seeded chat-context fixture
(architect-fixed, `0bf0e81`). (2) **The Flexible band went unreachable** — `isFlexible` demanded exact picker
titles, but LLM/legacy plans carry prose; fixed with a **display-only** `PrepPlanSessionBand(matching:)`
normalizer that never rewrites the stored label. (3) **"Loud" had overshot into "refuse everything"** — one
unparsed line rejected the whole return incl. learnings, even on the reviewed path; now the review sheet
**surfaces** the bad lines ("Couldn't parse — fix or remove…") for the human to fix, while the unreviewed
direct paste still hard-throws.

**Process fix that shipped with it.** The "CoreSimulator has no runtimes" excuse that let **two** uncompiled
PRs (#183, #184) through is dead: `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
compiles the app target with no simulator and no signing, and the Verification Pattern in `CURRENT_HANDOFF.md`
now mandates it.

**Deferred to the [ADR-0040 S3](decisions/ADR-0040-editable-at-the-grain-it-is-stored.md) lossless-or-loud
pass:** no save confirmation on a learning/step edit (it just appears), and "Paste Prep Plan" silently no-ops
on an empty clipboard or a missed *Allow Paste* prompt.

---
## ADR-0038 Amendment 1 — External-LLM handoff, S3a (the two-part return contract, on Menu)

**✅ DONE — architect-approved 2026-07-14. Jon device pass still owed.** yes-chef PR
[#183](https://github.com/jonphillips/yes-chef/pull/183).
[ADR-0038 Amendment 1](decisions/ADR-0038-external-llm-handoff.md): the handoff return is now
**`(Deliverable?, Learnings?)`, either may be empty** — the *reasoning* of a multi-turn session no longer dies
in ChatGPT. Proven on **Menu only** (its serializer already existed; Recipe/MealPlan are S3b).

**Prompt (both modes).** After the deliverable, the model returns a **`YC-LEARNINGS:`** marker line followed by
a bullet list of durable knowledge — a **structured list of distinct bullets, never a merged blob**
([[llm-curation-not-synthesis]]). A **learning-only return is first-class**, not an error. Bundles the
**ADR-0039 D5 prompt fix**: prep-plan bullets are **separable, atomic, context-free tasks, never choreography**
— the plan must never become a merged mega-recipe ([[automation-decays-near-the-stove]]).

**Parse — split before you parse.** `isEditablePrepPlanSessionHeader` treats any non-bullet, colon-terminated
line as a **session header**, so an unsplit `YC-LEARNINGS:` would be swallowed as a prep band and every learning
would become a prep step. `AIHandoffReturn` strips the token → **splits the body on the marker** → feeds *only*
the deliverable half to `applyingEditableReviewText` and parses the learnings half as bullets. The marker match
is **tolerant of markdown decoration and case** (`## **yc-learnings:**` splits correctly) — models bold their
headings no matter what the prompt says.

**Commit — new synced `Learning` table.** `id`, `sourceType` (reuses `AIHandoffSourceType`), `sourceID`, `text`
(plain text to start), `provenance` (`.externalHandoff`/`.inApp`), `dateCreated`, `dateModified`. Registered in
`makeSyncEngine` (the `CloudSyncTests` guard derives its expectation from the live schema, so it covered this
with no test edit). `(sourceType, sourceID)` is **polymorphic → no FK → no cascade delete**, so
`MenuRepository.deleteMenu` **hand-cascades** its learnings — orphans here would be *synced* ghosts, not
harmless local ones. **`learnings` is on the standing prod-schema promotion list.**

**Review.** `HandoffReviewSheet` now passes **two** `ChatApplyReviewItem`s — Deliverable and Learnings — each
independently editable, savable, and discardable (ADR-0024/0026).

**Review findings, fixed in-PR.** The prompt change is global, but the first pass taught only the App Intents
path to keep learnings — the **in-app paste path silently discarded every learning** and hard-errored on a
learning-only paste. `AIHandoffMenuPrepPlanImport.apply` now persists both halves and its empty-guard relaxed to
"empty deliverable **and** empty learnings = error." Also: the exact-match marker was hardened (above), the
error surface no longer says "Prep Plan" for a learnings failure, and a `UUIDGenerator`-vs-`() -> UUID` compile
error in the app target was fixed at merge — **the app target does not compile in the Codex sandbox, so
package-only green is not sufficient evidence for app-layer changes.**

**Not decided here (deliberately):** *where* learnings are displayed. Nothing reads the table yet — that is
ADR-0039 (the Playbook column) and a hard prerequisite of S3b (a read/delete surface, before the corpus grows
rows nobody can see or prune).

---
## ADR-0038 — External-LLM handoff, S2 (the App Intents surface)

**✅ DONE — merged + Jon device-passed 2026-07-14.** yes-chef PR
[#180](https://github.com/jonphillips/yes-chef/pull/180) (+ [#181](https://github.com/jonphillips/yes-chef/pull/181),
docs). [ADR-0038](decisions/ADR-0038-external-llm-handoff.md) S2: the external-LLM surface over the S1 core.
**The immediate loop works end-to-end on device** — `Export Handoff Context (menu) → Ask ChatGPT →
Import Handoff Result` returns a parsed prep plan into the review sheet with no human in the middle.

**App Intents (new `YesChefApp/AppIntents/` group).** Three `AppEntity`s (Recipe/Menu/MealPlan, all
`SyncableEntity` on our stable iCloud UUIDs) + `HandoffSource` as an `@UnionValue`.
`ExportHandoffContext(source:mode:)` creates the hand-off and returns a `HandoffExport` carrying the prompt and
`Menu.externalProjectName`. `ImportHandoffResult(handoffID:result:)` routes by id (param **or** stripped
token), stages the review, and `OpensIntent`s into `RecipeCollectionReviewSheet` via
`HandoffReviewCoordinator`/`HandoffReviewSheet`. `allowedExecutionTargets = .main` (in-process; the intents
call the repositories directly).

**Prompt modes.** `HandoffPromptMode` (`AppEnum`) exposes discuss/immediate in the Shortcuts action row.
**Default is `.immediate`** (`de8108e`): the Shortcuts surface exists *for* the headless `Ask ChatGPT` chain,
and a discuss prompt sent headlessly returns conversational prose the parser cannot use, while the reverse
mispairing is harmless. **The in-app Copy Prep Prompt button stays discuss and takes no mode** — the two
surfaces map to the two modes.

**Schema.** Additive synced `Menu.externalProjectName` (+ menu-detail field, repository write, trim-to-nil).
**Added to the standing prod-schema promotion list.** Strict block-on-duplicate dedupe lives in
`AIHandoffIntentImport.stageMenuPrepPlanReview` (marks imported when the sheet *opens* — the sheet remains the
sole writer of the durable artifact; a cancelled review therefore burns the session, and re-export is the
recovery: **confirmed as intended**).

**Device-pass findings (see the [PR #180 comment](https://github.com/jonphillips/yes-chef/pull/180#issuecomment-4964739760)).**
Two architect concerns were **retired** by the device pass: the `@ComputedProperty` + empty-query pattern on
`HandoffExport` resolves fine as a Shortcuts variable, and the `assumeIsolated` / dual-coordinator wiring holds
on the foreground path. **OQ5 resolved** — `source` is required, so a bare Action-Button invocation gets the
system picker.

**OQ6 RESOLVED — pessimistic.** ChatGPT's `Start chat in project` is **fixed-pick-only**: it resolves the
project at configure time and does **not** accept a variable (and appears to take no prompt input either). So
per-menu project auto-seeding from one generic shortcut is **not achievable**. This does *not* break the
hand-off — return→resource routing rides the `YC-HANDOFF:` token and is project-independent.
**`Menu.externalProjectName` is demoted from a routing key to an advisory reminder** (helper copy reworded to
match). Fallbacks: immediate mode as the automated loop; discuss mode via the in-app Copy/Paste buttons; an
optional `Export → Copy to Clipboard → Start chat in project` hybrid.

**Deferred:** no `AppShortcutsProvider` — the intents are Shortcuts-composable only (no zero-config
Siri/Action-Button/Spotlight surface). Note it could not have shipped the multi-step chain anyway, since that
chain includes ChatGPT's own action.

**Tests.** `AIHandoffTests` — immediate-prompt format contract, review-only import staging (no menu write),
duplicate blocking, project-name trim/clear.

**What S2 provoked.** Dogfooding the loop exposed that the hand-off reduces a rich multi-turn session to a
**context-free deliverable** — the *reasoning* dies in ChatGPT. Result:
**[ADR-0038 Amendment 1](decisions/ADR-0038-external-llm-handoff.md)** (the return artifact is
`(Deliverable?, Learnings?)`; Learnings commit to the resource's synced notes; S3 re-splits into **S3a**
contract-on-Menu / **S3b** Recipe+MealPlan serializers) and a new
**[ADR-0039](decisions/ADR-0039-playbook-column-thinking-vs-doing.md)** (the Playbook column; thinking-vs-doing;
**D5 — the prep plan holds tasks, never choreography**).

---
## ADR-0038 — External-LLM handoff, S1 (session-tracked core)

**✅ DONE — merged + Jon device-passed 2026-07-13.** yes-chef PR
[#179](https://github.com/jonphillips/yes-chef/pull/179).
[ADR-0038](decisions/ADR-0038-external-llm-handoff.md) S1: the transport-agnostic, **device-local** core
that generalizes the menu Copy-Prep-Prompt / Paste-Prep-Plan round-trip
([ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) D5) into a trackable hand-off, proven
through the existing menu paste path (no new UI beyond one info alert).

**Core (`AIHandoff.swift`).** New device-local `aiHandoffs` table
(id/sourceType/sourceID/taskType/createdAt/importedAt/status/schemaVersion/exportedPrompt; STRICT migration)
**excluded from the CloudKit `SyncEngine`** — the sync-exclusion "unknown" resolved cleanly because
`makeSyncEngine` is a table **whitelist**, so `AIHandoff` simply isn't listed and joins
`chatMessages`/`chatThreads`/`recipeActiveVariations` in `localOnlyTableNames` (guarded by `CloudSyncTests`).
`AIHandoffRepository` = create/find/markImported.

**Token round-trip.** `AIHandoffToken` (prefix `YC-HANDOFF:`, `prompt`/`header`/`stripping`). **Copy Prep
Prompt** creates a hand-off, prefixes the token, snapshots the exported prompt. **Paste Prep Plan** strips +
validates the token (matching menu + task), applies the plan and marks the hand-off imported **atomically**
(one `database.write`), and dedupes a repeat return. Missing/mangled token → self-describing fallback still
lands the plan (`.applied`). Outbound prompt now demands the Unicode `→` glyph; `editableReviewLine` hardened
to also accept ASCII `->`.

**Discuss-vs-immediate (device-pass learning).** S1's prompt is the *discuss* variant — the strict format is
emitted on "finalize" (confirmed on device: an un-finalized paste returns prose). The **immediate-mode**
prompt variant (format-on-first-response, needed for the automated App Intents chain) is deferred to S2.

**Follow-up (silent-failure fix, `48c5114`).** Device pass caught an asymmetry: a re-paste of an
already-imported hand-off returned `.duplicate` and `prepPlanPasted` discarded it (silent), while the
wrong-menu guard *throws* first (proper error). Fix: a separate `MenuDetailModel.Information` channel surfaces
`.duplicate` as an **informative, non-error** "Already imported…" alert; **non-destructive** (no re-apply → no
clobber of hand-edits). Core `apply` unchanged; strict block-on-duplicate dedupe reserved for S2's
`ImportHandoffResult`.

**Tests.** `AIHandoffTests` (token/import/dedupe/fallback), `CloudSyncTests` sync-exclusion guard,
`MenuPrepPlanTests` ASCII-arrow, `AIHandoffMenuPasteTests` (duplicate informs without replacing the plan).

**Pre-code de-risking (2026-07-13).** The whole loop was validated by hand before implementation: `Ask
ChatGPT` returns text as a Shortcuts value, and a live beach-menu round-trip came back in the exact
review-text format the parser accepts ([ADR-0038](decisions/ADR-0038-external-llm-handoff.md) D2/OQ3). **S2**
(App Intents surface + per-menu project + immediate-mode prompt) and **S3** (generalize the serializer to
Recipe/MealPlan) remain, out of this scope.

---
## ADR-0036 — promote a recipe-shaped menu note → a real recipe

**✅ DONE — merged + Jon device-passed 2026-07-13.** yes-chef PR
[#178](https://github.com/jonphillips/yes-chef/pull/178).
[ADR-0036](decisions/ADR-0036-promote-note-to-recipe.md) S1 + S2 (one batch) + a provenance-shape follow-up.
Turns a recipe-shaped **menu note-item** (`MealPlanItemKind.note`, no `recipeID`,
[[menu-item-recipe-id-invariant]]) into a real structured `Recipe`. **S1** = a **deterministic**
heading-based note→draft adapter (`MenuNoteRecipePromotion`, `RecipeParseBuilder`-family naming only — no
LLM: recognizes explicit `Ingredients`/`Instructions|Method|Directions|Preparation` sections, strips
bullets/step numbers, everything else stays as notes) → `WorkbenchDraftRecipe` → the existing ADR-0024
editable review sheet → commit to a new `Recipe`. Chose determinism over the ADR's proposed on-device LLM
parse per [[llm-vs-determinism-surface-boundary]] (reproducible, private, free, no truncation; quantity/unit
parsing still happens downstream at `RecipeRepository.save`). Entry point = a **Make Recipe** glyph on note
rows (`MenuDetailSections`). **S2** = an opt-in confirmation to swap the note row for a recipe-kind item
pointing at the new recipe (`MenuRepository.replaceNoteItemWithRecipe`), preserving day/meal/sort.
**Provenance (OQ2 resolved, follow-up commit):** original prose rides in as an **editable general
`RecipeNote`** (`From menu note "<title>":` + blank-line-collapsed prose), **not** a `RecipeSource` — the
source-card version was a pinned, non-deletable header crowding both the recipe and the menu row (caught on
device). On replacement the note row's `notes` is cleared (`item.notes = nil`) so the promoted row collapses
to its title; blank machine FK dropped (live back-link is the item's `recipeID`). No schema change → the
standing prod-schema follow-up is unaffected. Free-rider: `.lineLimit(3)` on the menu-row note text
(`MenuDetailSections.swift:276`) **closes the queued "Menu note-item truncation" effort**. New
`MenuNoteRecipePromotionTests` (parse + provenance-as-note + replacement-clears-row). `RecipeNote`-on-recipe
promotion remains a future **S3**, out of this scope.

---
## ADR-0037 — grocery seed-coverage diagnostic

**⏳ PENDING — architect-reviewed 2026-07-13; awaiting merge + Jon device pass before this entry is final
(fill the PR # and device-pass date on merge).** yes-chef PR
[#177](https://github.com/jonphillips/yes-chef/pull/177).
[ADR-0037](decisions/ADR-0037-grocery-seed-coverage-diagnostic.md) S1 + S2 (one batch). Closes ADR-0035 OQ1's
curation loop — a read-only, dev-facing review queue for canonical grocery names that miss
`GroceryStoreArea.seed(for:)`. **S1** = pure `SeedCoverageReport` + `make(from:)` in `YesChefCore` (seed hits
excluded via `seed(for:)` not raw `seedAreas`; uncovered vs covered-elsewhere split on any stored aisle;
most-common aisle → `suggestedArea`; count-desc/name-asc sort; deterministic tie-break) + a
`GroceryStoreAreaCache.seedCoverage(in:)` DB adapter over `IngredientLine ∪ GroceryItem` + a tested
Swift-literal export (`.other` placeholder for uncovered). **S2** = `SeedCoverageView` + an always-on
**Developer** section in `SettingsView` (two grouped lists, counts in headers, copy-per-row + copy-per-group via
`UIPasteboard`, reload on appear + `DatabaseChangeBeacon.didChange`). No schema change, no sync surface — purely
derived from existing durable columns ([[grocery-area-no-learned-cache]], [[llm-vs-determinism-surface-boundary]]).
Review fold: adapter switched to the `canonicalIngredientName` accessor (not the raw `canonicalName` column) so
rows with an unpopulated column aren't silently dropped from the queue. New `SeedCoverageReportTests`.

---
## Grocery quantity scaling fix

**Architect-reviewed 2026-07-12, Jon device-passed 2026-07-13 — yes-chef PRs
[#167](https://github.com/jonphillips/yes-chef/pull/167)–[#170](https://github.com/jonphillips/yes-chef/pull/170).**
Scaling a recipe / menu item / meal-plan item never scaled the quantities added to the grocery list —
generation and the source-removal recompute both read raw `line.quantity`. Fixed in `GroceryCore.swift` with one
source-provenance-keyed `groceryScale` helper (priority `menuItem.scale → mealPlanItem.scale → recipe.viewScale`),
applied in both `GroceryGeneratedItemDraft` (scale 1 preserves fraction text byte-for-byte) and `generatedMeasure`;
free-text quantities left unscaled. New + updated tests in `GroceryTests`/`GroceryPlanningTests` (293 pass).

---
## ADR-0035 S2 — on-device grocery store-area classifier

**Architect-reviewed 2026-07-13, Jon device-passed 2026-07-13 — yes-chef PR
[#174](https://github.com/jonphillips/yes-chef/pull/174).**
[ADR-0035](decisions/ADR-0035-grocery-store-area-grouping.md) S2 — the first `.onDevice`-by-design verb. A new
`GroceryCategorizationClient` (mirrors `MenuDepositClient`) classifies the *new, uncached* canonical names
(`aisle == nil`) once, folds output through `GroceryStoreArea.normalized`, and writes `aisle` via
`GroceryStoreAreaCache.applyClassified` — **never** overwriting user/seed/prior (the stability contract),
**never** on the writer, degrading silently to "Other" on `onDeviceUnavailable`. Runs on **both** triggers
(after each generation path AND once on grocery-detail appearance, guarded by uncached-names non-empty) so
existing lists fill without a regen. No schema change; categorization only *places* items, never invents or
merges list data ([[llm-vs-determinism-surface-boundary]]). Touches `GroceryModels.swift` / `GroceryViews.swift`
+ new `GroceryCategorization.swift` / `GroceryStoreArea.swift`; new `GroceryCategorizationTests.swift`. **Closes
ADR-0035.**

---
## ADR-0035 S1 — grocery store-area grouping

**Architect-reviewed & approved 2026-07-13, Jon device-passed 2026-07-13 — yes-chef PR
[#172](https://github.com/jonphillips/yes-chef/pull/172).**
[ADR-0035](decisions/ADR-0035-grocery-store-area-grouping.md), Accepted. The existing synced
`GroceryItem.aisle` column receives a deterministic seed and the flat "To Buy" list groups by store area (no
migration; a fresh migration runs the backfill). Store-walk order fixed to Jon's 13 areas (perishables last,
OQ1 resolved 2026-07-12); a hand-set aisle survives regeneration; Purchased stays a flat crossed-off tail. S2
(on-device long-tail classifier) landed in #174 above.

---
## ADR-0034 S3c — enrich the exported dish context (Amendment 1)

**Architect-reviewed 2026-07-12 — yes-chef PR
[#166](https://github.com/jonphillips/yes-chef/pull/166).**
[ADR-0034](decisions/ADR-0034-prep-plan-work-session-timeline.md) Amendment 1. The menu "Copy Dish Context"
button became a self-contained **frontier** prompt (renamed **"Copy Prep Prompt"**): serializes at `.frontier`
budget, threads full recipe **method** into `MenuChatItemContext` (with `InstructionSection` sub-headers, a
method-first trim rung on the on-device path), **uncaps ingredients** on the frontier path (8 stays the on-device
starting ceiling only), and **prepends a real intro prompt** (adapted `MenuPrepPlanClient.instructions` +
`tasteProfile`/`makeAheadPrepPlanPreference` via `aiPromptPreferences`) asking for **review-text** output so
ChatGPT's answer pastes back cleanly. The meal-calendar per-day make-ahead-strategy verb was left untouched.

---
## Meal-planner (Calendar) row affordance swap

**Architect-reviewed 2026-07-12 — yes-chef PR [#154](https://github.com/jonphillips/yes-chef/pull/154)
(branch `codex/meal-planner-affordances`).** Closes the effort in
[`efforts/meal-planner-affordances.md`](efforts/meal-planner-affordances.md) (Jon's 2026-07-11 dogfood batch,
effort #1). Reworks the meal-calendar row so a **row tap opens the recipe reader** (recipe rows) and the
**Edit-Meal sheet moves off the row tap** onto a dedicated right-hand affordance; note rows (no reader) tap
straight to Edit-Meal. App-layer only (`MealCalendarViews.swift`), no schema. Package tests + `git diff --check`
passed; app build blocked on an unavailable CoreSimulator service (per lean-verification policy, no retry — Jon's
device pass). **Miscommunication caught and resolved:** the brief named an "existing target/grocery row icon" to
sit beside the new calendar icon, but no such control exists in the code — Codex's first pass papered over the gap
and left **Edit-Meal reachable via three redundant controls** (row tap, the Meal-Actions ellipsis "Edit", and the
new calendar button). The architect review flagged the multiple edit paths; that surfaced the miscommunication,
Jon and Codex re-aligned on the intended single affordance model, and the effort was confirmed good. Parked
follow-ons still live in the effort doc: **drag-and-drop retest on Beta 3** and **cell images**.

---
## Workbench dogfood polish (Jon's 2026-07-11 two-device pass)

**Architect-approved 2026-07-11 — rides in the slice commit; app build + device pass are Jon's.** Effort
[`efforts/workbench-dogfood-polish.md`](efforts/workbench-dogfood-polish.md), all six slices shipped in the
working tree: candidate rows show thumbnail + source; draft rationale renders candidates by **title/source not
object ID** (chat context + synthesis prompt both hardened); the apply/review sheet is **scrollable**;
**archive-all-candidates** archives the candidate recipes *out of the library* + clears them from the workbench
(Jon-confirmed intent: the workbench distills the one true recipe and removes the noise; menu/meal-plan cascade
accepted); **pick a candidate photo** for the working recipe (copies BLOBs to a new hero + sets cover, validated
to a candidate → sync-safe); and **"Drafted From" provenance links** on the promoted recipe (degrade to title
snapshot on delete/archive). App-layer + two core files; package builds + 4 new tests pass. **Device note:**
archive-all deletes the candidate rows, so the "Drafted From" links clear with them — transient provenance by
design (a persistent-provenance variant is a separable follow-up if wanted).

---
## Chrome & navigation polish (Jon's 2026-07-11 two-device pass)

**Architect-approved 2026-07-11 — rides in the slice commit; app build + device pass are Jon's.** Effort
[`efforts/dogfood-fixes-2026-07-11-chrome.md`](efforts/dogfood-fixes-2026-07-11-chrome.md), all five slices
shipped in the working tree: side-menu order/naming (Recipes · Groceries · Calendar · Menus · Browser · Workbench
· Settings); AI-widget cleanup (dropped the on-/off-device disclaimer + static provider label + de-mangled a11y
hint, chat input two lines); recipe-detail toolbar reorder (Edit · Grocery · Add Meal · AI toggle · Workbench);
delete-a-recipe-image-without-replacing (new `removesHeroPhoto` draft flag, cover clears, sync-safe); and the AI
apply-action relabel + per-verb SF Symbols (Save to Notes / Suggest Dishes / Chef It Up / Create Prep Plan /
Revise Recipe, suffixes dropped). App-layer, no schema. Package builds + 29 touched tests pass.

---
## 🎉 iCloud sync working end-to-end across two devices (M4 milestone confirmed)

**Jon device-confirmed 2026-07-11:** recipes, images, menus, and the whole synced library round-trip
**end-to-end across two physical devices** (`iPad Pro 13-inch (M5)` ↔ `iPhone 17 Pro`). This is the M4
iCloud-sync milestone ([`milestones/M4-icloud-sync.md`](milestones/M4-icloud-sync.md), ADR-0002/ADR-0010)
**landing in practice** — the one-way gate everything preceded is crossed and holding. The earlier
"missing content on iPhone" scare was diagnosed (ADR-0028) as a throttled bulk *initial* sync that simply
needed to finish downloading, **not** data loss; once caught up, convergence is clean. We remain in the
CloudKit **Development** environment by design (schema still evolving) — the production-schema promotion is
the deliberately-held ops step in `CURRENT_HANDOFF.md`, not a blocker on dogfooding sync. Prior sync round-trip
milestone: the extension-sync fix ([[extension-sync-construct-not-run]], PR #49).

---
## ADR-0028 — Sync status indicator accuracy (throttled-initial-sync honesty)

**Accepted (scope corrected) 2026-07-10; fix on main, Jon device-passed via the two-device sync run above.**
Implements [ADR-0028](decisions/ADR-0028-multi-foreign-key-sync-loss.md). The dogfood "missing content on
iPhone" turned out to be **CloudKit rate-limiting a ~44k-row + 2.5k-asset first pull** (`CKError 7/2062`), not
multi-FK content loss — the debug "Local record counts" sheet showed the child tables **climbing, not zero**,
so the proposed schema/zone rebuild was **disproven and withdrawn** (holds [[sqlitedata-single-fk-sync-limit]]).
Two real bugs fixed instead: **(1)** the "Up to date" indicator lied — it flipped green mid-download; `SyncHealth`
gained an `isFetchingChanges` input + a `SyncDisplayStatus.downloading` case (gated after upload-pending) so the
row stays "Downloading changes from iCloud" until the pull completes (lives in **CloudSyncKit**, shared with
galavant; reducer-tested). **(2)** the demo-seed gate — deterministic `00000000-…` keys were polluting the zone.
The debug count-row sheet stays (it caught the misdiagnosis). Accepted limitation: no public throttle/backoff
signal exists (SQLiteData swallows the `CKError`), so the row can't say "paused by iCloud" and may briefly flash
"Up to date" between throttled batches — recorded in the ADR.

---
## ADR-0029 — Main-thread DB writes + over-heavy list/grocery fetch (the UI-stall pass)

**Accepted / Resolved 2026-07-11 — PRs [#148](https://github.com/jonphillips/yes-chef/pull/148) (S1) +
[#149](https://github.com/jonphillips/yes-chef/pull/149) (S2/S4/S5b + the S5a→S6c diagnostics + the S7 fix,
`ba9d7bd`). Jon device-confirmed.** Implements [ADR-0029](decisions/ADR-0029-main-thread-write-and-fetch-cost.md).
The dogfood symptom — archive ≈ 1 s, variation switch janky, then measured at **5.6–6.8 s** — resisted four
successive theories (writer convoy, image decode, COMMIT envelope, main-actor delivery), each retired by a
timestamped capture. **Finding 8 (the real root cause):** `GroceryIngredientChoiceRequest`, an **always-on
whole-library `@Fetch` re-running synchronously on the writer inside every affected commit** — so every quick
mutation paid ~5 s of self-inflicted writer occupancy ([[sqlitedata-fetch-writer-convoy]]). **S7 fix:** remove
the two always-on grocery `@Fetch`es from `GroceryLibraryModel`, add a **scoped** `YesChefCore` fetch (choices
for an explicit `Set<Recipe.ID>`), and load them **on-demand at presentation time** via `database.read` (pool
readers, never the writer) when the ingredient-selection sheet opens. Also shipped as correct hygiene: S1 async
off-main writes for the six tap handlers, S2 thumbnails-only list fetch (no full-res BLOBs), S4 off-main
downsampled+cached detail-photo decode, S5b. **Result: writer-api-return dropped from ~5000 ms to tens of ms on
every mutation; no schema change, no sync change, no image change.** New invariant recorded in the ADR: *no
always-on `@Fetch` may perform O(library) work or read full rows of tables with large inline BLOBs.* S3
memoization + fetch-animation narrowing closed as unnecessary (render work measured sub-millisecond throughout).
Residuals parked (not scoped): `RecipeListRequest` ×4 (post-S2 thumbnails-only, bounded — watch, don't rebuild).
The S7 behavioral test (`GroceryIngredientChoiceTests.swift`) is authored but still untracked — Jon commits it.

---
## ADR-0027 — "Capture to menu" harvest verb (S1)

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#141](https://github.com/jonphillips/yes-chef/pull/141)
(branch `codex/adr-0027-capture-to-menu`).** Implements
[ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md) (Accepted 2026-07-10), S1. A new **extraction**
menu chat verb — the inverse of the generative complement family — that takes content **already in the chat**
and captures it as one or more `.note`-kind `MenuItem`s. The model **segments and reshapes** rambling chat
prose into clean recipe-looking notes (title + body) and **never invents**; output is a JSON array of
`{title, body}`, one per distinct note ([[llm-curation-not-synthesis]]). Rode the already-merged ADR-0026
collection sheet ([#138](https://github.com/jonphillips/yes-chef/pull/138)). **Additive `aiSettings`
`captureToNotePreference` column only** (non-null, nonempty default), otherwise sync-safe by construction —
captured rows are always `.note` with no `recipeID` ([[menu-item-recipe-id-invariant]] sidestepped for free).

- **Payload + client (`YesChefCore/MenuNoteHarvest.swift`).** `MenuNoteHarvestPlan { notes: [HarvestedNote] }`
  / `HarvestedNote { title, body }` (Equatable/Sendable) with the ADR-0024 `editableReviewText()` /
  `applyingEditableReviewText(_:)` round-trip, mirroring `MenuComplement.swift`. The `@Dependency`-injected
  `MenuNoteHarvestClient` deliberately takes **no `context:` argument** — the menu is **not** sent (D2, the fix
  for Jon's "it sent the whole menu" surprise). Two prompt modes, one client: non-empty selection → the
  selection alone; empty → the assistant transcript. **LLM always runs** even for an exact selection (OQ2).
  Static `parse(_:)` tolerates ```json fences and drops empty-title elements. `maxTokens: 1536`,
  `reasoningEffort: .medium` (matches complement).
- **Wiring (`MenuModels.applyActionCatalog`).** A `ChatApplyAction<MenuNoteHarvestPlan>` titled "Capture to
  menu", mapping `plan.notes` → one `ChatApplyReviewItem` per note, each committing its own `.note` `MenuItem`
  via `commitCapturedNote` → `MenuRepository.addNoteItem`. **Placement (OQ1): deterministic Day 1 / Dinner** —
  menu detail renders all days in one scroll with no selected-day state, so captured notes land in a fixed slot
  the user moves afterward (flagged in the PR).
- **Selection plumbing fix.** The apply-menu tap resigns the assistant bubble's first responder before its
  action runs, which previously wiped the shared selection — so selection-scoping never survived to *any* verb.
  `ChatAssistantSelection.relinquish` now **retains** the text on resign (releasing only bubble ownership) and
  the action clears it via `clear(ifMatching:)` after consuming it. Latent bug the ADR assumed absent; fixes
  every selection-scoped verb, not just harvest.
- **Task preference.** New `AIPromptPreferenceKind.captureToNote` + a "Capture to Note" Settings editor with a
  recipe-formatting default prompt, shared through the existing model-boundary preference injection (ADR-0018).
- **Architect fix during review ([#141](https://github.com/jonphillips/yes-chef/pull/141), commit `05c481b`).**
  The harvest `AnyChatApplyAction` inherited the default `requiresSubject: true`, so the no-selection case fell
  back to the latest-reply subject and `run()` fed that reply in as `selection` — keeping the client in
  explicit-selection mode and making the ADR-0027 D2 **transcript-scan branch unreachable in production** (the
  existing unit test called the client directly, bypassing the wiring). Set `requiresSubject: false` so an
  empty selection reaches the client and the transcript branch runs; added a wiring-level guard test that
  builds the real catalog and asserts the flag.
- **Verification.** `swift test` (package) green — 278 tests; app + test targets compile clean
  (`build-for-testing`, generic iOS Simulator destination) so the wiring change and new tests build;
  `scripts/check-drift.sh` green. A device-bound build (iPad Pro 13-inch M5) could not run in this environment
  — no iOS 27 simulator present — consistent with the lean-verification stance. **Device pass complete
  (Jon, 2026-07-12):** selection path (highlight survives the apply-menu tap), transcript path (N notes), and
  Day 1/Dinner placement all confirmed on `iPad Pro 13-inch (M5)` + `iPhone 17 Pro`.

## ADR-0027 S2 — "Capture to notes" (the recipe sibling of the menu harvest verb)

**Merged to main — yes-chef PR [#147](https://github.com/jonphillips/yes-chef/pull/147) (branch `adr27s2`);
architect-confirmed in code + Jon device-passed 2026-07-12.** Implements
[ADR-0027](decisions/ADR-0027-harvest-chat-into-notes.md) D6/S2 — the recipe instance of the same harvest verb,
the sibling ADR-0027 S1 deferred until its shape proved out. Adds a **"Capture to notes"** extraction verb to the
recipe chat catalog (`RecipeDetailModel+Enrichment.swift`): captures a chat selection (or, absent one, the
assistant transcript) into one or more `RecipeNote`s on the recipe, reusing the same `MenuNoteHarvestPlan` /
`HarvestedNote` payload and client as the menu verb. Wired `requiresSubject: false` so the no-selection
transcript-scan branch stays live in production ([[harvest-verb-requires-subject-false]]); list commit shape, one
review item per note through the ADR-0026 collection sheet. Commits via the shared
`RecipeRepository.appendRecipeNote` primitive (`YesChefCore/RecipeCapturedNote.swift`) writing a `.general`
`RecipeNote` — the canonical recipe body is never touched. Schema-free / sync-safe (`.general` is an existing
`RecipeNoteType`). Package tests green; app build + device pass are Jon's (now done).

## ADR-0027 Amendment 1 — the tap-to-target "deposit" verbs (S1 recipe-append · S2 note-revise)

**Merged to main — yes-chef PR [#146](https://github.com/jonphillips/yes-chef/pull/146) (branch `adr27s1`) +
the Amd-1 S2 commit `4df9fc2`; architect-confirmed in code + Jon device-passed 2026-07-12.** Implements
[ADR-0027 Amendment 1](decisions/ADR-0027-harvest-chat-into-notes.md#amendment-1--deposit-chat-intelligence-onto-the-item-you-point-at-recipe-append--note-revise)
— write chat *intelligence* (a Compare verdict, a "here's how I'd change this" riff) onto the **existing menu
item you point at**, adaptively by canonical-ness:

- **A5 — tap-to-target binding (the one genuinely new UI piece).** `MenuModels` gains a device-local, unsynced
  `depositTargetItemID` + a "Deposit target" toggle row in `MenuDetailSections.swift` (target icon, a11y label,
  tinted highlight); tapping the active target clears it. The deposit verbs only appear when a target is set.
- **A2 — recipe target → append (S1, "Add to recipe notes").** `depositToRecipeActions` reshapes the
  intelligence into one note and appends it via `RecipeRepository.appendRecipeNote` with the **`.adaptation`**
  note type (a new, additive `RecipeNoteType` case — sync-safe, no migration); the recipe body is never
  rewritten (protect the canonical recipe).
- **A3 — note target → revise via a compose surface (S2, "Revise this note").** `reviseNoteActions` runs the
  `MenuDepositClient` revise mode (weaves intelligence into the note's current body) and surfaces the woven draft
  as the editable review text **beside the "Original note" as supporting evidence** (OQ-Amd-2 resolved: neither
  pure replace nor merge — a compose surface, the original stays salvageable), committing over `menuItems.notes`.
  `requiresSubject: false`.

Payload `DepositNotePlan { note: DepositedNote { text } }` + `MenuDepositClient` (extract + revise modes) in
`YesChefCore/DepositNote.swift`; `DepositNoteTests` cover it. **No queue / no auto-Workbench / no graduation**
(A4 — the recorded reversal): a deposit touches **only** the item pointed at. Schema-free; both writes are
additive/in-place on already-synced tables. **Still deferred by the ADR (separate future efforts, not Amd-1
follow-through):** OQ4 taste preference and A6/D5 promote-a-note → real recipe.

## Logging for Frontier LLM Interaction

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#139](https://github.com/jonphillips/yes-chef/pull/139)

- Jon just put this here. Claude may want more details -- feel free to rewrite. We can now view logs in the Xcode console.

## ADR-0026 — the LLM-review collection becomes the universal slide-up sheet (S1 + S2)

**Architect-reviewed & approved 2026-07-10 — yes-chef PR [#138](https://github.com/jonphillips/yes-chef/pull/138)
(branch `codex/adr-0026-review-collection-sheet`, commit `f135d25`; core check-drift green — 270 tests, 0 lint;
app layer device-passed by Jon).** Implements [ADR-0026](decisions/ADR-0026-review-collection-sheet.md)
(Accepted 2026-07-10), S1 + S2 in one PR. **Schema-free, sync-safe by construction** — an in-memory
review-surface refactor over the existing `ChatApplyReviewItem` collection, no table/column. Dispatch 2 (and
last) of the 2026-07-09 menu-planner pass; held apart from Dispatch 1's low-risk quick-fixes because it
re-touches the shared `RecipeChatWorkspace` apply-action presentation state. Extends
[ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (the per-item editable sheet — the layer below);
serves [ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) curation. [[chat-verb-commit-shapes]],
[[llm-curation-not-synthesis]].

- **S1 — collection sheet (D1–D3).** New host-agnostic `RecipeCollectionReviewSheet` (`YesChefApp`),
  parameterized by `[ChatApplyReviewItem]` + `commit`/`discard`/`discardAll`/`onEmpty` closures — **not** baked
  into `RecipeChatPanel`'s `@State`, which is what let S2 reuse it. It lists the staged set (title + summary +
  per-item Discard) and drills into the ADR-0024 editable review; per-item commit/discard removes the item and
  keeps the sheet open on the remainder; discard-all is one confirmed gesture. The cramped inline
  `ChatApplyReviewList` band is **removed** from `RecipeChatPanel`, along with its now-dead `ChatApplyReviewCard`,
  `ChatActionSummary`, and `ChatCommittedActionSummary`; the panel's `presentedReviewItem`/`actionSummary`
  `@State` collapses to a single `isReviewSheetPresented` bool. `ChatApplyReviewRow` was promoted from `private`
  so the new sheet can host it.
- **OQ behaviors preserved.** N=1 skips the list and auto-drills into its editable review (`reconcilePresentedItem`
  on appear/count-change); the N→1 transition (committing/discarding to the last item) re-drills cleanly; a
  lightweight per-item green commit confirmation lives in the sheet (OQ4 — replacing the removed panel-level
  `ChatActionSummary`); the per-item `supportingEvidenceRows` disclosure survives the hoist unchanged (OQ3).
- **D4 adjust verb — launch-only row.** The sole `.inline`-presentation consumer ("Adjust this recipe",
  ADR-0023) renders as a launch row inside the collection sheet whose primary action delegates to the item's
  commit, which opens the Compare-diff `RecipeAdjustmentReviewView` exactly as before — the sheet lists
  *everything the LLM proposed* while Compare-diff still **owns** the adjust review. No apply-action's commit
  contract changed; the router picks the row affordance from `presentation`.
- **S2 — reader-feedback curation adopts it.** `RecipeCaptureView`'s hand-rolled `Section("Reader Feedback")`
  proposal rows (each opening a one-off `ChatApplyReviewSheet`) are replaced by a single "Review N proposals"
  button that presents the same `RecipeCollectionReviewSheet`, hosted directly in the capture Form (no chat
  panel). The `ReaderFeedbackSheet.review` enum case dropped its per-tip associated value. Commit removes the
  tip from `readerFeedbackProposals` via the existing `acceptReaderFeedbackTip` → `discardReaderFeedbackTip`
  path; discard matches the tip by text (safe because proposals are deduped by lowercased text at stage time).
- **Verification.** `xcodegen generate` + `scripts/check-drift.sh` green; one app build attempt was blocked
  before compilation by an unavailable Xcode-beta simulator service (`simdiskimaged`) and not retried per repo
  rules. **Device pass owed (Jon):** the architect review flagged two interaction risks — (1) the adjust launch
  row presents Compare-diff from `RecipeDetailView` while the collection sheet dismisses from `RecipeChatPanel`
  in the same runloop (present-while-dismiss across two anchors — confirm Compare-diff isn't swallowed); (2) N=1
  auto-drill stacks the child review sheet over the collection sheet (functionally fine; confirm it reads
  cleanly, incl. iPad split-chat, OQ2).

---

## ADR-0025 D6 + D7 — curation-prompt preference + curated notes into chat (effort closed)

**Merged to main 2026-07-09 — yes-chef PR [#134](https://github.com/jonphillips/yes-chef/pull/134)
(branch `adr-0025-d6-d7-and-reader-feedback-editing`, commit `50b3965`; core carries unit tests, app layer
device-passed by Jon).** Closes the [ADR-0025](decisions/ADR-0025-reader-comment-ingestion.md) reader-comment
ingestion effort (Amendment 2026-07-09). Additive schema only — sync-safe.

- **D6 — DB-backed curation-prompt preference (ADR-0018).** Added `AIPromptPreferenceKind.readerFeedback`, an
  additive `aiSettings.readerFeedbackPreference` column, wired the curation request's `promptPreferenceKey`
  (previously `nil`) through `ReaderFeedbackCurationClient`, and exposed the editor in AI settings — the
  established prompt-preference pattern, no new storage.
- **D7 — curated notes feed the chat (read-only).** `RecipeChatRecipeContext` gained a **distinct
  `readerFeedback` bucket** fed from accepted `RecipeNote(.readerFeedback)` rows — context injection, not an
  actionable verb; no writes, no synthesis ([[llm-curation-not-synthesis]]).
- **Bundled with the effort (same PR).** A **capture review-sheet fix** (lifted the reader-feedback `.sheet`
  off the Form-embedded subview onto the parent `RecipeCaptureView` Form so tapping Review no longer collapses
  the presentation), **inline reader-feedback editing** (per-tip Edit/Done + Delete in the recipe's Reader
  Feedback section, backed by scoped/tested `RecipeRepository.updateReaderFeedbackNote` /
  `deleteReaderFeedbackNote` that only touch `.readerFeedback` notes), and a latent `MenuModels` build fix
  (explicit `return` in a multi-statement complement `.map` closure).
- **S6** — Jon's end-to-end device test on a real NYT recipe (Load Comments → curate → review/promote → accept
  → notes appear in Reader Feedback, drop out of cooking mode, reach the chat context). **Production-deploy
  note:** the additive `aiSettings.readerFeedbackPreference` column joins the held prod-schema checklist in
  `CURRENT_HANDOFF.md`.

**ADR-0025 effort arc (full lineage, all merged to main):** D1/D2 harvest + curation **scaffolding**
([#129](https://github.com/jonphillips/yes-chef/pull/129)), the **curation revision**
([#131](https://github.com/jonphillips/yes-chef/pull/131)) with its same-day companion **"Quick fixes"**
([#132](https://github.com/jonphillips/yes-chef/pull/132) — the bulk was `ReaderFeedbackCuration` +
`RecipeCaptureView` curation work, not the "meal-planner build fix" the earlier one-liner implied; carries
`ReaderFeedbackCurationTests`), and **D6/D7 + S6** ([#134], this entry) — NYT "Most Helpful" harvest →
LLM-curate distinct tips → reviewable `RecipeNote(.readerFeedback)` + curation-prompt preference + read-only
chat-context feed. Additive enum + `aiSettings` column, no new table; sync-safe. Effort closed.

---

## Menu-planner dogfood 2026-07-09 — quick-fixes bundle

**Merged to main 2026-07-09 — yes-chef PR [#136](https://github.com/jonphillips/yes-chef/pull/136).** The
one-PR, no-schema quick-fixes bundle from the 2026-07-09 menu-planner dogfood pass (brief
[`efforts/dogfood-fixes-menu-planner-2026-07-09.md`](efforts/dogfood-fixes-menu-planner-2026-07-09.md)): the
**chat selection-clear bug + a clear affordance**, the **complement note-body** write (ADR-0012 Amendment 2 —
complement suggestions land their body onto the `.note` `MenuItem`), the **prep-plan "explain better"** revision
(compose from the stored Make-Ahead strategy, just describe it more legibly — [[menu-planner-dogfood-2026-07-09]]),
and **variation rename**. App-layer, no schema; nothing left.

---

## ADR-0024 Slice 2 — list / structured verbs get editable review

**Architect-reviewed & approved 2026-07-09 — yes-chef PR [#128](https://github.com/jonphillips/yes-chef/pull/128)
(branch `codex/adr-0024-s2-editable-list-verbs`; built on device by Jon; core round-trip + fidelity carry unit
tests).** S2 of
[ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (Accepted 2026-07-09). **Schema-free, app-wide.**
Completes the ADR: every list / structured verb the S1 sheet showed read-only is now **editable while keeping
its commit shape intact** (D4) — no list flattened into an opaque string ([[chat-verb-commit-shapes]],
[[llm-curation-not-synthesis]]).

- **Per-shape parse round-trip (D4/OQ2 lean).** Each verb gained an `editableReviewText()` /
  `applyingEditableReviewText()` pair in `YesChefCore`: `ServeWithPlan`, `MenuComplementSuggestion`,
  `MealPlanComplementSuggestion`, `MealPlanMakeAheadStrategy`, `MenuPrepPlan`, and `WorkbenchDraftRecipe`
  (its **prose fields** — rationale/title/subtitle/summary/servings/yield/cuisine/course/ingredient-section/
  notes — beyond S1's rationale-only edit; ingredient/instruction lines stay structured, untouched). The edited
  text re-parses to the typed payload on commit; latent provenance (`sourceItem`/`sourceDish`) is preserved for
  lines the user left unchanged via a group-and-drain pop.
- **Unchanged-payload fidelity guard (the review fix, commit `Preserve unchanged editable review payloads`).**
  The commit path always re-parsed, even with zero edits — and the flat `"title: note"` format can't losslessly
  round-trip a colon-in-title Serve-With item (`"2:1 rice"` → `title "2" / note "1 rice"`), a regression from
  S1's faithful original-payload commit. Fixed by short-circuiting: when the committed text is byte-identical to
  the presented `editableText`, commit the **original payload** untouched (`action.commit(payload)` at the
  `AnyChatApplyAction` layer; `edited == original ? original : applying(edited)` at the four inline
  `ChatApplyReviewItem` sites). Invariant is now uniform: **un-edited commit → faithful original; edited commit
  → re-parse.** Two regression tests document the parser ambiguity and prove the guard commits the original.
- **D5 scope.** The ADR-0023 "Adjust this recipe" compare verb stays `.inline`, untouched.

---

## ADR-0024 Slice 1 — editable proposal preview (single-string verbs)

**Architect-reviewed & approved 2026-07-09 — yes-chef PR [#127](https://github.com/jonphillips/yes-chef/pull/127)
(confirm the number when cutting); merges after Jon's device pass** (the app layer — the presented sheet and its
iPad split-chat host — is verified only in Jon's Xcode build; the core D3 contract change carries a unit test).
S1 of [ADR-0024](decisions/ADR-0024-editable-proposal-preview.md) (Accepted 2026-07-09). **Schema-free,
app-wide.** The two-step S1 plan collapsed to one: the planned shared capture-sheet dismiss hardening (step 1)
was already landed by batch 5's "Harden capture review dismissal" commit — `RecipeCaptureView` and
`ShareViewController` both already carry `interactiveDismissDisabled` + `isModalInPresentation` + discard-confirm
— so S1 delivered the remaining editable-chat-sheet step.

- **D3 contract change (the risk) — additive.** `ChatApplyReviewItem` gains `presentation`
  (`.inline`/`.sheet`), `editableTitle`, `editableText`, and `commit` now takes an `approvedText` argument.
  Backward compatible: the legacy zero-arg `commit` init is preserved (wrapped `{ _ in }`), and a new
  `AnyChatApplyAction(editableSummary:commitEditedSummary:)` init sits beside the existing
  `renderedSummary`/`reviewItems` inits. Every prior call site keeps working; only the default presentation
  flips to `.sheet`.
- **D2 authorship.** Commit persists the edited string verbatim — Make-ahead / Chef-It-Up route through the
  newly-public `RecipeRepository.updateMakeAhead` / `updateChefItUp` (these sections are prose blobs stored as
  `String`, so editing the rendered text and writing it back is lossless); the committed-action summary reflects
  the approved text.
- **D4 per-shape.** Make-ahead / Chef-It-Up / workbench-rationale edit as prose (the workbench sheet edits only
  `rationale`, keeps the structured draft intact, and shows the full review in a "Full proposal" disclosure).
  List verbs (Serve-With, complements, prep-plan) inherit the roomy **read-only** scrollable sheet now; their
  editing is S2 — no list is flattened into an editable string.
- **D5 scope + OQ1.** `.sheet` is the app-wide default; the ADR-0023 "Adjust this recipe" compare verb stays
  `.inline` (verified the only compare verb). OQ1 dismiss-hardening built into the sheet:
  `interactiveDismissDisabled(hasUnsavedEdits)` + Discard-with-confirm-when-edited + commit disabled on empty.
- **Tests** — new `ChatApplyReviewItemTests.editableReviewItemCommitsApprovedText` proves the edited string
  reaches commit; the existing apply-action tests updated to the new `commit(_:)` signature. Core package builds
  and tests pass.

**Device-pass follow-ups (non-blocking, from the review):** OQ3 — confirm the sheet presents over the detail
view (not cramped inside the chat column) and doesn't fight the `ChatWorkspaceDetent` drag on iPad split-chat;
eyeball that the auto-presented sheet + its staged "Review" row behind it don't read as a duplicate.

---

## Dogfood fixes — batch 5 (mechanical polish)

**Architect-reviewed 2026-07-09 — yes-chef PR [#126](https://github.com/jonphillips/yes-chef/pull/126);
merges after Jon's device pass** (the app target never compiled in CI — its `PreferenceKey` concurrency
error and the whole app layer are verified only in Jon's Xcode build). Four mechanical dogfood fixes from
the 2026-07-08 pass, one PR; `efforts/dogfood-fixes-batch-5-mechanical-polish.md`. **Schema-free.**

- **Recipe-detail layout/toolbar** — "Chef It Up" now renders below Notes (both idioms); the Focus control
  became highlighted leading chevrons with the Edit button moved leading; the Chat button *toggles* the
  iPad split (balanced ↔ reader-only) instead of only opening.
- **Recipe editor** — multiline fields auto-grow to fit content (fixes the instruction-scroll truncation;
  also Summary/Notes/Source), via a measured-height `StackedTextEditor`; **Make-Ahead + Chef-It-Up are now
  editable** with a no-clobber guard (`RecipeEditorDraft.editsMakeAheadAndChefItUp` — a save that doesn't
  touch them preserves existing values); async save + spinner (`isSaving`), Save/Cancel disabled while
  saving, no double-save.
- **Recipe search** — a shared tokenized, case/diacritic-insensitive `RecipeSearchMatcher` (all query
  tokens must match, across the fields each picker already searched) replaces `localizedCaseInsensitiveContains`
  in the Menu, Meal-Calendar, Workbench, and string-filter pickers ("Sous Vide pork" → "Sous Vide indoor
  pulled pork").
- **Web/share capture review** — title / summary / servings / total-time are editable before import on both
  hosts (in-app `RecipeCaptureView` + share extension); provenance/dedup URLs strip tracking params and the
  fragment, preferring the page's canonical `og:url`. The first cut removed the *entire* query (a dedup
  collision on query-param sites); corrected in follow-up commit `5fd2934` to a tracking-key **denylist**
  (`URLProvenanceNormalization.strippingTrackingParametersAndFragment`) that keeps meaningful params — the
  new test asserts `?id=123` ≠ `?id=456` stay distinct. Known accepted asymmetry: the parsed canonical is
  preferred verbatim, not re-stripped (trusting the site's declared canonical).

New core tests cover the matcher, the Make-Ahead/Chef-It-Up round-trip + clear, the URL strip/dedup, and
review-edits-persist-on-import. The `PreferenceKey` concurrency fix (computed `defaultValue`) is folded in.

---

## Recipe edit proposals — S2 (the "keep as a variation" commit destination — ADR-0021's build)

**Merged — yes-chef PR [#123](https://github.com/jonphillips/yes-chef/pull/123)** (backfilled into this log
2026-07-09 from the ratified ADRs; confirm detail against #123). Implements
[ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S2, which **is** ADR-0021's build
([ADR-0021](decisions/ADR-0021-recipe-variations.md)); `efforts/recipe-edit-proposals.md`. Adds **"keep as
a variation"** as the second commit path on the *same* proposal surface built in S1 — the structured delta
the S1 extractor already produces *is* the ADR-0021 variation payload (no separate extraction; resolves
ADR-0021 OQ1/OQ2).

- **Schema (synced):** introduces the `recipeVariations` table + BLOB + migration — a synced-schema change,
  so it is on the standing production-deploy list in CURRENT_HANDOFF.
- The **reader fold** — a selected variation renders highlighted-in-place over the base recipe (add / change
  / remove).
- The **grocery fold** — deterministic, per [[llm-vs-determinism-surface-boundary]] (the variation delta
  folds into the grocery list without an LLM).
- Resolves **ADR-0023 OQ3**: overwriting a recipe that already carries variations must re-validate/rebase or
  warn, since the delta anchors on base-ingredient identity (the conservative overwrite-block).

---

## Recipe edit proposals — S1 (the "Adjust this recipe" verb + section-aware overwrite/undo)

**Architect-reviewed + Jon device-passed 2026-07-07** — yes-chef PR #122 (this slice). Implements
[ADR-0023](decisions/ADR-0023-recipe-edit-proposals.md) S1 (which extends
[ADR-0021](decisions/ADR-0021-recipe-variations.md)); `efforts/recipe-edit-proposals.md`. **Schema-free** —
no migration, no synced column. The **first chat verb that edits a recipe's canonical ingredients/method**
(Make-ahead/Chef-It-Up/Serve-With only ever wrote additive sidecar sections; the workbench draft only
*creates*). Made safe by construction: the model writes only to a transient preview, never to a stored
recipe, until a human tap.

Landed as two passes on branch `codex/adjust-recipe-s1`. **Pass 1** built the primitive: a `.adjustRecipe`
apply-action on `RecipeDetailModel.applyActionCatalog` (so it lands on **every recipe and the workbench
working recipe** at once, ADR-0023 D1); a **delta extractor** (`RecipeAdjustment.swift`) mirroring
`WorkbenchDraftRecipeClient` that emits a **structured delta** in ADR-0021 D2's closed op vocabulary
(`add`/`remove`/`substitute`/`scale` + prose method note / whole-step replacement — never a re-blended
recipe, [[llm-curation-not-synthesis]]), `high` effort with a `maxTokens: 16_384` budget that covers
reasoning **and** output and throws on truncation ([[reasoning-budget-starves-output]]); a **side-by-side
review** (`RecipeAdjustmentReviewView.swift`) reusing `WorkbenchCompare` canonical-name alignment (full-screen
cover on iPad, sheet on iPhone); and **overwrite-in-place** guarded by a **device-local, in-memory,
sync-excluded** one-level undo restore point (`RecipeBundleCoding` snapshot — the pristine `originalSnapshot`
provenance column is left untouched, ADR-0023 D5).

**Pass 2 (section-aware revision)** fixed the pass-1 limitation that only the *first* ingredient/instruction
section was edited (it round-tripped through a single `ingredientText`). It now mutates the detail's
`[IngredientLine]`/`[InstructionStep]` arrays **in place across all sections**, preserving each line's
`id`/`sectionID`/`sortOrder` (the ID-preservation S2 variation-anchoring wants); adds an optional `sectionName`
to the `add` op (case-insensitive match, else first section); a private `replaceEditableChildren` multi-section
overwrite/restore writer (atomic delete+insert of the recipe's own children — general notes only, so
provenance/photos/tags/categories/source/adaptation notes stay untouched); and a **latent-bug fix** to
`restoreRecipeAdjustment` so undo restores the **full multi-section** recipe instead of collapsing it to one
section. Core-tested (`RecipeAdjustmentTests` — cross-section apply, two-section overwrite, and the
two-section undo that broke before). **OQ4 held**: the plain-recipe and workbench-working-recipe paths are the
same `Recipe`+delta code, no fork. Review caught + fixed a `file_length` overflow (structs/methods split into
`RecipeDetailModel+Adjustment.swift`) and a `.first`-without-fallback build regression before merge.

---

## LLM-aligned Compare matrix (ADR-0022) — shipped S1–S4 + Compare→chat affordance

**Architect-reviewed + merged 2026-07-07** — yes-chef PRs [#116](https://github.com/jonphillips/yes-chef/pull/116)–[#120](https://github.com/jonphillips/yes-chef/pull/120).
Implements [ADR-0022](decisions/ADR-0022-llm-aligned-compare-matrix.md) (now **Accepted**), the semantic
upgrade to the Workbench Compare matrix; `efforts/compare-alignment.md`. **S1** ([#116](https://github.com/jonphillips/yes-chef/pull/116))
was a no-LLM **parse/key fix** that stands alone and improved the deterministic fallback: fixed the
singularizer `chilies → chily` bug and a dual-unit quantity leak. **S2–S4** ([#117](https://github.com/jonphillips/yes-chef/pull/117)/[#118](https://github.com/jonphillips/yes-chef/pull/118)/[#119](https://github.com/jonphillips/yes-chef/pull/119))
built the **LLM aligner**: clusters ingredient rows by culinary role (chicken breast ≡ thigh;
`chile`/`chiles`/`chilies` collapse to one row; `morita` ≈ `chipotle`) and orders by role ("protein at
top"), structured-out with verbatim cells, cached per candidate-set, with the deterministic `comparisonKey`
as the fallback when the LLM is unavailable. The **boundary** held: the LLM drives *presentational*
alignment on the read-only, self-correcting Compare surface only — grocery consolidation stays deterministic
([[llm-vs-determinism-surface-boundary]]). [#120](https://github.com/jonphillips/yes-chef/pull/120) added a
**Compare→chat affordance** (jump from the matrix into workbench chat) and extracted a shared
`ModelResponse.wasTruncated` (`ModelResponse+Truncation.swift`) used by both the aligner and the draft verb.
The prior-session review's two open questions (content-hash vs. identity for the cache; keep-or-split the
chat rework) were both resolved — the chat rework was split into its own PR (#120).

---

## Compare-key granularity — coarser matrix key, grocery key untouched

**Merged 2026-07-07** — yes-chef [PR #114](https://github.com/jonphillips/yes-chef/pull/114);
`efforts/comparison-key-granularity.md`. A second, coarser `CanonicalIngredient.comparisonKey` that the
Workbench Compare matrix aligns on so `fresh`/`frozen`/`dried` variants share one base row with the form
shown in the cells. The grocery canonical key is **untouched** (determinism-at-merge preserved); no schema.
Core-only. This became the *fallback* that ADR-0022's LLM aligner sits on top of.

---

## Recipe Workbench — S4 (Compare: ingredient-diff matrix + Full flip-through)

**Merged 2026-07-07** — yes-chef [PR #113](https://github.com/jonphillips/yes-chef/pull/113);
`efforts/recipe-workbench.md`. Completes the Workbench build arc **S1–S4**. App-layer only — no migration,
no new fetch, no sync touch. A pure `WorkbenchCompare.ingredientComparison` read (`WorkbenchCompareCore.swift`)
with unit tests, rendered by a responsive `WorkbenchCompareView` (full-screen cover on iPad via the
`.detailOnly` focus pattern, sheet on iPhone), reached from a **Compare** button in the Candidates header
(enabled at ≥2 comparable recipes). Two segments behind one entry point: the **Ingredients** aligned matrix
(canonical-name rows, working recipe pinned as a frozen first column, blank cell = ingredient absent) and the
**Full** whole-recipe flip-through (ingredients + directions, one recipe at a time — the parked tabbed
quick-view folded in here). Alignment is exact `canonicalName` match only; anything ambiguous drops to a
per-column "other" tail rather than force-merging (a wrong alignment is worse than an honest blank).

---

## Recipe Workbench — S3 (durable workbench log)

**Architect-approved + Jon device-passed 2026-07-06** — yes-chef
[PR #110](https://github.com/jonphillips/yes-chef/pull/110). The durable-history primitive (ADR-0019 Amdt 1):
a synced **`WorkbenchLogEntry`** table (`workbenchLog`) with an extensible
`kind: rationale | experiment | fork | observation | note`, `body`, `outcome?`, soft `relatedRecipeID?`,
`sortOrder`, `dateCreated`, cascade-owned under its workbench. Repository CRUD (add/update/delete, empty-body
guard, whitespace normalization, `dateModified` bump, `max+1` ordering) mirrors the candidate operations; a
Workbench Log section on the detail screen renders dated typed rows (edit-on-tap, swipe-to-delete) with a
manual add/edit editor; the log is grounded into `WorkbenchChatContext`; and a chat **"Save to Workbench Log"**
apply-action distills selected/latest assistant text into the log through the existing review-before-commit
surface. Ships the **store + manual/curate path first** — AI-*generated* experiment/fork entries layer on later
(new `kind` / compose path = no migration). Sync-safe (additive-nullable table, UUID PK, no unique index,
cascade FK matching `workbenchCandidates`, soft `relatedRecipeID`). 208 package tests + drift green; app-target
`xcodebuild` couldn't complete in CI (simdiskimaged crash) so the SwiftUI was closed by Jon's device pass.
Three non-blocking review notes parked in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md): the log
isn't self-trimmed against the chat-context budget (fold into on-device overflow work); `relatedRecipeID` is
plumbed but has no UI/title-snapshot yet; the chat-save path is a raw copy, not yet a distillation.

---

## Recipe Workbench — S2 (draft verb) + dogfood-hardening batch

**Architect-approved + build-green 2026-07-06** — yes-chef
[PR #107](https://github.com/jonphillips/yes-chef/pull/107). Pending Jon's device pass. **S2 draft verb**
turns a workbench into a real working recipe (the first commit surface): a synthesis apply-action + review
card writes a **new `Recipe`**, links it via `Workbench.draftRecipeID`, captures the pristine
`originalSnapshot`, and opens it in `RecipeDetailView`. New working recipes land at
`libraryPlacement: .reference` (out of default browse) with a one-tap **"Promote to library"** flip to
`.main`. The workbench task-framing string is defined **once** on `RecipeChatContext` and reused as the
spine of the draft-verb prompt so free chat and the commit path can't drift; `high` effort (ADR-0017),
curation-not-average guardrail ([[llm-curation-not-synthesis]]) enforced in the prompt.

**Dogfood-hardening rode the same branch** (206 package tests + drift green, app-target build green). Two
repos: **jon-platform** — LLMClientKit frontier `URLSession` request/resource timeouts raised (300s/600s)
so a `high`-effort synthesis isn't clipped mid-reason. **yes-chef** — draft-verb budget raised to 16k with
truncation surfaced as a real retryable error (not a silent empty draft); a persistent chat **error banner**
+ explicit timeout/offline messages; and a **remove / re-draft** affordance on the working recipe (deletes
an unpromoted `.reference` scratch draft, only unlinks a promoted `.main` recipe, always clears the soft-FK
link so drafting re-enables). Effort locked at **`high`** — dogfood-validated as a clear quality step over
`medium`. Sync-safe (UUID PKs, soft FKs + denormalized snapshots, additive migrations). Dogfood-surfaced
follow-ons parked in [`efforts/recipe-workbench.md`](efforts/recipe-workbench.md): synthesis-shaped draft
action (not gated on the last reply), AI effort/tier as a user-facing setting (ADR-0017/0018), tabbed
candidate/working-recipe quick-view. Design in
[ADR-0019](decisions/ADR-0019-recipe-design-studies.md) (whole, incl. both amendments).

---

## Recipe Workbench — chat controls (persisted tier · clear · stop)

**Architect-approved + Jon device-passed 2026-07-06** — yes-chef
[PR #105](https://github.com/jonphillips/yes-chef/pull/105). All three affordances landed in the **shared
panel** (`RecipeChatPanel`), so every chat surface inherited them at once: persisted `useFrontier` tier (new
`RecipeChatTierPreference`, mirrors `RecipeChatProviderPreference`; one global key ⇒ "remember the last model
I used anywhere"), `clear()` + confirm button (disposable scratch, no undo), and `stop()`/interrupt
(send↔stop off `isResponding`, cancellation checked on both tiers). Seam discipline held (ADR-0020) — generic
model methods + shared-panel controls, no domain pattern-match, no lift yet.

---

## Recipe Workbench — S1 + grounding fix + S1 polish

**Architect-approved + build-green 2026-07-06** — yes-chef
[PR #101](https://github.com/jonphillips/yes-chef/pull/101) (S1) +
[PR #103](https://github.com/jonphillips/yes-chef/pull/103) (grounding fix + polish). Pending Jon's device
pass. Slice 1 landed the workbench shell; the grounding fix + polish made it dogfoodable: the shared
`ChatWorkspaceSplit` now refreshes the chat model's context `onChange` (recipe/menu benefit too), editable
title, candidate-picker search, full-screen focus. Docs: `efforts/recipe-workbench.md`, ADR-0019, ADR-0020
(chat UI harvest).

---

## Menu planning overhaul (ADR-0012 Amendment 1)

**Build-green 2026-07-06** — yes-chef [PR #98](https://github.com/jonphillips/yes-chef/pull/98). Pending
Jon's device pass. All five slices shipped: tier-aware AI context + prep-plan-in-context + living-artifact
refinement · swipe-delete/move · inline meal-slot pill · full-screen focus · toolbar reorg. Drag-drop
reorder of dishes stays parked as the named follow-on (swipe-move is the interim). Effort doc
[`efforts/menu-planning-ux.md`](efforts/menu-planning-ux.md).

---

## AI configuration & transparency — ADR-0017 (model + effort) + ADR-0018 (taste profile)

**Architect-approved 2026-07-05** — cross-repo: yes-chef
[PR #96](https://github.com/jonphillips/yes-chef/pull/96) + jon-platform
[PR #23](https://github.com/jonphillips/jon-platform/pull/23) (`LLMClientKit`). **Synced-schema touch**
(new `aiSettings` table; ships to the prod schema at the next cut). Separated the two knobs that were
conflated — **model = capability floor, `reasoning_effort` = the per-task depth/cost dial** — then:

- **Model (ADR-0017 S1):** frontier OpenAI default → **`gpt-5.5`**, `gpt-5.2-chat-latest` retired. Added a
  provider-agnostic **`ReasoningEffort`** enum + `ModelRequest.reasoningEffort`; `OpenAIWire` emits a
  top-level **`reasoning_effort`** string when set and **omits it when `nil`** (Chat Completions shape).
  Anthropic/on-device ignore it. Wire test covers present-when-set / absent-when-nil.
- **Effort per feature (S2, D3 table):** assigned on **all 9 frontier call sites** — live/streaming recipe
  chat `medium` (extract-ready, Jon's call), Chef It Up / Serve With / make-ahead / prep-plan `high`,
  menu/meal complements `medium`. (The D3 table's `substitution`/`capture-parse` = `low` rows have no live
  call site — substitution was removed in PR #88; capture parse isn't a frontier `ModelRequest` — so
  9-site coverage is complete.)
- **Active model shown (S3, D4):** read-only "Active models" rows in `AISettingsView`, one per provider.
- **Taste profile at the boundary (ADR-0018 S4, D1):** promoted the lone device-local
  `recipeChatCustomInstructions` field to a **synced** taste profile stitched into `system` at the
  **`TieredModelClient`** boundary (in both `complete` and `stream`), so it reaches **every** generative
  call — closing the recipe-chat-only gap. Legacy `@AppStorage` value migrated on launch.
- **Per-task preferences (S5, D2/D3):** ~4 optional free-text fields (Chef It Up, Serve With, make-ahead /
  prep plan, complements) threaded via an opaque `promptPreferenceKey` on the request that the app maps to
  its synced settings; append **behind** the engineering prompt. Lookup tasks get no field. **No raw task
  prompts exposed** (D-rule: app owns contracts, user owns preferences).
- **Sync/schema:** new synced `aiSettings` table wired into `makeSyncEngine` **and** the schema, clearing
  the `CloudSyncTests` live-schema audit ([[extension-sync-construct-not-run]]); migration lives in the
  shared bootstrap so the share extension's DB gets it too.

Design in [ADR-0017](decisions/ADR-0017-llm-model-and-reasoning-effort.md) +
[ADR-0018](decisions/ADR-0018-prompt-customization-taste-profile.md). Non-blocking watch-items: singleton
settings row is row-level last-writer-wins across devices (fine for settings); `ReasoningEffort.none/.xhigh`
are unused and unverified against the live OpenAI wire (deferred to Jon's build, per ADR).

---

## Multi-recipe cook session — ADR-0016 (Reader-hosted, not Cooking Mode)

**Architect-approved + merged 2026-07-05** — yes-chef [PR #93](https://github.com/jonphillips/yes-chef/pull/93).
**Zero schema.** Ships a **cook session**: an ordered `[(Recipe.ID, ScaleContext)]` drawn from a planner day
*or* a menu, each recipe rendered in the **existing Reader**, with a pinned **chip-strip switcher**, a
**keep-alive** paged host (all per-recipe Readers stay mounted so switching doesn't reset scroll/scale, D4),
**session-only "done"** that shrinks the strip, keep-awake through the cook, and **per-placement `ScaleContext`
threaded** so a placement's pre-set scale flows straight through (D5). Recipe-kind items only; `.note`/
reservation rows filtered ([[menu-item-recipe-id-invariant]], D6). Entered via **"Cook these"** on a planner
day and on a Menu. Not Cooking Mode (left untouched), no voice (D7). Design + D1–D7 in
[ADR-0016](decisions/ADR-0016-multi-recipe-cook-session.md).

- **Layout fold-in** (same PR, per review): "Cook these" gave `MealCalendarDayHeader` three labeled buttons
  that overflowed the fixed-width agenda rail; wrapped in `ViewThatFits(in: .horizontal)` with a
  title-over-buttons stacked fallback, `titleBlock`/`actionButtons` extracted, `cookSession` made an optional
  closure, and the `CookSessionPresentation` build deduped into one computed prop.
- **Codex follow-up PR #94 was a wasted effort — rejected by Jon**, not merged.

---

## Cooking reader + planner follow-ons — independent reader columns + day-scoped make-ahead verb

**Architect-approved 2026-07-05** — yes-chef [PR #91](https://github.com/jonphillips/yes-chef/pull/91).
The cooking-workspace effort's queued dogfood follow-ons, two cohesive slices in one dispatch, **zero
schema**. **Slice 1 — independently-scrollable dense-reader columns:** the two-column iPad reader now pins a
fixed masthead (`header` + `metadata` above a `Divider`) over an `HStack` of two independent `ScrollView`s,
so a long ingredient list and long directions scroll separately instead of sharing one scroll. The refactor
split `recipeBody(isTwoColumn:)` into `compactRecipeBody` (picker/segmented) + a shared `directionsColumn`,
so the directions content is defined once and reused by both layouts; the narrow/segmented path is behaviorally
unchanged. Pure UI. **Slice 2 — day-scoped planner make-ahead verb:** a "Build make-ahead strategy" chat verb
over the selected planner day synthesizes a sequenced prep strategy across the day's recipes, leaning on saved
`makeAhead` notes. **Commit shape** ([[chat-verb-commit-shapes]]) = a `.note` `MealPlanItem` via the existing
`addNoteItem` — **no schema field** (ADR-0013's no-planner-container holds), `recipeID == nil` per
[[menu-item-recipe-id-invariant]]. Mirrors `complementAction`: empty `ChatApplyAction.commit`, real write in
the `ChatApplyReviewItem.commit`; parse failure degrades to empty steps → no review item → nothing written.
Structured steps (not a flattened blob) per [[llm-curation-not-synthesis]]. New `MealPlanMakeAheadStrategy`
model + `MealPlanMakeAheadStrategyClient` + parser + `MealCalendarRepository.addMakeAheadStrategyNote`, with
parse / tier-and-context-plumbing / staged-write-only-on-commit / day-ordering tests.

- **Non-blocking review note** (architect, folded forward, not filed as a bug): `MealPlanMakeAheadStep.sourceItem`
  is plumbed end to end (system prompt → JSON schema → parse → struct → test) but not yet rendered — kept as
  latent provenance for a future reconcile-against-day-items pass; a one-line comment on the field records the
  intent so raw item IDs never leak into note text. Decide keep-vs-drop when the broader Meal-Planner chat-verbs
  effort lands.
- **iPad device pass** (Jon): confirm the fixed masthead + independent column scroll feels right in both
  orientations (a tall header now permanently occupies vertical room above the columns).

---

## Chat persistence (ADR-0015) — local-only, per-subject, 1-month prune

**Architect-approved 2026-07-05** — yes-chef [PR #89](https://github.com/jonphillips/yes-chef/pull/89).
Chat is no longer ephemeral: a new local-only `chatMessages` SQLite table persists a thread **per subject**
— recipe id / menu id / planner day — so a conversation survives navigation, dismiss, and relaunch, and the
"same" subject opened from a different surface (reader vs. meal-planner) reopens the *same* thread (fixes
both "gone the minute I look away" and blank-on-surface-switch). **Local-only** — the table is deliberately
excluded from `YesChefCloudSync.makeSyncEngine`; the CloudSync live-schema audit test was amended to treat
`chatMessages` as the declared local-only exception (so the "new @Table silently stays local" tripwire stays
intact). **1-month time-based prune** — messages older than ~30 days are dropped on bootstrap and on every
chat write. Subject identity added to the recipe/menu/planner chat contexts (optional ids → graceful
"don't persist" when absent; all app call sites use the `detail:` initializers, so ids are populated).
`RecipeChatModel` loads the persisted thread on init and re-saves the whole thread in `send`'s `defer` after
the assistant text completes (empty placeholders are skipped). `RecipeChatMessage.Role` gained
`String`/`Codable`/`QueryBindable` conformances for storage. Design + resolved opens (SQLite-table-the-
SyncEngine-ignores; distill-into-the-recipe guardrail untouched — pure storage, no new nudge) in
[`docs/decisions/ADR-0015-chat-persistence.md`](decisions/ADR-0015-chat-persistence.md).

- **Non-blocking review notes** (architect, folded forward, not filed as bugs): prune uses a Swift-side
  `fetchAll().filter` rather than a SQL `where createdAt < cutoff`, so the `createdAt` index it creates is
  currently ornamental; `loadPersistedThread` runs a synchronous main-actor DB write (the prune) on every
  chat open. Both imperceptible at dogfood scale — fold into a later chat slice if chat volume grows.

---

## Reader photo affordances — set-as-cover + full-screen zoom

**Shipped 2026-07-04** — yes-chef [PR #87](https://github.com/jonphillips/yes-chef/pull/87). The cooking-
workspace effort's reader follow-on, two cohesive slices in one dispatch. **Slice 1 — manual "set as
cover":** a new nullable `Recipe.coverPhotoID TEXT REFERENCES "recipePhotos"("id") ON DELETE SET NULL`
(deleting the photo auto-nulls the cover → the `displaySortKey` heuristic resumes), resolved by a pure
`YesChefCore` cover function (override wins → else heuristic fallback for nil **and** dangling/unsynced ids),
unit-tested for the three cases; both the reader thumbnail and gallery default point at the one resolver;
"Set as Cover" / "Use Automatic" affordance. **The effort's first schema touch** — additive, nullable,
CloudKit-safe; added to the standing prod-schema promotion follow-up in `CURRENT_HANDOFF.md`. **Slice 2 —
pinch-to-zoom + pan** in `RecipePhotoFullScreenView` (`MagnifyGesture` + clamped drag, double-tap reset),
no schema. Design record in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) §
"Reader photo affordances". (Handoff bump did not ride in #87; repaired in the batch-4 PR.)

---

## Menu actionable chat (ADR-0012) — Slice 3: complement verb → inserts a `MenuItem`

**Architect-approved 2026-07-04** — yes-chef [PR #83](https://github.com/jonphillips/yes-chef/pull/83).
The **effort's last slice — ADR-0012 is now fully complete** (S1 grounded chat #81, S2 prep-plan #82, S3
complement #83). The "what would complement…" verb: the model proposes dishes, and the tap inserts a
`MenuItem` onto the menu via the existing review card (Decision #2). Serve-With motion at menu scale; the
tap-writes invariant holds — no chat turn mutates the menu. **No schema change** — committed `MenuItem`s are
ordinary rows, already sync-safe. Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Per-item insert commit shape** ([[chat-verb-commit-shapes]]) — one extracted payload emits **multiple**
  review cards, one per proposed dish, each committing independently. Added a second
  `AnyChatApplyAction(_:reviewItems:)` erasure initializer (the existing `renderedSummary:` single-card path
  refactored to route through it); rides the host's existing `ChatApplyReviewList` `ForEach` with **no host
  changes**. `MenuComplementClient` + `MenuComplementPlan`/`MenuComplementSuggestion`; `parse` reuses the shared
  `jsonObjectSlice ?? jsonArraySlice` idiom.
- **`MenuRepository.addComplementItem`** — a faithful analog of `addNoteItem` (requireMenu → validateDayOffset →
  `nonEmptyMenuText` → `nextSortOrder`), inserting an ordinary `MenuItem`. Wired into
  `MenuDetailModel.applyActionCatalog(for:)` alongside the S2 prep-plan action.
- **Review-feedback fix** (commit `56bc1ac`, folded before merge): the parser now **coerces every suggestion to
  `.note`** — a `.recipe`-kind row with no `recipeID` would violate the recipe⟹`recipeID` invariant the manual
  editor enforces (Save disabled without a selected recipe), rendering a book-icon row that is non-navigable and
  non-draggable. This write path can't attach a `recipeID`, so `.recipe`/`.reservation` both collapse to `.note`.
  Also removed the **dead batch-commit path** (`commitComplementPlan` / `MenuDetailError.emptyComplementSuggestion`)
  — the `reviewItems:` erasure never calls `action.commit`; each card commits via `commitComplementSuggestion`.
- **Tests:** parse (whitespace-trim, `.recipe`→`.note` coercion, slot/title drops), model-tier + menu context
  plumbing, staged no-write-until-committed-card, repository ordering + `invalidDayOffset` validation. Lean verify
  (swift test 163 green + one iPad build + check-drift).

**Non-blocking follow-up** (not a merge blocker): out-of-range `dayOffset` is only rejected at commit
(`validateDayOffset` throws on tap) — the parser can't range-check without menu context, and the review card
surfaces the error, so it's acceptable. Left as-is.

---

## Menu actionable chat (ADR-0012) — Slice 2: prep-plan verb → `Menu.prepPlan`

**Architect-approved 2026-07-04** — yes-chef [PR #82](https://github.com/jonphillips/yes-chef/pull/82).
The flagship commit verb of the Menu-scope effort and its **first schema touch**. Composes the S1 composite
grounding into a stored, staged pre-prep plan across all the menu's dishes. The tap-writes invariant holds —
extract → review card → commit, no chat turn mutates the menu. Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Additive `Menu.prepPlan: Data?`** (Decision #1) — a Codable BLOB of
  `PrepPlanStep { when: String; task: String; sourceDish: MenuItem.ID? }`. `when` is a free-text relative-day
  label ("morning of day 2"); `sourceDish` is a **nullable** `MenuItem.ID` back-pointer. Added via `ALTER TABLE
  "menus" ADD COLUMN "prepPlan" BLOB` — byte-for-byte the `serveWith` migration pattern. Additive-nullable,
  sync-safe; BLOB→CKAsset unconditional ([[sqlitedata-blob-cloudkit-asset]]). No reserved cols, no unique index.
- **`MenuPrepPlanClient` + apply-action/review card** (Decision #4): the system prompt **composes and
  sequences the existing per-recipe `makeAhead` notes** from the S1 context and is explicit — *do not invent or
  rewrite per-dish make-ahead prose*. Vocabulary hygiene held (ADR-0006): "prep plan" ≠ "make-ahead" in copy and
  identifiers. `MenuItem.ID` now seeded into the menu chat context so the model can return `sourceDish`
  back-pointers. `parse` reuses the shared `jsonObjectSlice ?? jsonArraySlice` idiom (mirrors `MakeAheadPlan`).
- **`MenuDetailModel.applyActionCatalog(for:)`** — a faithful analog of `RecipeDetailModel+Enrichment`
  (same `[weak self]` commit, tier/context plumbing). S1 left the menu catalog empty; S2 fills it. Menu **prep-plan
  section**: timeline/checklist render, source-dish labels, **regenerate** + **clear** affordances. **Passive
  snapshot** — no auto-recompute on menu edits; `sourceDish` only makes staleness *detectable* (ADR-0010 posture).
- **Tests:** parse (nullable + malformed-drop), encode/decode round-trip, `encode([]) → nil`, model-tier + menu
  context plumbing, staged no-write-until-commit, apply/clear persistence with `dateModified`. Lean verify
  (swift test 159 green + one iPad build + check-drift).

**Non-blocking follow-ups** (not merge blockers): `MenuDetailError.emptyPrepPlan` is effectively unreachable
(`AnyChatApplyAction` already filters empty rendered summaries) — harmless defensive guard. The prep-plan
**section is hidden while empty**, so the initial build entry is the chat workspace only (Regenerate reopens
chat); a "Build a prep plan" empty-state affordance is a possible later nicety — Jon's device-pass call.
**Standing schema follow-up:** promote the `Menu.prepPlan` BLOB to the production schema before any TestFlight
cut (folded into the standing Phase E prod-schema promotion in `CURRENT_HANDOFF.md`).

---

## Menu actionable chat (ADR-0012) — Slice 1: `.menu` context + grounded chat

**Architect-approved 2026-07-04** — yes-chef [PR #81](https://github.com/jonphillips/yes-chef/pull/81).
The Menu-scope instance of actionable chat (parent ADR-0011). **S1 proves composite grounding cheaply**:
one chat context over N dishes at once, seeded and conversational, **no commit verb and no schema change**.
Critique ("what's conceptually wrong with this menu") works immediately as grounded chat — S1's payoff
(Decision #5). Design + five resolved decisions in
[`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Additive `case menu(MenuChatContext)`** on `RecipeChatContext` (`RecipeChat.swift`), mirroring
  `case recipe(...)`; every enum switch updated, no default-case shortcuts. Menu-specific prompt/header/
  provider-warning copy alongside.
- **Composite grounding serialization (Decision #4):** one structured summary per `MenuItem` — title,
  capped key ingredients, prep/cook/total times, `dayOffset` + `mealSlot`, and each recipe's **existing
  `makeAhead` note verbatim** (the only field not newline-stripped, labelled "verbatim" for the model — it
  *composes* per-recipe make-aheads, does not re-derive them). Chat order == on-screen order.
- **Budget guardrail (Decision #4):** shrink ingredient caps 8→0 across all dishes first, then drop dishes
  from the tail (sorted ascending by day/slot/sortOrder, so lowest-`sortOrder`/earliest dishes are preserved
  longest). Any truncation is **always noted in the seeded context**, never silent.
- **Wired the existing context-general split** (`ChatWorkspaceSplit`) into the Menu screen with an
  **empty apply-action catalog** + compact chat-sheet fallback — a faithful mirror of `RecipeDetailView`'s
  wiring. `recipeIngredientLines` added to the `MenuItemRowData` **read-model only** (no `@Table`, no
  migration → sync-safe by construction). Shared system-prompt copy generalized "…edited or saved the recipe
  yourself" → "…anything yourself" for the composite subject.
- **Tests:** menu-chat serialization (dish summaries + verbatim multi-line make-ahead), budget-truncation
  notes (both notes fire; earliest dish survives, latest dropped), and menu-ingredient read-model plumbing.
  Lean verify (swift test + one iPad build + check-drift).

**Non-blocking follow-ups** (not merge blockers): `MenuDetailRequest` loads the full `IngredientLine` table
then filters in memory — consistent with the pre-existing `Recipe.fetchAll` in the same function, but a `.where`
candidate to fold into the parked `m1-s3-deferred-review-nits` fetch cleanup. Sort comparator is duplicated
across `MenuItemRowData` and `MenuChatItemContext` (distinct types; a shared helper is optional). Device pass
(iPad regular-width split reveal + Chat button + compact sheet) is Jon's.

---

## Phase E — grocery/pantry, Slice 4: `PantrySuppression` + grocery-list review section

**Architect-approved 2026-07-03** — yes-chef [PR #80](https://github.com/jonphillips/yes-chef/pull/80).
The milestone's **payoff and final slice** — no schema change, consumes the Slice 3 columns. **This
completes the grocery/pantry milestone** (last box ticked in
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md)).
Design rationale = [[grocery-pantry-threshold-design]].

- **Pure `PantrySuppression.evaluate(list:policies:)`** over the consolidated list → `{ shown,
  assumedInPantry, needsReview }`. Unlimited → `assumedInPantry`; threshold total **over/incomparable** →
  `needsReview`; threshold **under** → `assumedInPantry`; `alwaysConfirm` → `shown`. Runs on the cross-recipe
  consolidated total; incomparable units **fail safe to surfacing**; no model call on the path. Both sides key
  through the one `CanonicalIngredient.canonicalName` normalizer.
- **Add-back is one-shot, per-list, in-memory** — `pantryAddBackItemIDsByListID` moves a row to `shown` for
  that list only and never edits the pantry item's policy (Decision #7). Cleared when the item is deleted.
- **UI:** promoted **"You may need more"** review Section + a quiet **"Assumed in pantry"** `DisclosureGroup`
  with one-tap add-back. `isPurchased` never written (assumed is a distinct derived state). Share/plain-text
  excludes assumed rows. Empty-section guard moved into `GroceryItemsSection` — no stray headers.
- **Tests (pure, no UI/model):** unlimited never shown; threshold under hidden / over surfaced; cross-recipe
  total over threshold; incomparable units surface; add-back moves one row to `shown` and leaves policy
  untouched. CI green (153 tests + SwiftLint).

**Non-blocking follow-ups** (fold into a later grocery slice, not merge blockers): review headline uses a
hyphen vs the spec's em-dash `— X (total)`; `thresholdUsesCrossRecipeConsolidatedTotal` hardcodes the total
rather than deriving it from its sources (it exercises threshold-on-total, the right unit for this function,
not the consolidation summation itself). Standing Slice-3 release follow-up still applies: promote the pantry
+ `canonicalName` CloudKit fields to the **production** schema before any prod/TestFlight cut.

---

## Phase E — grocery/pantry, Slice 3: pantry policy model + `canonicalName` cache migration

**Architect-approved 2026-07-03** — yes-chef [PR #79](https://github.com/jonphillips/yes-chef/pull/79).
The milestone's **single synced-schema change**, carrying both the pantry policy columns and the
`canonicalName` cache deferred out of Slice 1. Milestone build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md).

- **Pantry policy on `PantryItem`.** New `PantryPolicy` enum (`unlimited` / `threshold(qty,unit)` /
  `alwaysConfirm`) over three columns: `isUnlimited: Bool` (default **true**), `thresholdQuantity: Double?`,
  `thresholdUnit: String?`. `storageValues`/`normalized` re-validate on both write and read, so threshold 0
  or a non-measure unit collapses to `alwaysConfirm`. Threshold offered only for volume/weight units
  (`canUseThreshold`, enforced in core **and** the editor UI). Static rule only — no depletion/inventory.
- **The `canonicalName` cache.** Added to `IngredientLine` / `GroceryItem`, populated at parse/generation
  and backfilled by `GroceryCanonicalNameCache.backfill`; `canConsolidate` / `isPantryStaple` re-pointed at
  the cached column with a `canonicalName ?? compute` fallback so nil rows still resolve.
- **Editor UI:** new `PantryViews.swift` — segmented *Always have it / Remind me / Always confirm*; quantity
  field hidden for count units; row summary shows the policy.
- **Sync-safe:** additive columns, UUID PKs untouched, no unique index. The one non-null column uses
  `NOT NULL ON CONFLICT REPLACE DEFAULT 1` so an older-schema peer's record backfills to `unlimited` instead
  of aborting the insert ([[sqlitedata-blob-cloudkit-asset]]).

**Two device-pass / release follow-ups** (flagged in the PR, not merge blockers): (1) the app target
(`PantryViews.swift` + `GroceryViews.swift`) was not compiled in this environment — Jon's build/device pass
covers it; (2) promote the new CloudKit fields to the **production** schema before any prod/TestFlight cut.

---

## Phase E — grocery/pantry, first dispatch: Slice 1 + Slice 2 (canonical key + `Measure`)

**Architect-approved 2026-07-03** — yes-chef [PR #77](https://github.com/jonphillips/yes-chef/pull/77).
Both pure-core `YesChefCore` slices in one PR, no UI, no schema migration (the `canonicalName` cache
column stays deferred to Slice 3 per the 2026-07-03 architect amendment). Milestone build order:
[`docs/milestones/grocery-consolidation-and-pantry.md`](milestones/grocery-consolidation-and-pantry.md).

- **Slice 1 — one canonical key + data alias table.** New `CanonicalIngredient.canonicalName(_:)` is the
  single normalizer (case/diacritic fold, hyphen-collapse, leading-descriptor strip, light
  singularization) with a **data** alias table (anchovy variants → `anchovies`, scallion/green onion,
  tomato pair). `canConsolidate` and `isPantryStaple` re-pointed at it; the `anchovy` `switch`,
  `groceryConsolidationKey`, and `normalizedPantryText` all deleted (zero dangling refs). Computed on read.
- **Slice 2 — bounded `Measure` compare/merge.** Known units → dimension (volume/weight/count) with
  conversion factors; `merged` combines same-dimension known units (`8 oz + 1 lb → 24 oz`) and, after
  review, **same-string units even when unknown to the table** (`splash + splash`); `compare → .over /
  .underOrEqual / .incomparable`. Cross-dimension pairs stay separate, no invented factors.

Review caught one regression before merge: the first cut required both units be in the dimension table,
so identical-but-unknown units (head/sprig/stalk/splash) stopped consolidating — a behavior the
`keep-incompatible-separate` test had locked in. Codex fixed it (859576f "Fix same-unit grocery measure
merging") to merge equal normalized unit strings and flip the wine assertion to a single merged row.
Codex authored; architect reviewed. Verified: `swift build`/`swift test` green, check-drift clean.

---

## Dogfood fixes — batch 3 (ingredient structure · Chef It Up + Serve With · substitution · keep-awake)

**Architect-approved 2026-07-03** — yes-chef [PR #75](https://github.com/jonphillips/yes-chef/pull/75).
Four cohesive slices in one PR, all from Jon's 2026-07-03 dogfooding. Effort doc:
[`docs/efforts/dogfood-fixes-batch-3.md`](efforts/dogfood-fixes-batch-3.md).

- **Slice 1 — ingredient list honors headers/sections/spacing.** `ingredientLineList` stopped
  hardcoding `"• "` on every line: `IngredientLine.isHeader` renders as a bold, bullet-less heading;
  `IngredientSection.name` renders as a subsection heading with spacing (`ingredientGroups`). The editor
  exposes the first section's title plus a per-line Header toggle; out-of-scope sections round-trip
  untouched. No schema change — the model already carried it.
- **Slice 2 — AI verbs Chef It Up + Serve With, verb buttons collapsed to an "Apply…" `Menu`.** Both
  mirror the make-ahead pattern end-to-end (additive-nullable `Recipe.chefItUp: String?` /
  `Recipe.serveWith: Data?`, structured extract client + pure commit op + catalog entry + own reader
  section with clear-as-undo). Serve With is a `{title, note}` accompaniment **list** with identity
  (`ServeWithItem.id`), each independently removable — *not* a Recipe row (promote-later seam left open).
- **Slice 3 — ingredient substitution, per-line, reveal-on-tap.** Additive-nullable
  `IngredientLine.substitution: String?`; a subtle swap glyph reveals the sub inline so the list stays
  scannable. Entry is from the ingredient row ("Find Substitute"), model proposes → explicit review sheet
  → tap writes `line.substitution`; manual set/clear via the editor. Clear = undo.
- **Slice 4 — keep the screen awake in the cook/reader presentation only.** New
  `keepsScreenAwakeWhilePresented()` modifier disables the idle timer while `.active`, restores it on
  background (`scenePhase`) and disappear; applied to `RecipeReaderView` + `CookingModeView`, not global.

New sync-safe columns (all additive-nullable, no unique index, UUID PKs; `serveWith` BLOB syncs as a
CKAsset like `originalSnapshot`, [[sqlitedata-blob-cloudkit-asset]]). Codex authored; architect reviewed.
Verified: `swift build` clean, `swift test` 135 pass (new enrichment-parse, commit/independent-undo,
substitution-write, and editor-structure round-trip tests), check-drift clean. Non-blocking notes handed
to Jon's device pass: keep-awake re-assert when backing out of cooking into the still-present reader;
read-only substitution review sheet; editing a line's text drops its metadata; incidental `viewScale`
preservation on edit. Menu/Meal-Planner chat verbs and reader photo affordances remain later efforts.

---

## Cooking workspace — Slice B (selection-scoped apply-actions + review card)

**Architect-approved 2026-07-03** — yes-chef [PR #74](https://github.com/jonphillips/yes-chef/pull/74).
Second/final slice of the cooking-workspace effort; realizes
[ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md) Amendment 1. Makes *what the model writes*
precise and human-chosen: a selected span (or the whole last reply as fallback) drives extraction, and
nothing lands in the reader until a review card is committed.

- **Type change** (`RecipeChat.swift`): `ChatApplyAction.extract` / `AnyChatApplyAction.run` go from
  `(_ messages: [RecipeChatMessage])` to `(_ selection: String, _ context: [RecipeChatMessage])`; `run`
  now returns `[ChatApplyReviewItem]` and **no longer commits** — commit is deferred to the review card.
  The make-ahead extractor takes `selection` as the primary subject, conversation as background
  (per-verb context scope, Amendment 1).
- **Selection arms the action bar** (`RecipeChatWorkspace.swift`): assistant messages render in a
  selectable text view; a selection targets that span, **empty selection falls back to the whole last
  assistant reply** (precision override, never a dead-button gate). The bar shows what it will act on.
- **Review-before-commit card**, inspector-resident: tapping an action runs `extract`, stages the decoded
  result as a Commit / Discard card; Commit lands in the reader in place, no chat turn writes on its own.
  Staged as a **list** (N=1 for make-ahead today) so Menu's multi-card motion slots in later without a
  rewrite — multi-card UI itself not built.
- **Action-verb strings folded off the action** (`extractingTitle` / `committingTitle` /
  `committedTitle`), retiring Slice A's hardcoded `"Saving make-ahead…"` / `"Saved to Make-ahead"`.
- **Architect-review fix folded into the PR:** selection was resolved against the raw markdown string
  while the text view displays the parsed string, garbling selections over any formatted reply and
  resetting in-progress selections on re-render; now read from the displayed text and compared
  rendered-to-rendered.

Codex authored the implementation; ran out of credits before the PR, so the architect reviewed, fixed,
and opened it. Verified: `swift build` clean, `swift test` 131 pass (incl. new
`stagedMakeAheadReviewItemWritesOnlyWhenCommitted` proving `run` stages nothing to the DB — only
`item.commit()` writes), check-drift clean. App target build + device UI pass are Jon's.

Effort doc: [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice B — **effort now
complete** (Menu/Planner chat verbs + reader photo affordances named there as later efforts).

---

## Cooking workspace — Slice A (the split + dense reader)

**Architect-approved 2026-07-03** — yes-chef [PR #73](https://github.com/jonphillips/yes-chef/pull/73).
First of two slices; implements [ADR-0011](decisions/ADR-0011-actionable-chat-make-ahead.md). Re-presents
`RecipeDetailView` from a photo-forward reader + chat `.sheet` into a **detented draggable split**.

- **Split host, context-general.** New `RecipeChatWorkspace.swift`: a `ChatWorkspaceSplit` that takes a
  `RecipeChatContext` + a `(RecipeChatModel) -> [AnyChatApplyAction]` catalog closure (not welded to
  `RecipeDetailView`), a visible grabber that snaps to three detents (reader-only / balanced / chat-dive)
  with per-device `@AppStorage` persistence and a VoiceOver adjustable cycler. `RecipeChatModel` re-hosted
  from the sheet into the inspector pane; chat behavior unchanged. iPad-only split; iPhone keeps the sheet.
- **Width-responsive reader.** `RecipeReaderView` renders off its own width, not device class: dense
  two-column (ingredients | directions) ≥ 640pt, segmented ingredients/directions toggle below — so the
  chat-dive detent reuses the narrow layout instead of a third design. Scale control lives in the toolbar.
- **Polish pass (Jon's device feedback, same PR):** thumbnail → reused `RecipePhotoGallery` sheet →
  full-screen enlarge (reference-document scans now included in `displayablePhotos`); chat host wording
  driven off `RecipeChatContext` (subject / prompt / context-header copy); duplicate AI-tier selector
  removed from the split (embedded-header only); **Focus toggle** collapses the recipe-list column to
  `.detailOnly` via `NavigationSplitViewVisibility`.
- **Deferred to Slice B / roadmap:** action-verb strings still hardcoded (`"Saving make-ahead…"` — Slice B
  reshapes that surface); reader photo affordances (manual set-as-cover, pinch-zoom) → effort doc roadmap.

Effort doc: [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § Slice A.

---

## Dogfood fixes — batch 2 (multiplier clip + AI provider picker)

**Merged 2026-07-03** — yes-chef [PR #71](https://github.com/jonphillips/yes-chef/pull/71). Two
design-free slices; ran in parallel with the cooking-workspace design.

- **Slice 1 — full-screen scale-multiplier clip fix:** the scale control no longer clips off the bottom
  in the full-screen recipe presentation (tactical fix; the cooking-workspace effort relocates the
  control to the toolbar structurally).
- **Slice 2 — AI provider picker:** `AISettingsView` now holds both a Claude and a ChatGPT (OpenAI) key
  against the multi-provider `APIKeyStore`; a stored `RecipeChatProviderPreference`
  (`recipeChatFrontierProviderKey`) lets the recipe chat pick its frontier provider
  (`RecipeChatModel.selectedProvider` / `availableProviders` / `activeTier`). No new backend — surfaced
  LLMClientKit's existing `OpenAIModelClient`; mirrors Galavant's provider-picker shape.

Effort doc: [`docs/efforts/dogfood-fixes-batch-2.md`](efforts/dogfood-fixes-batch-2.md).

---

## Recipe-multiplier rework — Slice C (per-placement persisted scale)

**Architect-approved 2026-07-03** — yes-chef [PR #70](https://github.com/jonphillips/yes-chef/pull/70).
Final slice of the dogfood-driven multiplier rework; closes the effort.

- Additive, sync-safe scale columns via one migration (`Schema.swift`): `viewScale` on `recipes`,
  `scale` on `menuItems` and `mealPlanItems` (all default `1.0`). New `RecipeScaleCore` +
  `RecipeScaleFormatting` seam and a small injected `ScaleContext` (`.recipe`/`.menuItem`/
  `.mealPlanItem`) so `RecipeDetailModel` reads the initial factor from — and writes changes back to —
  the storage site the context names (one read/write seam, not a branch per screen). Bare-recipe scale
  round-trips through iCloud. `RecipeScaleTests` added.
- Investigation confirmed the menu/planner navigation into recipe detail; all three `RecipeDetailView(`
  constructions were routed through the `ScaleContext` seam (`RecipeLibraryView`/`MenuViews`/
  `MealCalendarViews`).

Effort doc: [`docs/efforts/recipe-multiplier-rework.md`](efforts/recipe-multiplier-rework.md) — **complete**.

---

## Recipe-multiplier rework — Slices A+B (parse fix + dial-as-multiplier)

**Architect-approved 2026-07-03** — yes-chef [PR #69](https://github.com/jonphillips/yes-chef/pull/69).
First two slices of the dogfood-driven multiplier rework; Slice C (per-placement persisted scale) remains
Next Up.

- **Slice A (unicode-fraction parse, pure `YesChefCore`):** `IngredientParser` now maps vulgar-fraction
  glyphs (¼ ½ ¾ ⅓ ⅔ ⅛ … ⅕/⅙ family) to decimals and handles spaced (`1 ¼`), unspaced (`1¼`), and
  glyph-only (`⅓`) mixed numbers via a new `mixedNumberValue` branch. `IngredientScaler.format` renders
  scaled results back as mixed-number fractions (`2 ½`) with a 0–2-decimal fallback. Focused parser/scaler
  regression tests added.
- **Slice B (dials become the multiplier):** `scalePickerChanged` sets `scaleFactor` directly;
  `setScaledServings` / target-servings math removed. Whole-number range and `nearestSelection` start at 0
  so sub-1× steps (⅓×/½×/¾×) are reachable, clamped to `minimumScale` (⅓) to block 0×. Servings became a
  read-only derived "Makes ~N" line (hidden when unparseable); picker relabeled around the multiplier and
  the 1×/2×/3× quick buttons retired.

**Review:** approved; two minor findings Jon fixed himself before merge — dead `multiplierButtonTapped(_:)`
left orphaned after the quick buttons were removed, and an inert `.disabled()` on the `.wheel` picker rows
(the real clamp lives in `scalePickerChanged`). Duplicated fraction tables across the module boundary
(`IngredientScaler.commonFractions` vs `ScaleText`/`ScaleFraction`) noted as acceptable, not a change request.

Effort doc: [`docs/efforts/recipe-multiplier-rework.md`](efforts/recipe-multiplier-rework.md).

---

## Actionable chat (ADR-0011) — Slice 2: the abstraction + make-ahead

**Slice 2 (the final slice of the actionable-chat effort), architect-approved 2026-07-02** —
yes-chef [PR #68](https://github.com/jonphillips/yes-chef/pull/68). First cross-app instance of the
actionable-chat pattern landed end-to-end in yes-chef.

- Additive `Recipe.makeAhead` TEXT column + migration (additive, sync-safe); editor-save preserves it.
- `MakeAheadPlan` + `MakeAheadPlanClient` (defensive JSON extraction, mirrors `PlaceDiscoveryClient`);
  tested `RecipeRepository.applyMakeAheadPlan` / `clearMakeAhead`.
- General `(extract → commit)` apply-action **catalog** (`ChatApplyAction` / `AnyChatApplyAction`) —
  make-ahead is verb #1, not hardcoded. Invariant held: model proposes/structures, the **tap** is the
  only write.
- `RecipeChatContext` + `RecipeChatModel` (seeded from the on-screen recipe), chat panel + "Chat"
  button + dedicated "Make-ahead" section + clear affordance in `RecipeDetailView`; editable chat
  pre-prompt in AI settings.

**Review (3 findings, all fixed on the branch before approval):** (1) HIGH — `send()` built the model
request *after* appending the empty assistant placeholder, so the frontier path put an empty-content
assistant message on the Anthropic wire (400 every turn); fixed by capturing `history()` before the
placeholder. (2) MEDIUM — apply action hardcoded `.frontier(.anthropic)` instead of the chat's tier;
fixed by threading `tier` through `MakeAheadPlanClient`, with a regression test. (3) LOW — apply errors
dumped raw enum values; fixed by extracting the shared `RecipeChatErrorText.describe`.

Effort doc: [`docs/efforts/actionable-chat-make-ahead.md`](efforts/actionable-chat-make-ahead.md).
Remaining named-but-deferred work (Galavant adoption = ADR-0031 Slice 3; jon-platform cross-app ADR =
Slice 4) lives in other repos, "after the shape holds here."

---

## Actionable chat (ADR-0011) — Slice 1: the lift

**Slice 1 of the actionable-chat lift, architect-approved 2026-07-02** (3 PRs; merge jon-platform
first). Moved the shared model-client stack out of galavant into a new home package and adopted it in
both apps — a *move*, not a copy.

- **jon-platform PR #17** — new `packages/LLMClientKit` (source of truth): `ModelClient` /
  `TieredModelClient`, Anthropic/OpenAI/on-device clients, wires, `JSONValue`, `ModelTool`, keychain
  `APIKeyStore`, full tests, EXTRACTION-NOTES row. Review verified a faithful lift: every non-`APIKeyStore`
  diff vs the `GalavantAI` originals is doc-reference retargeting only (ADR-0014→`ai-model-access.md`,
  ADR-0017/0018→`actionable-chat.md`, both present at `docs/ios/`).
- **galavant PR #48** — retire in-repo `GalavantAI`, path-dep on LLMClientKit, repoint imports
  (−1,900 net). No leftover `import GalavantAI`.
- **yes-chef PR #67** — delete minimal `ModelClient` / `ClaudeAPIClient` / `ClaudeAPIKeyStorage`, adopt
  the package's `APIKeyStore`, wire `TieredModelClient.live` (−511 net). No dangling refs.

Adopters use a relative path dep (`../../../jon-platform/packages/LLMClientKit`) — harvest-now/
converge-later (ADR-0007); converging to a versioned dependency is a later follow-up.

**Known one-time cost (accepted, not fixed):** LLMClientKit's `APIKeyStore` migrates galavant's legacy
keychain service but not yes-chef's old one (service `com.jon.yeschef.ai.anthropic` / account
`claude-api-key` → now `com.jonphillips.llmclientkit.apikeys` / account `anthropic`). Existing yes-chef
installs must re-enter the Claude key once per device. Accepted — private app, recoverable, not worth code.

---

## Dogfood fixes — batch 1

**Slice 6 (PR #62), architect-approved 2026-07-02.** A **Share List** action in the grocery
detail actions menu (`GroceryViews.swift`) via native `ShareLink`, backed by a pure
`GroceryListPlainTextRenderer` (`YesChefCore`, subject = list title). Grouping/order come from
the same `selectedItemRows` the detail view sections use, so shared text mirrors the on-screen
To Buy / Purchased split exactly; quantity+unit, then title, with aisle/notes in parens.
Sync-safe (no persistence/schema change), fixture-tested (grouping + empty cases); package + 2
new tests green. Review found no blockers. Authored by Jon directly (Codex out of tokens).
*Non-blocking:* the `selectedListShareText` nil-list fallback is dead code (menu only renders
inside `if let selectedList`; `selectedListRow` is nil only with zero lists). When Phase E
store-section grouping lands, extend the renderer to reflect sections.

**Slice 5 (PR #61), architect-approved 2026-07-02.** Pinned the recipe-list search drawer via
`.searchable(placement: .navigationBarDrawer(displayMode: .always))` on the shared
`RecipeListView` so search no longer scrolls away with the list. One-line, idiomatic view change
— reuses the existing `.searchable` binding, no new state/scroll-tracking/custom control; applies
to both `.navigation` and `.selection` hosts and doesn't conflict with the top `safeAreaInset`
status bar. Both iPad/iPhone sim builds + `check-drift.sh` (111 core tests) green; no blockers.

**Slice 4 (jon-platform PR #16), architect-approved 2026-07-02.** Trailing `xmark.circle.fill`
clear button on the shared `WebExtractorKit` `WebBrowserView` address bar
(`packages/WebExtractorKit/Sources/WebExtractorKit/WebBrowserView.swift`). Shipped in
**jon-platform** (shared browser chrome), not this repo. Visibility: `!addressText.isEmpty` while
editing, `page.url != nil` when not; `clearAddress()` empties the field and focuses it, and the
predicate then flips so the button hides itself right after clearing. No blockers — clean, minimal
view chrome. No new test (pure view logic; rides the manual sim verification). Non-blocking: when
a page is loaded the X is a persistent "start a new navigation" affordance, not an edit-clear —
matches the dogfood ask.

**Slice 3 (PR #60), architect-approved 2026-07-02.** Archive-means-gone: archiving a recipe
deletes its meal-plan and menu-dish placements in the same sync-safe write, guards the
calendar/menu/detail resolution paths against archived references, renames the destructive action
to **"Archive"**, and adds a **Settings ▸ Archived Recipes** view to restore (recipe only) or
permanently purge (FK-cascading delete). Also folded in the two Slice 2 review items: the
`presentationBinding` helpers deduped into shared `gatedBinding` free functions, and the modal
"OK" add-confirmations became a root-level `@Observable` **toast** (haptic + VoiceOver +
Reduce-Motion). **Review found two blockers, both fixed on-branch:** (1) the toast was occluded by
the full-screen recipe cover — resolved by also rendering the shared toast overlay inside
`RecipeFullScreenCover`; (2) `xcodegen` had swept a bundle-ID flip
(`com.jonphillips`→`com.jon`) + scheme churn into the pbxproj — resolved by realigning
`project.yml` back to `com.jonphillips.yeschef` (preserving app identity + the
`iCloud.com.jonphillips.yeschef` container) and adding a `check-drift.sh` guard. 111 core tests
green. **Non-blocking watch item:** two `.sensoryFeedback` modifiers now observe the same toast
trigger, so adds from a full-screen recipe may double-buzz — eyeball during dogfooding and gate one
if noticeable. *(This slice is a good example of batching working: it did multiple cohesive things
in one clean dispatch.)*

**Slice 2 (PR #59), architect-approved 2026-07-02.** The meal editor locks to the viewed recipe
when launched from recipe detail (`MealPlanItemDraftContext.locksRecipeSelection`), and
add-to-meal / add-to-grocery fire in-context confirmations via the Slice 1 gated presenters.
Correct and consistent with Slice 1; no blockers. One UI-pass watch item: the confirmation is a
sheet→alert handoff on the same host (the app already proves this works via the capture-summary
alert), and Slice 3 retires it entirely by moving to a root-level toast.

**Slice 1 (PR #58), architect-approved and merged 2026-07-02.** Add sheets + all six
full-screen-recipe toolbar affordances (Add-to-Grocery, Add-to-Plan, Edit, Start Cooking, View
Original, Delete) present in-context via the shared gated-presenter pattern in
`AppDestinationPresentation.swift` (root presenters gated on `presentedRecipeID == nil`,
re-attached ungated inside `RecipeFullScreenCover`). Also updated the active-simulator target to
`iPad Pro 13-inch (M5) (16GB)`.

---

## Reader Feedback

**Slice 4 — Claude API client + Keychain key storage (PR #57), architect-approved 2026-07-02.**
The app's first LLM integration: a domain-free `ModelClient` boundary + minimal Claude Messages
API wire client in `YesChefCore` (injectable `Transport`, no network in tests, 114 tests green)
plus app-side `ClaudeAPIKeyStorage` (synchronizable iCloud-Keychain generic-password item,
`kSecAttrAccessibleAfterFirstUnlock`, never logged), a **Settings ▸ AI** pane with save/clear, and
`modelClient` wired to read the Keychain key at call time. **Architect review changed the default
model `claude-fable-5` → `claude-opus-4-8`** (commit `8b3b817`): Fable 5 returns 400 under
zero-data-retention orgs, costs 2×, and runs bio/cyber refusal classifiers — none of which fit a
personal-key recipe app; Opus 4.8 is the standard default and per-request override via
`ModelRequest.model` is unchanged. **Non-blocking, deferred to Slice 5:**
`ClaudeAPIClient.complete` branches only on HTTP status, so a 200 response with
`stop_reason: "refusal"` (or `max_tokens`) yields silent empty text — guard or document when the
extractor consumes it. Keychain iCloud sync is intentional (multi-device dogfooding).

**Slice 3 — NYT comment capture playbook + host-keyed extractor (PR #56), architect-approved
2026-07-02.** Host-keyed **"Load Comments"** action in `BrowserWorkspaceView` (separate from
Capture) driving a bounded NYT playbook (`BrowserCommentLoadingPlaybook` in `RecipeModels.swift` —
clicks Most Helpful, then "Show more comments" ≤4×, keyed on `cooking.nytimes.com`), plus a pure,
fixture-tested `RecipeReaderCommentExtractor` (`YesChefCore`, SwiftSoup, no WebKit) producing
`[RawComment { text, helpfulCount }]`. Architect verified the fixture math (76 cards/bodies/count
spans 1:1, full-integer counts, distinct-class reply not double-counted) and that anonymization is
structural (reads only `note_noteBody__ > p`, never the owner span). Keys on stable structure, not
hash suffixes. Extractor is intentionally dormant (test-only) until Slice 5 wires it into review.
**Non-blocking follow-ups deferred to Slice 5:** (a) strengthen the anonymization test (`contains`
a placeholder substring, not whole-text `==`); (b) comment the `helpfulCount` digit-filter
assumption that counts render as full integers, not abbreviated `"6.3K"`.

**Slice 2 — harvest the real NYT comment-thread fixture — DONE (architect sanitization step, not a
PR/Codex slice; 2026-07-01).** Jon captured the authenticated "Most Helpful, fully loaded" DOM for
Lemony White Bean Soup off-device; the architect sanitized it into
`Tests/YesChefCoreTests/Fixtures/WebRecipeCapture/SanitizedSites/nyt-comments.html` (recipe JSON-LD
+ verbatim `<section id="notes_section">`, 76 cards, synthetic commenter names, JSON-LD `review`
PII array dropped, no auth material present).

**Slice 1 — review-sheet dismiss-fragility hardening (PR #55), architect-approved and merged
2026-07-01.** Destructive-confirmation `confirmationDialog` on Cancel plus
`interactiveDismissDisabled` (in-app) / `isModalInPresentation` (share extension) while a draft is
under review, driven by a new `hasUnsavedReviewChanges` on `RecipeCaptureModel`/`ShareCaptureModel`.
Architect review found `hasUnsavedReviewChanges` excluded `isCommitting`, leaving swipe-to-dismiss
enabled during the async save (and, in the share extension, through the
`waitForPendingRecordZoneChanges` sync wait) — a mid-save swipe could dismiss while the import
completed in the background and later popped an unexpected `.captureSummary` sheet. Fixed by
dropping the redundant `!isCommitting` clause (it can only be `true` while `draft != nil`, so it
added no protection, only the gap) — landed as `51cfed1` directly on `main`. 108 tests pass,
swiftlint clean.

---

## Web capture (Milk Street, cleanup, DOM export)

**Web-capture cleanup slice (PR #54), architect-approved and merged 2026-07-01.**
`WebRecipeCaptureClient.fetchImageData` now streams the hero-image download via
`URLSession.bytes(for:)`, rejecting on a declared-oversized `Content-Length` before reading the
body and enforcing the 12 MB cap against actual bytes received.
`RecipeMilkStreetExtractor.extractPrintIngredients`/`extractBodyIngredients` collapsed into one
`extractIngredients` helper parameterized by an `IngredientExtractionSelectors` struct;
heading/item lines are buffered and only committed once a real item is found in that pass, closing
the orphan-heading-leaks-into-body-fallback gap from the PR #53 review. Also picked up the
`RecipePrintTemplate_ingredientRow__*` print-row markup fallback. Non-blocking: the hero-image
download iterates `URLSession.AsyncBytes` one byte at a time (slower than a chunked read) — revisit
if hero-image hydration is ever visibly slow.

**Milk Street print-template ingredient headings (PR #53), architect-approved and merged
2026-07-01.** The print-template ingredient path now recognizes
`RecipePrintTemplate_ingredientHeading__*` rows interleaved with `ingredientItem__*` rows, walking
heading/item elements in DOM order so section names attach before their items.
`milk-street-chicken-peanut.html` extended with real-shape print-template markup. Two non-blocking
nits (orphan-heading fallback gap, extract-print/extract-body duplication) folded into the cleanup
slice above.

**Milk Street sections/Tip/summary/time (PR #52), architect-approved 2026-07-01, merged.** Real
per-recipe summary (`RecipeSummaryContent_body__*`) outranking site-boilerplate meta description,
Tip callout captured as an editorial block (`[role=note][aria-label=Tip]`), servings/prep/cook/total
time from `ItemLabelList_item__*`, and a `RecipeDurationParser` unicode-vulgar-fraction normalizer
(`"1½ hours"` → 90 min) — all fixture-tested against a sanitized `milk-street-chicken-peanut.html`.
The fourth gap (ingredient subsection headings) was a branch-selection bug, not missing markup —
fixed in PR #53.

**Revive DEBUG DOM export (PR #51), architect-approved 2026-07-01, merged.**
`preserveRawImportHTML: true` gated `#if DEBUG` at both production capture call sites; Release stays
lean (PR #45 intent preserved).

**Milk Street parser hardening (PR #50), architect-approved 2026-07-01, merged.** Meta-tag JSON-LD
reading gated on truncation-sentinel detection, a `RecipePrintTemplate_*`/`RecipeBodyContent_*` DOM
fallback extractor (`RecipeMilkStreetExtractor`, amount+description join, empty-amount tolerant), the
new `truncatedStructuredData` warning, and sanitized recovered/truncated-only fixtures. Scoped to the
original gochujang reference capture; NYT teaser regression stays green.

---

## M4 — iCloud sync

**Share-extension iCloud sync — producer wait + consumer re-drain + enablement persistence (PR #49),
architect-approved 2026-07-01, round-trip confirmed on device.** Three defects, one landable unit:
  1. **Producer race (Codex):** stopped extension engine defers the `PendingRecordZoneChange` insert
     to a fire-and-forget `Task` that `completeRequest` killed → row lost.
     `ShareCaptureModel.saveButtonTapped` now bounded-polls `pendingRecordZoneChangeCount` until the
     row lands before completing. No `start()`/networking/`aps-environment` in the extension.
  2. **Consumer drain (Codex):** the pending table only drains inside `start()`
     (`enqueueLocallyPendingChanges`, `SyncEngine.swift:645`), which no-ops when already `isRunning`.
     Added a scene-`.active` foreground re-drain that cycles `stop()`+`start()` when pending rows
     exist.
  3. **Enablement gate (folded in directly, 2026-07-01):** `isManuallyEnabled` was set only by the
     volatile Xcode launch-arg, so an icon-tap / extension-handoff launch had sync OFF and neither the
     cold-launch `start()` nor the re-drain ever ran. Proven by reading the sim metadatabase: 81
     undrained rows == 81 metadata rows with NULL `lastKnownServerRecord`.
     `persistManualEnablementFromLaunchEnvironment()` mirrors the dev flag into persistent
     `UserDefaults`. See [[extension-sync-construct-not-run]].
  Follow-ups deferred: file upstream SQLiteData issues — (a) persist the pending change in the trigger
  synchronously (`// TODO` at `SyncEngine.swift:823-838`), (b) expose a public "drain persisted pending
  changes into a running engine" entrypoint. Before the S4 Production flip, replace the dev launch-arg
  gate with a real persisted opt-in.

**Share-extension iCloud entitlement hotfix (PR #48 merged, `5e8be14`).** Added the iCloud container +
CloudKit-service entitlements to `YesChefShareExtension` (app group preserved; no `aps-environment` /
background modes). Fixes the launch crash: `SyncEngine.init` eagerly builds `CKContainer(identifier:)`
even with `startImmediately: false`, and an unentitled container threw an uncatchable ObjC exception.
Entitlement-only. Crash fixed, but round-trip still broken (see PR #49).

**Slice 3 — logical-uniqueness hardening (upsert + dedup-on-read) (PR #47), architect-approved.**
Source-backed `recipeImportRef` duplicates converge on read: pick the earliest ref deterministically
(`dateCreated` → `id` → `recipeID`), delete duplicate imported recipes, and repoint
`MealPlanItem`/`MenuItem` (`ON DELETE SET NULL`) + `GroceryItemSource` (no FK) references to the
survivor before deleting losers. Title-only collisions stay data-preserving. Same converge-on-read
pattern for duplicate default `GroceryList`, `PantryItem` titles, `Tag` names, and sibling `Category`
names. Preview path is non-mutating. 100 tests green. Non-blocking follow-ups: default-list convergence
only self-heals via `ensureDefaultList`; the merge relies on GRDB's default `foreign_keys = ON`; the
`default:` branch in `importBundle` is now dead for source-backed keys.

**Slice 2 — CloudKit `SyncEngine` wiring (started OFF) (PR #46), architect-approved.** Additive CloudKit
**dev** entitlements (iCloud container `iCloud.com.jonphillips.yeschef`, CloudKit service,
`aps-environment`, `UIBackgroundModes = remote-notification`) via XcodeGen. `attachMetadatabase()` +
`SyncEngine(startImmediately: false)` in `bootstrapDatabase` enumerating all 23 synced `@Table`s;
iCloud account-status launch gate; sync opt-in defaults **OFF**. Share extension **constructs a stopped
engine** purely to install triggers / write `SyncMetadata` — it never starts or networks (**construct ≠
run**). `categories.parentCategoryID` loosened from a self-referential FK to a plain UUID column.
On-device dev round-trip partially confirmed (in-app browser capture round-trips; synced rows live in
the Private DB custom zone `co.pointfree.SQLiteData.defaultZone`).

**Slice 1 — lean original-provenance (PR #45 merged).** `RecipeBundleCoding.snapshotData` strips
`originalImportText` and photo `displayData`/`thumbnailData` from the snapshot blob (metadata +
`imageDataReference` retained); import/capture defaults `originalImportText == nil` via a test-only
`preserveRawImportHTML` seam. Snapshot is passive provenance — no production consumer of
`decodeSnapshot`.

---

## M3 — authenticated browser capture

**M3 authenticated browser capture (PR #44 merged, `2f5b588`).**
- **Capture editorial prose blocks** ("Why This Recipe Works" / "Before You Begin") — scoped DOM scrape
  (`RecipeEditorialProseExtractor`) mapping the blocks to labeled recipe notes, schema-first parser
  untouched; `WebRecipeEditorialProseTests`.
- **Show & curate notes + hero image in the review UIs** — notes shown with inline edit + per-block
  delete, plus a read-only hero preview, in **both** the share-extension review (`ShareViewController`)
  and the in-app browser capture review (`RecipeCaptureView`). Emptied notes drop at save/bundle time.

**Fork resolved (2026-06-30):** M3 capture is done and the pivot to the **iCloud sync gate** was made.
The full build order was authored (S1 lean provenance → S2 CloudKit setup + `SyncEngine` wiring, off →
S3 dedup-on-read hardening → S4 clean cutover/flip → S5 two-device verification). Modeling stays
sync-safe and deferred (no canonical-ingredient work before the flip). Ratified by
[ADR-0010](decisions/ADR-0010-cloudkit-sync-enablement.md); M3 recorded in
[ADR-0009](decisions/ADR-0009-in-app-authenticated-browser-capture.md).

---

## Implemented-behavior checkpoint (planning/grocery slice)

Snapshot of behavior implemented as of the meal-planning / menus / grocery slice. Background context,
not a dispatch target; much of this is derivable from code.

- A durable `mealPlanItems` SQLite table and `MealPlanItem` core model; items support recipes and
  freeform notes, with a reserved `reservation` kind and optional start/end time fields.
- A month-first Meal Calendar workspace with month, week, and day display modes; add recipe/add note
  flows from the calendar, plus a `Plan` toolbar button on recipe detail.
- Durable menu schema (`menus`, `menuItems`, `menuPlacements`). Menus can contain recipe dishes and
  freeform notes, be placed on the calendar, shifted, and removed without deleting the menu. Calendar
  rows projected from a menu preserve provenance and show as menu-derived.
- Menu detail: single navigation title, slide-in recipe browser inspector with search/filter,
  day-header add buttons, recipe drops onto a day, drag-to-move between days.
- Full-screen recipe presentation from menus and meal-calendar agenda rows.
- The meal calendar optimistically reflects item date edits/deletes while SQLiteData observation catches
  up. Week calendar cells are taller on wide layouts.
- Durable grocery schema (`groceryLists`, `groceryItems`, `groceryItemSources`). Sources preserve
  recipe, menu, menu placement, calendar item, and custom origins, including source titles/subtitles and
  original ingredient text.
- A minimal Groceries section: list creation, custom items, purchased state, add-from-calendar-range,
  add-menu, add-recipe. Recipe detail groups `Plan`/`Groceries` in the toolbar; groceries opens a
  shoppable-ingredient review sheet before adding.
- `Start Cooking` flame action lives in the recipe body near servings/time.
- Generated grocery ingredients consolidate conservatively when title, unit, aisle, notes, and quantity
  shape are compatible; compatible numeric quantities add together while each origin remains its own
  `GroceryItemSource` row. Purchased items and prep/comment-sensitive rows stay separate.
- Grocery rows expose their source breakdown; each source has an actions menu that removes only that
  source (row deleted when its last source is removed; consolidated numeric quantities recalculated).
- Ingredient-selection sheet before generation for `Shop`, add-from-calendar-day, and add-menu flows; all
  shoppable lines start selected; generation can be restricted to selected `IngredientLine` IDs.
- Conservative pantry assumptions: staples (salt, pepper, water, ice, common oils, cooking spray) shown
  in a "Skipped Pantry Staples" section, deselected by default, addable with a tap. Settings exposes an
  editable Pantry list (one item per line); pantry items sort alphabetically. Quantity tracking is
  explicitly out of scope.
- The meal-calendar recipe picker supports adding multiple recipes in one save.
- Ingredient parsing avoids treating food words (red/celery/anchovy) as units, splits comma preparations
  into notes, and normalizes anchovy fillets into "anchovies".
- Core tests cover meal calendar, menus, grocery source provenance, generated grocery
  consolidation/source-removal/ingredient-selection/pantry-assumption/ingredient-parsing, menu item
  moves, and alphabetical pantry sorting.

**Deferred from that slice:** drag/drop inside the calendar grid; restaurant reservation UI;
iCal import/export/sync; rich menu editing (editing existing dishes, duplicating menus, fine-grained
ordering within a day); higher-level source-aware grocery removal; quantity-based pantry inventory;
App Intents/Shortcuts; Reminders/Siri; store/category learning; importing Paprika menus/grocery lists.

---

## Strategic context (background, not a dispatch target)

Direction for the larger work so the architect can curate Next Up; never instructs the agent.

- The storage model can represent multiple origins for one grocery row, and the UI has a first review
  step before generation. The next pressure point is making source-aware removal and skipped pantry
  staples equally legible.
- Paprika allows recipe ingredients to be chosen before adding and recipes to be removed from the
  grocery list later; Yes Chef has the ingredient-selection affordance and still needs the broader
  removal/review affordances while keeping richer provenance intact.
- Source-aware removal is the next pressure test for consolidation (a single row may contain quantities
  from several recipes, menu placements, and calendar items).
- Pantry value comes first from making skipped known staples reviewable and easy to add back, not from
  tracking exact on-hand quantities.
- Treat Grocy as inspiration for shopping locations/assortments and product/barcode workflows, but keep
  Yes Chef recipe/planning-first rather than inventory-first.
- Menu drag/drop is implemented but still needs Jon's hands-on UI pass across iPad and iPhone before
  it's treated as settled.
