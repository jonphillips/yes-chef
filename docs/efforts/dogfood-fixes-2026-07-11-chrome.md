# Effort: Dogfood 2026-07-11 — chrome & navigation polish (mechanical bundle)

**Type:** App-layer UX polish. No schema, no new AI, no design fork — all four slices are re-presentation
of existing surfaces. **One dispatch, four cohesive slices, one PR.**
**Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
**Status:** **Ready** (from Jon's 2026-07-11 two-device dogfood).

**Read before starting:** `AppMainLayout.swift` (the side-menu / navigation source of truth),
`RecipeChatWorkspace.swift` (the AI *widget* — provider selector, the on-/off-device disclaimer text, the chat
text input), `RecipeDetailModel+Enrichment.swift` (the AI apply-action **context menu** verb definitions —
`title` / SF Symbol / destination-suffix strings for Save-to-Notes, Serve-With, Chef-It-Up, make-ahead, adjust;
paired case labels in `AISettings.swift`), `RecipeDetailView.swift` (the recipe-detail toolbar). Then
`CURRENT_HANDOFF.md` Verification Pattern.

**Build/verify (house constraint, [[lean-verification-default]]):** `xcodegen generate` if files are added;
build `YesChef` once for `iPad Pro 13-inch (M5)` with `-skipMacroValidation`; `scripts/check-drift.sh`. **No
simulator install** — Jon does the device pass (iPad both orientations + `iPhone 17 Pro` for the compact
toolbar/menu).

---

## S1 — Side-menu order + naming

Reorder the primary navigation to exactly (top → bottom):

1. **Recipes**
2. **Groceries**
3. **Calendar**  *(this is the meal-planner surface — confirm the label change from its current name)*
4. **Menus**
5. **Browser**
6. **Workbench**
7. **Settings**

Pure ordering + label change in the navigation source. Watch that any deep-link / restoration keyed on the
old order or destination titles still resolves.

## S2 — AI widget cleanup

In the chat panel (`RecipeChatWorkspace.swift`):

- **Remove the "content leaving the device" warning/disclaimer.** Jon: the provider dropdown already reveals
  where context goes, so the standing warning is redundant chrome. (Also fix the mangled accessibility hint
  string on the provider control while here: "Choose whether recipe context stays on device or is n a
  configured provider." — it's truncated.)
- **Remove the static "talking to X" label.** The dropdown selector already shows the active provider/model;
  the always-on label restates it. Keep the selector, drop the label.
- **Make the chat text input two lines tall** instead of one (taller default before scrolling).

## S3 — Recipe-detail toolbar reorder

Move the **Edit** button **back to the right-hand side** of the toolbar and make it the **left-most** button
in that trailing set. Final trailing order, left → right:

**Edit · Grocery · Add Meal · AI toggle · Workbench**

Straight `.primaryAction` ordering change in `RecipeDetailView.swift`.

## S4 — Delete a recipe image without replacing it

Today an image can only be *replaced*, not removed. Add a **delete-image** affordance on the recipe editor's
photo control so a cover/photo can be cleared outright (no replacement required). Clearing the cover photo
should behave correctly with the `Recipe.coverPhotoID` plumbing (PR #87) and sync (a cleared BLOB/asset is
sync-safe). Confirm the reader falls back to the placeholder cleanly when no image remains.

## S5 — AI apply-action context menu: relabel, re-icon, de-clutter

Simplify and polish the AI context menu (the apply-action verb menu, **not** the S2 chat widget). Verb
definitions live in `RecipeDetailModel+Enrichment.swift` (`title` + SF Symbol + the destination-suffix text).

**Labels — rename and drop the destination suffix entirely** (the "→ … section" tail goes; the action reads
clearly on its own, labels stay short/scannable):

| Current | New |
|---|---|
| Capture to notes | **Save to Notes** |
| Serve With → Serve With section | **Suggest Dishes** |
| Chef It Up → Chef It Up section | **Chef It Up** |
| Summarize make-ahead → Make-ahead section | **Create Prep Plan** |
| Adjust this recipe | **Revise Recipe** |

**SF Symbols — give each verb a distinct identity** (away from the near-identical checklist look):

| Menu item | SF Symbol |
|---|---|
| Save to Notes | `note.text.badge.plus` |
| Suggest Dishes | `fork.knife.circle` |
| Chef It Up | `wand.and.stars` |
| Create Prep Plan | `clock.badge.checkmark` |
| Revise Recipe | `pencil.and.outline` |

**Menu width — investigate, but expect the relabel to solve it.** SwiftUI's native `Menu` (a `UIMenu`
underneath) has **no public width API** — width is system-derived from the longest label, and the wrapping Jon
sees is caused by the long "→ … section" labels this slice removes. So: **apply the relabel first; the shorter
labels should eliminate the multi-line wrap without any container change.** Do **not** replace `Menu` with a
custom implementation. If, after the relabel, it still reads cramped on device, the smallest native-preserving
fallback is a `.popover` hosting a `List` of the actions (keeps SF Symbols + tap feel, loses the true system
menu chrome) — flag it for Jon as a follow-on rather than building it in this slice.

**Note the label churn touches tests** — the `-> Make-ahead section` / `-> X section` title strings appear in
`ChatApplyReviewItemTests`, `MakeAheadPlanTests`, `EditableReviewRoundTripTests`; update fixtures to match.

## Out of scope (tracked elsewhere)

- Fraction input accessory → [`fraction-input-accessory.md`](fraction-input-accessory.md).
- Edit-a-variation / promote-variation-to-standalone → design forks in `docs/open-questions.md`
  (2026-07-11 section).
