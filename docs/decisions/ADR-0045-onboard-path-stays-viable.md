# ADR-0045 — The onboard path stays viable: a **seeded, section-scoped Ask**, finalize parity, and the frontier model becomes a **setting**

> **Vocabulary:** **onboard** = a model call the app makes itself (`ModelCall` → `TieredModelClient`, on-device
> or a frontier API key). **outboard** = the copy/paste hand-off to an external chat app, where the *user's*
> subscription does the thinking. The **ask** is the prompt that opens a discussion; the **deliverable** is
> the structured thing a discussion terminates in.

Status: **Proposed** — 2026-07-24. Jon's call, made explicitly against the "dead code, nuke from orbit"
alternative he first reached for. Reverses an *implicit* drift (nothing ever decided to retire onboard; it
decayed because its affordances were never finished). Governed by
[ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) (tier/effort as settings) and
[ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) (the `.discuss` ask and the return block this
reuses wholesale); feeds [ADR-0043](ADR-0043-model-call-chokepoint.md)'s record.

## Context

**Outboarding was a pricing decision, not an architectural one.** The move to hand-offs was correct *on the
day it was made*: a flat-rate chat subscription beats per-token API billing for long deliberative sessions,
and [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) built a real contract around it. But that
is an **on-this-day financial judgment**. Provider pricing moves, and the on-device tier — already the
default backend and the degradation target ([[yeschef-onbard-model-tier]]) — is the one that gets better for
free. Deleting the onboard path would convert a **reversible commercial bet into an irreversible code fact.**
This ADR exists to keep the bet reversible.

**The decay is measurable, and it is an unfinished affordance rather than a removed one.** In the recipe
playbook's per-section overflow menu, every verb carries the section it was invoked from — except one:

| Menu item | Section-scoped? |
|---|---|
| Paste | ✅ `source: .recipeSection(recipeID, section)` |
| Edit / Write manually | ✅ `editingSection = section` |
| Clear | ✅ `clearingSection = section` |
| **Ask** | ❌ `action: ask` → the generic, un-scoped `chatButtonTapped` |

`chatButtonTapped` (`RecipeModels.swift`) is a **pure visibility toggle**: it opens the chat with the recipe
as context and seeds **no prompt**. So the section-scoped Ask already exists in the UI and is wired to the
wrong thing.

**That one gap disables everything downstream.** The apply-verbs (`Create Prep Plan` → Make-ahead,
`Chef It Up`, `Suggest Dishes`) are real buttons that fire real `ModelCall`s, but `canRun`
(`RecipeChatWorkspace.swift`) enables a `requiresSubject` action only when a **subject** exists — a selection,
or a latest assistant reply. From a cold Ask panel there are no messages, so the buttons render **grayed**.
The user's experience is therefore: *tap Ask → empty panel → every verb greyed out → conclude the feature was
removed.* Which is exactly what happened during the 2026-07-24 dogfood pass.

**The same verb is currently prompted twice, in two places, in two shapes.** Onboard, `MakeAheadPlanClient`
authors a one-shot **extraction** prompt. Outboard, `AIHandoff` authors a **conversational** `.discuss` ask.
Two authorings of one verb is the drift disease [ADR-0043](ADR-0043-model-call-chokepoint.md) exists to fight,
one level up: not "which model ran," but "which prompt is the real one."

### What this actually buys — stated honestly, because it is not an immediate win

1. **Optionality (the real justification).** Insurance against a pricing change or an on-device tier that
   becomes good enough. It pays off later or never, and that is the nature of a hedge.
2. **Prompt-source convergence (the immediate structural win).** D2 collapses two authorings per verb into
   one. This is worth doing *even if Jon never uses the onboard path again*.
3. **It gives ADR-0043's record real traffic** — today the inventory is nearly empty because most onboard
   verbs are practically unreachable. **This is a consequence, not a justification.** Building a feature to
   feed its own tracker would be backwards, and this ADR explicitly declines to argue that way.

## Decision

### D1 — Onboard is maintained as **optionality**; it is not deleted, and it is not promoted to default

