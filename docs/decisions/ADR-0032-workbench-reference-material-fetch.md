# ADR-0032 — Workbench reference material (app-side fetch, provider-agnostic context)

Status: **Proposed** — architect sketch, 2026-07-12. App-side (`YesChefCore` + app), ships **independently**
of ADR-0031 (Responses migration). Refines the Recipe Workbench (ADR-0019) chat surface; reuses the web
capture engine (ADR-0007) and the authenticated-capture posture (ADR-0009). Governed by the
LLM-vs-determinism surface boundary ([[llm-vs-determinism-surface-boundary]]) and
[[llm-curation-not-synthesis]].

## Context

Workbench chat context (`WorkbenchChatContext`) is a **static serialization** of already-stored data:
title, notes, the draft recipe, log entries, and candidate recipes' ingredients/instructions. There is **no
live fetching** in the chat path. Two real gaps surface when dogfooding a comparison discussion:

- **The model can't see the source page.** Each candidate carries a `sourceName`, and `RecipeSource.url`
  exists in the model — but the URL is never surfaced to the LLM, and the *page prose* (headnotes,
  technique discussion, the "why") was discarded at parse time. The chat reasons over the parsed skeleton,
  not the full source context the cook is looking at.
- **The cook wants to point the discussion at specific URLs** — including pages that are **not** candidates
  in the library at all ("compare these against this Serious Eats writeup I haven't captured").

The naive fix — *put the URL in the prompt and tell the model to read it* — is **rejected**: with no tool
the model can't fetch and will **hallucinate** plausible recipe content, the one unacceptable failure mode
for a fidelity-first cooking app.

### Why not each provider's native server-side web tool

Both providers can fetch server-side (Anthropic `web_search`/`web_fetch` on Messages; OpenAI `web_search`
on Responses, pending ADR-0031). We deliberately do **not** build on them:

| | Native provider web tool | App-side fetch (this ADR) |
|---|---|---|
| Provider-agnostic | ❌ three mechanisms (Anthropic tool / OpenAI tool / on-device none) behind one flag | ✅ identical bytes to every backend |
| Gated/authenticated sources | ❌ unauthenticated server fetch → login wall (Milk Street) | ✅ reuses capture engine + paste-in |
| On-device tier | ❌ no tools | ✅ same context (budget permitting) |
| Hallucination risk | low *with* tool | none — grounded text |
| Fidelity / trust boundary | provider-controlled | **we** own the reducer + injection surface |

Chasing native tools yields *more* provider-specific plumbing and *less* capability — and still hits the
gated sources the cook most cares about ([[paywall-gating-taxonomy]]), which is the entire reason the
authenticated share-extension capture path exists (ADR-0009). **Doing the fetch ourselves is the
LLM-agnostic implementation**, and it's the only one that solves gating.

## Decision (proposed)

