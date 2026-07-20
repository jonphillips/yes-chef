# ADR-0042 — The workbench hands off: deliberation outboards, structured writes stay in, and the return block is a terminal turn

> **Vocabulary:** the **return block** is the delimited payload a chat app emits on the *last* turn of an
> outboarded session (`YC-HANDOFF:` / `YC-LEARNINGS:`, ADR-0038) — **not** the shape of the conversation
> that produced it. A **deliberation surface** is one whose product is *judgment* (comparison, rationale,
> experiments, ideas); a **structured canonical write** is one that mutates typed recipe data (ingredient
> lines, instruction steps, variation deltas). This ADR says the first outboards by default and the second
> never does, and it pins what the return block may and may not contain.

Status: **Accepted** — 2026-07-20 (Jon ratified; D1/D4/D8 hand-validated end-to-end by the OQ6 live run,
all OQs resolved except the non-gating Claude-portability check). Opened Proposed the same day (architect +
Jon, in the "re-empower the workbench for the all-you-can-eat chat apps" conversation). **Extends
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
