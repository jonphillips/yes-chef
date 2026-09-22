# Effort: Recipe reader density and Playbook placement

Status: **Designed — Jon-approved direction (2026-09-22); not dispatched.**
Summary: Put variation selection beside the recipe, shorten the reader header, and make the Playbook a compact Notes → Chef It Up → Make-ahead reference with a Serve With capsule strip and Ask now in the sparkle menu.
Related: [ADR-0021 Amendment 5](../decisions/ADR-0021-recipe-variations.md#amendment-5--variation-selection-returns-to-the-reader-header-2026-09-22), [ADR-0039 Amendment 4](../decisions/ADR-0039-playbook-column-thinking-vs-doing.md#amendment-4--recipe-reader-density-and-playbook-order-2026-09-22), [ADR-0041](../decisions/ADR-0041-playbook-section-toolbar-and-scoped-handoff.md), [ADR-0048](../decisions/ADR-0048-playbook-edit-grain.md).
Supersedes: the recipe-reader placement in ADR-0021 Amd4-D1/D5 and the recipe Playbook Ask placement and section order in ADR-0039 D3/Amd1. The typed stores, variation fold, related-recipe edges, and section hand-off contracts remain.

## Decision and visual reference

Jon approved the direction after reviewing the birria recipe screenshots and an interactive mockup on 2026-09-22. The mockup is available in this local Codex workspace at
`/Users/jon/.codex/visualizations/2026/09/22/01a0caaa-7e7f-7c01-aa01-429bfe3124ce/recipe-reader-mockup.html`.
The behavior and acceptance criteria below are the durable contract; the mockup illustrates composition and density, not exact SwiftUI pixels or invented ingredient parsing.

The wide reader keeps Ingredients, Directions, and the resizable Playbook co-visible. The compact reader keeps its Ingredients / Directions / Playbook picker. The shared recipe header carries the variation selector on both layouts so a cook can change the active recipe while looking at the recipe, then read its folded changes below without returning from the Playbook. The Playbook is a short index by default; long prose expands at the existing Wide detent. Serve With is a horizontal capsule strip at the bottom of the Playbook, after its other sections. “Bottom” means the end of the Playbook content, not a fixed overlay over a scrolling column.

## Dispatch shape

**One effort, one PR.** The slices below are ordered implementation and review checkpoints, not separate dispatch prompts. They share `RecipeDetailView.swift`, `RecipePlaybookView.swift`, the existing recipe model, and one device-reading pass. The executor should finish all slices before marking the draft PR ready. A design problem found during the device pass goes into the same PR for correction rather than silently changing the contract.

When Jon/architect promotes this effort into `docs/CURRENT_HANDOFF.md` as **Next Up**, the executor prompt is: **“Do the Next Up effort in `docs/CURRENT_HANDOFF.md`.”** This file is a scoped candidate until that promotion; the current handoff has no designated target.

## Invariants

- Keep the current recipe, variation, related-recipe, and Serve With stores. This effort requires no schema or migration.
- Selection continues through `RecipeDetailModel.activeVariationSelectionChanged`; the existing resolved ingredient/instruction fold, highlights, active method note, grocery selection, and local-only active-selection behavior remain authoritative.
- Keep every variation action: Hand Off, Paste, Rename, Edit Variation, Split Off as Recipe, Promote to Base, and Delete. Keep related-recipe navigation, link, and unlink. Keep Serve With title, note, provenance, add, update, delete, reorder, and repair behavior.
- Keep recipe-level Hand off and Paste in the sparkle toolbar menu and the current per-section menus/return routing. “Ask now” invokes the existing `model.askButtonTapped` path and current Ask presentation.
- Preserve every ingredient line's `originalText`. No inferred structured ingredient value becomes a write to the recipe.

## Slice 1 — reader header and variation selection

1. In `RecipeDetailView.swift`, compress the wide Directions-column header to the composition shown in the mock: title with a small photo, a one-line summary with an explicit reveal for more, a compact stats row, and one compact category/tag row. Keep servings/scaling, total time, source, rating, difficulty, and other metadata reachable when present. Format long minute totals in hours and minutes for reading (`285 min` → `4 hr 45 min`) without changing stored minutes. Do not hide a non-unit scaling factor.
2. Put a **variation selector in the shared recipe header** for wide and compact layouts. Show it when variations exist; the closed control names the active variation or “Base Recipe.” Its menu contains Base Recipe and every named variation. Selecting Base deselects the active variation. Keep selected-state accessibility text and stable variation IDs.
3. The selector's **Manage Variations** action opens a focused sheet containing the existing per-variation management actions. Move `RecipeVariationChoices`' selection and management responsibilities into appropriate small views rather than keeping the long variation note in the Playbook reader. The active method note stays with Directions. Remove the now-redundant “Return to Base Recipe” button from Directions.
4. Remove the combined Choices section from the Playbook. Give related recipes a separately named, low-priority section after Make-ahead and before Serve With. Retain its link/unlink and navigation affordances even when no links exist; the empty section may start collapsed.

**Checkpoint:** Switching Base ↔ Cheese Sauce from the header updates the existing recipe fold in place, at either width. All management actions and related-recipe actions remain reachable. The starting position for Instructions moves visibly upward compared with Jon's 2026-09-22 screenshots without compressing the step text.

## Slice 2 — Playbook hierarchy and Ask entry

1. In `RecipePlaybookView.swift`, order the prominent sections **Notes → Chef It Up → Make-ahead**. Put Related Recipes below them, then the Serve With strip from Slice 3. Keep Deliberation Log and Learnings available beneath the primary sections; their order should not break the three-section priority.
2. Start these prose sections collapsed when a recipe opens. The collapsed header keeps its filled/empty dot and shows a short, faithful preview when filled. Derive preview text from the first meaningful stored line, with truncation only for display; do not generate a new summary or count newline-separated blob lines as records. Notes may show a real note count because they are rows. Empty sections show a compact add/write path after expansion, with no large placeholder.
3. In the Comfortable Playbook width, expanding long Notes/Make-ahead/Chef It Up shows a short excerpt and **Read full**. That action sets the existing Playbook detent to Wide and shows the complete stored text. Wide remains selected until the user changes the detent. Keep the existing section `•••` actions and Markdown/bullet rendering.
4. Remove the Playbook-top Ask button. Add **Ask now** to the existing sparkle toolbar menu in `RecipeDetailView.swift`, alongside Hand off and Paste. The menu calls the existing Ask action; the Ask panel and its context behavior do not change.

**Checkpoint:** In the birria recipe's default state, Notes is the first Playbook item and Directions remains the dominant reading column. Opening long Notes and Make-ahead produces readable line lengths through Read full. The sparkle menu exposes Hand off, Paste, and Ask now; all three still work.

## Slice 3 — Serve With strip and ingredient scan treatment

1. Render Serve With as one compact horizontal `ScrollView(.horizontal)` strip at the bottom of the Playbook. A filled state shows title capsules in stored order with a visible cue that more can scroll; an empty state shows a single **+ Add** action. Keep Add available when filled too. Use real `Button`s with item titles for VoiceOver.
2. Tapping a capsule opens its title and full note with edit/delete actions. A compact management sheet retains reorder and provenance/repair affordances backed by the current `RecipeDetailModel` methods. Reuse the existing row editor where it helps; the capsule strip is a reading surface, not a new storage or editing grain. A Serve With decode/repair failure remains visible and repairable.
3. In `IngredientLineRow`, improve first-glance scanning only where the line's parsed fields can be displayed without losing the meaning of `originalText` or the current scaled display. Make quantity/item visually primary and preparation/comment secondary. If the structured fields do not faithfully account for the line, render the current intact line instead. Headers, author annotations, optional/variation highlights, and scaled amounts keep their current semantics. Put any nontrivial display decision in a pure helper and test the birria-style long line and the verbatim fallback.

**Checkpoint:** Empty Serve With costs roughly one row; filled Serve With shows horizontally scrollable capsules. Item notes and all edit operations are accessible, including on compact width. Ingredient emphasis never silently drops source words or alters stored lines.

## Verification and device pass

- Run `scripts/check-drift.sh`. Since this effort touches `YesChefApp/`, run the elevated generic iOS build through `scripts/xcodebuild-summary.sh` using the command in `docs/CURRENT_HANDOFF.md`'s Verification Pattern. If app-layer model code changes, also run the required elevated `YesChefTests` target. Do not substitute a package build for the app build.
- Focus tests on the pure ingredient display/fallback logic and any new nontrivial state behavior. A test that merely mirrors view order is not useful.
- Jon's primary UI pass is on the **13-inch iPad**, portrait and landscape, using a long-title recipe, the birria recipe, an active variation, a long Note, long Make-ahead, and empty/filled Serve With. Also check the compact picker on iPhone or narrow iPad, larger text, and VoiceOver reachability of the variation selector, capsule row, and Ask now.
- Ready-for-review means the implementation and mock agree on hierarchy and reading density, and the existing variation, related-recipe, hand-off, and Serve With actions all remain reachable. The PR description should call out any deliberate visual departure from the mock and the device-pass observations.
