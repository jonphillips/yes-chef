# ADR-0039 — The Playbook column: separating *thinking* from *doing*

> **The organizing axis is not AI-vs-human and not content-type. It is *thinking vs. doing*.** Every
> cooking surface in Yes Chef mixes two modes: the deliberate, accumulative work of *figuring out how
> you'll run this* (make-ahead, learnings, adjustments, variations, prep strategy), and the in-the-weeds
> work of *actually running it* (ingredients, instructions, navigation). Today they are tangled. This ADR
> separates them.

Status: **Proposed** — 2026-07-14; **Amendment 1** (2026-07-15) resolves OQ1–OQ3 and corrects the recipe
framing; **Amendment 2** (2026-07-16) reframes the Playbook as a **persistent, resizable *Enrichment* column
shared by recipe and menu** — superseding Amendment 1's Cook/Plan toggle and D4's deleted menu column (see the
[Amendment 2](#amendment-2--2026-07-16-the-playbook-becomes-a-persistent-enrichment-column) section).
Origin: Jon, immediately after the [ADR-0038](ADR-0038-external-llm-handoff.md)
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

**Contents:** make-ahead, notes, Chef It Up, Serve With, Learnings (ADR-0038 Amd 1), variations (ADR-0021),
adjustments (ADR-0023), and the affordances that produce them (D3). Provenance is metadata, never the
organizing principle. *(Amendment 1 corrects the "third column" framing below and fixes the exact contents
cut — the recipe has **three peer regions**, not two columns; see [Amendment 1](#amendment-1--2026-07-15-oq1oq3-resolved-recipe-framing-corrected).)*

### D2 — **Make-ahead relocates out of the recipe body into the Playbook**

Make-ahead is **pre-execution by definition** — you read it two days out, never while searing. Moving it is
not burying cook-critical content; it *fixes* the cook scroll. This is a net win on both ends: the Playbook
gains its anchor content, and the body gets shorter and more navigable. *(Amendment 1 resolves OQ1: this is a
**full move** — the cook body shows no make-ahead at all, not even a compact summary.)*

### D3 — The in-app chat **demotes from "the AI" to "the quick one"**

Its job shrank; it did not disappear. The tiers become legible in the UI, and the Playbook column header owns
both:

- **Hand off to ChatGPT** (flat-rate, deep, multi-turn) — the **primary** affordance. ADR-0038's Copy Prompt.
- **Ask** (in-app, on-device/metered — [[yeschef-onbard-model-tier]]) — **secondary**, a **slide-over**. For the
  cheap and instant: *"what can I sub for gochujang?"* Offboarding for that is absurd. *(Amendment 1: "Ask" is a
  true slide-over, decoupled from any resize bar — the old draggable divider is retired.)*

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

- **OQ1 — RESOLVED (2026-07-15, Amendment 1): full move, body shows nothing.** No compact body summary. Start
  Cooking does not constrain this (and is not being killed). Playbook sections are collapsible with content
  indicators.
- **OQ2 — RESOLVED (2026-07-15, Amendment 1): a third segment on compact; a Cook/Plan toggle on wide.** Not a
  tab or sheet — the Playbook is a third case of the existing `Ingredients · Directions` segmented picker, and
  on wide iPad a Cook/Plan toggle swaps Directions ↔ Playbook with Ingredients pinned.
- **OQ3 — RESOLVED (2026-07-15, Amendment 1): collapsible days, collapsed by default when the service date is
  today-or-past.** The dumbest predictable option, no new mode.
- **OQ4 — RESOLVED (2026-07-14, with Jon): the Playbook subsumes by *display*; the content underneath stays
  *typed*.** The original lean here ("subsumes-by-display, not by schema") was read as *reuse the existing
  generic notes surfaces* — and that is **backwards**. The project's actual trajectory is to **decompose**
  notes into typed, granular homes (make-ahead got its own; Chef It Up got its own); "notes" is the residue
  being drained, not a destination. So a new content kind gets a **new typed home**, and the Playbook is the
  *column that renders them together* — not a schema that merges them. First application:
  [ADR-0038 Amendment 1](ADR-0038-external-llm-handoff.md)'s Learnings get their own synced `Learning` table
  rather than being dumped into `Menu.notes` or day-scoped `MenuItem` note-rows. **Granularity is also an AI
  affordance** — a typed record is addressable; a paragraph buried in a note blob is not.

## Amendment 1 — 2026-07-15: OQ1–OQ3 resolved, recipe framing corrected

Design discussion with Jon (2026-07-15), grounded in the current UI. Two things: a factual correction to the
recipe framing, and the resolution of OQ1–OQ3.

### The recipe has three peer regions, not two columns

The original text calls the Playbook "the third column" and speaks of "reclaiming" an empty column. That is
wrong about the code. Both the recipe and menu use a hand-rolled `ChatWorkspaceSplit`
(`YesChefApp/RecipeChatWorkspace.swift`) = **reader pane + a collapsible/resizable chat pane** — the pane
already zeroes out (`ChatWorkspaceDetent.readerOnly`) and is already a `.sheet` on compact. There was never an
empty column to reclaim; what changes is the pane's **content**.

The correct model: the recipe has **three peer regions — Ingredients · Directions · Playbook** — and *the
device decides how many are co-visible*:

- **Compact** (iPhone / iPad-narrow / macOS-narrow): one region at a time, via the existing `.segmented`
  `Picker` over `CompactSection` (`RecipeDetailView.swift:525`), which simply gains a **third case**:
  `Ingredients · Directions · Playbook`. This is why the split scales down without an iPad-only idiom
  ([[macos-longterm-target]]).
- **Wide iPad**: **Ingredients is pinned as a stable ⅓ anchor** (useful in both modes), and a **Cook / Plan
  toggle** swaps the other ⅔ between **Directions** (Cook) and **Playbook** (Plan). The toggle **sets preset
  detents** (reusing the `ChatWorkspaceDetent` metrics); the **manual draggable divider (`ChatWorkspaceDivider`)
  is retired** — its old reader-vs-chat job is gone now that "Ask" is a slide-over, and a free drag invites an
  "any blend" state that contradicts the bimodal thinking-vs-doing axis. The toggle is the wide-screen render of
  the same discrete-mode grammar as the compact picker.

The Playbook is a **first-class peer of Ingredients and Directions**, not a bolt-on pane.

### OQ1 — full move, body shows nothing

Make-ahead and the other migrated sections leave the cook body **entirely**; only the Playbook shows them. No
compact body summary. Start Cooking explicitly does *not* constrain this (nor is it being killed — it just gets
no vote here). **New requirement:** Playbook sections are **collapsible**, and each header carries a
**filled/empty content indicator** so you can see what's populated without expanding.

**Contents cut** (from `directionsColumn`, `RecipeDetailView.swift:542`):

| Section | Destination |
|---|---|
| Make-ahead (`Recipe.makeAhead`) | **Playbook** (full move) |
| Notes — reader feedback + other `RecipeNote` | **Playbook** |
| Chef It Up | **Playbook** |
| Serve With | **Playbook** |
| Instructions | stays in **Directions** |
| Active variation method note | stays in **Directions** (modifies how you cook now) |
| Workbench candidate links | stays in **Directions** |

**Make-ahead store:** `Recipe.makeAhead` (the `String?` column) stays **canonical**; `RecipeNote` of kind
`.makeAhead` is legacy/unused — noted, not migrated now. (This is a local exception to OQ4's decompose-into-typed
-homes trajectory, kept for low churn; revisit if it bites.)

### OQ2 — resolved by the three-region model above

Third segment on compact; Cook/Plan toggle on wide. Not a tab or a separate sheet.

### OQ3 — collapsible days, collapsed when today-or-past

The menu's launcher mode (D4) needs no unpredictable proximity trigger: the dish list is always present with
collapsible days; days collapse **by default once the service date is today or in the past**. No new mode.

### Unifying principle (spans D4 + OQ2/OQ3)

> **Key the mode off a date when there is one; off a manual toggle when there isn't.**

A **menu** has a service date → its planning→launcher shift is date-driven (OQ3). A **recipe** has no inherent
date → a manual Cook/Plan toggle is the honest control. The asymmetry is principled, not accidental.

## Amendment 2 — 2026-07-16: the Playbook becomes a persistent Enrichment column

Design discussion with Jon (2026-07-16), grounded in a week of dogfooding on a **13" iPad** (the design
target — the biggest iPad made; compact is treated as post-planning execution only). Two lived frustrations
pointed the same direction:

1. **The Cook/Plan toggle meant planning with the instructions gone.** Amendment 1 had the wide-iPad toggle
   *swap* Directions ↔ Playbook. In practice you do a lot of planning while wanting to *see* what you're
   cooking; swapping the instructions off-screen to plan was not sustainable.
2. **The menu's deleted third column left dead space on a planning artifact.** Half a 13" screen doing nothing,
   on the surface whose whole job is thinking.

Both say the same thing: **the Playbook should be co-visible with the body, always, and sized by hand — not a
mode you switch into.** This amendment supersedes Amendment 1's Cook/Plan toggle (OQ2) and its divider
retirement, and D4's "third column deleted / prep plan keeps primary middle-column placement," in favor of one
grammar shared by recipe *and* menu.

### The axis evolves: not a mode you toggle, but context you keep beside you

The original thesis modeled *thinking vs. doing* as two **modes** — separated spatially on the recipe (toggle)
and temporally on the menu (launcher). Dogfooding says they aren't cleanly separable moments: you glance at a
note *while* you cook, you scan the dishes *while* you plan. The distinction is still real, but it lives in the
**content** (what is *body* vs. what is *enrichment*), not in a mode the UI forces you between. And the
alternative — collapsing everything into Directions to get a clean "doing" view — would be a
content-management nightmare and fights [[decompose-notes-into-typed-homes]] head-on (the trajectory is typed,
granular homes, *not* prose merged back into instructions).

So a new **lens** — a principle, not new vocabulary; the name stays **Playbook**: the Playbook is the
**Enrichment column**. Additive context alongside the body, not a destination you toggle into. Its defining
property, in Jon's words: **it never becomes invisible unless you ask it to.**

### The unified grammar — Body · Playbook · Ask

Every cooking artifact has the same three region-types; **width** decides how many are co-visible, and the
Playbook's **width** is yours to set:

| | **Body** (what you execute) | **Playbook / Enrichment** (persistent, resizable) | **Ask** (transient slide-over) |
|---|---|---|---|
| **Recipe** | Ingredients + Directions | make-ahead · notes · Chef It Up · Serve With · Learnings · variations/adjustments | in-app quick chat |
| **Menu** | Dishes + placements | Prep Plan + Learnings + **ChatGPT handoff** (Copy Prompt / Paste) | in-app quick chat |

### Recipe (wide): three co-visible columns, no mode

On wide (13" is the target), **Ingredients + Directions + Playbook are all co-visible.** This **reverses
Amendment 1**: the **Cook/Plan toggle is gone on wide**, and the retired divider's rationale is moot — there is
no mode to blend, just three columns you size. Directions never leaves the screen to plan. **Compact is
unchanged:** the `.segmented` picker (`Ingredients · Directions · Playbook`, `RecipeDetailView.swift:560`),
one region at a time — the toggle survives *only* here, as a necessity of narrow width. iPhone is execution
mode; planning is already lost ([[macos-longterm-target]]).

### Playbook width: show/hide toggle + drag + snap detents

Three controls, each for the job it's best at (the pattern from Xcode/VS Code sidebars):

- **Toolbar show/hide toggle** — binary; restores the last width. The *honest* hide (dragging a column to
  zero is fiddly and easy to do by accident).
- **Drag-to-resize with snap detents** (Comfortable / Wide) — arbitrary width *plus* muscle
  memory. *(Amendment 2 dropped the original Peek rung: at its minimum width the Playbook collapsed to a
  degenerate sliver with no content floor mirroring the Directions floor, and the toolbar toggle already owns
  the honest hide — so a near-hide detent was redundant and broken. Two detents + the binary toolbar-hide is
  the Xcode/VS Code grammar without the broken corner.)*
- **A hard minimum on Directions** — the readability floor; snaps must never crush instruction line-length.
- **Persist the width** so it reopens where you left it.

*Implementation note:* the persistent Playbook likely becomes a real structural column, while **Ask and Browse
Recipes stay `.inspector` slide-overs on top** (two competing inspectors is the thing to avoid). To prototype
against a device — do not treat the exact detent widths as decided here.

### Menu: Dishes are the Body, the Playbook is the companion

This **reverses D4**. The prep plan is no longer "the primary middle column," and the third column is no longer
"deleted." Instead: **Dishes + placements = Body** (main pane), and **Prep Plan + Learnings + ChatGPT handoff =
the Playbook companion** — the *same* column concept as the recipe. This is what fills the dead space, keeps the
dishes always in view, and makes recipe and menu share one spatial grammar.

D4's real insight survives, demoted from a forced mode to a **soft default**: on or after the service date, the
Playbook simply *opens at a narrower detent* so the Dishes get the emphasis — **never forced, always draggable
back** (honoring "never invisible unless I want it"). OQ3's **collapsible days stay** as-is. The service date
sets the *default* emphasis; it never takes the choice away. **D4 as shipped stands in the tree until this
lands — nothing here forces a revert.** ([[prep-plan-horizon-redesign]] density gets its first co-visible test
here; watch the band list in a companion-width column.)

### Ask stays the slide-over (reaffirmed)

Unchanged from D3 / Amendment 1: **Ask is the chat-of-last-resort** — the quick-one-while-I'm-panicking. It is
**never promoted to a column** and never competes with the Playbook for structural space. Browse Recipes is
likewise a slide-over.

### Recipe header: compact to a single band

> **Corrected by Slice C below (2026-07-16).** Slice A shipped this as a *full-width band above all three
> columns*. That ratified Paprika's **density** but not its **composition** — actual Paprika nests the header
> into the top of the right column, letting Ingredients rise to the ceiling. Slice C fixes the geometry; the
> density lesson here stands.

Dogfooding surfaced dead space at the *top* of the recipe — a tall, spread header pushing Directions down.
This matters more now that Directions is a co-visible column whose vertical space is precious. Match a tight,
Paprika-style band (title · source · servings · thumbnail); density is craft, not a concession — the
differentiation lives in the Playbook, not in the header's air.

- **View Original → toolbar.**
- **Remove the recipe "Start Cooking" entry point.** It is one entry into a **shared** cook-session engine:
  `CookSessionView` is a single `TabView` over its items (`CookSessionView.swift:101`) — the recipe opens it
  with *one* item (the 40pt step-by-step Jon won't use); Menu/Calendar "Cook these" open the *same* view with
  *many* (the tabbed flow that stays and earns its keep). So the burial is **surgical**: delete
  `startCookingButton` (`RecipeDetailView.swift:549`) and the recipe library's `cookButtonTapped` path
  (`RecipeModels.swift:193`), plus any recipe-only single-item `CookSessionPresentation` init left dead.
  **`CookSessionView` and the Menu/Calendar entry points are untouched.** One clean, greppable removal commit —
  git is the archive, no live mothball ([[automation-decays-near-the-stove]]).

### Recipe header (Slice C): nests beside Ingredients — the real Paprika composition

Living with Slice B's three columns exposed the mis-ratification above: a *full-width band* still spends the
whole recipe's top edge on identity, and — now that all three columns are co-visible — it pushes **Ingredients,
Directions, *and* Playbook** down in lockstep. Paprika never does this. In Paprika the header is **column-scoped**,
nested at the top of the Directions side (thumbnail · title · rating · source · servings/last-prepared), and
**Ingredients starts at the very top-left.** That is the composition we meant; the band was a misread of it.

**The correction (13" is the target; compact unchanged):**

- **Kill the full-width band and the divider under it.** The two-column branch of the reader is now just the
  three columns filling full height (`RecipeReaderView.body`, `RecipeDetailView.swift:264`; drop the outer
  `VStack` + `header`/`metadata` band + `Divider` at lines ~269–279).
- **The header nests at the top of the *Directions* column only** — spanning Directions' width, scrolling with
  it. Not Directions + Playbook: keeping it Directions-scoped ties **identity + method** together and lets the
  **Playbook stay top-anchored** (Ask · Make-ahead · Notes rise to the ceiling instead of below a strip). This
  was the one fork; Jon chose Directions-only.
- **Ingredients and Playbook both rise to the top edge.** No strip above them. This is the vertical reclaim the
  band only half-delivered — and where Directions' precious column height ([[automation-decays-near-the-stove]]:
  space near the stove) actually comes back.
- **Cheat Ingredients narrower.** It was a fixed `⅓` (`contentColumnFraction`, `RecipePlaybookColumnLayout.swift`).
  Drop it below ⅓ (a knob to tune on device, not a decided point width — same discipline as the detents). The
  Directions-floor math in `RecipeWideColumnLayout` keys off this fraction, so a narrower Ingredients *widens*
  the Directions floor and the Playbook's max — verify the three still reconcile at the Wide detent.
- **Photo grows into the taller header box.** Beside a full-height Ingredients column the header can be taller
  than a top band allowed, so the cover photo grows **past Paprika's stamp size** (`HeaderMetrics` cap,
  `RecipeDetailView.swift`). This is a *deliberate* departure from Paprika's tiny thumbnail — recorded so it
  doesn't later read as drift.
- **No schema or migration.** Pure view-composition; `@AppStorage` keys from Slice B are untouched.

**Watch on the device pass:** the header now lives in the column whose width *varies most* — at the **Wide**
Playbook detent, Directions shrinks to its floor and the nested header gets tight (title wraps harder, photo
competes). That's the cost of Directions-only placement. Confirm the header still reads at Wide; if it collapses,
the fallback is a scale-with-width header, **not** a retreat to the band.

### Parked — refinement, not this amendment

- **Active scale factor is invisible on a scaled recipe.** Servings shows, but the ×2 does not — it wants a
  glanceable badge. A later polish sweep, deliberately kept off this 10,000-foot amendment.

### What this supersedes

- **Amendment 1 OQ2** (Cook/Plan toggle on wide) — the toggle is gone on wide; it survives only as the compact
  picker.
- **Amendment 1's divider-retirement rationale** — moot; the Playbook is a sized companion, not a same-pane
  mode blend, so resizability is not the "any blend" that was retired.
- **D4** ("third column deleted," "prep plan keeps its primary middle-column placement") — the menu gets the
  Body + Playbook grammar; the launcher insight survives as OQ3's collapsible days + the soft-default detent.
- **Slice A's full-width header band** — corrected by Slice C to the column-nested (Paprika) composition; the
  band's *density* lesson survives, its *geometry* does not.

### Unifying principle (updated)

> **Enrichment is always available and never forced away.** The body is what you execute; the Playbook is the
> context you keep beside it and *size to the moment*. Key the *default* emphasis off a date when there is one
> (menu) and off the user's own hand when there isn't (recipe) — but never take the choice away.

### Still open (prototype, don't pre-decide)

- Exact detent widths, and whether Ingredients also collapses on an 11" iPad (13" is the target, so this is
  secondary).
- Whether the Playbook width persists **per-surface** (recipe vs. menu — their content densities differ) or as
  one shared preference.
- Coexistence of the persistent Playbook column with the `.inspector`-based Ask/Browse slide-overs.

## Related

- [ADR-0038](ADR-0038-external-llm-handoff.md) + **Amendment 1** (Deliverable + Learnings — the content this
  column exists to hold), ADR-0034 (prep plan / horizon bands; D5 constrains it), ADR-0021 (variations),
  ADR-0023 (adjustments), ADR-0024/0026 (human as final author; the review sheet), ADR-0011 (in-app chat).
- Memory: [[yeschef-onbard-model-tier]] (why the in-app chat survives as the quick tier),
  [[personal-app-latency-tolerance]], [[llm-vs-determinism-surface-boundary]] (D5 is its cousin — the axis
  here is *abstraction vs. context*, not determinism), [[prep-plan-horizon-redesign]],
  [[macos-longterm-target]].
