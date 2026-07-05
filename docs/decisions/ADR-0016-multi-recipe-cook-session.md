# ADR-0016 — Multi-recipe cook session (Reader-hosted, not Cooking Mode)

Status: **Accepted** (2026-07-05, D1–D7 ratified by Jon in the design conversation). A new cooking
surface, not an extension of an existing ADR. Binds ADR-0006 (vocabulary hygiene) and the width-responsive
Reader shipped under the cooking-workspace effort (PRs #73/#74, #91).

## Context

Jon routinely cooks **2–3 recipes from a single meal-planner day at once**, bouncing between them over
~2 hours. Today each recipe opens in isolation, so "switch to the other dish" means **backing all the way
out of one recipe and re-navigating into the next** — repeatedly, for the whole cook. That back-out loop is
the pain this ADR removes.

### Two things this ADR is explicitly *not*

- **Not Cooking Mode.** `CookingModeView` + `CookingModeModel` (the step-by-step half-sheet, one step at a
  time) is a surface **Jon does not use and does not want** — he cooks from the *whole picture*, not a blind
  step-by-step. Cooking Mode stays in the tree, **untouched**; it is not the vehicle and is not retired here
  (a possible later cleanup, not now). The vocabulary matters (ADR-0006): this feature is the **"cook
  session"**, entered by **"Cook these"** — never call it "Cooking Mode."
- **Not voice.** The original prompt was voice control to switch recipes. It was **dropped by design** (D7):
  switching among a small, *visible* set of dishes is a one-tap problem, and a tap-to-switch is strictly
  better than tap-then-speak-then-hope-it-parses. Voice only adds value if it is *zero*-tap
  (always-listening wake word), which is the expensive/fragile path — a separate later exploration if ever.

### The unifying insight

A **meal-planner day** and a **Menu** are the same thing underneath: an **ordered set of recipeIDs, each
with its own scale context**. So one surface serves both, sourced from either.

### What already exists in this repo (verified at session start)

- **The Reader is the surface Jon cooks from** — `RecipeReaderView` inside
  [`RecipeDetailView.swift`](../../YesChefApp/RecipeDetailView.swift), the width-responsive two-column
  ingredients/directions view (two-column on iPad ≥ threshold, segmented toggle when narrow) with
  independently-scrolling columns (PR #91).
- **`RecipeDetailView(recipeID:scaleContext:…)`** already takes an **optional `ScaleContext`** and builds a
  per-instance `RecipeDetailModel(recipeID:scaleContext:)` (line 16–31). It carries its own toolbar — scale,
  chat, plan, groceries, edit — so **hosting one Reader per recipe is nearly free**: the session is a
  container that swaps between these instances.
- **`ScaleContext`** ([`RecipeScaleCore.swift`](../../YesChefPackage/Sources/YesChefCore/RecipeScaleCore.swift))
  has exactly `.recipe(Recipe.ID)`, `.menuItem(MenuItem.ID)`, `.mealPlanItem(MealPlanItem.ID)`. The scale Jon
  sets on a placement is **already stored against that placement's id** — so the session threads the source
  item's context and the pre-set scale flows straight through, **zero new scaling code**.
- **The day's recipe set already exists in the model**: `MealCalendarModel.itemsForDay(_:)`
  ([`MealCalendarModels.swift:352`](../../YesChefApp/MealCalendarModels.swift:352)) returns that day's
  `MealPlanItem`s; a Menu's items are the analogous set. Both include non-recipe rows (`.note` /
  reservation) that must be filtered out ([[menu-item-recipe-id-invariant]]).
- **Keep-awake already exists** (`keepsScreenAwakeWhilePresented()`, used by Cooking Mode) — reuse it so the
  screen stays lit through the cook.

## Decision

Ship a **cook session**: an ordered `[(Recipe.ID, ScaleContext)]` drawn from a planner day or a menu, each
recipe rendered in the **existing Reader**, with a **pinned chip-strip switcher**, **session-only "done"**
that shrinks the strip, and **per-placement scale threaded through**. No schema change. No voice. Cooking
Mode untouched.

### Resolved decisions (D1–D7, ratified by Jon 2026-07-05)

1. **Surface = the existing Reader, one per recipe.** The session hosts `RecipeDetailView`/`RecipeReaderView`
   per recipe — the whole-picture view Jon already cooks from. **Rejected:** Cooking Mode (step-by-step),
   which Jon explicitly does not use. Cooking Mode is left untouched, not retired.
2. **Switcher = a pinned chip/pill strip above the Reader.** One pill per recipe (title + done state); **tap a
   pill or horizontal-swipe the Reader** to switch. **Rejected: system `TabView` chrome** — bottom tabs
   collide with the nav bar, and we need to *control* the strip to show completion and shrink it, which system
   tabs don't afford. (`TabView(selection:)` page-style is acceptable as the *keep-pages-alive mechanism*
   behind a custom chip strip — see D4 — but not as the visible control.)