The hand-off stays the day-to-day path. Onboard must remain *reachable and correct* so the choice can be
re-made later without archaeology. This is a decision to **keep a door unlocked**, not to walk through it.

### D2 — The seeded ask is the **existing outboard `.discuss` prompt** — one prompt source per verb

The `.discuss` prompt in `AIHandoff` already reads: *"You may discuss this freely. When the user asks you to
finalize, return `<deliverableFormat.discussInstruction>`."* That is exactly the right opening for an onboard
discussion, and reusing it means **one authored ask per verb, serving both paths**. The one-shot extraction
prompts inside the apply-action clients stay where they are — they serve D5's extraction step, which is a
different job — but they stop being a *second answer to "how do we ask for a make-ahead."*

**Corollary, and it is the cheap half of finalize:** the finalize convention rides along inside that prompt
text for free. Onboard inherits it without authoring anything.

### D3 — Ask is **section-scoped** at every entry point

Thread the section through so an Ask invoked from Make-ahead opens a *make-ahead* discussion. Three entry
points exist and no more: the recipe top-level Ask, the recipe per-section menu Ask, and the Menu's own Ask.
This finishes the affordance ADR-0041 S2 already built for the outboard side (section-scoped hand-off) and
leaves the onboard side symmetric with it.

### D4 — **Finalize is a button, not a magic word** (resolves Jon's "food for thought")

Outboard, finalize *must* be typed — we only control the pasted text. Onboard, the chat is **our UI**, so a
typed magic word would reproduce the precise failure this ADR is fixing: an affordance nobody can see. So the
onboard discussion carries an explicit **Finalize** control.

Typing "finalize" keeps working — the seeded prompt says so, and there is no reason to break parity with the
outboard habit.

### D5 — Two mechanisms, deliberately, because the weak tier is the point

A finalize returns a deliverable one of two ways:

- **Terminal turn** — the conversation itself emits the block, parsed by the **same `AIHandoffReturn`
  parser** the outboard paste path uses. One parser, both paths.
