# ADR-0012 — Menu actionable chat: composite-subject verbs + staged prep plan

Status: **Accepted** (2026-07-03, resolved in design session with Jon). Extends **ADR-0011**
(actionable chat, the recipe-scope instance) to a **composite subject**. Binds jon-platform
`docs/ios/actionable-chat.md`. Realizes the "Menu + Meal-Planner chat verbs" effort in
`docs/efforts/cooking-workspace.md`, **Menu surface only** — the Meal-Planner (`MealPlanItem`,
absolute-date) surface is a named follow-on, not this ADR.

## Context

ADR-0011 shipped actionable chat for a **single recipe** (make-ahead, Chef It Up, Serve With,
substitution — all live, PRs #73–#75). The invariant holds throughout: *the model proposes and
structures; the human's tap is the only write.* The chat host (`RecipeChatWorkspace` /
`ChatWorkspaceSplit`) was deliberately built **context-general** — it takes a chat context + a
`(model) -> [AnyChatApplyAction]` catalog closure and is not welded to `RecipeDetailView`,
explicitly so it could receive a menu instance later.

This ADR is that instance. The mission (Jon, 2026-07-03): an AI chat over a **menu** that can

- develop a large **staged pre-prep plan** across all the menu's dishes, **stored on the menu**;
- **advise** — what would complement a given day, and what is conceptually "wrong" with a menu.

### The one genuinely new axis: a composite subject

Every ADR-0011 verb acts on a single recipe document. Menu verbs reason across **N dishes at
once**. That is the whole novelty, and it concentrates in two hard problems:

