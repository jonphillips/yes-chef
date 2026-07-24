# ADR-0043 — Every model call declares itself: one `ModelRequest` chokepoint, test-enforced, with the inventory derived from it

> **Vocabulary:** the **chokepoint** is the single construction site every `ModelRequest` passes through.
> The **record** is what it captures per call — `(surface, task, tier resolution, context layers, budget,
> effort)`. The **inventory** is the *derived* view of those records; it is never authored. "Registry" in
> conversation means the chokepoint plus its record — not a hand-maintained list, which is the exact artifact
> this ADR exists to prevent.

Status: **Accepted** — 2026-07-23. Jon ratified four calls in conversation: **this track takes the slot over
[ADR-0021](ADR-0021-recipe-variations.md) V1+V2 variations**; enforcement is a **test**, not a convention;
the user-facing half starts **dev-only**; and the workbench outcome verb is an **ADR-0042 amendment**, not its
own ADR. This document records those calls and derives the slice plan from them. Graduates the **Live
2026-07-21 open question** ("no inventory of model calls") out of
[`open-questions.md`](../open-questions.md) — including its `ModelRequest`-chokepoint lean, which this ADR
adopts wholesale. Governed by [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) (tier/effort are the
fields being recorded) and [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) (the taste-profile
layer injected at the `LLMClientKit` boundary is one of the context layers that must show up in the record).

## Context

**The forensics cost is measured, not asserted.** Jon, 2026-07-21: *"It takes a lot of forensics to track
what we've got, and it's opaque to the user."* Raised after tracing **one** question — which model the S4
brief extractor uses, and what context it gets — took half a dozen greps across Core and the app, by someone
with the codebase already open.

**The asymmetry narrows the work.** The **outboard** surface is already self-describing: nine verbs, one
enum (`AIHandoffTaskType`), one export switch. Nobody has ever had to grep for an external verb. The
**onboard** surface is **18 `.complete(` call sites across 15 files, built from 17 `ModelRequest(`
constructions** (measured 2026-07-23), each independently deciding tier resolution, prompt assembly, context
layers, token budget, and reasoning effort. **This is almost entirely an onboard problem.**

**The staleness constraint proved itself inside 48 hours.** The open question measured *19 call sites across
14 files* on 2026-07-21; the same count today is *18 across 15*. Nothing was deliberately restructured — the
tree simply moved. A markdown table of call sites would have been wrong by the second slice, and would then
be a *second* thing to do forensics against. **If this is built it must be derived or test-enforced.** This
is the same reasoning that produced `YC-CONTRACT: v<n>` in [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md)
D4: an artifact maintained outside the thing it describes drifts silently.

**"Inventory" is two problems with different fixes, and they must not merge.**

- **Architect forensics** — call site → tier resolution → context layers → budget. Fixes the tracking cost.
- **User opacity** — at runtime the cook cannot tell which model answered, or that it silently degraded.

A doc does not fix opacity; a status chip does not fix forensics. But **both fall out of one record**, which
is why they are one ADR and not two features.

**The damage is already on the board.** The S4 brief extractor (`HandoffReviewCoordinator.draftRecipeAdjustment`
→ `RecipeAdjustmentClient`) **re-implements tier selection instead of sharing it**: it ignores
`recipeChatTierPreference` (the Ask path honors it), falls back to `availableProviders.first` — arbitrary
enum order, not a user-meaningful choice — and with no API keys **silently drops to `.onDevice`** for a call
demanding `maxTokens: 16_384`, `reasoningEffort: .high`, and strict JSON that must parse or throw
([[reasoning-budget-starves-output]]). A missing key surfaces as `responseTruncated` on a carefully-argued
brief instead of *"add an API key."* That nit has been sitting in Ready Efforts as its own item; under this
ADR it stops being a nit and becomes a consequence that S3 removes structurally.

### Why `LoggingModelClient` is not already this

The obvious objection is *"we already have a seam that sees every call."* We do:
`LoggingModelClient` decorates `ModelClient` and logs `promptPreferenceKey`, `tier`, `maxTokens`, the full
assembled prompt, latency, `stopReason`, and a response shape. **It is not sufficient, and the reason is the
whole point of this ADR.**

A decorator observes at **completion** time and therefore sees **values, not provenance**:

- **Tier resolution is invisible.** It logs the tier that *arrived*. The S4 defect is in how that tier was
  *chosen* — an ignored preference and an arbitrary `availableProviders.first` fallback. A log line reading
  `tier=on-device` is indistinguishable from a deliberate on-device call.
- **Context layers are invisible.** It logs the concatenated prompt. Whether the taste profile or known
  learnings were layered in is not recoverable from the resulting string — which is exactly the
  judgment-vs-transcription split that took greps to find.
