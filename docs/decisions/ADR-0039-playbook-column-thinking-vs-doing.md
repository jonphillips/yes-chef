# ADR-0039 — The Playbook column: separating *thinking* from *doing*

> **The organizing axis is not AI-vs-human and not content-type. It is *thinking vs. doing*.** Every
> cooking surface in Yes Chef mixes two modes: the deliberate, accumulative work of *figuring out how
> you'll run this* (make-ahead, learnings, adjustments, variations, prep strategy), and the in-the-weeds
> work of *actually running it* (ingredients, instructions, navigation). Today they are tangled. This ADR
> separates them.

Status: **Proposed** — 2026-07-14. Origin: Jon, immediately after the [ADR-0038](ADR-0038-external-llm-handoff.md)
S2 device pass. **Depends on [ADR-0038 Amendment 1](ADR-0038-external-llm-handoff.md)** (the two-part
Deliverable + Learnings return contract — this ADR is *where those Learnings become visible*). Touches
[ADR-0021](ADR-0021-recipe-variations.md) (variations), [ADR-0023](ADR-0023-recipe-edit-proposals.md)
(adjustments), [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) (the prep plan and its horizon
bands), and the in-app chat panel (ADR-0011/0024/0026). **Milestone-sized, not a slice.**

## Context — the AI panel stopped earning its rent

The always-visible chat panel was designed for a world where **in-app chat was *the* AI**. ADR-0038 changed
that world: the heavy multi-turn reasoning now offboards to a flat-rate native LLM app, and Yes Chef's job
is to own the context going out and the durable artifact coming back. Two observations, from Jon's device
pass:

1. **On a menu, the third column is empty rent.** A "seeded with…" blurb and a text input occupy a quarter
   of an iPad, while the actual deliverable — the prep plan — is buried mid-body.
2. **On a recipe, the third column holds a real conversation whose value evaporates.** A discussion about
   freezing birria for a beach trip produced exactly the kind of durable knowledge ADR-0038 Amd 1 calls a
   *Learning* — and it lands nowhere.

Meanwhile the recipe body has the opposite problem: **make-ahead is bloating the cook scroll.** It competes
with Ingredients for attention at exactly the moment you're asking *"where the hell are the instructions?"*

## Decisions

### D1 — The third column is the **Playbook**: everything you've figured out about this recipe that isn't the recipe itself

Name: **Playbook**. Explicitly rejected:

- **"Intelligence"** — defines the column by *provenance*. Wrong: per ADR-0024 the human is the final author
  of everything that commits, so most of this content is at least partly Jon's. A hand-typed make-ahead note
  is not "the robot's stuff."
- **"Context"** — already load-bearing jargon in this codebase (`MenuChatContext`, "seeded with recipe on
  screen"). Overloading it would be actively confusing.
- **"Prep" / "Planning"** — too narrow; excludes Learnings, which are knowledge, not plans.

**Contents:** make-ahead, notes, Learnings (ADR-0038 Amd 1), variations (ADR-0021), adjustments (ADR-0023),
and the affordances that produce them (D3). Provenance is metadata, never the organizing principle.

### D2 — **Make-ahead relocates out of the recipe body into the Playbook**

Make-ahead is **pre-execution by definition** — you read it two days out, never while searing. Moving it is
not burying cook-critical content; it *fixes* the cook scroll. This is a net win on both ends: the Playbook
gains its anchor content, and the body gets shorter and more navigable.

### D3 — The in-app chat **demotes from "the AI" to "the quick one"**

Its job shrank; it did not disappear. The tiers become legible in the UI, and the Playbook column header owns
both:

- **Hand off to ChatGPT** (flat-rate, deep, multi-turn) — the **primary** affordance. ADR-0038's Copy Prompt.
- **Ask** (in-app, on-device/metered — [[yeschef-onbard-model-tier]]) — **secondary**, slides in. For the
  cheap and instant: *"what can I sub for gochujang?"* Offboarding for that is absurd.

This is what justifies de-emphasis without deletion, and it puts [[personal-app-latency-tolerance]] and the
cost ladder on screen instead of in Jon's head.

### D4 — A **menu** has no Playbook column. It *is* one — until service approaches.

A menu is a thinking artifact: you don't execute a menu, you execute its recipes. So the prep plan **keeps its
primary middle-column placement** and the menu's third column is **deleted**, not filled. The handoff/chat
affordance becomes a toolbar action or slide-in.

But the menu's mode shifts **over time** rather than over space (the recipe separates its two modes
*spatially*; the menu separates them *temporally*):