1. **Grounding a composite within a token budget.** Do *not* feed full text of every recipe.
   Feed structured summaries — titles, key ingredients, prep/cook times, and **each recipe's
   existing make-ahead note**. The menu prep-plan should *compose* the per-recipe make-aheads
   ADR-0011 already produces, not re-derive them. (Resolved — see Decision #4 below.)
2. **Temporal aggregation.** The prep plan is *scheduling* ("2 days out… morning of…"). This is
   the part that most wants a structured type so the UI can render a timeline/checklist and so the
   plan survives editing. (Resolved — structured; Decision #1.)

### What already exists in this repo (verified at session start — corrections in **bold**)

- **`Menu` (+ `MenuItem`, `menuID` FK)** — a curated grouping. **Correction to the skeleton's
  framing: a menu is NOT dateless.** `Menu.dayCount` plus `MenuItem.dayOffset` + `MenuItem.mealSlot`
  make it a **relative-day** structure — multi-day, meal-slotted, but with no *absolute calendar
  date*. This gives the prep plan a temporal spine to anchor to ("morning of day 2") without
  inventing a date type, and it means "what complements this *day*" is expressible at Menu scope via
  `dayOffset`. What the Planner adds later is the *absolute* date, not the day concept itself. No
  AI/plan field on `Menu` today.
- **`MealPlanItem`** — the **absolute date/slot** planner (`scheduledDate`, `mealSlot`,
  `kind` recipe/note/reservation). A *different* surface; the follow-on effort.
- **Storage precedent for both plan shapes already exists on `Recipe`:** `makeAhead: String?`
  (plain text) and `serveWith: Data?` (a structured Codable BLOB of `ServeWithItem`). A structured
  `Menu.prepPlan` is therefore the *serveWith* pattern, **not new infrastructure**.
- **`RecipeChatContext` is an enum** (`case recipe(RecipeChatRecipeContext)`). The menu instance is
  a new **`case menu(...)`** + a menu apply-action catalog — an additive case, per the
  context-general host design.
- The review-before-commit staging card (cooking-workspace Slice B) already stages
  `extract → review → commit`, so the "tap writes" invariant is reused for free.

## Decision

Deliver menu actionable chat as another consumer of the ADR-0011 mechanism: a `.menu(...)` case on
`RecipeChatContext` + a menu apply-action catalog, hosted in the existing split. Verbs classified by
**commit shape first** (per the `chat-verb-commit-shapes` rule — shoehorning every verb into
one-field-per-verb corrupts the model and the UI):

| Verb | Commit shape | Target | Resolution |
|---|---|---|---|
| **Staged pre-prep plan** | structured staged list `[PrepPlanStep{when, task, sourceDish}]` | new `Menu.prepPlan: Data?` (Codable BLOB, serveWith pattern) | **Structured** (D#1) |
| **"What would complement…"** | suggestion cards → tap inserts a `MenuItem` | new `MenuItem` on this menu | **Commits** (D#2) |
| **"What's conceptually wrong"** | **no-commit** — grounded conversation, not an apply-action | — | **Plain chat** (D#5) |

### Resolved decisions (design session, Jon, 2026-07-03)

1. **Prep-plan shape → structured.** `Menu.prepPlan: Data?`, a Codable BLOB of
   `PrepPlanStep { when: String; task: String; sourceDish: MenuItem.ID? }`. `when` stays a **String**
   (e.g. "2 days out", "morning of day 2") rather than a date type — the menu is relative-day, and a
   free-text temporal label keeps phrasing natural while still being a discrete, per-step field the
   UI can render as a timeline/checklist and that survives editing. `sourceDish` is an optional
   `MenuItem.ID` back-pointer for provenance/regeneration (nullable — a step may span dishes). This
   is the `serveWith` storage pattern; no new infrastructure.
2. **"Complement" verb → commits a `MenuItem`.** Serve-With motion at menu scale: the model proposes
   dishes, the tap inserts a `MenuItem` (`kind`, `title`, `dayOffset`, `mealSlot`) onto this menu via
   the existing review card. Advisory-only was rejected because it is indistinguishable from the S1
   grounded chat — a verb earns its name only by writing.
3. **Scope → Menu-only in this ADR.** The Planner-day version ("what complements *this Tuesday*",
   which needs `MealPlanItem`'s absolute `scheduledDate`) is a **separate follow-on effort** that
   reuses this same `.menu`-shaped context protocol with a date dimension added. Not in scope here.
4. **Composite grounding (Context problem #1) → compose per-recipe summaries, don't re-derive.**
   Feed the model one **structured summary per `MenuItem`**: title, key ingredients (capped),
   prep/cook/total times, `dayOffset` + `mealSlot`, and the recipe's **existing `makeAhead` note
   verbatim** when present. The prep-plan verb *composes and sequences* those existing make-aheads;
   it must not re-generate per-dish make-ahead prose. **Budget guardrail:** summaries only (never
   full instruction/ingredient bodies); if a menu is large enough to blow the budget, truncate the
   ingredient list per dish first, then drop lowest-`sortOrder` dishes last — never silently send a
   partial menu without noting the truncation in the seeded context.
5. **Critique ("what's wrong") → plain chat, not a verb.** S1 seeds the chat with the full composite
   context, so "what's conceptually wrong here" is answered conversationally for free. Verbs are
   reserved for commits; a critique has no coherent commit target, so it stays chat.

## Consequences / boundaries

- **Storage:** `Menu.prepPlan: Data?` is **additive-nullable, sync-safe**, following the ADR-0010 /
  make-ahead / serveWith playbook. As a BLOB it syncs as a CKAsset unconditionally per
  `sqlitedata-blob-cloudkit-asset` — no schema change beyond the additive column, no reserved
  columns, no unique index. Committed `MenuItem`s are ordinary rows, already sync-safe.
- **Snapshot staleness:** a stored prep plan is a **passive snapshot**. If a dish changes or leaves
  the menu, the plan goes stale — the `sourceDish` back-pointer makes staleness *detectable* but the
  plan is **not live-linked**. Passive data + a **"regenerate"** and **"clear"** affordance, same
  posture as reference/original provenance (ADR-0010). Do not auto-recompute on menu edits.
- **Invariant preserved:** model proposes/structures; **the tap writes.** No chat turn mutates the
  menu on its own; both the prep-plan write and every complement insert route through the existing
  review card.
- **Reuse, not rebuild:** the LLMClientKit stack, the split host, and the staging card are done.
  This ADR adds one context case + a catalog + two commit verbs (prep plan, complement), not new
  infrastructure. Critique is zero new surface.
- **Vocabulary hygiene (ADR-0006):** "prep plan" is the menu-scope term; it *composes* recipe-scope
  "make-ahead" and must not be conflated with it in UI copy or code identifiers.

## Slice plan

- **S1 — `.menu` context + grounded plain chat, no commit verb.** Add `case menu(MenuChatContext)`
  to `RecipeChatContext`, build the composite summary serialization (Decision #4), wire the existing
  split into the Menu screen. Proves composite grounding cheaply; **critique works immediately** as
  chat (Decision #5). No schema change.
- **S2 — the menu prep-plan verb → `Menu.prepPlan`.** Additive `Data?` column, `PrepPlanStep`
  Codable type, apply-action + review card, its own menu section with timeline/checklist render and
  regenerate/clear. Flagship; composes existing make-aheads (Decision #1, #4).
- **S3 — the complement verb.** Suggestion cards → tap inserts a `MenuItem` (Decision #2).
- **Follow-on effort (separate ADR) — Planner-day version** over `MealPlanItem` with the absolute
  date dimension (Decision #3).

## Amendment 1 — Menu AI context: tier-aware budget, prep plan in-context, living-artifact refinement

Accepted 2026-07-05 (design session with Jon). Ships in the **menu planning overhaul** dispatch
(`docs/efforts/menu-planning-ux.md`), not the original slices. Three fixes to how the menu chat is
grounded, all in `MenuChatContext` (`RecipeChat.swift`) + the prep-plan flow:

- **A1 — The 12K character budget is tier-aware, not a flat cap.** `serializedCharacterBudget = 12_000`
  is our own arbitrary constant (characters, ~3K tokens) — **unrelated to any API limit**; gpt-5.5 takes
  1M tokens. It was sized for the *weakest tier* (on-device, small context), and that starvation is the
  real cause of "the AI only sees one dish": when verbatim make-ahead notes overflow 12K, the serializer
  **drops whole dishes from the end** until one survives. Fix: budget **by tier** — small for on-device,
  one-to-two orders larger for frontier (100K+ chars is still trivial vs 1M tokens) — and clip make-ahead
  notes to a per-dish share instead of verbatim-or-drop, so **every dish stays represented**.
- **A2 — The prep plan is in the context.** `MenuChatContext` today carries title/notes/dayCount/items
  but **not `menu.prepPlan`** — so when asked to refine the plan, the model can't see it. Add the rendered
  prep plan to the serialization. This is the single change that unblocks iterative refinement.
- **A3 — The prep plan is a living artifact, not a one-shot field.** With A2 in place, reframe
  "Regenerate": the chat **reads the current plan and proposes edits against it** (converse → propose →
  Apply commits), instead of re-deriving from scratch. Pairs with ADR-0017's `high`-effort `MenuPrepPlan`.

Invariant unchanged: the model proposes and structures; the human's tap is the only write.

## Related

- ADR-0011 (the recipe-scope parent), ADR-0010 (sync/BLOB playbook), ADR-0006 (vocabulary hygiene).
- jon-platform `docs/ios/actionable-chat.md`; galavant ADR-0031 (the cross-app home).
- Memory: `actionable-chat-effort` (parent, complete), `chat-verb-commit-shapes`,
  `grocery-pantry-threshold-design` (an example of a design that stayed dialog-free).
