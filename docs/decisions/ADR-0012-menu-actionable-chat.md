# ADR-0012 — Menu actionable chat: composite-subject verbs + staged prep plan

Status: **Proposed** — SKELETON (drafted 2026-07-03 as the seed for a design session; sections
below marked **OPEN** are the decisions to resolve *with Jon* before this goes Accepted). Extends
**ADR-0011** (actionable chat, the recipe-scope instance) to a **composite subject**. Binds
jon-platform `docs/ios/actionable-chat.md`. The named "Menu + Meal-Planner chat verbs" later effort
in `docs/efforts/cooking-workspace.md`. Do **not** dispatch to Codex off this skeleton — it is
half-formed by design.

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
   ADR-0011 already produces, not re-derive them. (OPEN: exact summary shape + budget.)
2. **Temporal aggregation.** The prep plan is *scheduling* ("2 days out… morning of…"). This is
   the part that most wants a structured type so the UI can render a timeline/checklist and so the
   plan survives editing.

### What already exists in this repo (verify at session start; do not trust this list blind)

- **`Menu` (+ `MenuItem`, `menuID` FK)** — a **dateless** curated grouping of dishes. No AI/plan
  field today.
- **`MealPlanItem`** — the **date/slot** planner (`scheduledDate`, `mealSlot`
  breakfast/lunch/dinner, `kind` recipe/note/reservation). A *different* surface.
- `RecipeChatWorkspace` / `ChatWorkspaceSplit` — context-general split host (see above).
- The review-before-commit staging card (cooking-workspace Slice B) — already stages
  `extract → review → commit`, so the "tap writes" invariant is free to reuse.

### Two surfaces, likely two efforts

"Menu + Meal-Planner chat verbs" spans **`Menu`** (dateless — home for the prep plan + menu
critique) and **`MealPlanItem`** (day/slot — home for "what complements this *day*"). **Proposed
scope: `Menu` first; the planner-day version is a follow-on** that reuses the same context
protocol with a date dimension added. (OPEN — confirm with Jon.)

## Decision (OPEN — this is the skeleton to fill)

Deliver menu actionable chat as another consumer of the ADR-0011 mechanism: a `MenuChatContext`
+ a menu apply-action catalog, hosted in the existing split. Verbs classified by **commit shape
first** (per the `chat-verb-commit-shapes` rule — shoehorning every verb into one-field-per-verb
corrupts the model and the UI):

| Verb | Commit shape | Target | Status |
|---|---|---|---|
| **Staged pre-prep plan** | structured staged list `{when, task, sourceDish}` **or** plain TEXT blob | new `Menu.prepPlan` column | **OPEN: blob vs structured** |
| **"What would complement…"** | list / inline cards (Serve-With motion at menu scale) | adds a `MenuItem`/`MealPlanItem` **or** advisory-only | **OPEN: commit vs advise** |
| **"What's conceptually wrong"** | **no-commit** — grounded conversation, not an apply-action | — | Leaning: *not a verb* |

### Open decisions to resolve with Jon

1. **Prep-plan shape — blob vs structured.** Plain TEXT mirrors make-ahead exactly and ships fast;
   a structured `{when, task, sourceDish}` timeline is more work but *is* where the value lives
   (sequencing + checklist + survives edits). Draft lean: **structured** — weigh explicitly.
2. **"Complement" verb — commit a dish or just advise?** If it commits, it writes a `MenuItem`
   (Menu scope) / `MealPlanItem` (planner scope); if advisory, it's chat with no write.
3. **Scope — Menu-only vs Menu + Planner** in this ADR.
4. **How much per-recipe make-ahead to fold** into the menu plan, and the composite grounding
   budget (Context problem #1).
5. **Critique as a verb or as plain chat.** Draft lean: **plain chat** — seed the chat with the
   full menu and "what's wrong here" is answered conversationally; verbs are only for commits.

## Consequences / boundaries (draft — confirm)

- **Storage:** any new column (`Menu.prepPlan`, …) is **additive-nullable, sync-safe**, following
  the ADR-0010 / make-ahead / serveWith playbook (BLOB → CKAsset if structured, per
  `sqlitedata-blob-cloudkit-asset`).
- **Snapshot staleness:** a stored plan is a **passive snapshot** — if a dish changes or leaves the
  menu, the plan goes stale. **Do not live-link.** Passive text/data + a **"regenerate"**
  affordance, same posture as reference/original provenance (ADR-0010).
- **Invariant preserved:** model proposes/structures; **the tap writes.** No chat turn mutates the
  menu on its own; commits route through the existing review card.
- **Reuse, not rebuild:** the LLMClientKit stack, the split host, and the staging card are done.
  This ADR adds a context + catalog + one-to-three verbs, not new infrastructure.

## Proposed slice sketch (non-binding — for the design session)

- **S1** — `MenuChatContext` + wire the existing split into the Menu screen with grounded plain
  chat, **no commit verb**. Proves composite grounding cheaply; critique works immediately as chat.
- **S2** — the menu **prep-plan** verb → `Menu.prepPlan`, own section + regenerate/clear. Flagship.
- **S3** — the **complement** suggestion verb (cards; commit-vs-advise per decision #2).
- Planner-**day** version → separate later effort.

## Related

- ADR-0011 (the recipe-scope parent), ADR-0010 (sync/BLOB playbook), ADR-0006 (vocabulary hygiene).
- jon-platform `docs/ios/actionable-chat.md`; galavant ADR-0031 (the cross-app home).
- Memory: `actionable-chat-effort` (parent, complete), `chat-verb-commit-shapes`,
  `grocery-pantry-threshold-design` (an example of a design that stayed dialog-free).
