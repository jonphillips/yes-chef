# ADR-0045 — The onboard path stays viable: a **seeded, section-scoped Ask**, finalize parity, and the frontier model becomes a **setting**

> **Vocabulary:** **onboard** = a model call the app makes itself (`ModelCall` → `TieredModelClient`, on-device
> or a frontier API key). **outboard** = the copy/paste hand-off to an external chat app, where the *user's*
> subscription does the thinking. The **ask** is the prompt that opens a discussion; the **deliverable** is
> the structured thing a discussion terminates in.

Status: **Accepted** — ratified by Jon **2026-07-24**, same day it was drafted. D1–D7 stand as written;
**OQ4 is resolved (auto-send)** and **OQ3 is resolved with a correction that changes V1's scope** — see Open
questions. **Amendment 1 (2026-07-24, accepted): the onboard seed reuses the outboard prompt's *framing*, not
its *payload* — D2's reuse claim holds, but "does not re-author any prompt" narrows to the outboard prompt,
and OQ4's auto-send means auto-send on a *cold* thread only.** See Amendment 1. **Amendment 3 (2026-07-26,
accepted): the recipe playbook's Ask launcher becomes a plain button that opens the panel unseeded — the
section list moves entirely into the in-panel Discuss ▾, collapsing Amendment 2's "one control in two
placements" to one placement. D3's intent survives (every section is one control away); D6 is untouched. It
carries a binding condition — the cold panel needs an empty state and a reason on the greyed verbs, or V1's
"the feature was removed" defect returns verbatim.** See Amendment 3. OQ1 and OQ2 remain open and are **V2 concerns**, so they do not gate V1. Originally drafted as
Proposed — 2026-07-24. Jon's call, made explicitly against the "dead code, nuke from orbit"
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
- **OQ3 — RESOLVED (2026-07-24), and the answer corrects D3: there are FIVE cold-start entry points, not
  three.** The check was run before dispatch exactly as this OQ asked, and the drift ADR-0043 D2 measured had
  in fact happened here too. The full map:
  1. **Recipe column-top Ask** — `RecipePlaybookView.askButton` → `RecipeModel.chatButtonTapped`.
  2. **Recipe per-section menu Ask** — `RecipePlaybookView`'s `Button("Ask", action: ask)`, the *same*
     closure with the section dropped. **This is the diagnosed gap in the Context table.**
  3. **Menu Ask** — `MenuViews.askButtonTapped`.
  4. **Meal-calendar day-header Chat** — `MealCalendarViews.chatButtonTapped`, its own implementation
     building a `.mealPlan` chat context. **Not named in D3.**
  5. **Workbench Chat** — `WorkbenchViews` → `WorkbenchModel.chatButtonTapped`, building a `.workbench`
     context. **Not named in D3.**

  **All five open a cold panel that seeds nothing, so all five dead-end at D6's grayed verbs** — the defect is
  broader than the ADR claimed. But the *scoping* answer is unchanged: **V1 stays the three D3 named**, because
  they are the ones a `PlaybookSectionKind` is meaningful for; 4 and 5 have no section to carry and their
  seeds would be a different authoring job (a meal-plan opener, a workbench-deliberation opener). **They are
  recorded here as a known follow-on, not folded into V1** — a seeded-but-not-section-scoped opener for each is
  its own small slice, and building it on this ADR's momentum is the trap
  [[withdraw-not-defer-orphaned-schema]] names. D3's *"three entry points exist and no more"* is **factually
  wrong as written** and should be read as *"three section-scopable entry points."*
- **OQ4 — RESOLVED (2026-07-24, Jon): auto-send.** The seed is a *discussion opener*, not a final prompt, and
  the whole point is removing a cold start — a pre-filled composer leaves the buttons grayed until the cook
  types, which is most of the defect still standing. Pre-fill was the alternative and is rejected.

## Amendment 1 — The onboard seed reuses the outboard prompt's **framing**, not its **payload**

