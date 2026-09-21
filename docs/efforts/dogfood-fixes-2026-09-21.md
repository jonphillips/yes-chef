# Effort: Dogfood fixes — 2026-09-21 (Power Browser, capture curation, archive/delete, variation save, section reorder, focus tabs, workbench delete)

**Status: Designed — awaiting dispatch.** Triage + slice prompts for nine dogfood observations from Jon's
2026-09-21 pass. Deliberately **kept out of `CURRENT_HANDOFF`** ([[clean-up-handoff-means-sweep]],
[[handoff-bump-rides-in-slice-pr]]) — this doc is the backlog + sequencing record; each slice follows the
normal PR + handoff-bump ritual when taken.

**Owner:** Jon (product) · Claude (architect/diagnosis) · Codex (implementation). Default to batching a
cohesive thread into one Codex dispatch ([[batch-slices-and-lean-handoff]]); verify lean
([[lean-verification-default]]) — package build + `YesChefTests` for any model change
([[app-test-target-not-in-verification]]), Jon does the device pass.

**Concept links:** [[llm-curation-not-synthesis]] · [[decompose-notes-into-typed-homes]] ·
[[variation-anchor-repair]] · [[alert-ispresented-destructive-setter]].

---

## Source feedback (verbatim, 2026-09-21)

1. I need an affordance to reorder recipe sections.
2. Power Browser: Website should go away. It's a bunch of individual links to recipes … not useful.
3. Power Browser: For the remaining Source and Author, once I select either and then select a value, I
   can't close the list to get back to recipes, can't de-select selected categories, etc. Also, can these
   lists narrow by the existing selected categories.
4. Power Browser: I need an affordance to select categories not currently in one of the groups.
5. Recipe Capture in the Browser … I have a place to copy a prompt to curate the comments, but no place to
   paste the returned result. I also need to be able to delete tags that the process is trying to add
   because a whole bunch are listed in the metadata.
6. I feel like at one time I could view Archived recipes (so I could actually delete) but now I don't know
   how to. And I should have a choice to Archive a recipe or delete it rather than being a two-step process.
7. I am trying to create a variation, but when I tap the "save" button, nothing happens. (See screenshot.)
8. When I tap the "full screen" arrows, I'd like the tabs to automatically move from sidebar to the top if
   they are currently in sidebar.
9. I need to be able to delete a workbench. The delete button IS on the row swipe, but I can never get it
   from the swipe … it's "too far" and by the time I'm able to press it, the row assumes I'm making a
   complete swipe and archives.

---

## Thread A — Power Browser facets overhaul (items 2 + 3 + 4, one root corner)

**All three live in [PowerBrowserView.swift](../../YesChefApp/PowerBrowserView.swift) +
[PowerBrowserModel.swift](../../YesChefApp/PowerBrowserModel.swift).** They're the same surface and the
cleanest answer to item 3 (the navigation dead-end) is a restructure that also carries items 2 and 4 — so
this is one dispatch.

### Root cause / findings

