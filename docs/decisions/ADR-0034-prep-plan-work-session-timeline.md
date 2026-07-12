# ADR-0034 — The prep plan is one weaveable, work-session timeline

> **Vocabulary:** a *menu prep plan* is the staged, editable make-ahead document for one multi-day menu
> ([ADR-0012](ADR-0012-menu-actionable-chat.md)'s "Build prep plan" verb), stored as a JSON blob on
> `Menu.prepPlan` and shown in the **Prep Plan** section of the menu detail screen. A *step* today is
> `PrepPlanStep{when, task, sourceDish}`. This ADR reshapes that step and the verb behind it: from a
> **strict roll-up** of per-recipe Make-Ahead notes, sliced by *how far ahead of service*, into a
> **weaveable work-session timeline** — grouped by *when you're in the kitchen*, with every task tagged by
> the meal it feeds.

Status: **Accepted** — 2026-07-12 (Proposed 2026-07-12). Origin: Jon's 2026-07-12 dogfood conversation. **Supersedes the
"prep-plan stays strict" disposition** from [[menu-planner-dogfood-2026-07-09]] (the roll-up-only,
"do not invent" contract). Design capture: [[prep-plan-horizon-redesign]]. **Extends
[ADR-0011](ADR-0011-actionable-chat-make-ahead.md)/[ADR-0012](ADR-0012-menu-actionable-chat.md)** (the
`(extract → review → commit)` apply-action and the menu prep-plan verb) and rides
[ADR-0026](ADR-0026-review-collection-sheet.md)'s review sheet unchanged. Holds the
[[llm-vs-determinism-surface-boundary]] line: prep is **advisory**, read-only guidance a human edits
before it matters, so LLM invention is appropriate here (unlike the deterministic grocery merge).
Sync-safe by construction — the blob already syncs ([[sqlitedata-blob-cloudkit-asset]];
[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)).

## Context

Three observations from the dogfood pass, in Jon's words:

1. **The roll-up is tedious and it errors.** "Build prep plan" composes only from each dish's *stored*
   Make-Ahead field and is forbidden to invent (`MenuPrepPlan.instructions`: "Do not invent or rewrite
   per-dish make-ahead prose"). When no dish has a Make-Ahead note the model correctly returns
   `{"steps":[]}` and the app raises "No prep steps to build." So the plan is only as good as prior
   per-dish authoring, and the failure mode is an error. Meanwhile, **ignoring the verb and just asking
   the chat "make a plan for this day" works beautifully** — because free chat is unconstrained. Jon wants
   that inventive plan *as the verb*.

2. **He couldn't find where the plan "shows up."** It has a real home — the Prep Plan section on menu
   detail (`MenuViews.swift`, gated `if !steps.isEmpty`) — but between the strict verb erroring (section
   stays empty → hidden) and Jon living in the meal *calendar* (where the parallel
   `MealPlanMakeAheadStrategy` verb dumps its output as a **note item mixed into the day's dish list**,
   with no pane at all), he'd never seen it populated.

3. **"How far ahead of service" is the wrong axis for a multi-day menu.** A menu has many dishes across
   many meals, so every dish has its own service moment; "2 days before" is "2 days before *which* meal?"
   Bands measured against a single service force the human to visit each day and mentally interleave.
   What Jon actually wants: *"Wednesday evening: roast tonight's cauliflower, salt tomorrow's beef, make
   Friday's salsa."* One work session, tasks spanning several future meals, the interleaving done **for**
   him. Notably this is exactly how the LLM's own free-chat plan organized itself (by working day, each
   task noting what it feeds).

The prep plan is therefore **one document per menu** (never one-per-day), and its natural spine is the
**work session**, not the service horizon.

> The meal-calendar per-day `MealPlanMakeAheadStrategy` note verb is the wrong-shaped twin of this feature
> (per-day, dissolves into the dish list). This ADR makes the **menu** the home; realigning or retiring
> the calendar note verb is noted as deferred cleanup, not built here.

## Decisions

### D1 — One plan per menu, home is the menu-detail Prep Plan section

The prep plan stays a single blob on `Menu.prepPlan`, rendered in the existing Prep Plan section. Not
per-day, not on the calendar. Jon's "prep tomorrow's meat today" observation is the proof: tasks are
relative to future *meals*, not to the wall-clock day you do them, so a per-day home is structurally
wrong. The human authors, reads, and executes from this one surface.

### D2 — The step is reshaped: `session` + `serves` + tappable link

`PrepPlanStep` moves from `{when, task, sourceDish}` to:

- **`session: String`** (replaces `when`) — the work block: "Anytime, get ahead", "Sunday–Monday",
  "Wednesday evening", "Saturday · ~3 hrs out", "At service". Free-form label, **not a fixed enum** — the
  earlier "7 horizon bands" idea is retired here because real session labels ("Saturday ~3 hrs out")
  don't fit a fixed vocabulary. A sub-timing can live inside the label ("~3 hrs out", "25 min out").
- **`task: String`** — unchanged, the concrete kitchen task.
- **`serves: String?`** — new. The human-readable meal/day this task feeds ("tomorrow's beef", "Fri taco
  night"). This is the annotation that kills the mental interleaving — a mixed-meal work session reads
  cleanly because each line says what it's for.
- **`sourceDish: MenuItem.ID?`** — unchanged in the model, **newly load-bearing in the UI** (see D4): when
  present it makes the `serves` tag a live link to that dish's recipe. When null (a step spanning dishes),
  the `serves` label renders as plain text.

Steps are grouped into bands by `session`, in **plan-emitted order** (the array order the weave returns),
grouping consecutive same-session steps. A session labeled "Anytime"/"Flexible"/"Get ahead" sorts to the
top by convention. No chronological sort key is stored — order is the LLM's, editable by the human.

### D3 — The verb becomes a weave, not a roll-up (retires "do not invent")

Loosen the prompt: compose from stored per-recipe Make-Ahead notes **when present, and invent sequencing,
work sessions, and new prep steps** grounded in the menu's dishes and the conversation — emitting
`session` and `serves` for each step. Keep [ADR-0012](ADR-0012-menu-actionable-chat.md)'s
"current plan is the artifact being edited → return the full proposed replacement" contract, which is what
makes **incremental, day-by-day authoring** work: plan Wednesday → save → plan Thursday → the weave merges
it into the existing plan. This reverses the 2026-07-09 strict call deliberately; prep is advisory, and an
inventive editable plan beats a reproducible-but-empty one.

The empty-result path stays (a genuinely empty plan is still valid), but it stops being the *common* case,
so the "add Make-Ahead detail to the dishes" empty message is no longer the primary story.

### D4 — Banded, collapsible display; tappable `serves`; timing in the sub-labels

The flat checklist becomes **collapsible session bands** — all collapsed by default, a per-band step
count on the right, tap to open one. This is the reconciliation of the two modes in one surface:

- **Bird's-eye:** all bands collapsed = the whole arc at a glance.
- **"The heat is on":** collapse to the session you're in (e.g. "Saturday · ~3 hrs out") and it fills the
  screen as a countdown checklist — *provided* the weave (D3) orders that final session's steps by
  descending time and puts the minutes in each sub-label. That ordering is free from the prompt/array
  order; no new machinery.
- **No scrolling to piece it together:** the `serves` tag is a **live link** — tap
  `→ chicken fajitas` and you're in that recipe. This is the specific answer to "is go-time close enough
  to my menu items" — one tap from a prep step to the dish, no hunting between "the plan" and "the
  recipes." Data's already there (`sourceDish`); D4 just wires the tap.

### D5 — Clipboard both ways (the ChatGPT escape hatch)

- **Copy dish context out:** a button that dumps the already-built serialized `MenuChatContext`
  (`MenuChatContext.serialized`) to the clipboard, so the human can paste it into an external LLM and
  spend *those* tokens instead of ours.
- **Paste free text in:** the Prep Plan pane accepts a pasted free-text plan as its body. Because the plan
  already round-trips through editable review text (`MenuPrepPlan.editableReviewText` /
  `applyingEditableReviewText`), an imported plan can seed the document; the weave verb (D3) can then sort
  it into sessions / add `serves` tags on a later pass.

**Amendment 1 (2026-07-12) — the exported context is the _frontier_ view, with full method.** Dogfooding
D5 surfaced that "Copy dish context" reused `MenuChatContext.serialized()` at the **on-device 12k-char
budget** (~3k tokens), whose degradation ladder trims key ingredients to zero, truncates make-ahead notes,
and finally **drops whole dishes** — so on a real menu the pasted plan referenced dishes the external LLM
never saw. And recipe **method steps were never in the context at all**, starving the LLM of the
prep-ahead signal that lives in the method ("chill overnight", "salt the day before"). Since the entire
point of the escape hatch is to spend _their_ tokens, and a full menu with method is only ~2–18k tokens
(well under the 120k-char frontier budget), the copy-out now serializes at **`serialized(for: .frontier)`**
and the serialization carries **full recipe method** (fetched via `InstructionStep`, section-then-step
order, `InstructionSection.name` as a sub-header when a recipe has >1 section). Method is a **new trim rung
cut _first_** in `budgetedSerialization`, so the _shared_ on-device chat path is essentially unchanged
(method drops immediately under 12k) while the frontier export keeps everything. Export-only enrichment;
the on-device weave verb (D3) is untouched. → slice **S3c**.

## Deferred (on the record, explicitly not built here)

- **Calendar real-date anchoring.** Pin a menu to actual dates → resolve free-form session labels
  ("Wednesday evening") to real weekdays, and make "collapse to now" *automatic* (the app knows which
  session is current). Pre-anchoring, sessions are labels and there is no auto-"now" — all bands start
  collapsed, the human taps the one they want. This is the same deferral flagged throughout the design.
- **Cook mode.** A dedicated single-session execution surface: one band filling the screen, giant
  checkable steps, keep-awake, a live countdown ticking against the sub-label times, "next up" peeking at
  the bottom. The banded reader + ordered timing + tappable serves (D4) delivers ~80% of that feeling with
  zero new surface; cook mode is the last 20% and its own milestone.
- **Retire/realign the meal-calendar per-day make-ahead note verb** now that the menu owns the prep-plan
  home.

## Storage sketch

**No schema change.** `Menu.prepPlan` stays a BLOB holding JSON-encoded `[PrepPlanStep]`
(`MenuPrepPlanCoding`). The reshape (D2) is a **JSON-key** change inside the blob:

- Encode the new keys `session` / `serves` (keep `sourceDish`).
- **Back-compat decode:** existing blobs carry `when` and no `session`/`serves`. Decode reads `session`
  falling back to `when`; missing `serves` decodes to nil. Old plans render as single-step-per-band lists
  with no serves tags until re-woven — no data loss, no migration.
- BLOB syncs unchanged as a CKAsset; sync-safe by construction, no CloudKit concern
  ([[sqlitedata-blob-cloudkit-asset]]).

## Cost, honestly — and the slice plan

The verb, storage, review sheet, and Prep Plan section all exist. What's new is the step reshape, the
prompt loosening, the band grouping, the tappable tag, and the two clipboard affordances. Batched:

- **S1 — model + weave (first dispatch, part 1).** Reshape `PrepPlanStep` (`when`→`session`, add `serves`;
  keep `sourceDish`) with back-compat decode. Loosen `MenuPrepPlanClient` instructions to the D3 weave and
  emit `session`/`serves`/`sourceDish`. Update `editableReviewText`/`applyingEditableReviewText` round-trip
  and tests. Nothing visible yet, but everything rides on it.
- **S2 — banded UI + tappable serves (first dispatch, part 2).** `MenuPrepPlanSection` renders collapsible
  session bands (collapsed default, per-band count, plan-emitted order, "anytime" first). `serves` renders
  as a chip; tappable → navigate to `sourceDish`'s recipe when present, plain text when null. This is the
  display that makes S1 legible; bundle S1+S2 as one dispatch (the author-and-read pass).
- **S3 — clipboard (follow-up dispatch).** "Copy dish context" out + free-text paste-in. Small,
  independent; rides after S1+S2. **Shipped** in [#164](https://github.com/jonphillips/yes-chef/pull/164)
  (also folded in the parse-robustness `session`←`when` fallback).
- **S3c — enrich the exported context (Amendment 1, follow-up dispatch).** Copy-out serializes at the
  frontier budget and the serialization gains a full-method block with a method-first trim rung. Core
  plumbing (`MenuDetailRequest` fetch of `InstructionStep`/`InstructionSection`, new `recipeMethodLines` on
  `MenuItemRowData`, `method` on `MenuChatItemContext`, per-dish `Method:` render + trim rung in
  `budgetedSerialization`) + one app-layer line (`.serialized(for: .frontier)`). Follows S3.

Follow the [[batch-slices-and-lean-handoff]] default: S1+S2 is one Codex dispatch; S3 follows. Build brief
to live at `efforts/adr-0034-prep-plan-work-session-timeline.md` when dispatched.

## Open questions

- **OQ1 — session grouping when the human hand-edits.** Editable review text is line-based
  (`applyingEditableReviewText`). How does a hand-edited plan re-associate lines to sessions — a
  `session:` header line per band, or a per-line prefix? *Lean:* header line per band (mirrors how the
  bands read), parsed back on commit. Confirm during S1.
- **OQ2 — `serves` when `sourceDish` is null.** Plenty of steps span dishes or feed a meal generally. The
  chip is then a plain non-tappable label. Confirm that reads fine (no dangling link affordance) and that
  the weave is comfortable emitting `serves` prose without a dish ID.
- **OQ3 — does the weave need the stored per-recipe Make-Ahead at all now?** D3 says "compose when
  present, else invent." Confirm we still pass the per-dish Make-Ahead notes in context (we do, via
  `MenuChatContext`) so the weave *prefers* the human's authored notes over inventing from scratch —
  invention is the floor, not the default.

## Related

- ADR-0011/0012 (the apply-action + menu prep-plan verb this reshapes), ADR-0026 (the review sheet it
  rides), ADR-0002 (sync-by-blob), ADR-0022 (the determinism boundary this stays on the advisory side of).
- Memory: [[prep-plan-horizon-redesign]] (the design capture), [[menu-planner-dogfood-2026-07-09]] (the
  superseded strict call), [[llm-vs-determinism-surface-boundary]], [[llm-curation-not-synthesis]],
  [[batch-slices-and-lean-handoff]], [[sqlitedata-blob-cloudkit-asset]].
