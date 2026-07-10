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
(taste preference), deliberately deferred. **Amendment 1 (2026-07-10, ratified): a
[deposit sibling](#amendment-1--deposit-chat-intelligence-onto-the-item-you-point-at-recipe-append--note-revise)**
— write chat *intelligence* onto the **existing item you point at** (recipe → append to note body; note →
LLM revises in place). **No queue, no auto-Workbench** — durability is opt-in via a separate promote step.
Schema-free. **Extends
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

---

# Amendment 1 — Deposit chat intelligence onto the item you point at (recipe: append · note: revise)

> **Vocabulary:** a **deposit** takes intelligence **the model already produced in the chat** — usually
> advisory *reasoning* (a Compare verdict, a "here's how I'd change this" riff) — and writes it onto **the
> existing item you point at**, in the mode that item's canonical-ness demands:
> - **recipe → append.** The recipe is canonical/precious, so never rewrite it; add the intelligence to its
>   **note body** (a `recipeNote`). Record, don't transform.
> - **note → revise.** A menu note is disposable/non-canonical, so the LLM may **synthesize the intelligence
>   into the note's content**, rewriting it in place. This *is* a transform — and that is fine *only* because
>   a note is not precious. (Same reason Jon refuses to transform the recipe.)
>
> There is **no queue, no reminder inbox, no auto-Workbench, no graduation-to-candidate** — those were
> considered and cut (see A4). A note stays an **ephemeral menu note**; durability is **opt-in**, reached
> only by the separate, user-triggered **promote-to-recipe** step (out of scope, A6). Deposit is a sibling
> of the base capture verb (both write chat content onto a menu-surface item); the difference is base writes
> a **new** note, Amd-1 writes onto an **existing** one.

Status: **Accepted** — 2026-07-10 (Jon ratified same day, same menu-planner dogfood lineage as the base
ADR; converged across the same-day design thread from an auto-queue model to this explicit, queue-free one —
see A4 for the reversal). **Extends ADR-0027 base** (same harvest nature, same ADR-0011 apply-action
contract, same review-before-commit guardrails). **Schema-free** (like the base verb): the recipe path
writes an existing `recipeNote`; the note path rewrites the existing `menuItems.notes` column; nothing
touches `workbenchCandidates`. Nothing new for `SyncEngine` ([ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).
The note-revise path borrows the **editable-preview** pattern ([ADR-0024](ADR-0024-editable-proposal-preview.md))
so a rewrite is reviewed before it overwrites.

## Context

Same session, a **later** intent than the base verb. Jon had a menu, captured a "Roasted Chile-Lime
Cauliflower" **note** on it (via the base Capture verb), then added a "Charred Cauliflower Tacos" **recipe**
and ran **Compare** ("compare the recipe to the note"). The model returned a strong advisory verdict — use
the note as the base, skip the redundant romesco, steal the taco intent, push it toward the menu's Mexican
lane. **Good intelligence, produced in the moment, with nowhere to land.** Jon's instinct: *"Adjust the
note"* from that feedback — but there was no such verb and no way to point at the note.

The design thread that followed first reached for a durable **Workbench queue** — every deposit auto-copied
into a candidate so an idea could never be lost. Jon then cut it: *"If I want to make a note a real recipe, I
will trigger that wherever the note is. No weird workbench queue."* That collapses the model — the
"never lose the idea" guarantee is better served by an **explicit promotion**, not an auto-accumulating
inbox. What remains is a small, target-adaptive write. (The reversal is recorded in A4 so it is not
re-litigated.)

### The finding that still holds: the menu already makes items addressable

The menu tags **every** item (note and recipe) with its `MenuItem` UUID inside the serialized LLM context
(`MenuChatContext.swift:180`) and reads each item's notes **back** verbatim (`MenuChatContext.swift:200`).
So the model already reasons over an **addressable** item — the missing half is the *reverse channel*: Jon
pointing at that item and a result landing on it (A5).

The menu note's ephemerality (`menuItems` is inline + `ON DELETE CASCADE`, `Schema.swift:380`) is **no
longer a problem to engineer around** — it is the *intended* default. A note is a menu-scoped, disposable
thing; if it earns durability, promotion (A6) makes it real. We stopped trying to preserve every note
automatically.

## Decisions

### A1 — A **deposit** verb, target-adaptive by canonical-ness

One apply-action whose commit **branches on what you pointed at**: append onto a recipe (A2), revise a note
(A3). It does not generate new dishes (that is complement) and it does not touch the Workbench (A4). The
selection *source* is the chat intelligence (a Compare verdict, a riff); the selection *target* is the item
(A5).

### A2 — Recipe target → **append** to the recipe's note body

Write the intelligence as a `recipeNote` on that recipe (lightly tidied, but the recipe body is **never**
rewritten — protect the canonical recipe, per Jon's "I never want to adjust a recipe from the menu"). Durable
already; surfaces on the recipe. No Workbench entry, no reminder — you will see it on the recipe.

### A3 — Note target → **revise** the note through a **compose surface** (original + woven draft)

The LLM **synthesizes** the intelligence into the note, and the result overwrites `menuItems.notes` for that
note-kind row. This is a *transform*, permissible **because a note is non-canonical** — the exact inverse of
A2's rule. The note **stays on the menu, ephemeral and menu-scoped**; nothing is copied elsewhere.

But the LLM's woven version is **not assumed to be a drop-in replacement** (Jon: "I can't promise the thing I
want to save is a drop-in replacement"). So the edit sheet is a **compose surface**, not a blind approve:

- **The original note stays visible and copyable** — preserved source, so nothing the model dropped is lost;
  Jon can lift any of it back.
- **An LLM-woven combination** (original ⊕ the deposited intelligence) is the **editable draft**.
- **Jon assembles the final text** — edit the draft, paste from the original — and *that composed text* is
  what commits.

This is [ADR-0023](ADR-0023-recipe-edit-proposals.md)'s **side-by-side original-vs-proposed** pattern at note
scale, with [ADR-0024](ADR-0024-editable-proposal-preview.md) editability — cheaper, because a note has a
**single** commit destination (overwrite itself), not the recipe's overwrite-or-variation fork.

### A4 — **No queue. No auto-Workbench. No graduation.** (Recorded reversal)

An earlier turn of this design auto-copied every deposit into a `workbenchCandidate` to build a single
"reminder inbox." **Cut, deliberately.** Reasons: (1) it dragged in real machinery — an inbox-workbench
identity, a provenance column, dedup rules, distinct-origin styling — to solve "don't lose the idea," which
(2) **explicit promotion solves better and more honestly**: durability should be a *deliberate act*, not a
side effect of thinking out loud. A deposit therefore touches **only** the item you pointed at. "Add to
Workbench" remains a **separate, manual staging affordance** (a workbench candidate is already exactly that),
never auto-populated by this verb. Do not resurrect the queue without a new reason.

### A5 — Item selection as a **target** binding (the one genuinely new UI piece)

The base verb needed *selection-as-source* (built). This needs *selection-as-target*: tapping a menu item
(note or recipe) to make it the deposit destination. Model side is half-done (item UUIDs are already
in-prompt); the missing half is the menu-side binding that makes an item the commit target. The subject/verb
infra (`AnyChatApplyAction`, `requiresSubject`, `RecipeChat.swift:670`) is the hook, not greenfield.

### A6 — Out of scope (named, not folded in)

- **Promote a note → a real recipe.** User-**triggered wherever the note lives** (Jon's explicit shape), not
  a queue, not automatic. Under-specified on purpose — it drags in recipe placement + original-provenance
  ([[reference-placement-and-original-provenance]]) and is ADR-0023/0021-adjacent. Base ADR-0027 **D5**
  already deferred it; this amendment keeps it deferred. Spec it as its own effort when Jon wants it.
- **The seed-bubble verb model** (pre-populate an editable prompt instead of firing a verb blind). Related,
  but a **separate interaction concern Jon owns** ("not sure I need your help there").

## Storage sketch (schema-free)

- **Recipe path** → a new `recipeNote` row (existing table, `Schema.swift:273`).
- **Note path** → overwrites `menuItems.notes` on the existing note-kind row (existing column,
  `Schema.swift:388`).
- Nothing touches `workbenchCandidates`; no new table, column, enum case, or `SyncEngine` surface. Both
  writes are additive/in-place on already-synced tables — sync-safe by construction.

## Open questions

- **OQ-Amd-1 — verb name(s).** Is it **one** verb whose label adapts to the target, or **two** ("Add to
  recipe notes" on a recipe, "Revise this note" on a note)? The commit branches either way; this is purely
  how it reads. *Lean:* two labels, because "append" and "rewrite in place" are honestly different promises
  and a single label would hide which one you are about to get. Resolve at dogfood.
- **OQ-Amd-2 — note revise: replace or merge? → Resolved: neither — a compose surface.** The LLM does not
  decide; the edit sheet shows the **original note (copyable source)** beside an **LLM-woven combination
  (editable draft)**, and Jon assembles the committed text (A3). Chosen because the woven version can't be
  assumed to be a drop-in replacement, so the original must stay salvageable on screen. One remaining sub-
  choice for dogfood: whether the **raw deposited intelligence** also gets its own copyable pane, or stays
  folded into the woven draft only (*lean:* folded-only — the transcript already holds the raw text; two
  panes is enough).
- **OQ-Amd-3 — promotion (deferred).** Note→recipe is A6, its own effort; listed here only so it is not
  mistaken for part of this slice.

## Related

- Base ADR-0027 (parent — new-note capture vs. this existing-item deposit).
  [ADR-0024](ADR-0024-editable-proposal-preview.md) (the review-before-overwrite pattern the note path
  borrows). [ADR-0023](ADR-0023-recipe-edit-proposals.md) / [ADR-0021](ADR-0021-recipe-variations.md) (the
  *out-of-scope* transform / variations, and the eventual promote-to-recipe home).
  [ADR-0011](ADR-0011-actionable-chat-make-ahead.md) (apply-action contract).
  [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) (sync-safety).
- Memory: [[recipe-edit-proposals]], [[llm-curation-not-synthesis]], [[llm-vs-determinism-surface-boundary]],
  [[menu-item-recipe-id-invariant]], [[reference-placement-and-original-provenance]],
  [[menu-planner-dogfood-2026-07-09]], [[chat-verb-commit-shapes]].
