# Effort: Dogfood fixes — menu-planner pass (2026-07-09)

**Type:** Two real bugs + one prompt/data fix + one missing-affordance, all low-ambiguity and design-decided.
**One Codex dispatch, one PR.** **Owner:** Codex (implement) · Claude (architect/review) · Jon (product/device pass).
Sourced from Jon's menu-planner dogfood pass 2026-07-09 (`~/code/cooking/menu_planning_llm_questions_and_responses-1.md`).

**Batching intent:** these four slices are bundled into a **single dispatch** on purpose — each is small,
design-decided, and independent, sharing the chat/menu/variation surfaces and no shared risk. This is an
implementation checklist, **not** four PRs. The **review-collection sheet** ([ADR-0026](../decisions/ADR-0026-review-collection-sheet.md))
that came out of the same pass is a **separate dispatch** (it touches the shared apply-action presentation
state and carries real ripple risk) — do **not** fold it in here.

**Read first:** `RecipeChatWorkspace.swift` (`SelectableAssistantText` ~653–732, `latestReplySubject` ~476,
`run(_:)` empty-result ~409–415), `MenuComplement.swift` (`MenuComplementSuggestion` ~13, `instructions`
~137, `parse` ~165), `MenuModels.swift` (`applyActionCatalog` complement mapping ~500–520,
`commitComplementSuggestion` ~540), `MenuCore.swift` (`addComplementItem` ~239), `Models.swift`
(`MenuItem.notes` ~403), `RecipeAdjustment.swift` (`keepAdjustmentProposalAsVariation` ~469,
`setActiveVariation` ~498), `RecipeDetailView.swift` (`variationPicker` ~383–399),
`RecipeDetailModel+Adjustment.swift` (~54, ~78).

**Build/verify:** package `swift build` + core tests for the Core changes (Slice B parse/round-trip,
Slice D rename repository call — unit-test each). Slice A (chat selection) and the Slice D UI affordance
are iPad-primary — Jon does the device pass on `iPad Pro 13-inch (M5)` and `iPhone 17 Pro`.
`xcodegen generate` if files are added. No schema change in any slice (see Slice B).

---

## SLICE A — chat selection never clears on deselect (real bug)

Selecting assistant text, then deselecting (tap away) **leaves the stale selection active**, so the next
verb acts on text the user thinks they've dropped. Root cause: every bubble is a separate `UITextView`
sharing one `$selectedAssistantText` binding (`SelectableAssistantText`, ~653); deselecting often doesn't
fire `textViewDidChangeSelection`, so the last non-empty selection sticks, and there is **no explicit
clear affordance**.

1. **Reliable clear on deselect.** Ensure a collapsed/empty selection reliably writes `""` back to the
   binding — including when the user taps outside the text view or into another bubble. (When a different
   bubble gains a selection, the previously-selected bubble must surrender the shared binding.)
2. **Explicit clear affordance.** When a selection is active, show a small "Clear selection" control on the
   `ChatActionSubjectView` ("Acting on your selection" chip, ~603) so the user can drop it without hunting
   for empty space to tap.

**Acceptance:** deselecting text (tap away / select in another bubble) drops the subject back to "latest
reply"; the chip's clear control zeroes the selection; the verb never fires on stale selected text.

**Note (confirmed constraints, not changing here):** with no selection the verb acts on the **latest
assistant reply** (`latestReplySubject`, ~476) — intended. Selection **cannot span multiple bubbles**
(each is an independent `UITextView`) — an architectural constraint of the per-bubble design, parked for
ADR discussion (see below), *not* addressed in this slice.

## SLICE B — complement suggestions carry a body (ingredients live in the note)

