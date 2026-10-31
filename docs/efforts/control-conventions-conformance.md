# Effort — Control conventions conformance

Status: Ready
Summary: Every AI entry point becomes the Hand off · Paste · Ask now menu, and list rows lose their visible `…` in favor of context menus. Yes Chef is already the reference for the menu; this brings its other surfaces in line.

Implements: jon-platform `docs/ios/ui-and-platforms.md` § Controls (adopted 2026-10-31; the recipe detail
toolbar menu in `RecipeDetailView.swift` is the worked example). No schema change. No change to
handoff contracts or transport.

## 1. AI entry points

The recipe detail toolbar already matches the convention. These surfaces don't:

| Surface | Today | Becomes |
|---|---|---|
| Meal calendar toolbar (`MealCalendarViews.swift` ~271) | standalone **Ask** button | the three-item menu for the calendar's context. If the calendar has no hand-off of its own, the menu holds **Ask now** alone, still labeled and iconed as the menu; don't invent a hand-off. |
| Workbench (`WorkbenchViews.swift` ~216) | **Ask** inside an add menu | move it out to the toolbar's AI menu; the workbench's existing external-discussion hand-off becomes its **Hand off** item |
| Menu Playbook column header (`MenuPlaybookColumnView.swift` ~217) | bordered **Ask** button with an active ring | a scoped copy of the menu (allowed by the convention for an AI panel), matching the recipe Playbook's scoped menu (ADR-0041 Amd 1) |
| Recipe detail menu (`RecipeDetailView.swift` ~207) | **Ask now** has no state | checkmark while the chat tool is open (`askButtonTapped` already toggles it) |

Also fix the casing, everywhere it appears in the UI: **Hand off** (not "Hand Off", "Handoff", or
"Hand-off"). This covers `RecipeDetailView.swift:121` ("Hand Off Base Recipe" → "Hand off base
recipe") and `RecipeVariationPromotionPresentation.swift:101`. Code identifiers stay as they are.

Paste keeps its current behavior: always enabled, reads the pasteboard on tap, and every tap gives
visible feedback. The convention was written from it.

## 2. Row actions

Replace visible `…` / `ellipsis.circle` triggers **on list rows** with a `.contextMenu` holding the
same items, plus swipe actions for the one or two most-used items where the row doesn't have them
already:

- Grocery item row (`GroceryViews.swift` ~453): already has swipes; the menu moves to `.contextMenu`.
- Grocery source row (`GroceryViews.swift` ~502).
- Meal plan item row (`MealCalendarMealPlanItemRow.swift` ~32).
- Meal calendar day row's handoff `…` (`MealCalendarViews.swift` ~883) and the menu day handoff
  (`MenuDetailSections.swift` ~246): these are **AI** menus on a row. Make them the scoped AI menu
  (sparkles icon, Hand off · Paste verbs with the existing prep/complement variants as items) rather
  than a context menu. Discoverability matters more than quiet here.
- Placement actions (`MenuDetailSections.swift` ~488) and the Playbook section `…`
  (`RecipePlaybookView.swift` ~358): judge each one. If it's a row in a list, use a context menu. If
  it's a header on a standalone card, the `…` stays (allowed by the convention). Write the call
  you made in the PR.

Leave toolbar `…` menus alone.

## Done when

- No standalone "Ask" button remains (`grep -rn 'Label("Ask"' YesChefApp` is empty).
- Every AI menu uses the verbs and icons in the convention table, in that order, in sentence case.
- Ask now shows its checked state while chat is open.
- No `ellipsis.circle` on a list row. Each removed trigger's items are reachable by context menu,
  and the PR lists the ones kept as card or header `…`.
- `scripts/check-drift.sh` green. iPad screenshots of the meal calendar, workbench, and a grocery
  list in the PR.
