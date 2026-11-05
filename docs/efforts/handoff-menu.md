# Effort — One shared AI menu

Status: Ready
Summary: Lift the AI toolbar menu into a shared `HandoffMenu` in jon-platform, adopt it on all five Yes Chef screens,
and give Meal Calendar and Workbench Compare the Hand off and Paste they lack. No schema or sync change.

Implements: jon-platform `docs/ios/ui-and-platforms.md` § The AI entry point, and its `SEAM-LEDGER.md` row of the same
name. That rule is the decision, so there is no ADR here. Galavant adopts the view in its own brief,
`handoff-menu-adoption`.

## The rule being built

One menu, labeled **AI** with `sparkles`, holding **Hand off** (`sparkles.square.filled.on.square`), **Paste**
(`doc.on.clipboard`) and **Ask now** (`text.bubble.badge.sparkles`), in that order. A screen that offers chat also offers
a hand-off prompt. Hand-off-only menus on a row keep the **Hand off** label and its icon.

## Part 1 — jon-platform package PR (first)

Per `docs/agent-collaboration.md` § Dispatches whose code lands in jon-platform. Title it for this slice and link this
brief.

1. In `packages/LLMHandoffKit`, add a new target and library, `LLMHandoffUI`. **Don't add SwiftUI to the `LLMHandoffKit`
   target:** its manifest promises Foundation plus swift-dependencies, and the Yes Chef MCP server and Vinyl Fever's Core
   link it.
2. `HandoffSymbol` holds the four symbol names as public constants: `menu`, `handOff`, `paste`, `askNow`. `askNow` needs
   iOS 27, which both adopting apps target. The package's platforms stay as they are; say so in a doc comment.
3. `HandoffMenu` has two initializers, and adjust the generics as you see fit:
   - One purpose: `handOff: () -> Void`, `paste: () -> Void`, `isAskActive: Binding<Bool>`.
   - Several purposes: `paste`, `isAskActive`, and a `@ViewBuilder` of purpose items, shown in a **Hand off** submenu.

   Ask now is a `Toggle`, so the open state shows a checkmark. Label, icons and order are **not parameters**. That is the
   point of the lift. The view reads no pasteboard, because the caller's closure does, and this keeps the target free of
   UIKit.
4. Tests, in a new test target: each `HandoffSymbol` resolves on the host (`NSImage(systemSymbolName:…)`, behind
   `canImport(AppKit)`), so a mistyped name fails. Both initializers compile with a sample body.
5. Housekeeping in the same PR: move the seam from `SEAM-LEDGER.md` to `EXTRACTION-NOTES.md` (ledger rule 5), keeping a
   note that Galavant's adoption is still to come. Change "is being lifted into a shared view" in the Controls intro of
   `docs/ios/ui-and-platforms.md` to name `HandoffMenu`.

**Verification, listed in the PR body:** `scripts/quiet-run swift test --package-path packages/LLMHandoffKit`, plus a
build of Yes Chef and Galavant.

## Part 2 — Yes Chef PR (after Part 1 merges)

1. **`project.yml`:** add `LLMHandoffUI` to the `YesChef` target only, not the share extension. Regenerate the project.
2. **The three full menus become `HandoffMenu`:** `RecipeDetailView`, `WorkbenchViews`, `MenuPlaybookColumnView`. Behavior
   stays with the caller: Recipe keeps its base-recipe confirmation in the closure, and the Playbook keeps its
   `.accessibilityValue`.
3. **`WorkbenchCompareView` gains all three verbs**, using `.workbench(detail.workbench.id, task: .compare)`, the source
   `WorkbenchViews` already uses. This is harder than it looks, because Compare is a cover or sheet presented over the
   workbench, which is itself a sheet:
   - It needs its own `HandoffInAppTransport` and `.handoffTransportAlert`.
   - It needs its own `AppToastOverlay`. See the comment at `WorkbenchViews.swift` ≈ line 335: an overlay on the presenter
     doesn't draw over what it presents.
   - It needs its own `.handoffReviewDestinations()`, because the review sheet can't present from beneath the cover. The
     outer host must stand down while Compare is up, or two hosts bind one coordinator. Follow the claim pattern at
     `RecipeDetailView.swift` ≈ line 114 and `RecipeLibraryView.swift` ≈ line 473. Preferences don't cross a presentation,
     so claim from the workbench view on `model.isShowingCompare`. Check each outer host that wraps the workbench
     (`RecipeDetailView.swift` ≈ line 88, `RecipeLibraryView.swift` ≈ line 165, `RecipeDetailView.swift` ≈ line 446).
4. **`MealCalendarViews` toolbar gains all three verbs**, for the selected day:
   - Sources come from `HandoffExportSource.mealPlanSources(on: model.selectedDate, rows: model.selectedDayRows)`.
   - Hand off is a submenu: **Make-ahead**, **Complement**.
   - There is one Paste, using the make-ahead source. `HandoffExportSource.matches` compares source type and ID, not task,
     so a complement reply with its token still routes correctly. Pin that with a test. A reply with no token goes down
     the make-ahead path; that's accepted, because the week-rail row menu keeps its separate `Paste · Complement`.
   - **An empty day has no source.** Hand off and Paste stay enabled, and a tap gives visible feedback through the
     transport's existing toast or alert ("No meals on this day to hand off."). Don't hide or disable them.
   - The toolbar's host owns the transport, its alert and its `toastCenter`. Make `chatButtonTapped` non-optional if every
     caller passes it.
5. **`MealCalendarDayHeader`:** remove the hand-off actions, because the toolbar now covers the same day. Keep the grocery
   actions, and drop parameters and transports that end up unused. The week-rail row menu (`MealCalendarViews.swift` ≈
   line 889) stays as it is, since it serves a different day.
6. **Remaining literals:** `MenuDetailSections.swift:278`, `MealCalendarViews.swift` ≈ line 901, and `HandoffMenuActions`,
   `HandoffCopyPasteControls` and `ReaderFeedbackHandoffControls` in `HandoffInAppTransport.swift` use `HandoffSymbol`
   rather than string literals. Their labels don't change.

**Tests, in `YesChefTests`:** a `.mealPlan` source matches a stored complement hand-off for the same item and doesn't match
another item's. `mealPlanSources` returns nil for an empty day.

**Out of scope:** a local `Icon` enum for Yes Chef, and the other `sparkles` uses, which mean "AI" generally (Extract Recipe,
Curate, provenance, chat empty states).

**Verification:** `scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator, because this touches
app code ([`verification.md`](../verification.md)).

**Done when:** both PRs are in, the tests pass, no `Label("Ask now", systemImage: "sparkles")` remains, and closeout runs
(ADR-0005 D16), appending the device gate below.

## Device gate (Jon)

On iPad and iPhone, open the AI menu on a recipe, a menu's Playbook column, a workbench, Workbench Compare and the Meal
Calendar. Each shows `sparkles` and the three verbs in order, and Ask now shows a checkmark while chat is open. The Playbook
copy shows its "AI" text cleanly. In Compare, copy a prompt, then paste the reply: the toast and the review sheet both appear
over Compare, and closing it returns to Compare. On the calendar, hand off Complement from a filled day and paste the reply
through the single Paste: it opens the complement review. On an empty day, Hand off and Paste each explain why there's nothing
to do.

## Merge

The package lands in every consuming app and the app PR owes a gate, so Jon merges both (`agent-collaboration.md`, ADR-0005 D9).