3. **"Done" is session-only (ephemeral).** Marking a recipe done **collapses its chip** (dim + move to an
   overflow, or drop it) so the strip narrows to what's left; un-done restores it. **No persistence, no
   schema, sync-safe.** Persisting "I cooked this on this date" is a real but separate future ADR (a schema
   touch with sync implications, [[post-browser-sync-vs-features-tension]]) — deliberately **not** here.
4. **Per-recipe state is preserved across switches** — each recipe keeps its own **scroll position, ingredient
   checkmarks, and scale** while you bounce between them (the entire point vs. today's dismiss/reopen).
   *Implementation constraint for Codex:* the reader instances must be **kept alive** across a switch (e.g. a
   paged `TabView` with the index hidden, or a `ZStack` of retained pages) — **not** conditionally
   constructed one-at-a-time, which resets each Reader's `@State` on every switch.
5. **Scale is inherited from the source placement's `ScaleContext`** — `.mealPlanItem(item.id)` from a planner
   day, `.menuItem(item.id)` from a menu — set beforehand in the planner/menu context. **No scaling UI added
   to the session** (the Reader's existing scale toolbar item still works per-recipe if wanted, but the
   session adds nothing). Zero new scaling code (D5 rides entirely on existing `ScaleContext` plumbing).
6. **Source filtering — only recipe-kind items with a resolvable `recipeID` become chips.** `.note` /
   reservation items are excluded from the session ([[menu-item-recipe-id-invariant]]); they aren't cookable
   recipes and have no Reader to show.
7. **Voice is dropped from this feature** (rationale in Context). Not deferred-within-scope — removed. Revisit
   only as a standalone always-listening exploration if hands-free ever proves wanted.

## Consequences / boundaries

- **Zero schema change.** Session state (selected recipe, per-recipe done, checkmarks, scroll) is in-memory in
  an `@Observable @MainActor` session model. Nothing to sync, nothing to promote to the prod schema.
- **Reuse, not rebuild.** The width-responsive Reader, its scale plumbing, keep-awake, and the per-placement
  `ScaleContext` all exist. The net-new code is the **session container + chip strip + keep-alive paging +
  entry points**. Everything inside each pane is the Reader we already ship.
- **Cooking Mode untouched.** Left in place; may be retired in a later cleanup once the session proves out —
  not this ADR.
- **Entry points.** A **"Cook these"** affordance on a **planner day** (Slice 1) opens the session with that
  day's recipe-kind items in order; the same affordance on a **Menu** (Slice 2) opens it with the menu's
  recipe items. Present as a full-screen `NavigationStack`/cover with keep-awake on.
- **Vocabulary (ADR-0006).** "Cook session" / "Cook these," never "Cooking Mode." Planner and Menu stay
  distinct terms; both merely *source* the same session.
- **Invariant honored:** the session is read-for-cooking; it mutates no plan/menu on its own. Per-recipe
  edits still route through the Reader's existing toolbar actions.

## Slice plan (post-ratification)

- **S1 — the cook session + chip switcher, planner entry.** New `CookSessionModel`
  (`@MainActor @Observable`) holding the ordered `[(Recipe.ID, ScaleContext)]` + selected index + per-recipe
  session-done set. New `CookSessionView`: pinned chip strip (tap + swipe, completed chips collapse) over a
  **keep-alive** paged host of `RecipeDetailView(recipeID:scaleContext:…)`, one per recipe; keep-awake on.
  Wire the **"Cook these"** entry on a planner day, sourcing `itemsForDay`, filtered to recipe-kind items
  (D6), each with `.mealPlanItem(item.id)` scale (D5). Run `xcodegen generate`. iPad-primary; must also work
  on iPhone (chip strip + segmented Reader). No schema change.
- **S2 — Menu entry point.** Add the same **"Cook these"** affordance to a Menu, sourcing the menu's
  recipe-kind items with `.menuItem(item.id)` scale. Pure reuse of S1's `CookSessionView` — no new session
  surface. No schema change.

Two slices, **zero schema touch**. Lean verification is the default (`swift build` package if logic-only;
otherwise one app build for `iPad Pro 13-inch (M5) (16GB)` + `scripts/check-drift.sh`; no simulator install —
Jon does the device pass). Anything chip-strip / swipe / keep-alive-paging is **iPad + iPhone**, so Jon
passes on both `iPad Pro 13-inch (M5)` (both orientations) and `iPhone 17 Pro`.

## Related

- ADR-0006 (vocabulary hygiene — "cook session" ≠ "Cooking Mode"), the cooking-workspace effort
  ([`docs/efforts/cooking-workspace.md`](../efforts/cooking-workspace.md)) whose width-responsive Reader this
  hosts.
- Memory: [[menu-item-recipe-id-invariant]] (D6 filtering), [[post-browser-sync-vs-features-tension]] (why
  session-only done, D3), [[yeschef-milestone-arc]].
</content>
