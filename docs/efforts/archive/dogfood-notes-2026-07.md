# Dogfood notes, July 2026 — parked notes

**Status:** Parked 2026-10-30, moved from `open-questions.md` as written (jon-platform ADR-0005 D14).
**Summary:** Findings from the 2026-07-02/03 and 07-09 passes: ingredient authoring, the chat and reader, the menu planner. Some have shipped since, so check DONE-LOG.md before acting on one.

Restore the part you schedule to a brief in `docs/efforts/`, in the plan PR that schedules it.

## Recipe ingredient authoring — formatting fidelity (dogfood, 2026-07-02)

Jon, first dogfooding pass: ingredient entry has **no formatting flexibility**. Section
headers automatically get bullet points too; there's no bold/italic; and pasting a
formatted ingredient list from ChatGPT loses its structure. Open design fork — pick a
direction before anyone builds:

- **Markdown-authored ingredients?** Let the ingredient/notes fields accept Markdown and
  render it — cheapest, but collides with the structured `IngredientLine`/`IngredientSection`
  model (headers are already a first-class concept; bullets are applied by the renderer, which
  is why headers wrongly get one).
- **A tiny inline formatter** (bold/italic, and a "this line is a header, not an item" toggle)
  over the existing structured model — keeps structure, adds emphasis, fixes the header-gets-a-
  bullet bug directly.
- **Smart paste** — when text is pasted (esp. from ChatGPT), detect and preserve its
  structure (headers vs. items vs. emphasis) into the structured model rather than flattening.
  Overlaps the parser / canonical-ingredient work but is an *authoring* concern, not a
  shopping-merge one — keep them separate.

The immediate, uncontroversial sub-bug (headers rendering with a bullet) may be worth pulling
out as a small fix even before the larger direction is chosen. Not in the current arc; needs a
decision first.

## Dogfooding — AI chat + recipe reader (2026-07-03)

First dogfooding pass over the shipped make-ahead chat (PR #68) and the recipe reader (screenshots:
full-screen Paprika as the density reference; Yes Chef full-screen "Done" view). Six items, sorted
bug → cheap → effort. **Sequencing decision (Jon, 2026-07-03):** the dense reader and the slide-in
chat are **one unified "cooking workspace" effort**, not separate slices — they both rewrite how
`RecipeDetailView` presents, so design them together (needs a layout sketch before dispatch).

- **[Bug] Scale multiplier falls off the bottom in full-screen.** The scale control lives in the
  `Menu` ("Scale Ingredients", `RecipeDetailView.swift` `ScalePanel`, ~line 674) anchored bottom-
  right; in the full-screen presentation it clips below the viewport and becomes unusable. Small
  Codex fix — folds into a dogfood batch, no design needed.

- **[Cheap — backend already exists] Provider picker: Claude *or* ChatGPT, both keys in Settings.**
  Galavant has this. The Slice 1 lift already gave us `OpenAIModelClient`/`OpenAIWire` and a
  multi-provider `APIKeyStore` in LLMClientKit — `AISettingsView` only *surfaces* `.anthropic` today
  (`AISettingsView.swift:58`). So this is: add an OpenAI key field + a stored per-conversation
  provider preference that `RecipeChatModel`'s frontier tier reads. No new backend; mirror Galavant's
  UI. Dispatch-ready alongside the multiplier bug as **dogfood batch 2**.