- **Extraction call** — a separate structured `ModelCall` (today's apply-action), parsed into a typed plan.

This is **not** redundancy. A frontier model will emit a clean terminal block on request; a small on-device
model asked to *both* converse and emit strict structure is precisely where
[[reasoning-budget-starves-output]] bites. Since on-device is the tier this ADR is hedging *toward*, the
extraction call is the reliable floor, not legacy. It also keeps
[ADR-0042 D2](ADR-0042-workbench-handoff-and-the-return-block.md)'s boundary intact: the structured canonical
write stays a step the app controls.

### D6 — Seeding enables the buttons; **do not loosen `requiresSubject`**

Once the seeded ask has been sent, an assistant reply exists → `latestReplySubject` is non-nil → `canRun` is
true → the verbs light up. And "operate on whatever the user highlights" is **already** the implemented
behavior (`selectionSubject` wins over the latest reply). Both requirements fall out of D2/D3 for free.

Loosening `requiresSubject` to force the buttons on would let an apply-action fire with an **empty subject** —
a silent-garbage path of exactly the kind already being fixed on the learnings side. Rejected.

### D7 — The frontier **model** becomes a user setting

`FrontierProvider.defaultModel` is a hardcoded LLMClientKit constant (`claude-opus-4-8` / `gpt-5.6-terra`).
Yes Chef never overrides it; AI Settings *displays* it read-only. So the user picks a **provider** but not a
**model** — and the ADR-0043 S2 inventory now shows a model the user cannot change.

[[personal-app-latency-tolerance]] already established that **effort and tier belong in user settings, not
code constants**; model is the same principle one notch finer. The override point already exists —
`AnthropicModelClient(apiKey:model:session:)` takes a model — it is only `TieredModelClient.live()` that
declines to expose it.

**This does not apply to the outboard path**, which has no model to set: the user pastes into whichever
assistant they like. *Which external assistant the contract targets* is a separate ADR-0042 question and is
not touched here.

## What this does not do

- **It does not make onboard the default.** D1 is explicit.
- **It does not re-author any prompt.** D2 reuses; it does not write.
- **It does not touch the outboard contract**, `YC-CONTRACT` versioning, or the project instructions.
- **It does not add a schema.** No table, no column, no sync posture.

## Slices — with honest cost, because the payoff is deferred

**V1 — the seeded, section-scoped Ask (app; no schema).** Thread `PlaybookSectionKind` through the three Ask
entry points; give the chat opener an optional seed built from the existing `.discuss` ask; send it on open.
**Cost: the largest slice, and most of it is threading, not thinking** — `RecipePlaybookView` (pass the
section), `RecipeDetailView` (the `ask:` closure), `RecipeModels.chatButtonTapped` (accept a section, build
and send the seed), the Menu's equivalent, plus one Core helper that hands back the `.discuss` ask for a given
section. **This slice alone fixes the grayed-buttons problem** (D6) and is independently useful.

**V2 — the Finalize button + the shared return parser (app).** Add the control, send the finalize
instruction, run the reply through `AIHandoffReturn`, route into the existing review sheet. **Cost: moderate,
and concentrated in one place** — the review plumbing currently expects a return that arrived via the
paste/import intent, so the onboard-originated return needs the same entry. No new parsing, no new prompt.

**V3 — the frontier model as a setting (cross-repo: jon-platform + app).** Add a model resolver to
`TieredModelClient.live(...)` and pass it at backend construction; add a stored per-provider model preference
and an AI Settings picker. **Cost: small in code, but it crosses the package boundary**, so it wants to ride
with a slice already touching resolution — most naturally
[ADR-0043](ADR-0043-model-call-chokepoint.md) **S3**, which unifies `resolveTier()` and already has both repos
open. **Sequence V3 with S3 rather than here**, unless it is wanted sooner.

**Sequencing:** V1 stands alone and delivers the visible fix. V2 wants V1 (there is nothing to finalize
without a seeded discussion). V3 is independent of both and should follow ADR-0043 S3.

## Open questions

- **OQ1 — how do Finalize and the apply-verb buttons coexist without reading as two buttons for one job?**
  D5 keeps both mechanisms, but the *UI* may want a single control whose mechanism is chosen by tier
  (terminal turn on frontier, extraction call on-device). **Recommendation:** one button labelled for the
  deliverable, mechanism chosen underneath — but this wants a look at the real chat layout before it is
  settled, and it is the one thing here that could get fiddly.
- **OQ2 — at what tier do we trust the terminal turn?** D5 names the axis but not the threshold. Needs one
  on-device finalize attempt to answer empirically; do not guess it in advance.
- **OQ3 — scope beyond the recipe.** Menus have an Ask; meal-plan surfaces have their own verbs. V1 covers
  the three Ask entry points that exist today — confirm nothing else grew before dispatch, given the drift
  rate ADR-0043 D2 measured.
- **OQ4 — does the seeded ask send automatically, or land in the composer for editing?** Auto-send makes D6
  work immediately; pre-fill gives the cook a chance to aim it first, but leaves the buttons grayed until the
  first reply. **Recommendation: auto-send**, since the seed is a *discussion opener*, not a final prompt, and
  the whole point is removing a cold start.

## Related

- [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) — the `.discuss` ask, the return block, and
  the `AIHandoffReturn` parser this reuses wholesale; its D2 boundary is why D5 keeps the extraction call.
- [ADR-0041](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) — built the section-scoped **outboard**
  hand-off; D3 is the onboard half it left asymmetric.
- [ADR-0043](ADR-0043-model-call-chokepoint.md) — its record is what makes onboard traffic legible; **S3** is
  where D7/V3 should ride. Note the honest framing above: feeding the tracker is a consequence, not a reason.
- [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) — tier + effort as settings, which D7 extends to model.
- Memory: [[yeschef-onbard-model-tier]] (on-device is the default backend and the tier that improves for
  free), [[personal-app-latency-tolerance]] (settings, not code constants — D7's precedent),
  [[reasoning-budget-starves-output]] (why D5 keeps the extraction floor),
  [[actionable-chat-effort]] (the apply-verbs being revived), [[automation-decays-near-the-stove]].