- **The surface is approximate.** `promptPreferenceKey` is the nearest thing to a call-site identity and it
  is **optional**, logging `"unknown"` when absent. The record's `surface`/`task` should **subsume and
  firm up** that key rather than growing a second parallel identifier beside it.
- **It cannot be enforced.** Nothing fails when a call site is added; the decorator simply logs whatever it
  is handed, forever, with no notion of a site that should have declared itself.

So S1 is **not** "add a logging seam" — it is *"add, at construction, the provenance the existing seam is
structurally unable to infer."* Whether the record is then read by the decorator, or carried on
`ModelRequest` itself, is an implementation choice for the slice; the decorator stays useful and is not
replaced.

**Context layering is the hardest axis and has the least type support.** Proof from the same trace: the
outbound hand-off ask sends **taste profile + known learnings**; the extractor sends **neither** — a
deliberate and correct split (judgment vs. transcription) that was nonetheless **invisible until someone
grepped for it.** Highest surprise per unit of code, and the reason the record's `context layers` field is
the one that earns this ADR.

## Decision

### D1 — One chokepoint; every `ModelRequest` is constructed through it

All 17 construction sites route through a single place that captures the record. The 1:1-ish ratio between
`ModelRequest(` constructions and `.complete(` calls is what makes this cheap: there is already a natural
chokepoint in the shape of the code, it simply has no walls.

### D2 — Test-enforced, never convention (Jon's call)

A `.complete(` call site that bypasses the chokepoint **fails a test.** A convention will not survive two
slices — we have the drift measurement above, taken over two days, to prove it. The enforcement mechanism is
the load-bearing part of S1; if it is weak, everything downstream decays back to greps.

### D3 — The inventory is derived, never authored

No markdown table of call sites, in this ADR or anywhere else. The record is the source; any human-readable
view is generated from it. **This ADR deliberately contains no list of the 18 sites** — publishing one here
would create exactly the stale artifact D2 exists to prevent.

### D4 — The user-facing half reads the same record, and starts dev-only (Jon's call)

Which model answered, at which tier, and whether it degraded from what was asked for. **Dev-only view
first** — not shipped chrome. This keeps S2 cheap and defers the real product question (what a *cook* should
see when a call silently degrades) until the record exists to answer it from.

### D5 — Policy unification comes last, not first

The tempting order is "unify `resolveTier()` first, it's the actual bug." Rejected. **[ADR-0032](ADR-0032-workbench-reference-material-fetch.md)
introduces a context layer that does not exist today** (fetched, reduced, cached reference text). Unifying
context assembly *before* that shape exists designs the abstraction for the wrong thing, and we have a
standing lesson about building structure on ADR momentum ahead of its consumer
([[withdraw-not-defer-orphaned-schema]]). Record first, surface second, unify third — once everything already
flows through one place, unifying the *policy* is a small move rather than a rewrite.

### D6 — Declaring is not centralizing prompts (explicit non-goal)

The record captures **what context a call layers and at what budget**. It does **not** move prompt text into
one file, and it does not make prompts uniform. The deliberate asymmetries stay — the extractor still gets
neither taste profile nor learnings ([ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) Amd1-D1),
and that split becomes *visible* rather than *enforced away*. A registry that flattened those differences
would destroy the thing it was built to reveal.

## What this does not do

- **It does not touch the outboard surface.** `AIHandoffTaskType` is already self-describing; adding it to
  the record buys nothing.
- **It does not add a verb.** No new model call, no new prompt, no schema.
- **It does not decide the degradation UX.** D4 stops at dev-only on purpose.

## Slices

**S1 — the chokepoint and the record (Core; no schema, no user surface, no behavior change).** One
construction site; all 17 sites routed through it; the record type; the enforcement test. Recording only —
tier resolution stays exactly as each call site does it today, correct *and* incorrect. Forensics is
discharged the moment this lands. **The enforcement test is the slice's real deliverable** — a version of
this that relies on reviewers noticing is a failed slice.

**S2 — the dev-only inventory view (app; debug-gated).** Reads the S1 record: surface, task, tier actually
used, context layers, budget, effort. Dev-only per D4.

**S3 — policy unification (Core + app; the first slice that changes behavior).** One shared `resolveTier()`
honoring both `recipeChatProviderPreference` and `recipeChatTierPreference`, with an **honest error when the
only available tier cannot do the job** rather than a silent `.onDevice` fallback. **This absorbs the S4
extractor-drift entry from Ready Efforts** — it is deleted there, not tracked twice. The extractor's
conversation-framed prompt is the *other* half of that nit and stays separate: it is a prompt-authoring fix,
not a policy one.