Add a **per-workbench "reference material" list**. Each entry is one of:
- a **URL** → fetched by *our own* engine, **reduced** to readable text, and **cached**; or
- **pasted text** → the gating fallback (the cook pastes authenticated content the server can't reach).

Reference material is injected into the chat context as **plain grounded text**, behind the frontier
context budget. Fetching never enters the `ModelClient` seam — it's just text in the prompt, so it works
identically across Anthropic, OpenAI, and on-device.

- **Fetch** reuses `WebRecipeCaptureClient.fetchHTML` + the existing parsers (ADR-0007); no new client
  infra, no new entitlements (runs in-app, not the extension).
- **Reduce, don't dump.** Raw HTML/page text blows the on-device budget (9k chars *total*) instantly, so a
  reference entry stores a *reduced* readable extract (the editorial-prose path already exists), not the raw
  page. Reduction is grounded extraction, **never synthesis** ([[llm-curation-not-synthesis]]).
- **Cache** the reduced text on the entry (copy the `CompareAlignmentCacheStore` per-set pattern, ADR-0022)
  so we fetch once, not per turn; an explicit **refresh** re-fetches.
- **Dedupe** against candidates — if a reference URL matches a candidate's source, don't double-inject.
- **Budget-aware** — reference material is frontier-tier meaningful; on the on-device budget it's trimmed
  first (it's supplementary to the candidates, which stay primary). Same soft-cap/trim discipline
  `WorkbenchChatContext` already applies.

Anthropic's already-wired `web_search` may remain an **optional cheap fallback for public discovery** ("find
me a page about X"), but it is **not** the mechanism and is **not** mirrored into OpenAI.

## Consequences / boundaries

- **Reuse, not rebuild.** Fetch (ADR-0007 engine), reduce (editorial-prose extraction), cache (ADR-0022
  store pattern), inject (extend `WorkbenchChatContext` serialization). Net-new: a reference-entry model +
  the list UI + the reducer wiring + budget placement.
- **Fidelity is the whole point.** We own the reducer and the injection text, so no hallucinated source
  content and a controlled prompt-injection surface (fetched web text is untrusted — it's *reference*, never
  instructions; the system prompt must frame it as data). [[llm-vs-determinism-surface-boundary]]: this is
  an **advisory read** surface (context for discussion), never a data write — it never touches grocery,
  pantry, or any persisted recipe field.
- **Gating handled honestly.** Public pages fetch clean; data-gated pages get the **paste-in** path. The UI
  should detect a likely login-wall fetch and prompt "paste the page text instead," rather than silently
  feeding the model a paywall.
- **Sync posture (open question).** Lean toward **device-local, not synced** for the cached extract (a
  presentational/working artifact, like the Compare alignment cache, ADR-0019 D4) — though the *list of
  reference URLs* the cook typed may deserve syncing as workbench content. Decide in session.
- **Latency** — a fetch+reduce is seconds, on add/refresh only, then cached ([[personal-app-latency-tolerance]]).
  Budget thinking + output if the reducer is an LLM call ([[reasoning-budget-starves-output]]).

## Open questions for the design session

1. **Reducer: parser-prose extraction or an LLM summarize pass?** Recommend **parser/editorial-prose
   extraction first** (deterministic, free, already built); add an optional LLM reduce only if raw extracts
   prove too noisy. Keeps it grounded and cheap.
2. **Sync granularity** — cache extract device-local (recommended), but sync the typed URL list as workbench
   content? Or keep the whole feature local?
3. **On-device behavior** — trim reference material out entirely under the 9k budget (recommended: it's
   supplementary), or attempt a hard-reduced snippet?
4. **Candidate URLs too, or explicit list only?** The cook's ask is the explicit list; offering "also pull
   the source prose for existing candidates" is a cheap extension but risks re-deriving what candidates
   already contain. Recommend **explicit-list first**, candidate-prose as a parked follow-on.
5. **Gated-fetch UX** — how aggressively to detect a login wall and route to paste-in vs. just showing the
   thin result.
6. **Keep the `web_search` public-discovery fallback in v1, or park it?** Recommend park — ship the
   deterministic fetch first; add discovery only if dogfooding wants it.

## Slice plan (proposed)

- **S1 — reference-entry model + fetch/reduce/cache core (`YesChefCore`, no UI).** A `WorkbenchReference`
  (URL or pasted text) + a core that fetches via `WebRecipeCaptureClient`, reduces to readable text, and
  caches (CompareAlignment-style store). Unit-tested with a stubbed fetch client — fixture HTML → asserted
  reduced text. No network in CI.
- **S2 — inject into chat context.** Extend `WorkbenchChatContext` to serialize reference material behind
  the frontier budget, deduped against candidates, trimmed-first on-device. Pure, unit-tested against the
  existing budget tests.
- **S3 — the list UI + gating fallback.** Add/edit/remove reference entries on the workbench; paste-in path;
  login-wall detection → "paste the page text" affordance; refresh. Device pass on iPad + iPhone
  ([[lean-verification-default]]).
- **Later (parked)** — LLM reduce pass, candidate-source prose, `web_search` public discovery.

## Related

- **ADR-0019** (Recipe Workbench — the chat surface this extends; D4 passive-artifact posture),
  **ADR-0007** (web capture engine — the fetch/parse we reuse), **ADR-0009** (authenticated browser capture
  — why gating needs the paste-in path), **ADR-0022** (Compare aligner — the device-local per-set cache
  pattern to copy), **ADR-0025** (reader-comment ingestion — prior art for harvesting non-recipe page prose),
  **ADR-0031** (Responses migration — explicitly *not* a dependency; native tools deliberately not the
  mechanism).
- Memory: [[paywall-gating-taxonomy]] (gated data needs authenticated/paste-in capture),
  [[galavant-capture-engine-reuse]] (the harvested engine this reuses),
  [[llm-vs-determinism-surface-boundary]] (advisory read, never a write),
  [[llm-curation-not-synthesis]] (reduce = grounded extraction, never flatten),
  [[personal-app-latency-tolerance]] (seconds-on-add is fine), [[reasoning-budget-starves-output]]
  (budget both if the reducer is an LLM call), [[lean-verification-default]].