- **Item 2 (Website):** `PowerBrowserSourceFilters` iterates `RecipeBrowserSourceField.allCases`
  ([PowerBrowserView.swift:175](../../YesChefApp/PowerBrowserView.swift#L175)), which includes `.website`
  (Core enum, [RecipeBrowser.swift:52-57](../../YesChefPackage/Sources/YesChefCore/RecipeBrowser.swift#L52)).
  Every distinct URL becomes its own option → a useless wall of single-recipe links.
- **Item 3 (dead-end + no de-select + no narrowing):** Source/Author render as `NavigationLink`s that push
  `PowerBrowserSourceFilterPicker` into the **sidebar column** of a `.balanced` `NavigationSplitView` that
  also has `.toolbar(removing: .sidebarToggle)`
  ([PowerBrowserView.swift:170-226](../../YesChefApp/PowerBrowserView.swift#L170)). Pushing a picker into a
  peer sidebar column is the dead-end the cook hit — there's no obvious way back to results, and it's
  inconsistent with the facet rows right above it, which are inline `DisclosureGroup`s. (De-select *does*
  work in the model — `sourceValueButtonTapped` toggles — but the picker's affordance reads one-way.) The
  options list is built from **all** `browserData.sources`
  ([PowerBrowserModel.swift:174-180](../../YesChefApp/PowerBrowserModel.swift#L174)), never scoped to the
  current result.
- **Item 4 (loose categories):** the sidebar only surfaces categories that belong to a facet
  (`result.availableFacets`). Categories with `facetID == nil` are unreachable — **even though the engine
  already filters by them** via `query.looseLabelIDs` / `matchesLooseLabels`
  ([RecipeBrowser.swift:9,420](../../YesChefPackage/Sources/YesChefCore/RecipeBrowser.swift#L420)). Pure UI
  gap; no engine work.

### Fix approach

1. **Drop Website** from the Source section — filter `.website` out of the iterated fields (keep the Core
   enum case; it may be used for display elsewhere). Confirm no other consumer relies on it appearing here.
2. **Convert Source & Author (and Cookbook/Publication) from `NavigationLink` pickers to inline
   `DisclosureGroup` rows**, matching the facet rows directly above them — same tap-to-toggle row
   (`PowerBrowserFacetValueRow` style with a checkmark), same "stay on the results" behavior. This deletes
   the navigation dead-end (item 3a), makes de-select an obvious same-row re-tap (item 3b), and keeps the
   result list visible while filtering. Keep the search-to-filter for long lists (an inline searchable or a
   simple contains-filter field per group).
3. **Narrow source/author options to the current result** (item 3c): compute each field's option list from
   the sources of `result.matchingRecipeIDs`, not the whole library, and show a per-value matching count
   like the facet rows do. (Preserve already-selected values even if their count drops to keep them
   de-selectable.)
4. **Add a loose-categories affordance** (item 4): a new sidebar section ("Other Labels" / "Ungrouped
   Categories") listing categories with `facetID == nil` that appear in the current result, each toggling
   membership in `query.looseLabelIDs`. Wire them into `activeSelections` / the selection bar so they show
   as removable chips like the rest.

**Size:** medium. **Priority:** high (item 3 is a genuine dead-end). View + model only, no schema, engine
already supports loose labels.

### Codex dispatch prompt

> **Power Browser facets overhaul.** In `YesChefApp/PowerBrowserView.swift` and `PowerBrowserModel.swift`:
> (1) Remove the **Website** field from the Source filters — filter `.website` out of the
> `RecipeBrowserSourceField.allCases` iteration in `PowerBrowserSourceFilters`; leave the Core enum
> unchanged. (2) Replace the `NavigationLink` → `PowerBrowserSourceFilterPicker` pattern for the remaining
> source fields (Source, Author, Cookbook, Publication) with **inline `DisclosureGroup` rows** that live in
> the sidebar alongside the existing facet disclosure groups, using the same tap-to-toggle row with a
> selection checkmark and a matching-recipe count. Selecting/deselecting must never navigate away from the
> results. Keep a contains-filter for long lists. (3) Scope each source field's option list to the sources
> of the **current** `result.matchingRecipeIDs` (not all of `browserData.sources`), but always keep
> already-selected values present so they stay removable. (4) Add a new sidebar section for **ungrouped
> categories** (`category.facetID == nil`) that appear in the current result; tapping toggles the category
> in `query.looseLabelIDs` (the engine already filters on this — do not touch the engine), and these must
> appear as removable chips in `activeSelections` / the selection bar. No schema changes. Build the package
> and run `YesChefTests`; leave the device pass to Jon.

---

## Thread B — Capture comment curation: paste door + bulk tag removal (item 5)

Two sub-items in [RecipeCaptureView.swift](../../YesChefApp/RecipeCaptureView.swift).

### 5a — "no place to paste the returned result"

**Finding:** the paste door *exists* — `ReaderFeedbackHandoffControls`
([HandoffInAppTransport.swift:388-409](../../YesChefApp/HandoffInAppTransport.swift#L388)) pairs
"Copy Curation Prompt" with a system `PasteButton` rendered next to it in the Reader Feedback section
([RecipeCaptureView.swift:474-494](../../YesChefApp/RecipeCaptureView.swift#L474)). But a bare system
`PasteButton` is exactly what this codebase has repeatedly found unreliable/undiscoverable — the doc
comment on `HandoffCopyPasteControls`
([HandoffInAppTransport.swift:316-324](../../YesChefApp/HandoffInAppTransport.swift#L316)) records that
`PasteButton` silently disappears in menus/overflow, and ADR-0041 Amd 1 / ADR-0042 S4 both retired it for a
plain button that reads `UIPasteboard.general.string` directly. The cook copied the prompt, went to
ChatGPT, came back, and couldn't find/use the return.

**Fix:** replace the `PasteButton` in `ReaderFeedbackHandoffControls` with an **explicit labeled button**
("Paste Curated Comments") that reads `UIPasteboard.general.string` and calls
`transport.pastedReaderFeedbackResults(...)` — same pattern as the recipe-body hand-off menu
([RecipeDetailView.swift:191-203](../../YesChefApp/RecipeDetailView.swift#L191)). Ensure the paste control
is shown in every place the copy prompt is (it already is, gated on `readerFeedbackComments` non-empty).
Repro from the **in-browser** capture path first (the cook said "in the Browser").

### 5b — "delete tags the process is trying to add … a whole bunch in the metadata"

**Finding:** site keywords land in `draft.page.tagNames` and render as editable rows with one-at-a-time
swipe-to-delete ([RecipeCaptureView.swift:326-335](../../YesChefApp/RecipeCaptureView.swift#L326);
model getters/`removeReviewTags` at [RecipeModels.swift:477-504](../../YesChefApp/RecipeModels.swift#L477)).
When a page dumps 20+ keywords, one-by-one swipe is unusable. This is edit-not-massage territory
([[decompose-notes-into-typed-homes]]; verbatim passthrough per the 2026-08-06 Thread C1 decision) — so a
bulk clear is in-bounds, we're just removing before commit.

**Fix:** add a **"Remove All Tags"** button in the Categories & Tags section header/footer (and the same for
Categories while we're there), backed by trivial `removeAllReviewTags()` / `removeAllReviewCategories()` on
the model. Optionally support `EditMode` multi-select delete for the same list. Keep the per-row swipe.

**Size:** small (both). **Priority:** medium. View + tiny model methods, no schema.

### Codex dispatch prompt

> **Capture comment-curation fixes.** (A) In `YesChefApp/HandoffInAppTransport.swift`, change
> `ReaderFeedbackHandoffControls` so the return is taken by an **explicit labeled button** ("Paste Curated
> Comments") that reads `UIPasteboard.general.string` and calls `pastedReaderFeedbackResults`, replacing the
> system `PasteButton` (which the codebase has repeatedly found undiscoverable — see the doc comment on
> `HandoffCopyPasteControls` and ADR-0041 Amd 1 / ADR-0042 S4). Match the plain-button pattern used by the
> recipe-body hand-off menu in `RecipeDetailView.swift`. Verify it appears in the in-browser capture flow.
> (B) In `YesChefApp/RecipeCaptureView.swift` + `RecipeModels.swift`, add a **"Remove All Tags"** action to
> the Categories & Tags section (and "Remove All Categories"), backed by new `removeAllReviewTags()` /
> `removeAllReviewCategories()` model methods that clear `draft.page.tagNames` / `.categoryNames`. Keep the
> existing per-row swipe delete. Build package + run `YesChefTests`.

---

## Thread C — Archive vs. Delete lifecycle (item 6)

### Root cause / findings

- **Archived recipes view exists but is buried.** `ArchivedRecipesView`
  ([RecipeLibraryView.swift:542-579](../../YesChefApp/RecipeLibraryView.swift#L542)) is only reachable via
  **Settings → Archived Recipes** ([SettingsViews.swift:270](../../YesChefApp/SettingsViews.swift#L270)).
  The cook remembers it being easier to find — it moved into Settings.
- **Delete is a forced two-step.** The library and detail swipe/menu only offer **Archive**
  (`deleteButtonTapped` → archives; [RecipeLibraryView.swift:452-459](../../YesChefApp/RecipeLibraryView.swift#L452),
  [RecipeDetailView.swift:237-241](../../YesChefApp/RecipeDetailView.swift#L237)). Permanent delete only
  exists **inside** the archived view ([RecipeLibraryView.swift:562-569](../../YesChefApp/RecipeLibraryView.swift#L562)).
  So deleting = archive → hunt for Settings → Archived → Delete Permanently. The confirmation +
  `deleteArchivedRecipe` destination already exist ([AppDestinationPresentation.swift:131-151](../../YesChefApp/AppDestinationPresentation.swift#L131)).

### Fix approach

1. **Make Archived Recipes discoverable from the recipe library** — add an entry point from the Recipes
   list (a toolbar/overflow item "Archived Recipes", or a status-bar link). Keep the Settings row too.
2. **Offer Archive *and* Delete at the point of action** — in the library swipe and the detail overflow,
   present both: "Archive" and a destructive "Delete…" that goes straight to the existing
   permanent-delete confirmation (`confirmDeleteRecipe`/`deleteArchivedRecipe` path), so the cook chooses
   without the archive detour.
3. **Heed [[alert-ispresented-destructive-setter]]** — SwiftUI writes the `isPresented`/`item` binding to
   nil *before* the confirm action fires; make sure the delete confirmation captures the `recipeID` in the
   button closure, not from a binding that's already been cleared. This exact class of bug shipped past
   three reviews on the ADR-0030 restore path.

**Size:** small–medium. **Priority:** medium-high (destructive UX). View + presentation wiring; the delete
repository path already exists.

### Codex dispatch prompt

> **Archive/Delete recipe lifecycle.** (1) Add a discoverable entry to **Archived Recipes** from the recipe
> library (toolbar overflow item in `RecipeListView`, routing to the existing `ArchivedRecipesView` /
> `.archivedRecipes` pane); keep the Settings row. (2) In the library row swipe
> (`RecipeLibraryView.swift`) and the recipe-detail overflow menu (`RecipeDetailView.swift`), offer **both**
> "Archive" and a destructive "Delete…" — the latter routes directly to the existing permanent-delete
> confirmation (`deleteArchivedRecipe` destination in `AppDestinationPresentation.swift` /
> `confirmDeleteArchivedRecipeButtonTapped`), so delete is one step, not archive-then-delete. (3) Capture
> the `recipeID` inside the confirm button's closure — do **not** read it from the `isPresented`/`item`
> binding inside the action (SwiftUI clears it first; see the ADR-0030 restore bug). Build package + run
> `YesChefTests`.

---

## Thread D — "Create a variation → Save does nothing" (item 7)

**Bug — root cause confirmed from code (no screenshot needed).** Jon's detail: the Save button was
"absolutely colored and everything looked good to go." That rules out the disabled-button theories and
points squarely at a **swallowed-error / silent-failure** in the *adjustment review* flow — **not** the
`RecipeVariationEditor` (Edit Variation) surface I first guessed.

### Root cause

"Create a variation" is the **Adjust Recipe → Keep as Variation** flow. `RecipeAdjustmentReviewView` shows
title "Adjust Recipe" when `review.variationID == nil` and its confirmation button is **"Keep as Variation"**
([RecipeAdjustmentReviewView.swift:100-109](../../YesChefApp/RecipeAdjustmentReviewView.swift#L100)). The
button is enabled whenever the name is non-empty, and the name **defaults to "Variation"**
([line 173-177](../../YesChefApp/RecipeAdjustmentReviewView.swift#L173)) — so it always looks ready.

Two failures compound into "nothing happens":

1. **The save closure fails silently up the stack.** `keepAdjustmentAsVariationButtonTapped` — in *both*
   entry points ([RecipeDetailModel+Adjustment.swift:65-89](../../YesChefApp/RecipeDetailModel+Adjustment.swift#L65)
   and [HandoffReviewCoordinator.swift:502-524](../../YesChefApp/HandoffReviewCoordinator.swift#L502)) — on a
   thrown write sets `errorMessage`/`isShowingError = true`, **leaves `adjustmentReview` non-nil** (so the
   cover stays up), and returns `false`.
2. **The error alert is on the wrong layer.** The review is presented as a **`fullScreenCover`** (regular
   width) or **`sheet`** (compact) via `adjustmentReviewPresentation`
   ([RecipeDetailView.swift:91-93,929-939](../../YesChefApp/RecipeDetailView.swift#L929)). The
   `$model.isShowingError` / `$coordinator.isShowingError` alert is attached to the **parent**, which is now
   fully covered → **the alert cannot present.** Meanwhile `RecipeAdjustmentReviewView`'s `else` branch just
   resets `isKeepingVariation` and shows nothing
   ([RecipeAdjustmentReviewView.swift:144-151](../../YesChefApp/RecipeAdjustmentReviewView.swift#L144)).

Net: colored button → fires → write throws → every feedback channel is swallowed → "nothing happens." This
is a cousin of [[alert-ispresented-destructive-setter]] — an alert stranded behind its own cover. The same
silent-`else` shape sits on **Overwrite** and **Save Variation** too (lines 153-169), so those fail the same
way. **Overwrite** even sets `isShowingError` from `RecipeDetailModel.overwriteAdjustmentButtonTapped`
([lines 44-62](../../YesChefApp/RecipeDetailModel+Adjustment.swift#L44)) behind the same cover.

### Open question — *why* does the write throw?

Making it loud will reveal the real error on Jon's device, but the prime suspect is anchor normalization:
`keepAdjustmentProposalAsVariation` writes a model-proposed adjustment as a variation overlay, and the
ADR-0021 defect ([[variation-anchor-repair]]) is anchors copied from model output that were never normalized
to base row IDs. Codex should check that repository call for a throw-on-unresolvable-anchor path while
wiring the visible error.

### Fix approach

1. **Surface the error inside the cover, not behind it.** Give `RecipeAdjustmentReviewView` its own error
   presentation (an `.alert` on its own `NavigationStack`, driven by state the closures can set) — or have
   the `overwrite` / `keepAsVariation` / `saveVariation` closures signal failure in a way the review view
   itself renders. No failure path may depend on an alert attached to the covered parent.
2. **No silent `else`.** All three button handlers must show *why* on failure, not just reset the spinner.
3. **Then diagnose the underlying throw** (likely anchor normalization) once its message is visible; fix or
   file as a follow-up depending on what it is.

**Size:** small–medium. **Priority:** **high** (create-a-variation is dead for the cook). No longer blocked.

### Codex dispatch prompt

> **Fix "Create a variation → Save does nothing."** The bug is in the Adjust Recipe → Keep as Variation
> flow, not the Edit-Variation editor. `RecipeAdjustmentReviewView` is presented in a `fullScreenCover`/
> `sheet` (`adjustmentReviewPresentation` in `RecipeDetailView.swift`), but its save closures
> (`keepAdjustmentAsVariationButtonTapped`, `overwriteAdjustmentButtonTapped` in
> `RecipeDetailModel+Adjustment.swift` **and** `HandoffReviewCoordinator.swift`) report failure by setting
> `isShowingError` on the parent view — which is covered, so the alert never shows — and the review view's
> button `else` branches silently reset. Fix: (1) present the error **inside** `RecipeAdjustmentReviewView`'s
> own `NavigationStack` (its own `.alert`, driven by state the closures can set on failure), so Keep as
> Variation / Save Variation / Overwrite always give visible feedback; no failure path may rely on an alert
> attached to the covered parent. (2) Remove the silent `else` no-ops. (3) Then reproduce the underlying
> write throw — check `RecipeRepository.keepAdjustmentProposalAsVariation` for an anchor-normalization /
> unresolved-anchor throw (ADR-0021, `variation-anchor-repair`); report the actual error message. Build
> package + run `YesChefTests`; Jon does the device pass to confirm the real error and whether a follow-up is
> needed.

---

## Thread E — Reorder recipe sections (item 1)

### Root cause / findings

The editor renders each ingredient/instruction section as its **own Form `Section`** via
`ForEach($model.draft.ingredientSections)` / `instructionSections`
([RecipeEditorView.swift:166-234](../../YesChefApp/RecipeEditorView.swift#L166)) — shared by the editor and
Create Recipe (`RecipeEditorFields`, ADR-0051 D1 / ADR-0053 D2). There is **no reorder affordance**, and
`.onMove` does not apply cleanly to a `ForEach` of whole `Section`s (it reorders rows within one section,
not sections). Sections carry a persisted `sortOrder`.

### Fix approach

Add per-section **Move Up / Move Down** controls (menu or buttons in each section, disabled at the
ends), backed by a `moveIngredientSection(id:direction:)` / `moveInstructionSection(...)` on
`RecipeEditorModel` that reorders the draft array and **renumbers `sortOrder`**. This is the least-invasive
option and works inside the Form-of-Sections layout, and it lands in both the editor and Create Recipe for
free. (A dedicated "Reorder Sections" edit-mode sheet is the heavier alternative — only if Jon wants
drag-reorder; note the 2027 SDK's `reorderable()` exists but this Form-section shape doesn't fit a single
`ForEach`/`List`.) Confirm the reorder is one of the draft's `hasUnsavedEdits` triggers.

**Size:** small–medium. **Priority:** medium. Editor model + view; sortOrder already persists, no schema.

### Codex dispatch prompt

> **Reorder recipe sections.** In `YesChefApp/RecipeEditorView.swift` (`RecipeEditorFields`) and
> `RecipeEditorModels.swift`, add **Move Up / Move Down** controls to each ingredient section and each
> instruction section (disabled at the ends). Back them with `moveIngredientSection(id:up:)` /
> `moveInstructionSection(id:up:)` on `RecipeEditorModel` that reorder the `draft.ingredientSections` /
> `.instructionSections` array **and renumber `sortOrder`** so the order persists on save. This must work in
> both the editor and Create Recipe (they share `RecipeEditorFields`). Ensure reordering marks the draft
> dirty (`hasUnsavedEdits`). Build package + run `YesChefTests`.

---

## Thread F — Focus/full-screen relocates the app tabs (item 8)

**Needs a short spike first — the SDK control surface is uncertain.**

### Findings

- The "full screen arrows" = the **Focus** toolbar button, which toggles the recipe tab's
  `NavigationSplitView` between `.doubleColumn` and `.detailOnly`
  ([AppMainLayout.swift:331-333](../../YesChefApp/AppMainLayout.swift#L331),
  `FocusToolbarButton` in [RecipeDetailView.swift:158-160](../../YesChefApp/RecipeDetailView.swift#L158)).
  That hides the **recipe list**, not the app's tab sidebar.
- The **app tabs** are a `TabView` with `.tabViewStyle(.sidebarAdaptable)`
  ([AppMainLayout.swift:137](../../YesChefApp/AppMainLayout.swift#L137)) — a left sidebar in regular width
  (ADR-0046). That's the "tabs in the sidebar" the cook means. In focus/full-screen they still eat width;
  the cook wants them to fall back to the top/bar presentation to reclaim it.

### Fix approach

1. **Spike:** determine the supported way, on the current (2027) SDK, to programmatically collapse a
   `.sidebarAdaptable` `TabView` into its tab-bar presentation (or drive its sidebar-expanded state) in sync
   with a focus toggle. Consult the SwiftUI 2027 notes ([[macos-longterm-target]] app-shell caveat). If
   there's no clean binding, evaluate swapping `tabViewStyle` (`.sidebarAdaptable` ↔ tab-bar) while focus is
   active, and confirm it doesn't reset tab customization/selection.
2. **Slice:** lift focus state so `AppMainLayout` can react — when the recipe (and menu/workbench) detail
   enters `.detailOnly`, request the tab presentation move to top/bar; restore on exit. Guard to regular
   width only (compact already shows a bottom bar).

**Size:** medium (spike-gated — could be small or "not cleanly possible"). **Priority:** medium. Report the
spike result to Jon before building; if the SDK won't cooperate, say so plainly rather than hacking it.

### Codex dispatch prompt (spike first)

> **Spike: relocate app tabs on focus.** The app tabs are a `TabView.tabViewStyle(.sidebarAdaptable)` in
> `AppMainLayout.swift`; the recipe/menu/workbench "Focus" buttons toggle their `NavigationSplitView` to
> `.detailOnly`. Determine, on the current SDK, whether the sidebar-adaptable tab presentation can be driven
> programmatically (collapse sidebar → top/bar) so it can follow the focus toggle in regular width. Report:
> is there a supported binding/API, or must we swap `tabViewStyle` (and does that clobber tab customization
> or selection)? Do not build the feature yet — return findings.

---

## Thread G — Workbench delete swipe conflict (item 9)

### Root cause

`workbenchSwipeActions` declares two trailing swipe buttons — **Mark Completed** first, then destructive
**Delete** ([WorkbenchViews.swift:80-103](../../YesChefApp/WorkbenchViews.swift#L80)) — with no
`allowsFullSwipe` override. SwiftUI's default full-swipe triggers the **first** trailing action, so a long
swipe fires **Mark Completed** ("archives") before the cook can tap Delete, which sits further in. Exactly
the reported "it's too far / it archives instead."

### Fix approach

Set **`allowsFullSwipe: false`** on the workbench trailing `swipeActions` so both buttons require a
deliberate tap — no accidental full-swipe. (Delete is destructive/irreversible, so making Delete the
full-swipe action is the wrong direction.) While here, confirm `deleteWorkbenchButtonTapped` has a
confirmation dialog; if not, add one — a workbench delete with no confirm + an accidental swipe is how data
walks off.

**Size:** tiny. **Priority:** medium. One line + optional confirm. Could ride with Thread D or go as its own
quick PR.

### Codex dispatch prompt

> **Fix workbench delete swipe.** In `YesChefApp/WorkbenchViews.swift`, set `allowsFullSwipe: false` on the
> trailing `swipeActions` in `workbenchSwipeActions` so the full-swipe no longer auto-fires "Mark Completed"
> before the cook can reach Delete; both actions require an explicit tap. Verify `deleteWorkbenchButtonTapped`
> is guarded by a confirmation dialog; add one if it isn't. Build package + run `YesChefTests`.

---

## Suggested sequencing

| # | Thread | Size | Priority | Notes |
|---|--------|------|----------|-------|
| 1 | G — Workbench delete swipe | tiny | med | Fastest win; one line + confirm |
| 2 | D — Create-variation Save bug | sm–med | **high** | Root cause confirmed (swallowed error behind cover); core action dead |
| 3 | A — Power Browser overhaul | med | high | Items 2+3+4 in one PR |
| 4 | C — Archive/Delete lifecycle | sm–med | med-high | Mind [[alert-ispresented-destructive-setter]] |
| 5 | B — Capture curation (paste + tags) | small | med | Items 5a+5b in one PR |
| 6 | E — Reorder sections | sm–med | med | Lands in editor + Create Recipe |
| 7 | F — Focus relocates tabs | med | med | **Spike first**; may not be cleanly possible |
