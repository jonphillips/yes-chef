# ADR-0032 — Workbench reference material (app-side fetch, provider-agnostic context)

Status: **Accepted** — 2026-07-23 (Jon ratified). Opened Proposed as an architect sketch, 2026-07-12.
**What ratification covers: the Decision and its boundaries** — a per-workbench reference list (URL or
pasted text), fetched by *our own* engine, reduced to readable text, cached, and injected as **plain grounded
text**; the rejection of each provider's native server-side web tool as the mechanism; and the
advisory-read-only boundary (never a data write). **What it does not cover: the six open questions below,
which remain open for a scoping session** — they carry architect recommendations, but ratifying the ADR did
**not** adopt them, and **OQ5 (gated-fetch UX) carries no recommendation at all.** The slice plan is still
marked proposed and is **not dispatchable until that session happens**; see
[ADR-0043](ADR-0043-model-call-chokepoint.md) D5, which sequences the chokepoint arc *around* this ADR's
context layer precisely because the layer does not exist yet. App-side (`YesChefCore` + app), ships **independently**
of ADR-0031 (Responses migration). Refines the Recipe Workbench (ADR-0019) chat surface; reuses the web
capture engine (ADR-0007) and the authenticated-capture posture (ADR-0009). Governed by the
LLM-vs-determinism surface boundary ([[llm-vs-determinism-surface-boundary]]) and
[[llm-curation-not-synthesis]].

