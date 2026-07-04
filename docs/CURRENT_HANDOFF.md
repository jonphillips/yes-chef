# Current Handoff

Last updated: July 4, 2026 (**ADR-0013 complete** — S2 day-scoped complement verb → inserts a `.note`
`MealPlanItem`, PR #86 → approved (S1 was PR #85); both slices shipped, zero schema. **Next Up = Reader
photo affordances** — manual set-as-cover (the effort's first schema touch) + full-screen pinch-zoom;
two cohesive slices, one dispatch. Lean verification is the default.)

The **short entry point** for a fresh Yes Chef conversation. This file is deliberately lean: it holds
**Next Up** (the dispatch target), the **Ready Efforts** queue, and the **Verification Pattern** —
nothing else. Completed-slice history, the implemented-behavior checkpoint, and strategic background
live in [`docs/DONE-LOG.md`](DONE-LOG.md) (read-rarely archive — do **not** read it on a dispatch).
`docs/AGENTS.md` remains the authoritative project/agent guide.

## Next Up

**Single dispatch target.** Dispatch to the coding agent with:
*"Do the Next Up effort in `docs/CURRENT_HANDOFF.md`."* If this section is empty, missing, or
ambiguous, the agent must **STOP and ask Jon — never infer the next task.** See
`docs/AGENTS.md` § Work Intake & Dispatch. A dispatch may bundle **several cohesive slices** (one
PR); do all listed, in order.

**Reader photo affordances — two cohesive slices, one dispatch.** Full design + decisions in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) § "Reader photo affordances" — read
that section first. Both surfaced from the Slice A device pass; independent but cohesive, so do **both, in
order** in one PR. **Read first:** `RecipeDetailView.swift` — `primaryDisplayPhoto` + the private
`displaySortKey` heuristic, `RecipePhotoGallery` (its own default-selection heuristic), and
`RecipePhotoFullScreenView`.

- **Slice 1 — manual "set as cover" (user override, persisted, sync-safe).** The reader cover is picked by
  `displaySortKey` and can choose a scanned reference page / low-res shot over the nice photo. Add a
  user override. **Storage home (decided, architect):** a new nullable column **`Recipe.coverPhotoID`**
  pointing to the chosen `RecipePhoto` — mirror the existing loose recipe-pointer shape
  (`TEXT REFERENCES "recipePhotos"("id") ON DELETE SET NULL`, same as `menuItems.recipeID`), so deleting
  the photo auto-nulls the cover and the heuristic resumes. **Not** a `RecipePhoto.isCover` bool (a
  multi-row flag invites two-covers sync conflicts; a single scalar resolves last-writer-wins). Additive,
  CloudKit-safe; bump `Recipe.dateModified` on set/clear. **Factor the resolver into `YesChefCore`** as a
  pure `coverPhoto(...)` function (override wins → else `displaySortKey` fallback for nil **and**
  dangling/not-yet-synced ids) and **unit-test the three cases** (this logic is FoundationModels-free, so
  a core test runs under `swift test` here). Point both the reader thumbnail and the gallery default at
  the one resolver. UI: a "Set as Cover" / "Use Automatic" affordance on the selected photo. iPad + iPhone.
- **Slice 2 — pinch-to-zoom + pan in `RecipePhotoFullScreenView` (no schema).** It only scale-to-fits;
  scanned pages aren't legible. Add `MagnifyGesture` + simultaneous drag-to-pan (clamped), double-tap to
  reset, close button still reachable. Pure view change — no schema, no core logic. iPad + iPhone.

