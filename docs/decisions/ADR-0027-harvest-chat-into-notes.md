# ADR-0027 — Harvest chat into notes: a capture verb (extraction, not generation), selection-scoped

> **Vocabulary:** a **harvest verb** takes content **already present in the chat** — a user's text
> selection in an assistant bubble, or, absent one, the transcript itself — and commits it as **one or
> more distinct notes** on the current subject. The model **segments and lightly tidies** (a title + a
> body); it **never invents** content not in the source. This is the opposite operation to the
> **complement family** (`MenuComplement` / `MealPlanComplement`), whose whole job is to *generate new*
> dishes. Proven here on the **menu** (the surface Jon hit); the recipe / meal-plan / workbench instances
> are named siblings, not this ADR.

Status: **Accepted** — 2026-07-10 (Jon ratified same day; proposed 2026-07-10, dogfood pass 2026-07-10,
menu-planner). Verb name is **"Capture to menu"** (OQ5). All open questions resolved below except OQ4
(taste preference), deliberately deferred. **Extends
[ADR-0012](ADR-0012-menu-actionable-chat.md)** (menu actionable chat — same `MenuItem`-`.note` commit
target, ADR-0012 Amendment 2) and **[ADR-0011](ADR-0011-actionable-chat-make-ahead.md)** (the
`(extract → review → commit)` apply-action contract). **Rides [ADR-0026](ADR-0026-review-collection-sheet.md)**
(the collection sheet — this is a list commit shape). **Sibling to [ADR-0025](ADR-0025-reader-comment-ingestion.md)**
(the other harvest→curate→distinct-notes flow; there the source is the NYT comment thread, here it is the
chat transcript — same output shape, different well). Holds **[[llm-curation-not-synthesis]]** and
**[[llm-vs-determinism-surface-boundary]]** (advisory, reviewed-before-commit; the selection path is
near-deterministic). A consumer of the **[[chat-verb-commit-shapes]]** axis (list commit). Honors
**[[menu-item-recipe-id-invariant]]** — captured note-recipes are always `.note`, no `recipeID`. Additive
in-memory payload only — **no schema change**, sync-safe ([ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

Dogfooding the menu chat 2026-07-10, Jon was looking at a menu. The assistant had, in an earlier reply,
described a specific cauliflower dish (ingredients, spicing, method). Jon wanted exactly that dish kept as
a **note on the menu** — so he highlighted the cauliflower paragraph and tapped **"What complements
this?"**. The logging showed the whole menu context *and* the whole transcript going up, and the model
returned **two new dish suggestions**. Nothing captured the thing he had highlighted.

That is the **complement verb behaving correctly for what it is.** `MenuComplement` is a **generative**
verb: `applyActionCatalog` (`MenuModels.swift:462`) wires its `extract: { selection, messages in … }` to a
client that takes the selection *plus* the full transcript *plus* the serialized menu `context` and
**synthesizes new complementary dishes** (`MenuComplementSuggestion`s). Given a selection, it treats it as
one more thing to riff on, not as content to preserve. Wrong verb for the intent, not a bug.

### Key finding: the selection plumbing already exists — only the verb is missing

The infrastructure Jon's intent needs is **already built**:

- `ChatAssistantSelection` (`RecipeChatWorkspace.swift`) captures highlighted assistant-bubble text into a
  shared, ownership-tracked selection store.
- `actionSubject(for:)` (`RecipeChatWorkspace.swift:485`) **already prioritizes** a `.selection` subject
  over the fallback `.latestReply` — so Jon's highlight *did* reach the verb as a `ChatActionSubject`.
- The apply-action contract already passes `(selection, messages)` into every `extract` closure
  (`ChatApplyAction`, `YesChefCore/RecipeChat.swift`).

So the gap is **not** plumbing and **not** a new selection surface. It is a verb whose job is to **keep the
subject** rather than generate from it.

### The one axis that matters: generate vs. harvest

Every existing menu/recipe verb (complement, chef-it-up, substitution, prep-plan) is **generative** — the
model produces new material. Jon's ask is the **inverse**: the cauliflower dish already exists in the
transcript; he wants to **capture** it, not manufacture more. That is extraction, not synthesis — the same
family as ADR-0025's comment harvest, only the source is the conversation instead of a reader thread. A
flag on `MenuComplement` cannot express this: the two verbs differ in their fundamental relationship to the
content (invent vs. preserve), and they have different output shapes and different prompts. It is a new
verb.

## Decisions

### D1 — A new **"Capture to menu"** harvest verb, distinct from the complement family

Add a harvest apply-action to the menu catalog. Its contract is **extraction**: the model may **segment**
the source into distinct note candidates and **lightly tidy** each (a title + a body drawn from the
source), and it **may not invent** content absent from the source. The output shape is a **JSON array of
`{title, body}`** note candidates — the [[llm-curation-not-synthesis]] guardrail enforced at the
*output-shape* level (a model can ignore "don't invent"; it can't easily emit dishes that aren't there when
the contract is "return one item per distinct thing already present"). One accepted candidate is common;
several is allowed (a highlighted range, or a transcript, may hold more than one keepable dish).

### D2 — Selection scopes the source; absence broadens it (and the menu is a target, never a source)

- **Selection present → the source is the selection alone.** Do **not** send the serialized menu context.
  The menu is the **write target**, not source material — sending it is exactly the surprise Jon saw ("it
  sent the whole menu"). **The LLM still runs on the selection** (OQ2, resolved): even a highlighted range
  needs the model to (a) decide whether it holds **one dish or several** and (b) reshape still-rambling chat
  prose into a **clean, recipe-looking note** (a title + a tidy body). This is real work, not a passthrough —
  but cost-of-error stays trivial (a note reviewed before commit), so it remains the advisory side of
  [[llm-vs-determinism-surface-boundary]].
- **No selection → the source is the transcript** (assistant messages). The model scans for distinct,
  note-worthy dishes/tips and proposes candidates. This is where curation matters: **precision over
  recall, empty list is a valid answer** (same bar as ADR-0025 D3).
- **Menu context is advisory at most, never the source.** Its only defensible use is a dedup hint ("don't
  propose a note for a dish already on the menu"). *Lean:* omit it entirely in S1; add the hint only if
  duplicate proposals prove noisy.

### D3 — Commit target is a `MenuItem` note, always `.note` kind

Each accepted candidate becomes its **own `MenuItem` note** (title + body), the identical write target
`MenuComplement` uses for its per-dish body (ADR-0012 Amendment 2). A captured note-recipe is **always a
`.note`** — it carries **no `recipeID`** because it is not a recipe yet — which sidesteps
[[menu-item-recipe-id-invariant]] cleanly and for free (the invariant only bites recipe-kind rows).

### D4 — Rides the ADR-0026 collection sheet; no new review UI

This is a **list commit shape**, so its candidates surface through the universal ADR-0026 review-collection
sheet: keep / edit / discard per item, N=1 auto-drills to the editable review, the sheet stays open on the
remainder. Reuse it unchanged.

### D5 — Promotion to a real recipe is a separate, downstream step (out of scope)

The harvest verb makes **the note**. Turning that note into a real recipe ("Create a recipe from this
note") is a **later, separate action** — it touches recipe placement and original-provenance
([[reference-placement-and-original-provenance]]) and must not be folded in here. Jon flagged this
distinction explicitly; honor it. Harvest → note; promote → recipe. Two steps.

### D6 — Scope is the menu; recipe / meal-plan / workbench are named siblings

Prove the verb on the **menu**, where Jon hit it. The verb *concept* and the selection machinery are
shared (`RecipeChatWorkspace`), but the **commit target is per-surface** (a `RecipeNote` on a recipe, a
`MealPlanItem` note on the planner), mirroring how complement already has both `MenuComplement` and
`MealPlanComplement`. The **recipe** instance (capture a chat tip into a `RecipeNote`) is the obvious next
sibling — a named follow-on, not this ADR.

## Storage sketch (sync-safe by construction)

**None.** A new in-memory payload (`[HarvestedNote { title, body }]`) and a new apply-action; commit writes
**existing** `MenuItem` note rows through the path complement already uses. No new table, no new column, no
enum case, nothing new for `SyncEngine`. The transient selection/transcript source is device-local; only
the **accepted** notes persist.

## Cost, honestly — and the slice plan

The verb is cheap because three of its four pieces already exist: the selection subject (built), the
`MenuItem`-note commit target (built, ADR-0012 Amd2), and the review surface (ADR-0026). What is genuinely
new is one payload type, one **extraction** prompt/client, and the catalog wiring.

- **Prerequisite [ADR-0026](ADR-0026-review-collection-sheet.md) S1 (the collection sheet) is already
  merged** ([#138](https://github.com/jonphillips/yes-chef/pull/138), `RecipeCollectionReviewSheet`).
  Harvest is a multi-item verb and rides that sheet directly — no sequencing hold, unblocked now.
- **S1 — the harvest verb on the menu.** A `MenuNoteHarvestPlan` payload (`[HarvestedNote]`), a new client
  with the segment-don't-invent prompt (selection-scoped per D2, LLM always runs per OQ2), and a new
  `ChatApplyAction` in `MenuModels.applyActionCatalog` whose `commit` writes `MenuItem` notes. **Prove the
  selection path first** (the exact thing Jon hit: highlight → one note), then the no-selection
  transcript-scan path.
- **S2 (deferred) — the recipe sibling.** Same verb, `RecipeNote` commit target. Do only if S1's shape
  subsumes it cleanly.

## Open questions

Resolved with Jon 2026-07-10 (confirm-don't-re-litigate notes for the build), except OQ4 (deferred, on
record).

- **OQ1 — note placement on the menu. → Resolved (the lean).** A captured note-recipe drops into the
  **currently-viewed day / an unslotted parking spot**; Jon moves it. Do **not** ask the LLM to invent
  placement for a dish he is merely capturing (that was the complement verb's mistake).
- **OQ2 — selection path: LLM or no-LLM? → Resolved: LLM, always.** No no-LLM fast path. Even an exact
  selection routes through the model, which does two jobs the raw text can't: **detect one-vs-many items**
  in the highlighted range, and **reshape rambling chat prose into a recipe-looking note** (title + tidy
  body). See D2.
- **OQ3 — single-bubble selection limit. → Understood, no change.** `ChatAssistantSelection` cannot span
  bubbles (a parked question, per its own code comment). Jon's cauliflower dish sat in **one** bubble, so
  S1's selection path is unblocked; the no-selection transcript-scan path covers the multi-bubble case
  anyway. Cross-bubble selection stays parked (the multi-bubble fork in [[menu-planner-dogfood-2026-07-09]]).
- **OQ4 — a taste preference (ADR-0018)? → Deferred (on record).** "What counts as note-worthy" in the
  transcript-scan path could later be an `AIPromptPreferenceKind`. **Not** in scope: the guardrail (segment,
  don't invent) stays code; ship without a preference, add one only if the scan needs tuning.
- **OQ5 — verb name. → Resolved: "Capture to menu."** Note the grammar shift from the complement verb (a
  *question*, "What complements this?") to an *imperative capture*.

## Related

- ADR-0012 (menu actionable chat — the `MenuItem`-note commit target), ADR-0011 (the apply-action
  contract), ADR-0026 (the collection sheet — this verb's review surface), ADR-0025 (the sibling
  harvest→notes flow; NYT-thread source vs. chat source), ADR-0023 / ADR-0021 (promote-to-recipe /
  variations — the *out-of-scope* downstream step).
- Memory: [[chat-verb-commit-shapes]], [[llm-curation-not-synthesis]], [[llm-vs-determinism-surface-boundary]],
  [[menu-item-recipe-id-invariant]], [[reference-placement-and-original-provenance]],
  [[menu-planner-dogfood-2026-07-09]].
