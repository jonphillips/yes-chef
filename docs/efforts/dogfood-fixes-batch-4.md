# Effort: Dogfood fixes — batch 4 (shared chat polish + substitution removal)

**Type:** Bug fix + layout nits on the **shared** chat surface, plus a feature removal.
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/device pass)
**Status:** **Next Up** (`CURRENT_HANDOFF.md` § Next Up). Sourced from Jon's dogfood pass 2026-07-04.

**Key leverage:** the chat UI is **one shared component** — `RecipeChatPanel` + the
`ChatWorkspaceSplit` container in `YesChefApp/RecipeChatWorkspace.swift`, consumed identically by
`RecipeDetailView.swift`, `MenuViews.swift`, and `MealCalendarViews.swift`. Slice 1 fixes therefore
land on **all three** surfaces at once.

**Read first:** `RecipeChatWorkspace.swift` (`SelectableAssistantText`/`IntrinsicTextView` ~line 538,
`ChatWorkspaceSplit`/`readerWidth` ~line 38), `MealCalendarViews.swift` (~line 250 split host), and the
substitution surface enumerated in Slice 3.

**Build/verify:** Verification Pattern in `CURRENT_HANDOFF.md`. Slice 3 changes core + adds a migration →
`swift build` the package and run the core tests; the chat-height and layout slices are iPad-primary — Jon
does the device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`. `xcodegen generate` if files are added.

---

## SLICE 1 — assistant replies truncate / overlap (real bug)

**Symptom** (Jon, screenshots 2026-07-04): long assistant responses render clipped and overlap the next
bubble, on both Claude and ChatGPT tiers.

**Root cause (architect read, to confirm on implement):** assistant bubbles render through
`SelectableAssistantText`, a **non-scrolling** `UITextView` (`isScrollEnabled = false`) whose height is
supplied by a custom `IntrinsicTextView.intrinsicContentSize` reading `contentSize.height`
(`RecipeChatWorkspace.swift` ~line 612). Inside a `LazyVStack` in a `ScrollView`, that intrinsic height is
read before the layout width is settled, so tall replies report a stale/short height → truncation and
overlap. Classic self-sizing-`UITextView`-in-SwiftUI trap.

- **Fix direction:** make the text view report a height computed against its **actual** available width
  (e.g. size via `sizeThatFits`/`systemLayoutSizeFitting` at the laid-out width, or re-invalidate on width
  change), so each bubble claims its true height in the stack. Confirm the diagnosis before committing.
- **Acceptance:** a multi-paragraph assistant reply shows in full, no clipping, no overlap with the
  following bubble; verified in all three hosts (recipe reader, menu, meal-planner day) and both chat tiers,
  iPad + iPhone. Text selection still works.

## SLICE 2 — two shared-chat layout nits

### 2a — planner day-view chat "oddly inset"

The meal-planner split host wraps its reader in `ScrollView { agendaContent.padding() }` with a
`.frame(minHeight: 560)` (`MealCalendarViews.swift` ~line 257) — the recipe and menu hosts don't add that
extra padding/min-height, which is why the planner day agenda reads as oddly inset next to the chat pane.

- **Fix direction:** align the planner split-host reader framing with the recipe/menu hosts (drop the
  redundant inset / reconcile the padding) so the day agenda sits flush like the other two.
- **Acceptance:** planner day view with chat open matches the recipe/menu chat layout's insets; no regression
  to the non-split (`agendaContent`) path.

### 2b — let the chat expand to ~75% (so the reader *can* flip to the iPhone layout)

**Corrected from the first draft** (Jon 2026-07-04): the reader collapsing to the iPhone segmented layout is
**desired**, not a bug. The actual problem is the **`chat-dive` detent only reaches ~50%**, so the user can
never drag the chat wide enough to *see* that collapse. Widen it.

- **Root cause:** `chatWidth(for: .chatDive)` = `min(max(total*0.48, 440), available*0.58)` — chat maxes at
  ~58% of width (`RecipeChatWorkspace.swift` ~line 135). Two things then pin it there: the drag **snaps to
  the nearest detent** on release (`nearestDetent`, ~line 140), and `proposedChatWidth` hard-caps the drag at
  a **360pt reader floor** (`total − divider − 360`, ~line 124). So even dragging past 58% snaps back, and
  the floor blocks ~75% on most iPad widths anyway.
- **Fix direction:** raise the `chat-dive` target to **~75%** of total (so it *settles* there), and lower the
  `proposedChatWidth` reader floor enough that the reader can shrink below the **two-column → segmented**
  threshold and flip to the iPhone layout (which is the intended, acceptable narrow state). Keep a floor that
  keeps the segmented reader usable (don't let it go to zero — that's what the `reader-only` detent is for).
  Consider a third detent step or just widening `chat-dive`; Codex's call, but the **settled** max must reach
  ~75%. Verify the snap picks the wide detent, not a rubber-band back.
- **Acceptance:** on iPad (portrait **and** landscape), drag the chat pane to ~75% and **release** — it stays
  wide, and the reader flips to the segmented ingredients/directions layout and remains usable at that width.
  The `balanced` and `reader-only` detents are unchanged; VoiceOver detent-cycler still reaches every step.

## SLICE 3 — remove the ingredient-substitution feature (full removal, incl. column)

**Decision (Jon 2026-07-04):** the substitution feature was a mistake — the AI suggested *vegetable broth*
for whole milk in a baking dish. Kill it entirely. **Full removal is safe now precisely because iCloud sync
is not yet live** — the additive-only CloudKit discipline protects deployed schema, and there is no
production deployment to protect. Substitutions are stored **per-recipe** (a column on `IngredientLine`,
which has a non-optional `recipeID` — no shared ingredient catalog), so nothing cross-recipe is affected.

Remove, top to bottom:

- **AI suggestion path (core):** `IngredientSubstitutionSuggestion` + `IngredientSubstitutionClient` and its
  dependency key + system prompt (`RecipeEnrichment.swift` ~lines 53, 203–280), and the
  `setIngredientSubstitution(...)` helper (~line 326). Drop `substitution` from the chat system-prompt verb
  list wording (`RecipeChat.swift` ~line 954) if present.
- **App UI:** `pendingSubstitution` / `isFindingSubstitution` / `PendingIngredientSubstitution`
  (`RecipeModels.swift` ~line 832), the `.sheet(item: $model.pendingSubstitution)` +
  `IngredientSubstitutionReviewView` (`RecipeDetailView.swift` ~line 114), the noisy per-ingredient
  substitution menu entry, and the manual **Substitution** field in the editor (`RecipeEditorView.swift`
  ~line 263).
- **Model + schema:** `IngredientLine.substitution` (`Models.swift` ~line 692) and its `CodingKeys` case
  (~line 826); `RecipeEditorDraft.substitution` + its wiring (`RecipeEditorDraft.swift`, `RecipeCore.swift`
  ~lines 898, 931). **Add a destructive migration** dropping the column:
  `ALTER TABLE "ingredientLines" DROP COLUMN "substitution"` (modern SQLite supports `DROP COLUMN`; if the
  toolchain's SQLite needs a table rebuild, do the standard rename-recreate-copy dance). This is a
  **schema-shrinking** migration — note it in the PR; it is only acceptable because sync is pre-launch.
- **Tests:** delete/retire the substitution assertions in the enrichment/editor tests.
- **Acceptance:** project builds; no `substitution` symbol remains outside migration history; a recipe with a
  previously-entered substitution loads cleanly (field simply gone); core tests green.

> **Slicing note:** Slice 3 touches a different subsystem from Slices 1–2 (core + migration vs. shared chat
> view), but **Jon confirmed 2026-07-04: keep it bundled in this batch** — one dogfood-batch-4 PR, all three
> slices. Not a separate migration PR.