- **[Effort — the cooking workspace, unified] Dense reader + chat inspector on one draggable split,
  used simultaneously.** Design converged with Jon 2026-07-03 (sketches in chat). Three coupled wants,
  plus the resolved presentation model below.
  1. *Dense cooking reader.* When actually cooking, Jon wants Paprika's information-density
     (everything visible/scannable, photo displayed smaller) — not the current photo-forward reader.
     The deliverable is **density**: tight ingredient/step layout, scale always reachable, no wasted
     vertical space.
  2. *Chat as a side inspector worked **alongside** the recipe, never modal, never full-screen.* Chat
     is `.sheet(item:)` today (`RecipeDetailView.swift:98`) — modal, so you can't touch the recipe
     underneath. The reader must stay visible for the whole interaction, or it's "chatting about a
     recipe" rather than "cooking with an assistant."
  3. *"Start Cooking" is deliberately **not** the primary affordance (design principle, bank it).*
     Jon: "no one actually cooks with blinders on" — you look ahead, re-check ingredients, think two
     steps out. Step-by-step is at most a secondary mode; the reader is a dense *reference* surface,
     not a wizard.

  **Resolved design decisions (2026-07-03):**
  - **Scale control → toolbar** (pinned, always reachable). This is the *structural* fix for the
     full-screen clip bug; batch 2's fix is only tactical.
  - **Reader is width-responsive, not device-responsive.** Two-column (ingredients | directions) in
     **both** iPad orientations; below a width threshold it flips to the **iPhone layout — a
     Paprika-style segmented ingredients/directions toggle** (Jon confirms Paprika's segmented control
     is acceptable on iPhone). Keying the layout off *current width* (not device class) is what makes
     the draggable split cheap — the narrow layout already has to exist for iPhone.
  - **Detented draggable split (Jon's idea, 2026-07-03), not two modes.** A draggable grabber (the
     divider) snaps to detents — *balanced* (default) / *chat-dive* (chat wide, reader collapsed to the
     segmented compact layout so its content stays usable) / *reader-only* (chat closed, reader
     full-width). This dissolves the earlier inspector-vs-focus-mode fork into one continuous control.
     **Discipline: snap-to-detents, not free continuous resize** — free-drag split panes aren't an iOS
     idiom; detents share the sheet-`presentationDetents` muscle. Persist the last detent. **iPad only**
     (landscape + portrait); iPhone has no room to split, so there chat is a separate push/sheet and the
     reader is its normal segmented self. Needs a **visible grabber** (discoverability) and a **VoiceOver
     alternative** that cycles detents (a custom divider isn't self-evident to assistive tech).
  - **Provider picker lives in the chat header** ("Claude ▾"), per-conversation, one tap — richer than
     batch 2 strictly needs (batch 2 only adds the keys + a stored preference); this surfaces it in the
     workspace.
  - **The apply-action "control center" is inspector-resident, not a separate screen.** Selection arms a
     compact action bar; tapping an action stages the extracted result as a **transient review card**
     in the inspector (Commit / Discard) — the one surface that may borrow extra room (grow taller / pop
     as a popover over the reader) because it's momentary. **The commit lands in the reader on the left**,
     in place. The tap on Commit is the only write (ADR-0011 invariant + Amendment 1 selection-scoping).

  **Spec'd:** [`docs/efforts/archive/cooking-workspace.md`](../../efforts/archive/cooking-workspace.md) (Slice A = split +
  width-responsive reader; Slice B = selection-scoped apply-actions). Starts after batch 2 merges;
  awaiting Jon's dispatch greenlight.

  **Same window on Menu + Meal Planner (Jon, 2026-07-03) — shapes the host now, built later.** Jon wants
  the chat window on a **Menu** ("full make-ahead plan for this menu", "what dish is this menu missing?",
  "good apps with this menu") and the **Meal Planner**. This is the forcing function for building the
  workspace host **context-general** (a `RecipeChatContext.menu(...)`/`.mealPlan(...)` case + a
  screen-supplied verb catalog), not welded into `RecipeDetailView`. The menu verbs map onto the two
  motions ADR-0011 already named: **cross-dish make-ahead** (distill → a menu-level commit target, a
  Menus-model decision) and **"missing dish"/"good apps"** (suggestion cards → one-tap add menu item —
  the second motion + second context). So the review surface is designed to stage a **list** of
  committable results (N=1 for recipe make-ahead today). Named/deferred as **separate efforts** in the
  cooking-workspace effort doc; not built in the recipe workspace slice.

- **[Effort — revises ADR-0011] Selection-scoped apply-actions.** See the drafted **Amendment 1** on
  [ADR-0011](../../decisions/ADR-0011-actionable-chat-make-ahead.md) (Proposed 2026-07-03, awaiting Jon).
  The shipped design feeds the *whole conversation* to `extract`; Jon's dogfooding insight is that
  models don't answer in discrete commit-able units (one reply may hold three side dishes), so the
  apply-action input should be a **highlighted text span** (conversation as context, selection as the
  payload) and the buttons react to what's selected. A genuine evolution of the actionable-chat
  invariant — Yes Chef is the proving ground that feeds jon-platform, so it's an ADR amendment, not a
  silent code change.

## Dogfooding — menu-planner pass (2026-07-09)

Source: `~/code/cooking/menu_planning_llm_questions_and_responses-1.md`. The mechanical fixes from this
pass are scoped in `docs/efforts/archive/dogfood-fixes-menu-planner-2026-07-09.md`; the review-area fix is
[ADR-0026](../../decisions/ADR-0026-review-collection-sheet.md). These two are the **design** residue — decide
with Jon before any build:

- **[Design — per-bubble selection constraint] Multi-bubble / whole-transcript selection.** Chat
  selection can't cross bubbles because each assistant message renders as an independent `UITextView`
  (`SelectableAssistantText`), so a verb's payload is capped at one bubble's worth of highlighted text.
  Jon confirmed the limit while dogfooding. Lifting it needs either the transcript rendered as a **single
  text view** or an explicit **"select messages" mode** (per-message checkboxes feeding a combined
  payload). A rework, not a tweak; interacts with the drafted ADR-0011 Amendment 1 (selection-scoped
  apply-actions) above.
- **[Design — feeds ADR-0014 × ADR-0021] Hand-editing a variation (define a header / edit content).**
  Variations are LLM-created (`keepAdjustmentProposalAsVariation`) then shown **read-only**; there is no
  manual editing of variation content, so "add a section header to a variation" has no home. A section
  header can only appear implicitly today, when an add-ingredient delta names a new section. Lands on the
  open [ADR-0014](../../decisions/ADR-0014-recipe-text-editing-model.md) (header/text-editing model) crossed
  with [ADR-0021](../../decisions/ADR-0021-recipe-variations.md) (variations as named deltas): does a variation
  become hand-editable, and does that reuse the recipe header-editing affordance? (Variation **rename** is
  *not* here — it is a scoped quick fix in the effort above.)
