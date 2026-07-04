# ADR-0013 — Meal-Planner actionable chat: day-scoped complement verb

Status: **Accepted** (2026-07-04, D1–D3 ratified by Jon; D4–D6 inherited from ADR-0012). Extends
**ADR-0011** (recipe-scope) and **ADR-0012** (menu-scope) to the
**absolute-date planner surface**. Binds jon-platform `docs/ios/actionable-chat.md`. This is the
Meal-Planner follow-on that ADR-0012 explicitly deferred as "a separate follow-on ADR" (ADR-0012
Decision #3).

## Context

Actionable chat now exists at two scopes, both live:

- **ADR-0011 — single recipe** (make-ahead, Chef It Up, Serve With, substitution; PRs #73–#75).
- **ADR-0012 — menu** (`.menu` context + grounded chat, prep-plan verb → `Menu.prepPlan`, complement
  verb → inserts a `MenuItem`; PRs #81–#83). The invariant holds throughout: *the model proposes and
  structures; the human's tap is the only write.*

The chat host (`RecipeChatWorkspace` / `ChatWorkspaceSplit`) was deliberately built
**context-general** — a chat context + a `(model) -> [AnyChatApplyAction]` catalog closure, not welded
to any one screen — explicitly so it could receive new surface instances. ADR-0012 was the menu
instance; this ADR is the **meal-planner** instance.

The mission: bring the **complement verb** to the meal planner — "what would go well with *this
Tuesday*" — where the tap inserts a `MealPlanItem` onto that day.

### The one genuinely new axis: an absolute calendar date

Every ADR-0012 verb reasoned over a **relative-day** structure (`Menu.dayCount` + `MenuItem.dayOffset`).
The planner's `MealPlanItem` carries an **absolute `scheduledDate`** (plus `startTime`/`endTime`). That
is the whole novelty, and it concentrates in three questions the menu pattern does not answer by
analogy — the three decisions that need Jon's sign-off (D1–D3).

### What already exists in this repo (verified at session start)

- **`MealPlanItem`** (`@Table("mealPlanItems")`) — `kind` (recipe/note/reservation), `recipeID?`,
  `title`, **`scheduledDate: Date`** (absolute), `mealSlot`, `notes`, `startTime?`/`endTime?`,
  `sortOrder`, timestamps, `scale`. **There is no parent `MealPlan` container table** — the planner is
  a flat set of dated items, not a container with a header row.
- **`MealCalendarModel`** (app) — holds **`selectedDate`** (`startOfDay`) + `selectedDateTitle`
  ("Tuesday, July 8") + `selectedDayRows`; `MealCalendarDayAgendaView` already renders exactly that
  day's items. This is the natural chat subject and host.
- **`MealCalendarRepository.addRecipeItem(on:mealSlot:...)`** and its note-add sibling already insert a
  `MealPlanItem` with `nextSortOrder(on:mealSlot:)` — the exact insert path the complement commit
  reuses (the `addComplementItem` analog of ADR-0012, but on `scheduledDate` instead of `dayOffset`).
- **`RecipeChatContext`** is an enum (`.recipe`, `.menu`). The planner instance is a new additive
  **`case mealPlan(MealPlanChatContext)`** + a planner apply-action catalog.
- The review-before-commit staging card and the multi-item `AnyChatApplyAction(_:reviewItems:)`
  erasure (added in ADR-0012 S3) already stage `extract → review → commit`, so the "tap writes"
  invariant and the per-item insert shape are reused for free.

## Decision

Deliver meal-planner actionable chat as another consumer of the ADR-0011/0012 mechanism: a
`.mealPlan(...)` case on `RecipeChatContext` + a planner apply-action catalog, hosted in the existing
split, scoped to the **selected day**. Verbs classified by **commit shape first**
([[chat-verb-commit-shapes]]):

| Verb | Commit shape | Target | Resolution |
|---|---|---|---|
| **"What would complement…"** | suggestion cards → tap inserts a `MealPlanItem` | new `MealPlanItem` on the selected day | **Commits** (D4) |
| **"What's conceptually wrong / what's missing"** | **no-commit** — grounded conversation | — | **Plain chat** (D5) |
| **Staged prep plan** | — | *no storage home* | **Out of scope** (D6) |

### Resolved decisions (D1–D3 ratified by Jon, 2026-07-04)

1. **Subject scope → the selected day.** The chat subject is the
   `MealCalendarModel.selectedDate` and its items — "what complements *this Tuesday*." This bounds the
   token budget naturally, matches the existing day-agenda UI, and is the literal phrasing of the
   mission. **Rejected alternatives:** whole-week (unbounded grounding, and the planner has no natural
   week container); the entire plan (unbounded). *If you'd rather the subject be a rolling window
   (e.g. selected day ± 1, or the visible week), say so — it changes the grounding serialization.*
2. **Insert date → fixed to the subject day; the model picks `mealSlot` only.** Every committed
   complement lands on the selected day's `scheduledDate`; the model
   proposes only `mealSlot` (breakfast/lunch/dinner/snack). This keeps calendar-date arithmetic **out
   of the LLM's hands** — no free-text date parsing, no "the night before" temporal ambiguity, no
   invalid-date review cards. **Rejected alternative:** let the model propose a relative date offset
   ("prep the night before") — reintroduces the temporal-parse complexity ADR-0012 deliberately
   avoided; defer to a later slice if it proves wanted.
3. **No planner prep-plan verb in this ADR.** ADR-0012's flagship prep-plan verb wrote to
   `Menu.prepPlan` — a column on the menu container. **The planner has no container table
   to store a plan on.** Giving the planner a staged prep plan therefore requires a *new storage-home
   decision* (a `MealPlan` header table, or a date-keyed plan store) that is out of scope here. This
   ADR ships the complement verb + grounded critique chat only; a planner prep plan is a possible
   later ADR if wanted.

### Decisions inherited from ADR-0012 (not re-opened)

4. **"Complement" verb → commits a `MealPlanItem`.** Serve-With motion at planner scale: the model
   proposes dishes, the tap inserts a `MealPlanItem` (`kind`, `title`, `scheduledDate`, `mealSlot`) via
   the existing review card. Per-item insert shape — one payload emits **multiple** review cards, one
   per proposed dish, each committing independently (the ADR-0012 S3 mechanism). **recipeID invariant
   ([[menu-item-recipe-id-invariant]]): coerce every suggestion to `.note`** — this write path cannot
   resolve a suggested title to a real `Recipe`, and a `.recipe`-kind row with a nil `recipeID` renders
   as a broken, non-navigable row. Parser collapses `.recipe`/`.reservation` → `.note`, exactly as the
   menu complement verb does.
5. **Critique → plain chat, not a verb.** With the day seeded into the chat, "what's conceptually
   wrong / what's missing on Tuesday" is answered conversationally for free. Verbs are reserved for
   commits; a critique has no coherent commit target, so it stays chat (ADR-0012 D5).
6. **Composite grounding → compose per-item summaries, don't re-derive.** Feed the model one
   structured summary per `MealPlanItem` on the selected day: the **absolute date rendered as
   weekday + date** ("Tuesday, July 8"), `mealSlot`, title, and — for recipe-kind items — key
   ingredients (capped), prep/cook/total times, and the recipe's existing `makeAhead` note verbatim.
   Same budget guardrail as ADR-0012 D4 (summaries only, never full bodies). Cheaper here — a single
   day is a small N.

## Consequences / boundaries

- **Storage: no schema change at all.** Committed `MealPlanItem`s are ordinary rows, already
  sync-safe. Unlike ADR-0012 (which added the `Menu.prepPlan` BLOB), this ADR touches no schema — the
  complement verb reuses the existing `MealPlanItem` insert path, and there is no prep-plan column
  (D6). Nothing to promote to the production schema.
- **Invariant preserved:** model proposes/structures; **the tap writes.** No chat turn mutates the
  plan on its own; every complement insert routes through the review card.
- **recipeID invariant:** enforced by coercion to `.note` (D4, [[menu-item-recipe-id-invariant]]) —
  the planner hits the same wall the menu did, and resolves it the same way.
- **Reuse, not rebuild:** LLMClientKit, the split host, the staging card, and the multi-item review
  erasure are all done. This ADR adds one context case + a catalog + one commit verb. Critique is zero
  new surface.
- **Vocabulary hygiene (ADR-0006):** the planner term stays "meal plan / planner"; "menu" is the
  other surface, and the two must not be conflated in copy or identifiers.

## Slice plan (post-ratification)

- **S1 — `.mealPlan` context + grounded plain chat, no commit verb.** Add
  `case mealPlan(MealPlanChatContext)` to `RecipeChatContext`, build the selected-day composite summary
  serialization (D6), host the existing split in `MealCalendarDayAgendaView` scoped to `selectedDate`.
  Proves day grounding cheaply; **critique works immediately** as chat (D5). No schema change.
- **S2 — the complement verb → inserts a `MealPlanItem`.** Suggestion cards → tap inserts onto the
  selected day (D4); coerce to `.note`; reuse the `MealCalendarRepository` insert path. No schema
  change.

Two slices, **zero schema touch** — leaner than ADR-0012. Lean verification is the default.

## Related

- ADR-0011 (recipe-scope parent), ADR-0012 (menu-scope sibling, the pattern this mirrors), ADR-0010
  (sync playbook), ADR-0006 (vocabulary hygiene).
- jon-platform `docs/ios/actionable-chat.md`; galavant ADR-0031 (cross-app home).
- Memory: `actionable-chat-effort`, `chat-verb-commit-shapes`, `menu-item-recipe-id-invariant`.
