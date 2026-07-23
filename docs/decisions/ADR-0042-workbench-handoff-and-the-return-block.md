# ADR-0042 — The workbench hands off: deliberation outboards, structured writes stay in, and the return block is a terminal turn

> **Vocabulary:** the **return block** is the delimited payload a chat app emits on the *last* turn of an
> outboarded session (`YC-HANDOFF:` / `YC-LEARNINGS:`, ADR-0038) — **not** the shape of the conversation
> that produced it. A **deliberation surface** is one whose product is *judgment* (comparison, rationale,
> experiments, ideas); a **structured canonical write** is one that mutates typed recipe data (ingredient
> lines, instruction steps, variation deltas). This ADR says the first outboards by default and the second
> never does, and it pins what the return block may and may not contain.

Status: **Accepted** — 2026-07-20 (Jon ratified; D1/D4/D8 hand-validated end-to-end by the OQ6 live run,
all OQs resolved except the non-gating Claude-portability check). Opened Proposed the same day (architect +
Jon, in the "re-empower the workbench for the all-you-can-eat chat apps" conversation).
**[Amendment 1](#amendment-1--the-ask-outboards-a-revision-brief-returns-and-the-in-app-extractor-still-writes-the-delta-2026-07-21)
— Accepted 2026-07-21 (Jon ratified; S4 is the dispatch target).** The recipe body gets an export door; a
prose *revision brief* returns and feeds the shipped in-app extractor — schema-free, no contract bump, and
D2 held by keeping identity off the paste door. **Its prompt is hand-validated end-to-end (2026-07-21):
shape, terminal turn and the `YC-CONTRACT: v2` echo all held, and Amd1-OQ1 resolved to keep learnings with
a re-aimed ask (Amd1-D7).** S0/S1 shipped in [#212](https://github.com/jonphillips/yes-chef/pull/212), S2
in [#214](https://github.com/jonphillips/yes-chef/pull/214) (device-passed 2026-07-21). **Extends
[ADR-0038](ADR-0038-external-llm-handoff.md)** (the hand-off core, its
in-app Copy/Paste door in Amd 2, and the `Learning` typed home in Amd 1) by adding the **workbench** as a
hand-off source and by writing down the return-payload contract that ADR-0038 left implicit. **Governed by
[ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md)** (the grain principle decides which returns may
be prose and which must be pinned). **Amends the slice plan of [ADR-0023](ADR-0023-recipe-edit-proposals.md)**
(retires its S3 in-app refine loop, promotes its S3 workbench-log deposit) and **of
[ADR-0019](ADR-0019-recipe-design-studies.md)** (its S3 `Workbench.experiments` BLOB is superseded by
`workbenchLog` rows). Holds the [[llm-vs-determinism-surface-boundary]] line and applies
[[llm-curation-not-synthesis]] to every return shape here.

## Context

**The direction changed, and the docs hadn't caught up.** Everything the workbench does — compare
candidates, draft a working recipe, propose experiments — lives in the **in-app, API-driven chat**. That was
the only option when ADR-0019 and ADR-0023 were written. Since then the external hand-off (ADR-0038) has
shipped and been dogfooded across four surfaces (make-ahead, Chef It Up, Serve With, menu prep plan), and
the all-you-can-eat chat apps give effectively unmetered high-effort reasoning **and a live thread you can
argue with**. The workbench is the most deliberation-heavy surface in the app and has **zero** hand-off
wiring: `AIHandoffSourceType` is `recipe · menu · mealPlan`.

**The `conversationURL` dead end changed the frame but not the direction.** [ADR-0038 Amd 3 is
withdrawn](ADR-0038-external-llm-handoff.md#amendment-3--an-optional-user-pasted-conversationurl-to-reopen-the-live-chat-2026-07-15):
ChatGPT exposes no live `/c/` link and no URL scheme, so we cannot deep-link back into a session. That is a
real loss for *returning* to a thread — it is **not** an argument against outboarding, and it may change if
OpenAI ships one.

**We have already run this experiment badly once, and that failure is the whole reason this ADR exists.**
In ADR-0041 S2.5 (`3cf2880`), the Playbook handed off in `.discuss` mode, which never emits a
`DeliverableFormat.example` — so the blob sections' only shape signal was "plain, paste-ready review text."
ChatGPT answered with a **report**: headings, nested Markdown bullets, and an assessment of what the recipe
already did well. The flat-list renderer prefixed the whole thing `• ` line by line. Serve With was spared
only because its contract lived in its own section prompt. The fix was to pin the shape in the prompt, where
it holds regardless of mode. **The lesson generalizes:** the model stayed in *interlocutor* mode when it
should have switched to *emitting a value*, and nothing in the prompt told it to switch.

## Decisions

### D1 — The return block is a terminal turn, not the shape of the conversation

The point of outboarding is to converse: argue, push back, iterate, change your mind. **None of that is
constrained by this ADR.** The contract binds exactly one turn — the one where the human says "emit the
return block." That turn behaves like a **function return**: it emits a value and nothing else. Every
failure so far (S2.5's report; the pre-format-pinning Serve With junk) is the model remaining a good
conversational partner past the point where a partner was wanted.

**The mechanism already exists** — ADR-0038's `YC-HANDOFF:` / `YC-LEARNINGS:` markers delimit the payload.
What was missing is not transport but **discipline about what is allowed inside the markers**, which is D4.

### D2 — Outboard deliberation; structured canonical writes stay in-app (ratified)

The axis is **not** "LLM vs. deterministic" ([[llm-vs-determinism-surface-boundary]] already drew that one)
and **not** "in-app vs. external." It is **advisory prose vs. structured write**:

- **Outboards by default:** anything whose product is judgment — comparison, rationale, experiments, ideas,
  critique, planning prose. The return lands in a text field a human reads, or in a small pinned list they
  review item-by-item. A bad item costs one delete.
- **Never outboards:** anything that mutates **canonical recipe data** — ingredient lines, instruction
  steps, ADR-0021 variation deltas. These carry **identity** (`id` / `sectionID` / `sortOrder`), and
  ADR-0021 variation anchors bind to base-ingredient identity. A wrong identity is a *silently corrupted
  recipe plus orphaned anchors*, not a visible junk line — and re-parsing returned prose into the closed op
  vocabulary is precisely the "human authors the wire format" failure [[editable-at-the-grain-stored]]
  names. [ADR-0041 OQ5](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) already refused the
  whole-recipe-blob version of this on the same grounds.

**Consequence for `adjustRecipe`:** the task type is *declared* in `AIHandoffTaskType` but its import path
is `case .prepPlan, .adjustRecipe, .mealPlanMakeAheadStrategy: throw .wrongTask` — an unwired placeholder.
**It stays unwired.** Adjust-recipe's *ideation* may be outboarded as ordinary discussion ("how would you
rethink this braise?"); its *write* remains the in-app structured verb (ADR-0023 S1/S2, shipped). Do not
build a paste-back that lands a delta.

### D3 — Prose is welcome exactly where it terminates in a human-read text field

The corollary that decides, per deliverable, whether to pin a format:

- **Terminates in a text field a human reads** (a `workbenchLog.body`, a note) → **no format needed.** The
  judgment *is* the payload; there is nothing to parse and therefore nothing to lose.
- **Feeds typed fields** (a `{hypothesis, change, rationale}` triple, a `title: note` pair) → **pin the
  format**, and parse **lossless-or-loud** per ADR-0040.

This is why the log deposit is the cheap half of this ADR and the experiments list is the half that needs a
round-trip proof (OQ1).

### D4 — The contract lives in the chat app's project instructions, generated from Core — not bundled into every prompt

**The prompt is the wrong home for the contract, and the code says why.** `AIHandoffPrompt` is asymmetric:
`.immediate` ends with *"Use this exact format:"* followed by a literal `deliverableFormat.example`, while
`.discuss` gets `discussInstruction` — **a single clause with no example at all** (`AIHandoff.swift:473` vs
`:483`). Discuss mode has always carried the weaker contract, and **that asymmetry is the S2.5 root cause**:
the blob sections' only shape signal was "paste-ready notes," so ChatGPT returned a report. `3cf2880` routed
around it by pinning the shape in two per-section prompts; **the structural gap was never closed.** Adding a
`workbenchExperiments` format case would inherit that same one-sentence discuss instruction — for a shape
*three times* more structured than the one that already broke.

Bundling more text into each prompt does not fix it either: the contract is then restated per verb (drift),
re-sent per hand-off (bloat), and still has to survive an arbitrary number of conversational turns before
`finalize` retrieves it.

**Decision: the contract is stated once, persistently, in the chat app's project custom instructions.** The
prompt shrinks to token + context + the verb's ask.

- **Custom instructions are the ceiling, confirmed (Jon, 2026-07-20):** the ChatGPT **iOS** app cannot take
  an uploaded skills/instructions *file*. Plain pasted project instructions are the most durable host
  available on the surface where the work actually happens — the same "the mobile app defines the ceiling"
  lesson as the withdrawn `/c/` URL. Portable: Claude projects take custom instructions too.
- **One shared "Yes Chef" project to start (Jon's call), not per-source.** This deliberately diverges from
  [ADR-0038 OQ6](ADR-0038-external-llm-handoff.md)'s per-source anchor, on the observation that **a menu has
  a natural end** — the service date passes and the deliberation is done, so the thread drifting down the
  list costs nothing ([[mode-trigger-date-vs-toggle]]). **If one project ever gets painful, split on the
  sources with long lives — the recipe and the workbench study — not on menus.** `Menu.externalProjectName`
  stays; it is now an override, not the default.
- **The app generates the instruction text from one Core constant** — the same source the parser and the
  prompt serializer read — surfaced as a **copy button in Settings**. This is what keeps a hand-pasted blob
  of config that lives outside version control from silently diverging from the parser.
- **A version marker makes drift loud.** The generated instructions carry a contract version and the return
  block echoes it (`YC-CONTRACT: v<n>`). The app knows what it expects: a stale paste returns an old
  version, a missing paste returns no marker, and **both are caught** — surfaced as "your project
  instructions are out of date, re-copy from Settings." Without this, config drift is exactly the silent
  wrong-shape failure ADR-0040's lossless-or-loud rule exists to prevent. **Do not also restate the format
  in the prompt:** two copies can contradict after an edit, and the marker already reports when the one
  remaining copy is stale.

**The prohibitions, compressed to those with evidence behind them** (pasted text has a length budget, and a
sprawling list is both less pasteable and less followed):

- **No preamble, sign-off, headings, or nesting.** *(S2.5.)*
- **No assessment of what is already good.** *(The S2.5 defect by name — the one the model most wants to
  produce, and the one the OQ1 run confirmed it will suppress when told.)*
- **No merged summary where distinct items were requested** ([[llm-curation-not-synthesis]]).
- **No partial credit** — if a field cannot be filled, **omit the item** rather than fabricate one.

Dropped as defensive rather than evidenced: *no recap*, *no emphasis markup* (the parser already strips
`**`/`*`, and `learningBullets` accepts `-`/`*`/`•`). **No ranking** moves to the per-verb ask, since it is
only meaningful where a verdict was plausible (compare).

### D5 — The workbench becomes a hand-off source, with three deliverables of deliberately different shapes

`AIHandoffSourceType` gains `.workbench`. Three task types, **not** equally ready:

- **Compare candidates (`workbenchCompare`).** The return is **not** a per-recipe walkthrough —
  `WorkbenchCompareCore` already aligns candidates on canonical name and renders that better than prose can,
  and restating the matrix in sentences is pure noise. What is wanted is what the matrix *cannot* produce:
  a handful of **named differences with a claim attached** — *"hydration: 65% vs 78%, and that is why #2 has
  the open crumb."* One per line. Advisory and read-only, so it sits on the safe side of
  [[llm-vs-determinism-surface-boundary]]. **Commit shape:** deposit as `workbenchLog` `.observation` rows,
  or no-commit advisory ([[chat-verb-commit-shapes]] — classify at slice time).
- **Experiments (`workbenchExperiments`).** ADR-0019 already specified `{hypothesis, change, rationale}`.
  One experiment per block, each field individually parseable, because each lands in a typed field. **Wire
  shape settled by hand-run (OQ1 + OQ6): labeled three-line blocks — `Hypothesis:` / `Change:` /
  `Rationale:`, in that order, one sentence each.** Labels beat a pipe-delimited line because the review
  sheet is text the human *reads and edits* before commit (ADR-0024), so the wire format must be legible to
  a person, not only to a parser — and a dropped label is loud rather than silent. **The parser splits
  blocks on the label cycle (a new `Hypothesis:` opens a block), never on blank lines** — OQ6 proved
  whitespace does not survive the paste path. **Emits no learnings — see D8.**
- **Draft a working recipe (`workbenchDraft`) — DEFERRED, and deliberately last.** A drafted recipe is
  structured canonical data, which D2 says does not come back through the paste door. It is *less* severe
  than adjust-recipe (creating has no IDs to preserve and no variation anchors to orphan, and the existing
  capture parser could take it), but it is still the sharp edge. If it is ever built, it lands as a
  **reviewable candidate**, never straight into the working recipe, and the **rationale returns as a
  separate block** — never smeared into the ingredient list as parentheticals, which is the same
  human-as-wire-format failure in miniature.

### D6 — The workbench log is how thinking returns (the `Learning` analogue)

ADR-0038 Amd 1 gave the recipe hand-off a two-part return: the deliverable **plus** durable learnings. The
workbench's equivalent is the **`workbenchLog`** — and it matters *more* here, because once deliberation
happens in a thread we cannot deep-link back into (Amd 3, withdrawn), **the log is the only thing that
survives the session.** An outboarded compare or experiment set that deposits nothing is a conversation that
never happened.

This **promotes** the half of ADR-0023 S3 that was previously a footnote: a committed adjustment on the
workbench drops a `.rationale` / `.experiment` entry. Same mechanism, now load-bearing.

### D7 — ADR-0023's in-app iterative refine loop is retired, not deferred

ADR-0023 S3's first half — keep chatting to revise a *live* proposal, re-extracting each turn — was the
conversational editing loop originally asked for. **Under D1/D2 it is unwanted, not merely unscheduled.**
Refinement in a live thread is free, better-reasoned, and unmetered; an in-app multi-turn proposal loop
would be a worse copy of it, and would have had to answer two questions it never did (what the delta anchors
to on turn two; where the conversation lives while a full-screen review is up). Recorded as **withdrawn**
so it is not rebuilt on the momentum of the old slice plan — the [[withdraw-not-defer-orphaned-schema]]
lesson, applied one week later to a non-schema slice.

**What survives it:** ADR-0023 S1/S2 (the verb, the preview, the side-by-side, both commit destinations)
are shipped and unaffected. The in-app verb remains the *only* path that writes a delta (D2).

### D8 — The two-part return is not universal: the experiments verb emits no learnings

ADR-0038 Amd 1 made every hand-off return two parts — the deliverable **plus** `YC-LEARNINGS:`, durable
knowledge *established during the discussion*. **That contract does not hold for `workbenchExperiments`, and
the OQ1 hand-run proved it empirically:** three of the four returned learnings were the experiments' own
hypotheses and rationales restated as established fact ("Brown butter is a compatible variation that deepens
flavor"). Only one was general technique.

This is **structural, not a prompt-tuning miss.** An experiment is a *conjecture*; nothing has been
established at proposal time. Emitting learnings there would write untested guesses into the synced
`Learning` table as durable facts about the recipe — precisely the pollution [[llm-curation-not-synthesis]]
and ADR-0040's lossless-or-loud instinct exist to prevent, and worse than noise because the store's whole
value is that its contents are *known*.

**Decision: `workbenchExperiments` omits the `YC-LEARNINGS:` section from its outbound prompt and ignores it
if returned.** The experiment already has the correct home for knowledge — its **`outcome`**, filled in after
the thing is actually tried. **An experiment is a pending learning, and recording its outcome is what
promotes it.** Emitting a learning at proposal time short-circuits the try-then-know lifecycle the log exists
to capture.

**Scope:** experiments only. `workbenchCompare` may legitimately establish something during discussion and
keeps the two-part return. **Generalization for future verbs:** ask whether the deliverable is *findings* or
*conjecture* — conjecture-shaped verbs suppress learnings.

### D9 — Threads carry a structured title, and the title is advisory only

With **one shared Yes Chef project** (D4) threads accumulate, and since the `/c/` deep-link is dead
([ADR-0038 Amd 3, withdrawn](ADR-0038-external-llm-handoff.md)) **finding a thread by name is the only
reopen affordance left.** A predictable title recovers part of what that withdrawal cost, for free.

**Shape: `<TaskType>: <Object name>`** — `Chef It Up: Boiled Broccoli`, `Prep Plan: Jack's Birthday`,
`Experiments: Chocolate Chip Cookies`, `Compare: Chocolate Chip Cookies`. **The left side is the task, not
the object kind** (Jon's first sketch was `Recipe: …`): ADR-0041 made recipe hand-offs **section-scoped**, so
one recipe can have three live threads at once and `Recipe: Boiled Broccoli` would name all three
identically. Task type is unique per hand-off and already on the `AIHandoff` record, so the title is derived,
never authored. The cost is that the title no longer says "this is a menu" — accepted, since the object name
carries that in practice.

**Mechanism — unresolved, and it must not become load-bearing.** The OQ6 hand-run disproved the obvious
approach: a title-shaped **first line** is *not* mirrored by ChatGPT's auto-titler (opening line
`Experiments: Chocolate Chip Cookies` → actual title *"Explore Cookie Experiments"*). ChatGPT claims, when
asked, that it can set a title on request; **treat that as unverified** — models routinely assert
capabilities they lack. So: ship the title-shaped first line **and** an explicit request in the project
instructions, and take whichever works.

**Whatever happens, the title is a human affordance for finding a thread — never a data channel.** Routing
is the `YC-HANDOFF:` token's job and already works. **Nothing parses the title, and no behavior depends on
it**, so a failed or paraphrased title costs discoverability, not correctness. Do not add a fallback that
reads it.

## Amendment 1 — the ask outboards, a *revision brief* returns, and the in-app extractor still writes the delta (2026-07-21)

**D2 is upheld, not weakened — but D7 subtracted a half and nothing was ever built to replace it.** D7
retired ADR-0023 S3's in-app refine loop on the stated premise that *refinement happens in the live external
thread*. That premise was never wired: there is no way to get a recipe's **body** out to such a thread, and
no way to get the result of arguing about it back. This amendment builds the missing half, at the only place
it can go without touching D2 — **the ask goes out, prose comes back, and the structured write is still
authored in-app against live rows.**

### The gap (from the code, not from a want)

- **`.adjustRecipe` is unwired in both directions.** Declared in `AIHandoffTaskType`
  (`AIHandoff.swift:55`), but no exporter builds it — `HandoffIntents.swift:159` mints recipe metadata only
  from `PlaybookSectionKind.handoffTaskType` — and the import path throws `.wrongTask`
  (`AIHandoff.swift:887`). D2 named that unwired import and said *stay unwired*. It said nothing about the
  export, and the export is what is actually missing.
- **The recipe body has no hand-off door at all.** ADR-0041 scoped recipe hand-offs to the three Playbook
  sections; `RecipeHandoffContext.prompt(for:)` (`AIHandoffContext.swift:15`) is keyed on
  `PlaybookSectionKind` and takes no other task. So the most deliberation-heavy content in the app —
  ingredient lines and method steps — is the one thing that cannot be outboarded, while make-ahead notes
  can.
- **What that costs in practice (Jon, 2026-07-21).** Hand-copy the recipe into ChatGPT, argue the revision
  out well — then come back and re-state the ask in the in-app chat, where a one-shot metered extractor
  infers a delta from a thin transcript. **The reasoning is discarded at the boundary**, which is precisely
  the loss D7 assumed would not happen.

### Amd1-D1 — The middle term: outboard the ask, return a **brief**, derive the delta in-app

A three-part pipeline, none of it new machinery:

1. **Out:** the recipe body + the cook's question, as an ordinary `.discuss` hand-off.
2. **Back:** a **revision brief** — advisory prose stating a *decided* revision in a cook's language
   (*"take the butter to 120g and brown it; move the salt into the dry mix; rest 20 minutes before
   shaping"*). **Never ops, never IDs, never a rewritten recipe.**
3. **In:** the human edits the brief, then taps once to hand it to the **existing** in-app extractor
   (`RecipeAdjustmentClient`, `RecipeAdjustment.swift:301`), which resolves it into a structured delta
   against live `id`/`sectionID`/`sortOrder`, and lands in the **existing** side-by-side review with the
   **existing** two commit destinations.

**Why this is D2-compliant rather than a loophole:** nothing carrying identity crosses the paste door. The
returned artifact has no anchors to orphan and no line IDs to corrupt; a bad brief costs one edit before
anything is drafted, and a bad draft costs one dismissed review. **The delta is still authored in-app,
against rows that exist, by the component built to do exactly that.**

**And the extraction gets *easier*, not harder.** The extractor's prompt already takes
`selection` + conversation + full recipe context (`RecipeAdjustment.swift:345`). Today it must infer an
intent from a rambling in-app transcript. Given a brief it *transcribes an already-decided change* — the
same job, with the hard half already done by the better-reasoned thread.

### Amd1-D2 — The paste door never carries **identity**; that is the durable form of D2

D3 sorted returns into two bins: *terminates in a human-read field* → no format; *feeds typed fields* → pin
the format. **The brief is a third case** — it lands in a text field a human reads **and edits**, and that
text is then fed to an in-app LLM step that produces the structured write. So:

- **No format is pinned** (it is prose for a person), and
- safety comes not from parsing but from **two human gates** — edit the brief, then review the delta
  side-by-side — plus the structural fact that the write is composed in-app.

**Generalized rule: *prose out, prose back, structure derived in-app, a human gate at each end.*** This is
the shape for any future "the external thread should change canonical data" want. **`workbenchDraft`
(D5/S3) should be revisited under this shape** rather than as a paste-back of a recipe — a drafted recipe
returning as a *brief the in-app draft verb consumes* is a different, safer proposition than a recipe
returning as data.

The invariant worth carrying forward is therefore **"the paste door never carries identity,"** not
"adjust-recipe never outboards." The latter was a corollary, and it was too strong: it conflated the
*write* with the *thinking that decides the write*.

### Amd1-D3 — Learnings stay on, but the D8 test must be re-run against this verb

D8's question is *findings or conjecture?* A brief argued out against a real recipe produces genuine
findings, so the two-part return holds and `YC-LEARNINGS:` stays. **But the D8 failure mode is plausible
here and must not be assumed away:** an untested revision is itself a conjecture, and the OQ6 run showed the
model will happily restate a verb's own proposals as established fact. **Gate on a hand-run** (the OQ3/OQ6
method) before the import slice: if the learnings come back as the brief restated, suppress them per D8.
Recorded as Amd1-OQ1 — **and resolved by the 2026-07-21 hand-run, in a third way neither this decision nor
D8 anticipated: see [Amd1-D7](#amd1-d7--learnings-stay-with-a-re-aimed-ask-resolves-amd1-oq1-hand-run-2026-07-21).**

### Amd1-D4 — Scope: whole recipe body, one task type, and the in-app verb is unchanged

- **`.adjustRecipe` becomes export-capable at the recipe-body scope.** The body is **not** a
  `PlaybookSection` and must not be forced into one — ADR-0041 D5 already refused that for Notes on the same
  grounds. `RecipeHandoffContext` gains a task-keyed entry point beside `prompt(for: section)`; the context
  is the **whole** recipe (no `excludingPlaybookSections:` filter — the Playbook is legitimate context when
  rethinking the dish), plus the taste profile and the known-learnings block the section prompts already
  send.
- **`.discuss` is the default mode.** Arguing is the entire point; `.immediate` remains available for the
  "just tell me" case.
- **The in-app "Revise Recipe" verb stays exactly as it is.** OQ5's answer holds — *complementary, not
  redundant*: the in-app verb distills a live in-app chat, the hand-off exports for a fresh external one,
  and **both converge on the same side-by-side review and the same two commit destinations.** Nothing is
  retired by this amendment.
- **No new `AIPromptPreferenceKind` in v1.** The taste profile carries the standing preference; add a
  per-verb preference only if dogfooding asks.

### Amd1-D5 — The brief is transient; the commit path is untouched

The return routes to a **brief review sheet** — the ADR-0024 editable preview, holding the brief text and
its learnings, with a primary action (*"Draft the revision"*) that calls the extractor and then presents
`presentAdjustmentReview`. From there the flow is the shipped ADR-0023 S1/S2 one: overwrite-with-undo, or
keep as an ADR-0021 variation.

**The brief itself is not stored** — transient and device-local, like the proposal it produces (ADR-0023
D2). A recipe has no `workbenchLog`, so there is no durable home standing ready, and **inventing one is the
wrong reflex**: the durable channel already exists and is `Learning`. On the workbench, where a log *does*
exist, the brief is the natural body for D6's committed-adjustment `.rationale` deposit. Recorded as
Amd1-OQ2 in case dogfooding disagrees.

### Amd1-D6 — No contract bump — and that is the evidence this shape is right

`AIHandoffReturnContract` (`AIHandoff.swift:511`) already says: on finalize, emit the token, echo the
marker, **return the requested deliverable**, include learnings, and obey the prohibitions. **A prose brief
needs no stanza of its own** — unlike experiments, which needed one because they are parsed. So this
amendment ships **no contract change and no version bump**, and no re-paste of project instructions.

Treat that as a **test, not a convenience**: *if a new return would require its own stanza in the contract,
it is structured, and D2 applies to it.* The brief needing nothing but the base contract is the strongest
available evidence that it sits on the advisory side of the line. What the *prompt* must carry is the ask —
state the revision as plain prose a cook could follow; **do not** write ops, IDs, or a rewritten recipe.

### Amd1-D7 — Learnings stay, with a **re-aimed ask** (resolves Amd1-OQ1; hand-run 2026-07-21)

*Method:* the OQ3/OQ6 method — the v2 contract in the project instructions, a real multi-turn argument about
a library recipe (chicken marsala with a rosemary-garlic cream fettuccine), then `finalize`.

**What held, and confirms the amendment's load-bearing claims:** it switched out of interlocutor mode on the
single word `finalize`; the token came first and `YC-CONTRACT: v2` echoed; the brief came back as six plain
one-change-per-line entries, each with its reason attached, **no preamble, no headings, no nesting, and no
assessment of what the recipe already did well.** The shape needs no contract stanza — **Amd1-D6 confirmed
in the shape we would ship.**

**What recurred — the D8 pattern, but only partially.** Of five learnings, **three were the brief restated
as fact** (brown the mushrooms; fold the parmesan into the sauce; rosemary at the end) and one was partial.
That is the pollution D8 named: unverified claims landing in the synced `Learning` table as established
knowledge.

**What broke the tie, and is why suppression is the wrong answer here.** One learning was the best thing in
the return, and **the brief structurally cannot carry it** — *the dish's identity is rosemary, marsala,
mushrooms and garlic cream; spinach, sun-dried tomatoes, bacon, or truffle oil would dilute it rather than
improve it.* That is **argument residue: what was considered and rejected.** It exists only because there
was an argument, it is durable, and unlike an experiment's conjecture it has **no other home** — there is no
`outcome` field waiting to receive it. D8's experiments could suppress precisely because the knowledge had
somewhere better to go; here it would simply be lost.

**Decision: keep the two-part return, and aim the learnings ask at the residue instead of the deliverable.**
The verb's prompt adds one sentence:

> In the learnings section, record only what was **considered and rejected**, or established as a
> **constraint on this dish** — never restate a change that already appears in the brief.

**This is prompt aim, not enforcement, and it must not be mistaken for a guarantee** — nothing parses
learnings, and a restated learning costs one delete in the review sheet. **Fallback, pinned now so it is not
re-argued later: if a second hand-run still returns mostly restatements, suppress learnings for this verb per
D8** and accept the loss of the residue.

*Generalization for the D8 test:* a verb's learnings survive when the discussion produces knowledge the
deliverable **cannot** carry. Experiments failed that test (the conjecture belongs in `outcome`); the
revision brief passes it (rejected alternatives appear nowhere in a change list).

### Storage — schema-free, and off the promotion list

`AIHandoff` is device-local (not in `makeSyncEngine`'s table list — verified in the main storage sketch), so
adding an export path and an import route for an already-declared task type costs **no tables, no columns,
and nothing on the standing prod-schema promotion list.** The brief is transient; both commit destinations
are shipped writers.

### Slice — S4, after S2 (app + Core prompt, no schema)

- **S4a — the door out.** Task-keyed `RecipeHandoffContext` entry point + the `.adjustRecipe` prompt;
  recipe-body export wired into `HandoffIntents` metadata and the in-app Copy door (ADR-0038 Amd 2); the
  derived D9 title line (`Adjust Recipe: <recipe name>`). **The gate is satisfied — hand-run 2026-07-21,
  see Amd1-D7.** Ship the ask **as tested**, plus the D7 learnings sentence:

  ```
  You are helping rethink one recipe. Discuss it freely: argue, push back, ask
  questions, and change your mind. When the cook asks you to finalize, return a
  revision brief.

  A revision brief is plain prose stating the revision you and the cook settled on:
  what to change, and why, in a cook's language. One change per line, in the order the
  change happens. Refer to ingredients and steps by their existing wording so each
  change can be matched to the recipe as it stands.

  Return only the brief itself: nothing before it, nothing after it, no title, no
  summary of the discussion. One change per line, like this:

  Take the butter to 120g and brown it before creaming — more nutty depth, less spread.
  Move the salt into the flour instead of the wet mix so it distributes evenly.
  Rest the dough 20 minutes before shaping so the flour hydrates.

  Do not return a rewritten recipe, an ingredient list, JSON, IDs, or any structured
  format. Yes Chef derives the structured edit from your brief itself, and the cook
  reviews that edit side by side against the current recipe before anything is saved.

  In the learnings section, record only what was considered and rejected, or
  established as a constraint on this dish — never restate a change that already
  appears in the brief.
  ```

  **The illustrative lines are deliberate.** D4's diagnosis of S2.5 was that `.immediate` mode gets a literal
  `deliverableFormat.example` while `.discuss` gets a single clause with nothing to imitate — and this verb
  lives in `.discuss`. The example is per-verb and lives in the *ask*, so it does not collide with the
  contract (Amd1-D6). **Adding a `DeliverableFormat` case is not sufficient on its own:** its
  `discussInstruction` is one clause, so the shape must come from the `RecipeHandoffContext` ask, exactly as
  the shipped section prompts do it.
- **S4b — the door back.** `.recipe` × `.adjustRecipe` import route (replacing the `.wrongTask` throw) →
  brief review sheet → *"Draft the revision"* → existing extractor → existing side-by-side → existing
  commits.
- **Watch, from the same hand-run: the shared op vocabulary has no step *insertion*.** Two of the six
  returned changes were finishing steps ("finish with lemon before serving"), and method ops are whole-step
  **replacement** only — so the extractor will smuggle them into the tail of an existing step and the
  side-by-side will blame the wrong step. Not a blocker for S4, and **not S4's decision to make**: the op
  vocabulary belongs to [ADR-0021 Amd1-D5](ADR-0021-recipe-variations.md#amd1-d5--the-op-vocabulary-bounds-the-editable-surface-and-it-extends-on-demand-for-free),
  where it is now the first extension candidate. Do not extend it from inside this slice.
- **Verify** per the house pattern: `swift build` + Core tests (the routing case and a return-payload
  round-trip: token, marker, prose body, learnings), one elevated `generic/platform=iOS` build,
  `scripts/check-drift.sh`. **Jon's device pass is the real signal** — outboard a real revision, argue it,
  finalize, paste, edit the brief, draft, review, commit as a variation.

### Amendment 1 open questions

- **Amd1-OQ1 — RESOLVED (2026-07-21, hand-run): learnings stay, with a re-aimed ask — see
  [Amd1-D7](#amd1-d7--learnings-stay-with-a-re-aimed-ask-resolves-amd1-oq1-hand-run-2026-07-21).** The D8
  pattern did recur (3 of 5 restated), but one learning carried **argument residue** the brief cannot hold
  and nothing else would keep. Suppression is the pinned fallback if a second run does not improve.
- **Amd1-OQ2 — RESOLVED 2026-07-23: DURABLE, reversing the lean below.** Dogfooding disagreed, exactly as
  this question anticipated — the 2026-07-21 S4 pass showed the why is the scarce output of an unmetered
  session and the one thing unreconstructable from the result. The brief is retained **verbatim** in a
  **recipe-scoped deliberation log**, per
  [ADR-0021 Amd 3](ADR-0021-recipe-variations.md#amendment-3--the-why-survives-the-commit-a-recipe-scoped-deliberation-log-2026-07-23)
  (Accepted), which also answers the "bigger question" the lean deferred: the recipe-scoped log is that
  log, and it deposits on **overwrite** as well as on keep-as-variation. *Original lean, kept for the
  record:* discarded; learnings are the durable channel,
  and a recipe-scoped deliberation log is a bigger question than this amendment.
- **Amd1-OQ3 — a brief argued about an *active variation* would silently anchor to the base recipe.** The
  reader resolves a variation for **display only** (`RecipeVariationDisplayModel.swift:25`), while adjust
  applies its proposal to the base `detail` (`RecipeDetailModel+Adjustment.swift:21`). Outboarding makes
  this trap easier to hit, because the exported context would show whichever text the cook is looking at.
  **v1 must export the base recipe and say so in the sheet, or refuse to export while a variation is
  active.** The general fix belongs to the variation-grain question (`docs/open-questions.md` — the
  variation ↔ Workbench umbrella fork), not here.

## Storage sketch — S1 is schema-free; S2 adds three synced columns

- **`AIHandoffSourceType` gains `.workbench`; `AIHandoffTaskType` gains `workbenchCompare` +
  `workbenchExperiments`.** `AIHandoff` is **not** in `makeSyncEngine`'s table list (verified — it is
  device-local, as ADR-0038 intended), so these additions carry **no CloudKit prod-schema cost** and go
  nowhere near the standing promotion list.
- **Experiments land as `workbenchLog` rows with `kind = .experiment`, not a BLOB.** The table exists, is
  synced, and already carries `kind · body · outcome · relatedRecipeID · sortOrder · dateCreated`, with
  `WorkbenchLogEntryKind` = `rationale · experiment · fork · observation · note`. **This supersedes
  ADR-0019 S3's `Workbench.experiments: Data?` BLOB** — which is the `Menu.prepPlan` defect exactly
  (ADR-0040: a blob's elements can only be regenerated, never repaired), and which ADR-0019's own A3 had
  already floated replacing with the log. **Do not build the BLOB.**
- **`workbenchLog` gains three nullable synced columns — `hypothesis` / `change` / `rationale` — in S2**
  (OQ2, resolved). Meaningful only for `kind = .experiment`; the triple is typed rather than smeared into
  `body` because an experiment is **write-many** (its `outcome` is filled in later) and ADR-0040 puts
  human-repairable content in typed fields. Additive, and **must go on the standing prod-schema promotion
  list in CURRENT_HANDOFF in the same PR.** We are pre-prod by design, which is precisely why the shape gets
  fixed **now** rather than after promotion locks it.
- **S1 remains schema-free** — compare deposits into the existing `body` as prose a human reads (D3), so the
  column work lands only when experiments do.

## Cost, honestly — and the slice plan

The machinery is a known quantity: four hand-off round-trips shipped, the review sheet, the marker/routing
core, the section-scoped `matches()` fix. What is new is a **source type**, two **prompt contracts**, and
the log deposit. The expensive part is not code — it is **taste**, and it is bought by hand-running the
prompts before building parsers around them (the OQ3 method that un-gated ADR-0041 S2).

- **S0 — the contract lands in the project (Core + Settings, no schema, no parse).** One Core constant
  holding the return contract + prohibitions + its `YC-CONTRACT: v<n>` version; a **Settings copy button**
  emitting it for the Yes Chef project's custom instructions; the return path reads the echoed marker and
  surfaces a stale/missing-instructions error (D4); the derived `<TaskType>: <Object>` title line on every
  outbound prompt (D9). **The v1 contract text is already hand-validated end-to-end by the OQ6 run** — ship
  what was tested. Small, and it improves the *existing* verbs immediately by closing the `.discuss`
  no-example gap.
- **S1 — the log deposit + `.workbench` as a source (no schema, no parse).** Wire `.workbench` into
  `AIHandoffSourceType` and the router; ship **compare** first, since its return is prose landing in
  `workbenchLog` rows a human reads (D3 → no format to get wrong). Also lands ADR-0023 S3's committed
  adjustment → `.rationale` entry (D6). *De-risks the source wiring on the deliverable with the lowest
  cost-of-error.* **Not gated on OQ6** — nothing here is parsed.
- **S2 — experiments. UN-GATED (OQ6 resolved 2026-07-20). The schema slice.** The pinned three-field block,
  its parser (lossless-or-loud, **splitting on the label cycle, not blank lines** — OQ6), the three nullable
  `workbenchLog` columns + migration (OQ2), `.experiment` rows, and the per-field edit affordance that
  justifies typing them. **Add the columns to the standing prod-schema promotion list in the same PR.**
  Emits **no learnings** (D8). Unit-cover the no-blank-line case explicitly — it is the shape the live run
  actually produced, not a hypothetical.
- **S3 — DEFERRED, not queued: `workbenchDraft`.** Per D5. Revisit only with a concrete want; it designs
  its own review surface against its own requirements.

Verify per [[lean-verification-default]] — package build + tests for the parse, one app build, check-drift;
**Jon device-passes** the round-trip.

## Open questions

- **OQ1 — PARTIALLY resolved (2026-07-20, Jon's live ChatGPT hand-run): the three-field block is
  *expressible*; whether it *survives* is OQ6.** *Method:* the OQ3 method — a hand-run of a pinned
  `Hypothesis:` / `Change:` / `Rationale:` block spec plus the prohibitions, against a real library recipe.
  *Result:* **4/4 blocks held** — all three labels present and ordered, one sentence per field, no spill
  across line boundaries, blank-line separation intact — and **every prohibition was obeyed**, including the
  assessment-of-what's-already-good one that broke ADR-0041 S2.5. The `*` list marker it chose is already
  handled (`AIHandoff.learningBullets` accepts `-` / `*` / `•`).

  **This result is weaker than it first appears, and the ADR should not lean on it.** The run was *single*
  and, more importantly, *single-turn*: the format was stated and invoked in the same breath. **That is
  `.immediate` shape — and immediate mode is the one condition under which we have no documented failure.**
  Every real failure (S2.5) happened in `.discuss`, where the contract must survive N turns before
  `finalize`. The run therefore proves the *shape* is producible; it says nothing about *durability*, which
  is the whole risk. **The run's more consequential finding was the learnings redundancy → D8.**
- **OQ6 — RESOLVED (2026-07-20, Jon's live ChatGPT run): the contract survives a long conversation from
  project instructions. S2 is un-gated.** *Method:* the v1 contract pasted into the Yes Chef project's
  custom instructions; a thread opened with title line + token + recipe only (**no format in the prompt**);
  several turns of genuine discussion; then `finalize`. *Result — the load-bearing claims all held:* it
  **switched out of interlocutor mode** on `finalize`; the token came back first; **`YC-CONTRACT: v1`
  echoed**, proving the drift-detection channel works; all four experiments carried all three labels in
  order; and **D8's learnings suppression held** despite being stated once, many turns earlier. Together
  these confirm **D1** (the terminal turn), **D4** (the contract belongs in project instructions, not the
  payload), and **D8**.

  **One real failure, and it changes the parser:** the **blank line between blocks did not survive.** The
  four experiments came back run together. It is *not determinable* whether the model dropped the separator
  or the copy-paste collapsed it — **and that ambiguity is the finding**, because the paste path is exactly
  where whitespace is mangled and production cannot distinguish the two either. **Therefore the parser keys
  on the label cycle — a new `Hypothesis:` line begins a new block — and never on whitespace.** More robust
  regardless of cause, and it degrades by mis-splitting rather than by silently merging four experiments
  into one.

  *Still owed (non-gating):* the same run on **Claude**, since D4 claims portability.
- **OQ2 — RESOLVED (2026-07-20, Jon): add the typed columns to `workbenchLog`.** *The first pass of this
  ADR leaned the other way — toward cramming the triple into the existing `body`/`outcome` to stay
  "schema-free" — and that lean was **wrong**, for a reason worth recording so it does not recur:* it priced
  in a **prod-schema lock that has not been paid.** We are in CloudKit **Development** by design; promotion
  to Production is a deliberately-held ops step, and every schema change since Phase E simply accumulates on
  the standing promotion list. **While we are pre-prod, "it would lock a record type" is not a reason to
  choose a worse shape** — it is a reason to get the shape *right now*, before the cut makes it permanent.
  (Contrast [ADR-0041 Amd 3](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md): `PlaybookSectionMeta`
  was withdrawn for **no consumer + a key orphaned by a dead field** — a *justification* failure, not a cost
  one. Experiments have an obvious consumer: the feature itself.)

  **The deciding question is ADR-0040's:** should a human be able to repair the `hypothesis` without
  regenerating the `change` and `rationale`? **Yes** — experiments are the one log kind with a real
  **lifecycle** (proposed → tried → outcome recorded later, which is why `outcome` already exists on the
  row). That is write-many, so the fields are typed fields, not prose smeared into one column
  ([[editable-at-the-grain-stored]]).

  **Shape — columns on `workbenchLog`, not a second table.** Nullable `hypothesis` / `change` / `rationale`,
  meaningful only for `kind = .experiment`. This is a discriminated union flattened into one table, which is
  a real smell, but the alternative is worse here: **the log's whole value is being one append-only
  chronological deliberation stream** (`rationale · experiment · fork · observation · note` interleaved by
  `sortOrder`), and a separate `workbenchExperiments` table would have to be merged back into that stream at
  read time. At personal-app row counts the nulls cost nothing. Add the columns to the standing prod-schema
  promotion list in the same PR. *(Revisit only if experiments grow fields that no other kind could ever
  share — then they are a different entity and deserve their own table.)*
- **OQ3 — is compare's return a commit or advisory-only?** Depositing every compare into the log could turn
  a read-once observation into permanent clutter — the anti-proliferation instinct of ADR-0023 D6. *Lean:*
  the human picks per item in the review sheet, as with learnings; default nothing.
- **OQ4 — RESOLVED (2026-07-20, Jon): neither — the contract leaves the payload entirely** and lives in the
  chat app's project custom instructions, generated from one Core constant (D4). *This question was
  ill-posed:* it offered "per-prompt" vs. "in the shared serializer," which are two flavors of the same
  buried assumption — that the contract ships **inside** the hand-off. It does not. The residual concern the
  question was really about (a config blob outside version control drifting from the parser) is answered by
  the `YC-CONTRACT: v<n>` marker, not by where the string is assembled.
- **OQ5 — what happens to the in-app workbench verbs once the external path exists?** ADR-0041 OQ4's answer
  for the Playbook was *complementary, not redundant* (the in-app verbs distill a live conversation; the
  hand-off exports for a fresh one). Confirm the same holds here before retiring anything.

## Related

- [ADR-0038](ADR-0038-external-llm-handoff.md) + Amd 1 (`Learning` as the two-part return, the model for D6)
  / Amd 2 (the in-app Copy/Paste door this rides) / **Amd 3, withdrawn** (why there is no reopen link),
  [ADR-0019](ADR-0019-recipe-design-studies.md) (the workbench, its log, and the superseded `experiments`
  BLOB), [ADR-0023](ADR-0023-recipe-edit-proposals.md) (S3 retired by D7, S3's log deposit promoted by D6;
  S1/S2 unaffected), [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) (the grain principle behind
  D3 and the BLOB supersession), [ADR-0041](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) (the
  S2.5 blob-report defect that motivates D1/D4; OQ3's hand-run method; OQ5's whole-recipe refusal behind
  D2), [ADR-0021](ADR-0021-recipe-variations.md) (the variation anchors D2 protects),
  [ADR-0024](ADR-0024-editable-proposal-preview.md) (the review sheet as the human's last edit),
  [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) (effort/tier — largely moot for outboarded work).
- Memory: [[llm-vs-determinism-surface-boundary]] (the boundary D2 extends), [[editable-at-the-grain-stored]]
  (why a delta never round-trips as prose), [[llm-curation-not-synthesis]] (D4's distinct-items rule),
  [[handoff-stateless-both-directions]] (refinement belongs in the live thread — the root of D7),
  [[withdraw-not-defer-orphaned-schema]] (why D7 is withdrawn rather than parked),
  [[decompose-notes-into-typed-homes]] (why experiments get rows, not a blob),
  [[chat-verb-commit-shapes]] (classify each return's commit shape before slicing),
  [[personal-app-latency-tolerance]] (why unmetered external reasoning is attractive here),
  [[lean-verification-default]].