**Load test, after S1 and before S3 — the three stranded advisory verbs.** `menuComplement`,
`mealPlanComplement`, and `readerFeedbackCuration` have in-app prompts but **no hand-off ask**; each needs
one authored fresh (ask, deliverable format, the D8 learnings call, commit shape). They are the first real
load on S1's record: **if the record cannot express them trivially, S1 was modeled wrong**, and we learn it
for the price of three small verbs instead of twelve. This also discharges the *"Menu is under-served by
hand-off verbs"* candidate Jon named 2026-07-21 — check it against the parked **ADR-0013 meal-planner verbs**
entry first, which overlaps. Classify each verb's commit shape before slicing ([[chat-verb-commit-shapes]]).

**Load-test result (2026-07-24, PR [#226](https://github.com/jonphillips/yes-chef/pull/226)).** The record
was sufficient, but not uniformly: `tasteProfile` had to become a first-class context layer. The two
complement calls include it because their prompts inject the taste profile and complement preference;
`readerFeedbackCuration` explicitly omits it because curation transcribes comment evidence rather than making
a taste judgment. That is the first production use of `omitted:` and proves the included/omitted distinction
earns its place. No tier-policy change was needed, so S3 remains independently scoped.

**Free rider:** the workbench compare hand-off passes `deliverableFormat = .menuPrepPlan`
([`HandoffIntents.swift:345`](../../YesChefApp/AppIntents/HandoffIntents.swift)), so the copied prompt closes
with *"return the paste-ready **prep plan**."* One line, user-visible in the pasted text, already noted as a
non-blocking follow-up from the ADR-0042 S2 review. It rides with whatever lands nearest it — it does not
earn a slice.

## Open questions

- **OQ1 — RESOLVED (2026-07-23, Jon): in-memory, not persisted.** Forensics needs only the former, and
  persisting would turn *"which model answered this"* into durable history — a feature with a schema, a sync
  posture, and a retention question, none of which S1 or S2 needs. **The record lives for the life of the
  call.** Revisit only if the dev view proves it needs history, and treat that as a new decision rather than
  an extension of this one.
- **OQ2 — RESOLVED (2026-07-23, Jon): declared layers plus the final character count.** The record names the
  layers a call assembles (`taste profile`, `learnings`, `candidates`, `log`, …) and records the resulting
  total size — **not** per-layer byte accounting. The declaration is what makes the judgment-vs-transcription
  asymmetry legible (D6); the final count is what catches a budget surprise. Per-layer bytes buy precision
  nobody has asked for and would push toward measuring at serialization time, which drags the record back
  toward the completion-time seam it is supposed to precede.
- **OQ3 — RESOLVED (2026-07-23, Jon ratified [ADR-0032](ADR-0032-workbench-reference-material-fetch.md)).**
  The reference-material context layer is now an accepted direction, so D5's ordering stops being contingent:
  the chokepoint arc lands first, and reference material's layer is the **first new layer S1's record must
  express** — which makes it a second, harder load test after the three advisory verbs. **It is still not
  dispatchable:** ADR-0032's six open questions (including OQ5, which carries no recommendation) need a
  scoping session, and its slice plan remains marked proposed. Ratified ≠ scoped.
- **OQ4 — the workbench outcome verb has no scope yet.** Jon ratified only its *placement* (an ADR-0042
  amendment, per D8's corollary: a conjecture suppresses learnings, but a **cooked** experiment is findings,
  so learnings come back on). The amendment gets written when the phase is scoped — deliberately **not**
  now, so it is not built on this ADR's momentum.

## Related

- [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) — the outboard surface this measures against
  (nine verbs, one enum); its D4 `YC-CONTRACT: v<n>` marker is the precedent for D2's enforcement stance; its
  D8 is what OQ4's amendment extends. Its Amd1-D1 judgment/transcription split is D6's worked example.
- [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) (tier + `reasoningEffort`, the recorded fields),
  [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) (the taste-profile layer),
  [ADR-0032](ADR-0032-workbench-reference-material-fetch.md) (the unbuilt context layer D5 sequences around),
  [ADR-0013](ADR-0013-meal-planner-actionable-chat.md) (overlaps the load-test verbs).
- Memory: [[reasoning-budget-starves-output]] (why a silent `.onDevice` fallback is a real defect, not a
  degradation), [[personal-app-latency-tolerance]] (effort/tier belong in user settings, not code constants),
  [[yeschef-onbard-model-tier]] (the on-device tier is the default backend and the degradation target),
  [[llm-vs-determinism-surface-boundary]], [[withdraw-not-defer-orphaned-schema]] (D5's ordering caution),
  [[chat-verb-commit-shapes]] (the load-test verbs), [[lean-verification-default]].
