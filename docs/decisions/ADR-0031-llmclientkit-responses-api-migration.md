# ADR-0031 — Migrate the OpenAI backend of LLMClientKit to the Responses API

Status: **Proposed** — architect sketch, 2026-07-12; **open questions resolved with Jon same day**
(stateful `store: true` from S1; hard cut-over of Chat Completions). Ready to execute in a jon-platform
session. Platform-level (`jon-platform/packages/LLMClientKit`), **not** a YesChef feature — affects every
consumer of the kit. Deliberately **decoupled from** ADR-0032 (Workbench reference-material fetch); that
feature does **not** depend on this migration and must not be used to justify it. Builds on the LLMClientKit
house pattern (ADR-0011/0012 actionable chat, ADR-0017 effort tiers).

## Context

`LLMClientKit` speaks two backends behind one `ModelClient` seam:

- **Anthropic** → the **Messages API** (`AnthropicModelClient` / `AnthropicWire`). Already exposes the
  server-side **`web_search`** tool (`web_search_20260209`, gated by `ModelRequest.webSearchMaxUses`).
- **OpenAI** → the **Chat Completions API** (`OpenAIWire.baseURL = /v1/chat/completions`), with an explicit
  code comment that Chat Completions "is the stable, well-precedented surface." That was a sound call when
  written.

It has aged. OpenAI's own migration guide (developers.openai.com/api/docs/guides/migrate-to-responses) now
states: *"While Chat Completions remains supported, Responses is recommended for all new projects."* Chat
Completions is **not deprecated** — but it is the trailing-edge surface, and the gap is widening:

- **Native hosted tools** — `web_search`, `file_search`, code interpreter, computer use, and **remote MCP**
  — live on **Responses only**. On Chat Completions, web search exists solely via the model-locked
  `*-search-preview` variants, which we can't apply to a general `gpt-5`/`gpt-4o` call.
- **Statefulness** (`store: true`) preserves reasoning and tool context turn-to-turn instead of us
  rebuilding it every call.
- **Caching** — OpenAI reports **40–80% better cache utilization** vs Chat Completions. On a single-user
  app that re-sends recipe/workbench context every turn ([[personal-app-latency-tolerance]]), that is a
  direct, recurring cost win.
- **Reasoning preservation** matters to us specifically. [[reasoning-budget-starves-output]] is our scar
  tissue on reasoning-model token budgeting; Responses keeps reasoning context across turns rather than
  forcing a rebuild that competes with output for the budget.

### The current abstraction is already leaking

