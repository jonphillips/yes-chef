# Effort: Menu planning overhaul — AI context + swipe/delete + affordances + toolbar reorg

**Type:** UX re-presentation + one AI-grounding fix. Builds on the shipped menu screen
(`MenuViews.swift`) and menu chat (ADR-0012). **Not a from-scratch build.**
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Queued** (one dispatch, sequenced slices, after the ADR-0017/0018 AI-config dispatch).
**Decisions it implements:** [ADR-0012 Amendment 1](../decisions/ADR-0012-menu-actionable-chat.md)
(menu AI context) + this effort's own UX calls. Design record: the 2026-07-05 design conversation.

**Read before starting:** ADR-0012 (whole, incl. **Amendment 1**), `MenuViews.swift` (the detail view,
toolbar, day sections, item/placement drafts), `MenuChatContext` in
`YesChefPackage/Sources/YesChefCore/RecipeChat.swift` (the serialization this revises), and the
**`swiftui-whats-new-27`** skill (the iOS 27 `swipeActions()` API for swipe-in-`ScrollView`; its
reorder API waits for the parked drag-drop follow-on).

**Build/verify (house constraint):** package logic via `swift build`; app via `-skipMacroValidation`,
built once; `xcodegen generate` after adding files; then `CURRENT_HANDOFF.md` Verification Pattern.
Menu work is **iPad-primary** — Jon does the primary pass on `iPad Pro 13-inch (M5)` in **both**
orientations, plus `iPhone 17 Pro` for the compact toolbar/sheet paths.

---

## The invariant this preserves

The menu chat grounds on the *whole* menu, and the model **proposes; the tap writes** (ADR-0011/0012).
Nothing here mutates the menu without an explicit tap (delete gets a confirm).

## Slice plan

- **S1 — AI can see the whole menu + the prep plan** *(highest value; ADR-0012 Amendment 1).*
  Tier-aware context budget (small on-device, large frontier) + clip make-ahead notes per-dish so **no
  dish is silently dropped** (A1); add the rendered **prep plan** to `MenuChatContext` (A2); reframe
  Regenerate as **read-and-refine the current plan**, not one-shot re-derive (A3). Pairs with the
  `high`-effort `MenuPrepPlan` from ADR-0017.

- **S2 — Swipe + delete.**
  - Dish row: swipe-**delete** (destructive) + swipe **"Move to day…"** (a day menu — the interim before
    drag-drop; `moveMenuItem(toDayOffset:)` already exists at `MenuViews.swift:515`).
  - Menu-list row: swipe-**delete with confirmation**.
  - *Impl note:* the dish list is a `VStack` in a `ScrollView`, **not** a `List` — use the iOS 27
    `swipeActions()` API (see the `swiftui-whats-new-27` skill).

- **S3 — Meal-time & row affordances.** Inline tappable **meal-slot pill** per dish (tap → Breakfast /
  Lunch / Dinner / … menu), matching the Paprika checklist; keep row-tap → the full edit sheet (which
  already has Day + meal-slot pickers). Don't copy Paprika's chrome — just the fast inline path.

- **S4 — Full-screen focus.** Reuse the Recipe List/Detail collapse affordance so selecting a menu can
  **hide the menu-list column** (when focused on "NJ 2026" you shouldn't have to see "Emerald Isle").

- **S5 — Toolbar reorg** (Jon's green-line drawing).
  - **Drop the redundant Chat ✨ button when the split AI panel is active** (`isSplitEnabled`); keep it in
    compact/iPhone, where it opens the chat sheet.
  - **Move Add Dish (+) and Place (📅+)** out of the right `.primaryAction` toolbar into a **left-aligned
    control set inside the detail body**, near the "Dishes" header — not in the list column.
  - **Extend Place** to also edit **number of days** (a day-count stepper already exists in the codebase
    — `MenuViews.swift:748` — to reuse), not just start date.

## Out of scope / parked follow-ons

- **Drag-and-drop reorder of dishes across days** — the eventual replacement for S2's "Move to day…".
  Deferred by Jon (2026-07-05) to keep this batch lower-risk; a named follow-on using the iOS 27 reorder
  API (`swiftui-whats-new-27`). S2's swipe-move is the interim.
- **Anthropic extended-thinking budget** and any auto-router — not here (ADR-0017 "Why not").
