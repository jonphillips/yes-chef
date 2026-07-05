# Effort: Cooking workspace — dense reader + chat inspector on a draggable split

**Type:** UI re-presentation + generalization of the shipped make-ahead chat (PR #68) and the batch-2
provider picker. **Not a from-scratch build.**
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Slices A + B shipped + approved** (PRs #73 / #74 → DONE-LOG) — the split, dense reader,
context-general host, and selection-scoped apply-actions. The Menu/Planner chat-verb follow-ons also
shipped (ADR-0012, ADR-0013 — both complete). **The reader photo affordances (below) shipped** (PR #87 →
DONE-LOG). Two dogfood-sourced follow-ons remain **queued** here (not dispatched): a **day-scoped
make-ahead verb** for the meal planner (§ "Out of scope → Meal Planner context") and
**separately-scrollable ingredients/directions** in the dense reader (§ Slice A).
**Decision it implements:** [ADR-0011](../decisions/ADR-0011-actionable-chat-make-ahead.md) + its
**Amendment 1** (selection-scoped apply-actions, Accepted 2026-07-03). Design record:
`open-questions.md` § "Dogfooding — AI chat + recipe reader (2026-07-03)".

**Read before starting:** ADR-0011 (whole, incl. Amendment 1), the shipped
`YesChefPackage/Sources/YesChefCore/RecipeChat.swift` (the chat model, context enum, and
`ChatApplyAction` this effort revises), and `RecipeDetailView.swift` (current photo-forward reader +
`.sheet(item: $model.destination.chat)` presentation this effort replaces).

**Build/verify (house constraint):** FoundationModels-linked test bundles can't run under `swift test`
here — `swift build` the package; build the app with `-skipMacroValidation`. On-device tier verifies on
device. `xcodegen generate` after adding files; then the Verification Pattern in `CURRENT_HANDOFF.md`.
Anything selection/split-gesture is **iPad-primary** — Jon does the primary pass on
`iPad Pro 13-inch (M5)` in **both** orientations.

---

## The invariant this preserves

The reader is **always visible** while chatting — never full-screen chat, never a modal sheet over the
recipe. That's the whole point: cooking *with* an assistant, not chatting *about* a recipe. Every apply
lands in the reader, in place. **The user's tap on Commit is the only write** (ADR-0011).

## What already exists (build on it, don't reinvent)

- `RecipeChatContext` — **already an enum** (`case recipe(RecipeChatRecipeContext)`), `serialized()` into
  the system prompt. Menu/Planner are new cases, not a reshape.
- `RecipeChatModel` (`@MainActor @Observable`) — ephemeral messages, on-device streaming / frontier
  complete, `useFrontier`, `selectedProvider` + `availableProviders` (batch 2), `systemPrompt()`
  built from `context.serialized()`. Context-agnostic in substance; only the *name* and the prompt's
  "Discuss the recipe" wording are recipe-specific.
- `ChatApplyAction<Payload>` + `AnyChatApplyAction` — the catalog type. `extract` currently takes the
  **whole conversation** (`[RecipeChatMessage]`); Amendment 1 changes that (Slice B).
- `MakeAheadPlan` + `applyMakeAheadPlan` + `Recipe.makeAhead` — verb #1, unchanged here.

---

## SLICE A — the split + dense reader (no chat *behavior* change)

Re-present `RecipeDetailView`: replace photo-forward reader + chat sheet with the **detented draggable
split**. Chat behavior is unchanged — the existing `RecipeChatModel`/chat view is simply **re-hosted**
from `.sheet` into the inspector pane.

- **Detented draggable split (iPad).** A draggable grabber (the divider) that **snaps to detents**, not
  free continuous resize (free-drag panes aren't an iOS idiom; detents share the sheet-
  `presentationDetents` muscle). Detents: *reader-only* (chat closed, reader full-width) / *balanced*
  (default) / *chat-dive* (chat wide, reader narrow). Drag feels live, settles on a detent. **Persist**
  the last detent (per-device `@AppStorage` is fine; not synced). A **visible grabber** for
  discoverability; a **VoiceOver alternative** that cycles detents (a custom divider isn't self-evident
  to assistive tech).
- **Width-responsive reader (key architectural move).** The reader renders off its **current width, not
  the device class.** ≥ threshold → dense **two-column** (ingredients | directions), in *both* iPad
  orientations. < threshold → the **iPhone layout: a segmented ingredients/directions toggle**
  (Paprika-style; Jon confirms it's acceptable on iPhone). This is what makes the split cheap — the
  narrow layout already has to exist for iPhone, so the *chat-dive* detent reuses it instead of adding a
  third reader design. Density: small photo (thumbnail, not hero), tight line-height, no wasted vertical.
- **Scale control → toolbar** (pinned, always reachable). This is the **structural** fix for the
  full-screen clip bug; it **supersedes batch 2's tactical fix** — remove/replace that once this lands.
- **iPhone:** no room to split. Chat is a **separate presentation** (push/sheet), and the reader is its
  normal segmented self. The divider/split is iPad-only (landscape + portrait).
- **New view files** (keep `RecipeDetailView.swift` from ballooning): a `RecipeWorkspaceSplit` container
  (grabber + detents + persistence), a width-responsive `RecipeReaderView` (two-column ↔ segmented). Run
  `xcodegen generate`.
- **Acceptance:** open a recipe on iPad, drag the divider through all three detents; the reader stays
  usable at every width (flips to segmented when narrow); scale is reachable from the toolbar at every
  detent; chat works exactly as it does today, just docked in the inspector. iPhone unchanged except
  chat presentation. `swiftui-specialist`/`swiftui-pro` checkpoint on the split + reader.

> **Queued reader polish (dogfood 2026-07-04, not yet dispatched):** in the two-column dense reader,
> **ingredients and directions should scroll independently** — today they share one scroll. Give each
> column its own `ScrollView` so a long ingredient list and long instructions scroll separately on iPad
> (the narrow/segmented layout is unaffected — only one is visible at a time there). Small, self-contained;
> fold into the next reader slice.

## SLICE B — selection-scoped apply-actions (ADR-0011 Amendment 1)

Make *what the model writes* precise and human-chosen. Revises the catalog input from "the whole
conversation" to "a selected span, with the conversation as context."

- **Type change** (`RecipeChat.swift`): `ChatApplyAction.extract` from
  `(_ messages: [RecipeChatMessage]) -> Payload` to
  `(_ selection: String, _ context: [RecipeChatMessage]) -> Payload`; `AnyChatApplyAction.run` likewise.
  The make-ahead action passes `selection` as the primary subject; whether it also leans on `context` is
  **its own choice** (Amendment 1: extractor context scope is decided per-verb — make-ahead may want the
  back-and-forth; a focused card-distill may not).
- **Text selection over assistant messages** in the inspector arms the action bar. **Empty selection →
  falls back to the whole last assistant reply** (Amendment 1: selection is the *precision override*,
  never a dead-button gate). Buttons show what they'll act on ("Acting on your selection: …").
- **Review-before-commit card** (the "control center" moment, inspector-resident): tapping an action
  runs `extract`, stages the decoded result **as a card in the inspector** (Commit / Discard) — the one
  surface that may borrow extra room (grow taller / pop as a popover over the reader) because it's
  transient. **Commit lands in the reader on the left**, in place. No chat turn writes on its own.
- **Acceptance:** highlight one item in a multi-item reply → the action bar targets that span → tap →
  review card → Commit → it lands in the reader's make-ahead section. Deselect → the action falls back to
  the last reply. In-memory-DB test the commit; `swift build` (FM bundle can't run here).

## Generality threaded through A/B (design-for, don't build)

Jon (2026-07-03) wants this same window on **Menu** ("full make-ahead plan for this menu", "what dish is
this menu missing?", "good apps with this menu") and **Meal Planner**. So the host must be **context- and
motion-general from the start**, even though only recipe make-ahead ships here. Constraints:

- **Host is screen-agnostic.** Factor the split + inspector + catalog + review card as a reusable surface
  that takes a `RecipeChatContext` + `[AnyChatApplyAction]` catalog — **not welded into
  `RecipeDetailView`.** `RecipeDetailView` becomes *one host* that supplies `.recipe(...)` + the
  make-ahead verb. A later Menu screen supplies `.menu(...)` + menu verbs without reshaping the host.
  (Optional low-priority rename to shed the recipe-specific prefix: `RecipeChatModel` →
  `ChatWorkspaceModel`, `RecipeChat.swift` → `Chat.swift`. Churn-vs-clarity — flag, don't mandate.)
- **Context enum stays open.** `.menu(...)` / `.mealPlan(...)` are additive cases; a menu context
  serializes its **dishes** (so a menu prompt can reason across the whole menu). Don't hardcode
  recipe-shaped assumptions into `serialized()`. Make the system prompt's "Discuss the recipe" wording
  **context-aware**.
- **Review surface must not assume exactly one result.** Recipe make-ahead is one plan → one commit. But
  the named menu verbs split into two motions (see below), and "what's this menu missing" yields
  **several suggestion cards**, each individually committable. So design the review surface to stage a
  **list** of committable results (N = 1 for make-ahead today) — a small generalization now that avoids a
  rewrite later. Do **not** build the multi-card UI here; just don't foreclose it.

## Out of scope (named, deferred — Jon 2026-07-03; keep the design honest)

The Menu/Planner verbs prove the host generalizes; they are **separate efforts**, not built here. They
map onto the two motions ADR-0011 already named:

- **Menu, distill motion — "full make-ahead plan for this menu."** Like recipe make-ahead but
  **cross-dish**: the extract reasons over *all* the menu's dishes and sequences prep across them; the
  commit target is a **menu-level** make-ahead (a menu-modeling decision — new field vs. computed —
  deferred to the Menus model work). Stresses menu-context serialization.
- **Menu, suggestion-cards motion — "what dish is this menu missing?" / "good apps with this menu."**
  The other motion (galavant ADR-0030 proactive cards): structured cards, each **one-tap added as a
  lightweight menu item** (commit = add menu item). Validates that the catalog spans **both motions** and
  a **second context**.
- **Meal Planner context** — a `.mealPlan(...)` case shipped (ADR-0013: grounded chat + complement verb).
  **Queued follow-on verb (dogfood 2026-07-04):** a **day-scoped "make-ahead strategy" for all items on a
  planner day** — synthesize a prep sequence across *all* the day's recipes, **leveraging each recipe's
  saved `makeAhead`** where present but reasoning across the combined set. Distill motion, cross-recipe (the
  planner analogue of the Menu make-ahead verb). Classify commit shape first ([[chat-verb-commit-shapes]]) —
  likely a no-commit advisory or a per-day note, not a per-recipe field write. Respect
  [[llm-curation-not-synthesis]]: sequence/select distinct prep steps, don't flatten the recipes into one
  blob.
- **Chef It Up** (`Recipe.chefItUp`) — the second recipe field, per ADR-0011.

### Reader photo affordances (SHIPPED — PR #87 → DONE-LOG, 2026-07-04)

Surfaced testing Slice A; shipped in one dispatch (PR #87): manual set-as-cover (`Recipe.coverPhotoID`) +
full-screen pinch-zoom. Design record retained below for reference. Two cohesive, independent slices.

**Read first:** `RecipeDetailView.swift` — `primaryDisplayPhoto` (~line 641) + the private `displaySortKey`
heuristic (`isLowResolution` → `kindRank` → `sortOrder`), `RecipePhotoGallery` (its *own* default-selection
heuristic, ~line 726), and `RecipePhotoFullScreenView` (~line 784). The heuristic today: high-res beats
low-res, then `.hero` beats other kinds, then lowest `sortOrder`.

#### Slice 1 — manual "set as cover" (user override, persisted, sync-safe)

The reader cover is chosen by `displaySortKey` and can pick a **scanned reference page over a pretty
photo** (the nice shot loses when it's a `.gallery` kind that ties the scan at kind-rank 1, or is lower-res
than the scan — resolution wins before kind, so even a `.hero` can lose). Let the user override it; the
override is a per-recipe pointer, **not** a re-tune of the sort.

- **Storage home (decided — architect).** A new nullable column **`Recipe.coverPhotoID`** pointing to the
  chosen `RecipePhoto`. Mirror the existing loose recipe-pointer shape:
  `ALTER TABLE "recipes" ADD COLUMN "coverPhotoID" TEXT REFERENCES "recipePhotos"("id") ON DELETE SET NULL`
  (same as `menuItems.recipeID` / `mealPlanItems.recipeID`). Deleting the photo auto-nulls the cover → the
  heuristic resumes for free. **Rejected:** a `RecipePhoto.isCover` bool — a multi-row flag invites
  two-covers sync conflicts; a single scalar on the recipe resolves last-writer-wins naturally. Additive,
  nullable, CloudKit-safe. This is the effort's **first schema touch** → add to the standing prod-schema
  promotion follow-up in `CURRENT_HANDOFF.md`. Bump `Recipe.dateModified` on every set/clear so sync
  propagates and conflicts resolve last-writer-wins.
- **Resolution (factor into core + unit-test).** Move cover resolution into `YesChefCore` as a pure
  function `coverPhoto(coverPhotoID:from:)` (or similar): if `coverPhotoID` resolves to a photo in the
  displayable set → use it; **else fall back to the existing `displaySortKey` heuristic** — covering nil
  **and** a set-but-not-yet-synced/dangling id (never blank). This logic is FoundationModels-free, so a
  core unit test **runs** under `swift test` here — cover the three cases (override wins / nil falls back /
  dangling falls back). Point **both** the reader thumbnail (`primaryDisplayPhoto`) and the gallery's
  default selection (`RecipePhotoGallery.selectedPhoto`) at the same resolver so "cover" is consistent
  everywhere. (`displaySortKey` itself is unchanged — the override sits *in front of* it.)
- **UI.** A "Set as Cover" affordance on the selected gallery photo (and/or in the full-screen viewer) —
  context menu or button; writes `coverPhotoID` via a model/repository method. Offer "Use Automatic"
  (clear back to nil) when a manual cover is set. iPad + iPhone.
- **Acceptance.** A recipe whose scan currently wins the thumbnail → set a real photo as cover → the reader
  thumbnail **and** the gallery default both switch to it and persist across relaunch; delete the cover
  photo → thumbnail falls back to the heuristic; core unit tests green.

#### Slice 2 — pinch-to-zoom + pan in the full-screen viewer (no schema)

`RecipePhotoFullScreenView` only scale-to-fits; scanned pages and detailed photos aren't legible. The
enlarge flow (thumbnail → gallery → full-screen) otherwise works well.

- Add a magnify gesture (`MagnifyGesture`) + simultaneous drag-to-pan, clamped so the image can't be lost
  off-screen; double-tap toggles fit ↔ zoomed (reset). Keep the existing close button reachable at any
  zoom. iPad + iPhone; VoiceOver unaffected (the image already carries a label). **Pure view change — no
  schema, no core logic.**
- **Acceptance.** Open a scanned page full-screen → pinch to zoom and pan to read fine print → double-tap
  resets → close works at any zoom.

**Net-new cost (honest):** the grabber + detent gesture + persistence + VoiceOver cycler, and the
width-responsive reader flip (half-owed for iPhone anyway). The selection + review card revises types
already in place. The generality is mostly *discipline* (don't weld to `RecipeDetailView`), not extra
code.