`ModelRequest.webSearchMaxUses` is an **Anthropic-shaped knob** on a supposedly backend-agnostic request —
silently ignored on the OpenAI/Chat-Completions path (there's nowhere for it to land). Any future "give the
model web access" capability inherits this asymmetry unless the OpenAI surface can host equivalent tools.
Responses is what lets the neutral seam actually be neutral.

### What this ADR is *not*

- **Not an Anthropic migration.** Anthropic already lives on the Messages API with server tools available;
  it needs no surface change. The asymmetry (Anthropic Messages ↔ OpenAI Responses) is fine — both are each
  provider's current-recommended surface. We are moving the *trailing* backend up to parity, not unifying
  APIs.
- **Not a prerequisite for ADR-0032.** The Workbench reference-fetch is app-side and provider-agnostic by
  construction; it ships on either OpenAI surface.

## Decision (proposed — open questions resolved with Jon, 2026-07-12)

Migrate `OpenAIModelClient` / `OpenAIWire` from **Chat Completions** to the **Responses API**, adopting
**server-held conversation state (`store: true`)** from the first slice, and **hard-cutting** the Chat
Completions wire in the same slice. `ModelRequest`/`ModelResponse` stay source-compatible for plain
completions, but the **seam evolves** to carry a conversation-continuity token (see below) — so this is
*not* a purely-internal wire swap.

Scope of the wire rework:
- **Endpoint** `/v1/chat/completions` → `/v1/responses`; request shape `messages[]` → `input`.
- **Output parsing** `choices[0].message.content` → `output_text` into `ModelResponse.text`, extracting
  **only** the message output — *not* the interleaved reasoning items (keeps defensive JSON parsing robust).
- **Function/verb tools** (actionable-chat `ModelTool[]`) re-mapped to the Responses tools shape. `complete()`
  stays **single-shot** (the tool loop lives in the consumer `ChatModel`, unchanged) — the port just maps
  Responses output items → `ModelResponse.toolCalls` the same way.
- **Streaming** — text-only, as today: map `response.output_text.delta` → `ModelChunk(text:)`, reuse the
  shared SSE line parser. Tool deltas are never streamed.
- **Reasoning effort** — relocate the already-sent `reasoning_effort` value from a top-level field to
  `reasoning: { effort }`. Confirmed against OpenAI docs (2026-07-12): the 5.6 family's native set is
  `none/low/medium/high/xhigh/max`, so our `none`/`xhigh` map 1:1 (their extra `max` is unused).
- **Default model bump** — `OpenAIWire.defaultModel` `gpt-5.5` → **`gpt-5.6-sol`** (Jon, 2026-07-12) — the
  flagship 5.6 tier, matching the quality-over-cost posture ([[personal-app-latency-tolerance]]). Rides this
  slice because S1a rewrites `OpenAIWire` anyway; a separate edit would be clobbered. Model/tier selection is
  properly an ADR-0017 concern — and belongs in user settings, not a hardcoded constant — but the constant
  still needs a current value, and this is it. (Cost-balanced `gpt-5.6-terra` / cheap `gpt-5.6-luna` are the
  siblings if the tier is revisited.)

### Statefulness: the seam consequence (DECIDED — go stateful now)

`store: true` only pays off if we send `previous_response_id` **instead of** re-sending prior turns. That
forces three things beyond the wire:
- **The seam grows a continuity token.** `ModelResponse` must surface the response id OpenAI returns, and
  the request path must accept a prior id to thread. **ADR-0015 chat persistence stores the id per thread.**
- **The chain will break — fallback is mandatory, not optional.** On tier degradation to on-device, or any
  Anthropic turn (stateless), or an expired/missing id, the OpenAI wire **falls back to a full-context
  send**. We therefore **always retain full context locally** and never rely solely on server state; the
  cache/reasoning win applies on the happy path (consecutive OpenAI turns) and correctness holds everywhere.
- **ZDR guard.** `store: true` errors on zero-data-retention accounts. Gate `store` on a capability check
  (or confirm the account isn't ZDR) rather than assuming it's available.

### Native tools — still later (unchanged)

The migration *unlocks* OpenAI `web_search`/MCP but this slice does **not** adopt them. Decide per-feature
later whether a native tool beats the app-side approach — a decision ADR-0032 already answers "app-side" for
the reference-fetch case.

## Consequences / boundaries

- **Output-parity is the bar for completions; statefulness is a deliberate behavior *change*.** Every
  existing feature (actionable chat, draft synthesis, Compare aligner, harvest, extraction one-shots) must
  produce equivalent output through the new wire — but the *state model* changes (server-held for
  consecutive OpenAI turns). Verify the request/response encoding with the kit's wire round-trip tests
  ([[lean-verification-default]] — stubbed transport, fixture request → fixture response → asserted
  `ModelResponse`; no live network in CI), **plus new tests for the continuity token**: id threaded on
  consecutive turns, full-context fallback when the id is absent/mismatched/degraded.
- **The seam is no longer fully frozen.** `ModelResponse` gains the response id and the request path a prior
  id; plain one-shot `complete`/`stream` callers are source-compatible, but the **chat-persistence consumer
  (ADR-0015) changes** to store/thread the id. That's the intended blast radius of the stateful choice.
- **Platform blast radius.** This is a `jon-platform` change; read the jon-platform house rules first
  ([[architect-role-and-handoffs]]). Any other kit consumer rides the same wire — one-shot callers are
  unaffected; only stateful chat consumers touch the new token.
- **`webSearchMaxUses` cleanup deferred, not forced.** The leaky knob can stay as-is through this port; a
  later slice can generalize it into a neutral `webAccess` capability once *both* backends can host it.
- **Measure before claiming the cache win.** `store: true` is what unlocks OpenAI's 40–80% cache-utilization
  and reasoning-preservation claims — but confirm on our own traffic; don't quote the headline number
  untested.

## Open questions — resolved 2026-07-12

1. **Stateless vs stateful** — **DECIDED: go stateful (`store: true`) from S1.** Captures the
   caching + reasoning-preservation win immediately; reworks ADR-0015 to persist the response id; mandatory
   full-context fallback when the chain breaks (see *Statefulness: the seam consequence*).
2. **Reasoning-effort mapping** — **RESOLVED:** `reasoning_effort` is already sent today; Responses
   relocates it to `reasoning: { effort }`. Confirmed the 5.6 family natively accepts `none`/`xhigh` (set is
   `none/low/medium/high/xhigh/max`), so no remapping needed; [[reasoning-budget-starves-output]] budgeting
   still funds thinking + output.
3. **Streaming parity** — **RESOLVED from code:** streaming is text-only (tool deltas never streamed; the
   tool loop lives in the consumer via single-shot `complete`). Port maps `response.output_text.delta` →
   `ModelChunk(text:)`. No consumer depends on Chat-Completions delta shapes — the seam is `ModelChunk(text:)`.
4. **Retire Chat Completions** — **DECIDED: hard cut-over.** Delete the Chat Completions wire in S1; parity
   guarded by the frozen request/response seam + wire round-trip tests. No flag, no dead path.
5. **Structured-output parsing** — **RESOLVED:** concatenate `output_text` into `ModelResponse.text`
   extracting *only* message output (not reasoning items); defensive JSON parsing then works unchanged.

### New implementer-facing items surfaced by the stateful choice

- Where the `previous_response_id` is persisted (ADR-0015 thread record) and how it's invalidated
  (provider switch, tier degradation, expiry).
- ZDR capability check before enabling `store` (it errors on zero-data-retention accounts).

## Slice plan (proposed)

- **S1a — Responses wire + hard cut-over.** Rewrite `OpenAIWire` request/response encode+decode and
  `OpenAIModelClient` transport to `/v1/responses`; **delete** the Chat Completions wire. Verb tools →
  Responses shape (single-shot `complete`, tool loop stays in the consumer); text-only streaming via
  `output_text.delta`; `reasoning: { effort }`; `output_text`-only extraction into `ModelResponse.text`.
  Wire round-trip tests re-fixtured to Responses. **Bump `defaultModel` → `gpt-5.6-sol`** in the same
  rewrite. This slice alone restores output parity.
- **S1b — statefulness (same dispatch, on top of S1a).** Add the continuity token: `ModelResponse` surfaces
  the response id; the request threads a prior id with `store: true`; **mandatory full-context fallback**
  when the id is absent/mismatched/degraded; ZDR capability gate. Persist the id in the ADR-0015 thread
  record. New tests: id threaded on consecutive OpenAI turns, fallback on degrade/provider-switch.
  - **Carried from S1a review ([jon-platform#31](https://github.com/jonphillips/jon-platform/pull/31)):** surface
    streaming `response.failed` as an error instead of a clean finish. S1a maps `response.failed` /
    `response.incomplete` to `.stop` and `OpenAIModelClient.stream` finishes the continuation, so a
    mid-stream provider failure ends the stream with partial/empty text and no thrown error (the parsed
    reason is discarded). Fold this into S1b's error handling — throw a `ModelClientError` on
    `response.failed` — since S1b already introduces the stream-failure/degrade seam. New test: a
    `response.failed` SSE terminal event throws rather than yielding a silent finish.
- **Later (parked) — neutral web-access capability.** Generalize `webSearchMaxUses` → a backend-agnostic
  `webAccess` knob now that OpenAI can host it, if/when a feature wants native provider search (note:
  ADR-0032 deliberately does **not**).

## Related

- **ADR-0017** (LLM model + reasoning effort — the tiers this wire serves), **ADR-0011/0012** (actionable-chat
  structured-output + tool loop that must survive the port), **ADR-0015** (chat persistence — the
  state-ownership model that `store: true` would touch), **ADR-0032** (Workbench reference-fetch — the
  feature this migration is explicitly decoupled from).
- OpenAI migration guide: https://developers.openai.com/api/docs/guides/migrate-to-responses
- Memory: [[reasoning-budget-starves-output]] (budget thinking + output; reasoning preservation is why this
  matters to us), [[personal-app-latency-tolerance]] (caching win on a re-sending single-user app),
  [[architect-role-and-handoffs]] (jon-platform house rules first), [[lean-verification-default]]
  (stubbed-transport wire tests, Jon does the device pass).