Per **[ADR-0012 Amendment 2](../decisions/ADR-0012-menu-actionable-chat.md#amendment-2--complement-suggestions-carry-a-body-ingredients-live-in-the-note)**.
The "What complements this?" verb captures **title only**, so the model's ingredient/spice/method detail is
discarded before commit. `MenuItem` already has a `notes: String?` column, so this is **schema-safe**.

1. **Body on the suggestion.** Add optional `body: String?` to `MenuComplementSuggestion`. Request it in
   `instructions` (extend the JSON to `{"kind","title","body","dayOffset","mealSlot"}`, `body` = the
   ingredient/detail prose for that one dish) and capture it in `parse`.
2. **Body in review + round-trip.** Render `body` in `rendered()` / `editableReviewText()` and parse it
   back in `applyingEditableReviewText` so the human can **edit the ingredients** in the review sheet
   before commit.
3. **Store into the note.** Thread `body` through `commitComplementSuggestion` → `addComplementItem` into
   `MenuItem.notes`. Keep the `.note` coercion and the no-`recipeID` invariant ([[menu-item-recipe-id-invariant]]).

**Acceptance:** a complement suggestion with ingredient detail commits a `.note` menu item whose body
(rendered by `displayNotes`) contains the ingredients; editing the body in review before commit persists
the edit; a body-less suggestion still commits cleanly (nil note). Core test for parse + edit round-trip.

## SLICE C — prep-plan empty result explains itself (keep the contract strict)

Build Prep Plan pointed at chat prose returns `{"steps":[]}` and the user sees the **generic** "The
assistant did not return anything to review" (`run(_:)`, ~412). That is *correct* behavior — the verb
composes from **stored per-recipe make-ahead fields**, not from chat prose ("Do not invent or rewrite
per-dish make-ahead prose", `MenuPrepPlan.swift` instructions) — but the message hides the *why*. **Keep
the contract; explain better** (Jon's call, 2026-07-09).

1. **Per-action empty message.** Let an apply-action supply a **custom empty-result message** used when
   `extract` returns nothing, instead of the one generic string in `run(_:)`. Default stays the current
   generic text.
2. **Prep-plan's message points at the source.** The prep-plan action's empty message explains it builds
   the plan from each recipe's **Make-Ahead** field and there was nothing to compose — e.g. *"No prep
   steps to build. The prep plan is assembled from each recipe's Make-Ahead notes — add Make-Ahead detail
   to the dishes, or ask in chat for a specific step to add."* (Copy is Jon's to finalize.)

**Acceptance:** Build Prep Plan on a menu with no Make-Ahead detail shows the specific message naming
Make-Ahead as the source; other verbs' empty results are unchanged.

**Explicitly out (parked):** *loosening* the prep-plan verb to compose steps from chat prose was
considered and rejected this pass (invention risk) — do not change the prompt contract.

## SLICE D — rename an existing variation (missing affordance)

A variation's `name` is set once at creation (`keepAdjustmentProposalAsVariation(name:)`, ~469); there is
`setActiveVariation` but **no rename** and no UI, so a badly-named variation is stuck.

1. **Repository rename.** Add `RecipeRepository.renameVariation(_ id:to:in:now:)` (mirrors the
   `setActiveVariation` shape) updating `RecipeVariation.name` + `dateModified`. Sync-safe (existing
   `recipeVariations` table).
2. **Model + UI.** Add `RecipeDetailModel.renameVariation(_:to:)` and a rename affordance next to the
   variation picker (`variationPicker`, RecipeDetailView.swift ~383) — e.g. a rename button/context action
   that presents a small text-field alert seeded with the current name, committing on save.

**Acceptance:** an existing variation can be renamed from the recipe detail; the new name shows in the
picker and the active-variation label; the change persists and syncs. Core test for `renameVariation`.

---

## Parked for ADR discussion (not in this dispatch)

Two design questions from the same pass are **not** quick fixes and feed existing ADR threads — logged in
`docs/open-questions.md`, decided with Jon before any build:

- **Multi-bubble / whole-transcript selection.** Today selection can't cross bubbles (per-bubble
  `UITextView`). Selecting across the transcript needs a single-text-view render or a "select messages"
  mode — a rework, not a tweak.
- **Hand-editing a variation (define a header / edit content).** Variations are LLM-created then shown
  read-only; there is no manual editing of variation content, so "add a header to a variation" has no home.
  Lands on the open **[ADR-0014](../decisions/ADR-0014-recipe-text-editing-model.md)** (header/text-editing
  model) × **[ADR-0021](../decisions/ADR-0021-recipe-variations.md)** (variations as named deltas).