- **Far from service:** the menu is a planning surface. The prep plan is the point.
- **Near service:** the menu becomes a **launcher**. Foreground the **dish list** (with collapsible days);
  **collapse the prep plan.** Day-of, the job is *get me into the right recipe fast*, not *show me the plan*.

The menu remains the day-of home base; the calendar is a time-index *into* menus, not a replacement.

### D5 — **The prep plan holds tasks, never choreography**

The distinction is **kind**, not horizon:

| | Definition | Trust |
|---|---|---|
| **Task** | Separable, atomic, context-free. *"Salt the chicken Wednesday." "Pull the beef to temp at 4."* | ✅ at **any** horizon, service hour included |
| **Choreography** | Interleaved cooking instructions woven across several recipes. *"Now sear the beef while the salad rests."* | ❌ **never** |

Choreography strips the recipe context the cook actually reasons with, and so it will never be trusted — which
means generating it is worse than useless, it is noise that buries the tasks that *are* trustworthy. **The prep
plan must never become a merged mega-recipe. The recipes hold the cooking.**

This is the same failure as auto-sequenced "Start Cooking," and it generalizes:

> **Automation's value decays as you approach the stove.** Far from service, abstraction is a gift. Near
> service, abstraction is a liability. Yes Chef hands control *back* as the clock runs down.

Extends ADR-0024: the human is the final **author**, and also the final **navigator**.

**Follow-on:** [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md)'s prompt contract needs an amendment —
instruct the model to emit **tasks, never choreography**. Don't generate what will never be trusted.

## Consequences

- The recipe body gets shorter and cook-navigable; the Playbook becomes the deliberate surface.
- ADR-0038 Amd 1's Learnings finally have somewhere to *be seen*, not just stored — which is what makes the
  harvest worth doing.
- The menu's empty column is reclaimed as screen real estate.
- ADR-0034's prep plan gets a scope boundary (D5) that should make it smaller, sharper, and more trusted.

## Open questions

- **OQ1 — Playbook on the recipe: home or workshop?** Does make-ahead *move* entirely (body shows nothing),
  or does the body keep a compact read-only summary with the Playbook as the authoring/review surface? Leaning
  **home with a compact body summary**; Start Cooking must still surface what it needs.
- **OQ2 — compact/phone layout.** There is no third column on iPhone (and [[macos-longterm-target]] means this
  must not become an iPad-only idiom). Is the Playbook a tab, a sheet, or a section?
- **OQ3 — what triggers the menu's temporal mode shift (D4)?** Automatic (service date proximity), manual
  toggle, or simply "collapsible days, collapsed by default when the menu is in the past/present"? Prefer the
  dumbest thing that works; avoid a mode the user can't predict.
- **OQ4 — RESOLVED (2026-07-14, with Jon): the Playbook subsumes by *display*; the content underneath stays
  *typed*.** The original lean here ("subsumes-by-display, not by schema") was read as *reuse the existing
  generic notes surfaces* — and that is **backwards**. The project's actual trajectory is to **decompose**
  notes into typed, granular homes (make-ahead got its own; Chef It Up got its own); "notes" is the residue
  being drained, not a destination. So a new content kind gets a **new typed home**, and the Playbook is the
  *column that renders them together* — not a schema that merges them. First application:
  [ADR-0038 Amendment 1](ADR-0038-external-llm-handoff.md)'s Learnings get their own synced `Learning` table
  rather than being dumped into `Menu.notes` or day-scoped `MenuItem` note-rows. **Granularity is also an AI
  affordance** — a typed record is addressable; a paragraph buried in a note blob is not.

## Related

- [ADR-0038](ADR-0038-external-llm-handoff.md) + **Amendment 1** (Deliverable + Learnings — the content this
  column exists to hold), ADR-0034 (prep plan / horizon bands; D5 constrains it), ADR-0021 (variations),
  ADR-0023 (adjustments), ADR-0024/0026 (human as final author; the review sheet), ADR-0011 (in-app chat).
- Memory: [[yeschef-onbard-model-tier]] (why the in-app chat survives as the quick tier),
  [[personal-app-latency-tolerance]], [[llm-vs-determinism-surface-boundary]] (D5 is its cousin — the axis
  here is *abstraction vs. context*, not determinism), [[prep-plan-horizon-redesign]],
  [[macos-longterm-target]].