**Scoping session held 2026-07-25 — all six open questions are resolved and the slice plan is ratified; see
[Amendment 1](#amendment-1--the-scoping-pass-gated-capture-moves-into-the-in-app-browser-and-the-extract-becomes-synced-content-2026-07-25).**
Two of the six resolutions **revise** the recommendations below rather than adopt them: the gated-fetch
mechanism is now **in-app browser capture** (not paste-in — OQ5), and the reduced extract now **syncs** as
workbench content (not device-local — OQ2). The original Decision and open-question text stand as the
historical record; the amendment layers the resolutions on top.

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

## Amendment 1 — the scoping pass: gated capture moves into the in-app browser, and the extract becomes synced content (2026-07-25)

The design session ratified in one pass. Four open questions adopt their existing recommendation; **two revise
it** (OQ5, OQ2), and the revision to OQ5 is what forces the revision to OQ2 — they are one decision with a
ripple, not two.

### OQ5 (resolved, revises the Decision) — the gated path is the in-app browser, not paste-in

The ratified Decision made **pasted text** the gating fallback. That is now demoted. The mechanism the
programmatic `fetchHTML` cannot reach — an authenticated, data-gated page ([[paywall-gating-taxonomy]]) — is
better served by **routing the cook through our in-app browser** (the WebView already behind recipe capture,
ADR-0009 posture) and offering **"Capture to Workbench"** on the rendered page. The WebView holds the login, so
the capture is **authenticated by construction** — the same fidelity path recipe capture already trusts, with
no lossy select-all/copy/paste. Acquisition is therefore **layered by gating**, not a single primitive:

- **Public page → URL paste → programmatic `fetchHTML` → reduce.** The Decision's fast path, unchanged. Low
  friction; NYT-pixel-style gating parses clean here.
- **Gated page → in-app browser capture.** Replaces paste-in as the primary gated path. Milk-Street-style
  server-gated data needs the authenticated DOM, which only the WebView produces.
- **Paste-in survives only as a last-resort escape hatch** for the rare page even our WebView will not render.

**This dissolves OQ5's hard part.** The question was "how aggressively to detect a login wall and route to
paste-in vs. show the thin result" — a heuristic that gets edge cases wrong. It collapses to: **a thin/failed
programmatic fetch offers "Open in browser to capture."** The cook's presence in the authenticated WebView is
the signal; there is no wall-classifier to tune. Trust boundary is unchanged — captured DOM is still **untrusted
reference data, never instructions** (the system prompt frames it as data, per Consequences).

**One accepted cost:** browser capture is interactive and one page at a time — no background/batch fetch of many
URLs. Fine for the workbench's deliberate, low-volume "compare these against this writeup" use; named so it is a
chosen trade, not a surprise.

### OQ2 (resolved, revises the lean) — the reduced extract syncs; only raw HTML stays transient

The Decision leaned **device-local** for the cached extract, by analogy to the Compare alignment cache. That
analogy **breaks under OQ5**: the Compare cache is device-local because it is *recomputable* from synced data. A
browser-captured, authenticated, gated-page extract is **not recomputable on a second device** — device B
cannot re-fetch (login wall) and browser capture is interactive. A device-local extract would make the
reference **useless on the other device**, which holds only a bare URL it cannot resolve. So the extract crosses
from *cache* to *captured content* and **syncs as workbench content.** Three tiers:

- **Reference entry** (URL / label / kind / provenance) — **synced**.
- **Reduced readable extract** (the text injected into context) — **synced** (the revision). Small,
  budget-bounded; a synced BLOB is a CKAsset and sync-safe ([[sqlitedata-blob-cloudkit-asset]]), a new synced
  table is cheap ([[synced-table-cost-calibration]]).
- **Raw fetched/captured HTML** — **transient**, never persisted; only the reduced text survives.

Consequence: `WorkbenchReference` is a **synced** record type — register it in `CloudSync` and add it to the
standing prod-promotion list. A typed table, not a notes dump ([[decompose-notes-into-typed-homes]]).

### OQ1, OQ3, OQ4, OQ6 (resolved, adopt the recommendation — with one sharpening)

- **OQ1 — deterministic reduce first, but generic-readability, not the recipe parser.** Reference pages are
  arbitrary (a technique writeup, a food-science post), so the reducer is a **generic readability extraction**
  (strip nav/footer/scripts → main/article prose), not the recipe-schema editorial-prose parser, which assumes
  recipe-page structure. Grounded extraction, never synthesis ([[llm-curation-not-synthesis]]). The **LLM
  reduce pass stays parked**; when it ships it is the **first LLM call through [ADR-0043](ADR-0043-model-call-chokepoint.md)'s
  provenance chokepoint carrying a genuinely new context layer — the harder second load test** the chokepoint
  arc was sequenced around (ADR-0043 D5). Budget thinking + output when it does ([[reasoning-budget-starves-output]]).
- **OQ3 — trim reference material out first under the on-device 9k budget.** Adopted; it is supplementary to
  the candidates. ADR-0042 is the relief valve: reference-heavy deliberation **outboards** to a frontier chat
  where the full extract rides in the handoff payload, so the on-device squeeze rarely reaches the case that
  needs references.
- **OQ4 — explicit list first; candidate-source prose parked.** Adopted. The parked follow-on inherits the same
  gating layering (a candidate whose source is gated needs browser capture, not `fetchHTML`).
- **OQ6 — park `web_search` public discovery.** Adopted firmly: it is Anthropic-only and un-mirrorable to
  OpenAI/on-device, so it breaks the provider-agnostic spine that is the whole point of doing the fetch
  ourselves. Ship the deterministic path; add discovery only if dogfooding asks.

### Slice plan — now ratified, with the amendment folded in

- **S1 — reference-entry model + reduce/cache/store core (`YesChefCore`, no UI).** `WorkbenchReference`
  (**synced**, entry + reduced extract) plus a core that accepts **either a URL to `fetchHTML` or already-captured
  content** and runs both through **one** generic-readability reduce → store. Unit-tested with a stubbed fetch
  client and fixture HTML → asserted reduced text. No network in CI.
- **S2 — inject into chat context.** Unchanged: extend `WorkbenchChatContext` to serialize reference material
  behind the frontier budget, deduped against candidates, trimmed-first on-device. Because the extract is now
  durable synced content, the **same reference layer also composes into the ADR-0042 outboard handoff payload**,
  not only the onboard chat — one source, both surfaces.
- **S3 — list UI + in-app browser capture.** The meat of the amendment: add/edit/remove reference entries; the
  URL fast path; **"Open in browser → Capture to Workbench"** as the gated path; paste-in as last-resort;
  refresh. Refresh is an explicit replacement of the selected durable extract: S3 makes its source/capture kind
  visible and confirms a replacement, because a public fetch may be less complete than an authenticated browser
  capture; S1 deliberately does not rank or merge them. Device pass on iPad + iPhone
  ([[lean-verification-default]]).
- **Later (parked)** — LLM reduce pass (ADR-0043 load test), candidate-source prose, `web_search` discovery.

**Dispatch status:** ratified ≠ was; **scoped now** — S1 is dispatchable off this amendment. Sequence S1 → S2 →
S3; S1+S2 are package-verifiable, S3 needs the device pass.
