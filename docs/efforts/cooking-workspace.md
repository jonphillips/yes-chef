# Effort: Cooking workspace — dense reader + chat inspector on a draggable split

**Type:** UI re-presentation + generalization of the shipped make-ahead chat (PR #68) and the batch-2
provider picker. **Not a from-scratch build.**
**Owner:** Codex (implement, per slice) · Claude (architect/review) · Jon (product/review)
**Status:** **Slice A shipped + approved 2026-07-03** (PR #73 → DONE-LOG) — the split, dense reader,
context-general host, and Jon's device-feedback polish. **Slice B is now the dispatch target** (see
`CURRENT_HANDOFF.md` § Next Up).
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
- **Meal Planner context** — a `.mealPlan(...)` case; verbs TBD.
- **Chef It Up** (`Recipe.chefItUp`) — the second recipe field, per ADR-0011.

### Reader photo affordances (roadmap — Jon, 2026-07-03, from Slice A device pass)

Surfaced testing Slice A; not part of A or B. Anchored here (moved out of `open-questions.md`).

- **Manual "set as cover" / thumbnail selection.** The reader thumbnail is chosen by a heuristic
  (`primaryDisplayPhoto`: high-res → `.hero` → lowest `sortOrder`). It can pick a **scanned
  reference-document page over a pretty photo** when the nice shot is a `.gallery` kind (ties the scan at
  kind-rank 1) or is lower-res than the scan (resolution wins before kind — so even a `.hero` can lose).
  Let the user pick and persist the cover; a user override, not a re-tune of the sort.
- **Pinch-to-zoom (+ pan) in the full-screen photo viewer.** `RecipePhotoFullScreenView` currently only
  scale-to-fits; add magnification so scanned pages and detailed photos are legible. The enlarge flow
  (thumbnail → gallery → full-screen) otherwise works well.

**Net-new cost (honest):** the grabber + detent gesture + persistence + VoiceOver cycler, and the
width-responsive reader flip (half-owed for iPhone anyway). The selection + review card revises types
already in place. The generality is mostly *discipline* (don't weld to `RecipeDetailView`), not extra
code.