Accepted 2026-07-24, from the architect review of PR [#227](https://github.com/jonphillips/yes-chef/pull/227)
(V1's first implementation). Ships on V1's own branch via
[`docs/efforts/adr-0045-v1-review-fixes.md`](../efforts/adr-0045-v1-review-fixes.md) — this is a correction
to V1 before it merges, not a later slice.

**What D2 did not anticipate.** *"Reuse the existing `.discuss` prompt"* is right about the **authored
thinking** and wrong about the **envelope**. The outboard prompt is **self-contained by construction**: it is
pasted into a bare external thread with no system prompt, so it must carry the subject, the format contract,
and the transport instructions itself. Onboard, that same text lands **on top of** the chat's own
`systemPrompt()`, which already owns the role, the subject, the format rules, and the **tier-budgeted**
context.
Reused verbatim, the first turn therefore shipped the recipe or menu **twice** — and the seed's copy was
tier-blind, bounded at the *frontier* budget (120k chars) while the system prompt's copy was correctly
budgeted for the active tier (12k on-device). That is [[reasoning-budget-starves-output]] with the rail
bypassed, on precisely the tier D1 exists to hedge toward.

- **A1 — The reusable unit is framing + preferences + finalize convention; the context payload and the
  transport sentences are destination-specific.** Prompt builders take an explicit
  `AIHandoffPromptDestination` (`.outboard` / `.onboard`) that gates **exactly two** things: whether the
  serialized subject block is appended, and whether transport-only sentences appear (the menu prompt's *"This
  text will be pasted back into the recipe app…"* — nothing is pasted onboard). Everything else stays
  byte-identical across destinations, so **D2's one-authored-ask-per-verb claim holds unchanged** and the
  outboard string is provably untouched. Note the sentence that *does* survive onboard: *"the cook reviews
  and edits it in Yes Chef before it is saved"* is true on both paths — the review sheet is exactly that.
- **A2 — D2's "does not re-author any prompt" is narrowed to "does not re-author the outboard prompt."**
  One onboard-only sentence is authored: *the format contract describes the finalized return, not this
  conversation.* Without it the opener carries **three formatting contracts at once** (the system prompt's
  prose rules, the section prompt's flat-list contract, and `discussAsk`'s "discuss freely"), and the
  likeliest first reply is an immediate deliverable dump — which satisfies **D6's letter** (a reply exists,
  the verbs light up) while missing its point. Authoring one line beats the alternative of loosening the
  shared text for both paths.
- **A3 — OQ4's auto-send means auto-send on a COLD thread only.** Chat threads persist 30 days per
  recipe/menu, so an unqualified auto-send re-seeds and re-bills on every re-open of a warm panel — and it is
  redundant, because a restored thread already ends in an assistant reply and `latestReplySubject` is already
  non-nil. The cold start is the whole defect; a warm thread never had it.
- **A4 — D3's "section-scoped at every entry point" includes RE-scoping.** A scoped Ask invoked while a
  differently-scoped panel is open **re-scopes and seeds that section**, keeping the open transcript. It does
  not dismiss the panel. The dismiss-toggle is correct only when the invoked section matches the open one.
  On wide iPad the panel is a non-modal companion, so switching sections with it open is the *normal* flow,
  not an edge case.
- **A5 — The onboard discussion sees the section it is discussing; the outboard hand-off deliberately does
  not.** `serialized(excludingPlaybookSections:)` omits the target section so a fresh hand-off cannot echo
  its own prior output. That is a **blind-regeneration** concern. A discussion about improving what is
  already written wants to see what is already written, so the asymmetry is **intended** — recorded here so
  it is not "fixed" into symmetry later.

Invariants unchanged: `requiresSubject` is **not** loosened (D6), and scope stays the **three
section-scopable entry points** (OQ3) — A1's seam makes the meal-calendar and Workbench openers look cheap,
which is exactly when [[withdraw-not-defer-orphaned-schema]]'s momentum trap fires.

## Amendment 2 — One section-picking control, not per-section Ask (2026-07-24)

Accepted 2026-07-24, from the V1 device pass. **D3 said "section-scoped Ask at *every* entry point," and V1
implemented that as an `Ask` item in each section's overflow menu plus a column-top `Ask` defaulting to
Make-ahead.** The device pass showed two problems with that literal reading:

1. **On iPhone the chat is a full-height modal sheet**, so once it is open the playbook's per-section Ask
   menus are behind it and unreachable — the Make-ahead → Serve With re-scope that works on the iPad companion
   had no path at all. An in-panel switcher is *required* on iPhone, not optional.
2. **With the switcher added, per-section Ask became a second, unrelated-feeling door to the same thing** —
   and the one that had caused V1's original defect (the section-menu Ask that dropped its section).

**The mechanism changes; the intent of D3 is preserved.** Section-picking becomes **one control in two
placements**: a single **Ask ▾** launcher on the playbook (pick a section → open scoped to it), and the open
panel's **title as a Discuss ▾** switcher (move an already-open discussion, keeping the transcript). Both route
through one method (`RecipeDetailModel.askSection`) that opens-or-switches and **never closes** — dismissal is
the panel's own explicit **Done** button, since a crowded sheet toolbar is awkward to swipe past. The
per-section overflow `Ask` items are **removed**; the overflows keep Hand-off / Paste / Edit / Clear. "Ask at
every section" is now satisfied by one menu that lists every section, not by duplicated per-section items.

## Amendment 3 — **Ask opens the panel.** The launcher stops picking sections (2026-07-26)

Accepted 2026-07-26, from Jon's iPhone pass during the dogfood ferry. **Amendment 2 made the playbook's Ask a
`Menu` over every section, so there is no way to open the panel without first choosing a seeded discussion.**
Jon's report: *"if I want to just ask 'what's a good substitution for buttermilk' I first have to fake it doing
a whole complex 1-of-3-choices query."*

**This is the V1 defect's mirror image, and the symmetry is the lesson.** V1 existed because tapping Ask
produced an empty panel with every apply-verb greyed, and the cook concluded the feature had been removed. The
fix guaranteed a reply would exist — **by refusing to open the panel without a seed**. That closed the reported
bug and silently closed the free-form question with it. Both failures come from the same move: treating "the
panel is open" and "a seeded discussion has started" as one event.

**They are two events, and the launcher only owns the first.**

**Decision — the launcher becomes a plain button.** Tapping **Ask** opens the panel, unseeded, with the input
focused. The section list is **removed from the launcher**. Section-picking keeps the home it already has: the
open panel's **Discuss ▾** switcher, which Amendment 2 built and which
[`RecipePlaybookView.swift`](../../YesChefApp/RecipePlaybookView.swift)'s own comment already calls *"the same
control once open."* Amendment 2's "one control in two placements" collapses to **one control in one
placement** — the redundancy was the defect, not the design.

**The tap arithmetic, stated honestly:** a free-form question goes from *unreachable without faking a section*
to **one tap**; a seeded section discussion goes from two taps to **three** (Ask → Discuss ▾ → section). That is
the right direction. The buttermilk question is asked mid-cook with one hand; a seeded section discussion is
deliberate, less frequent, and already the heavier act ([[automation-decays-near-the-stove]]).

**Binding condition — the cold panel must not read as broken, or V1 returns verbatim.** An unseeded panel today
shows only `ChatContextHeader`'s one-line context footnote above an empty transcript, with the apply-verbs
greyed and **unexplained**. That is precisely the screen that produced V1's "the feature was removed"
conclusion. So this amendment does not ship without:

1. **An empty state in the transcript area** naming what the panel is for — ask anything about this recipe, or
   pick a section from Discuss ▾ to start a guided discussion.
2. **A stated reason on the greyed apply-verbs** — they need a reply before they can act. Greyed-with-a-reason
   is a working control; greyed-in-silence is a broken feature.

**D3 is amended, not abandoned.** "Ask is section-scoped at every entry point" was always about *reachability*
of scoped discussion, not about forcing scope as the price of entry. Every section remains one control away,
inside the panel. **D6 is untouched** — `requiresSubject` does not loosen, and the apply-verbs still require a
real assistant reply; the empty state explains that gate rather than removing it.

**Menu surfaces are unaffected.** The Menu's Ask ▾ (Prep Plan · Complement · Regenerate) lists *verbs*, not
sections, and has no in-panel equivalent to fall back on. It stays a menu. This amendment is about the
**recipe** launcher, where the duplication actually exists.

### Codicil to Amendment 3 — the embedded panel header contract (2026-07-26)

Added the same day, from Jon's iPad pass on the amendment's own implementation. **Moving the chrome into the
panel (where it belongs) made visible how much of it there is.** An *empty* panel presented ten elements to say
*"ask me something"*: Discuss ▾, a trash, a tier chip, a close, a context line, an empty state, a disabled
Apply, an explanation of the disabled Apply, the input, and Send.

**The embedded header is `[ Discuss ▾ | title ] ……… [ ⋯ ] [ ✕ ]`** — one primary control, one overflow, one
dismiss. `⋯` holds **Clear Chat** (destructive, keeping its confirmation) and the **model/tier** picker. `✕`
renders only where the panel owns its dismissal; the `ChatWorkspaceSplit` surfaces keep theirs in the divider.

Two rules, stated so they survive the next surface:

1. **A destructive control is never adjacent to a dismiss control.** Clear Chat already confirms, so a
   fat-finger costs a Cancel rather than a transcript — but the confirmation is a safety net, not a licence for
   the adjacency. Destructive goes in the overflow.
2. **The least-used control does not pay for header width.** The tier picker is a *per-conversation privacy
   override*, not a per-question choice; it belongs behind the overflow, and it cannot move to AI Settings
   entirely precisely because the override is the point.

**And the amendment's own binding condition is satisfied once, not twice.** The empty state and the
disabled-Apply footnote explained the same emptiness in two places; the explanation belongs in the empty state,
and Apply stays visible-but-disabled without narrating. Relatedly, `ChatContextHeader` must stop announcing
*"Seeded with the recipe on screen."* on a panel that was deliberately opened **unseeded** — true before this
amendment, false after it, and "seeded" is internal vocabulary besides.

**This contract is the reason to settle it now.** Every embedded panel — Recipe, Menu, Calendar, Workbench —
renders the same `RecipeChatPanel` header, and the modal sheet path groups its trailing controls the same way.
Settling the shape before it spreads is cheaper than harmonizing four copies later, which is the drift this
ADR's own ferry dispatch exists to undo. Implementation: `efforts/dogfood-ferry-2026-07-25.md` **Slice G5**.

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