**Standing release follow-up carried from Phase E (not a dispatch on its own):** before any prod/TestFlight
cut, promote to the **production** schema the Phase E Slice 3 pantry-policy + `canonicalName` CloudKit
fields, the ADR-0012 S2 `Menu.prepPlan` BLOB (PR #82), **and** the reader-photo-affordances
`Recipe.coverPhotoID` column (Next Up — the effort's first schema touch), and
note the app target (`PantryViews.swift` / `GroceryViews.swift`) compiles only in Jon's device pass, not CI.

Phase E is **fully complete** — Slice 4 (`PantrySuppression` + review UI, PR #80 → DONE-LOG), Slice 3
(pantry policy + `canonicalName` migration, PR #79 → DONE-LOG), Slices 1 + 2 (canonical key + `Measure`,
PR #77 → DONE-LOG). Dogfood batch 3 is
**complete** (ingredient structure · Chef It Up + Serve With · substitution ·
keep-awake; PR #75 → DONE-LOG). The cooking-workspace effort is **complete** (Slices A + B shipped,
PRs #73 / #74 → DONE-LOG). Its **Menu chat-verbs** follow-on shipped as ADR-0012 (complete). Its remaining
named follow-ons — **Meal-Planner chat verbs** and **reader photo affordances** — live in
[`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) as separate later efforts.

## Ready Efforts (queue)

Drawn into **Next Up** as needed (one dispatch, one or more cohesive slices); not itself a dispatch
target.

- **Recipe → grocery list w/ pantry checking** (Phase E) — **complete.** All four slices shipped: canonical
  key + `Measure` (PR #77), pantry policy + `canonicalName` migration (PR #79), `PantrySuppression` + review
  UI (PR #80) — all → DONE-LOG. Design rationale = [[grocery-pantry-threshold-design]]. Standing release
  follow-up (promote CloudKit fields to prod schema) noted under Next Up.

- **Actionable chat / LLMClientKit** (ADR-0011) — **complete.** The lift (Slice 1, 3 repos) + make-ahead
  (Slice 2) + Chef It Up / Serve With / per-line substitution shipped 2026-07-02/03 (PRs #73–#75 →
  DONE-LOG); `LLMClientKit` is a live path-dep. The **Menu** verb instance shipped as ADR-0012 (complete,
  above). The one remaining named-later verb — **Meal-Planner chat verbs** (`MealPlanItem`, absolute-date) —
  lives in [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md); classify each new verb's
  commit shape first ([[chat-verb-commit-shapes]]).

- **Dogfood fixes — batch 3** — complete (PR #75 → DONE-LOG; ingredient structure · Chef It Up +
  Serve With · substitution · keep-awake). Non-blocking device-pass notes recorded in the DONE-LOG entry.

- **Dogfood fixes — batches 1 & 2** — complete (PR #66, PR #71 → DONE-LOG). The batch-1 Slice 7
  delete-source-clobbers-amount-edit follow-up remains parked in
  [`docs/efforts/dogfood-fixes-batch-1.md`](efforts/dogfood-fixes-batch-1.md) for a later grocery slice.

- **Menu actionable chat** (ADR-0012, **Accepted** 2026-07-03) — **complete.** All three slices shipped:
  S1 (`.menu` context + composite grounding + grounded chat, PR #81 → DONE-LOG, no schema), S2 (prep-plan verb
  → `Menu.prepPlan`, PR #82 → DONE-LOG; the effort's first schema touch), S3 (complement verb → inserts a
  `MenuItem`, PR #83 → DONE-LOG, no schema). The Planner-day (`MealPlanItem`, absolute-date) version is a
  **separate follow-on ADR** (now ADR-0013, Accepted — in Next Up). Design + all five resolved decisions in
  [`docs/decisions/ADR-0012-menu-actionable-chat.md`](decisions/ADR-0012-menu-actionable-chat.md).

- **Meal-Planner actionable chat** (ADR-0013, **Accepted** 2026-07-04) — **complete.** Both slices shipped,
  zero schema: S1 (`.mealPlan` context + selected-day grounded chat, PR #85 → DONE-LOG) and S2 (complement
  verb → inserts a `.note` `MealPlanItem` on the selected day, PR #86 → DONE-LOG). Day-scoped (D1), inserts
  land on the subject day with model-picked slot (D2), no planner prep-plan verb (D3, no container table).
  Design in
  [`docs/decisions/ADR-0013-meal-planner-actionable-chat.md`](decisions/ADR-0013-meal-planner-actionable-chat.md).

- **Cooking workspace** — **complete** (Slices A + B, PRs #73 / #74 → DONE-LOG). Its Menu chat-verbs
  follow-on is now its own effort above (ADR-0012). The reader **photo affordances** (manual set-as-cover,
  pinch-zoom in the viewer) remain a named later effort in
  [`docs/efforts/cooking-workspace.md`](efforts/cooking-workspace.md) (host built context-general to
  receive them).

**Parked (not dispatched):**
- **Dogfood the core loop on two devices** — capture ~15–20 real recipes via the extension, cook from
  them (phone captures / iPad cooks, exercising the untested multi-device dedup-on-read convergence).
  Blocked on Apple shipping iOS Beta 3; Jon's simulator-pass feedback still marinating. The most
  annoying gaps found here still choose the real next milestone after the dogfood batch.

Comment ingestion stays in `docs/open-questions.md` until it is a scoped effort. Full completed-work
history and the implemented-behavior checkpoint are in [`docs/DONE-LOG.md`](DONE-LOG.md).

## Verification Pattern

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the
device pass regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files.
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise build `YesChef` **once** for `iPad Pro 13-inch (M5) (16GB)` (`-skipMacroValidation`).
- Run `scripts/check-drift.sh`.
- **Do not install/launch on simulators by default** — skip the install loop and hand straight to
  Jon's UI pass. Only boot/install a simulator when a change genuinely can't be confirmed from build
  + tests, and say why in the PR.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
