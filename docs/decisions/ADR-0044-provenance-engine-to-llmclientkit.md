# ADR-0044 — The model-call provenance engine belongs in `LLMClientKit`; Yes Chef keeps the taxonomy — lift after ADR-0043 S3, validated by Galavant

> **Scope note:** this is a **stub**. It records the *seam* and the *trigger*, and deliberately does **not**
> design the generic API. Per [ADR-0043 D5](ADR-0043-model-call-chokepoint.md) and
> [[withdraw-not-defer-orphaned-schema]], the record's shape is not yet validated — the ADR-0043 **load test
> has not run** — so committing a generic abstraction into the shared boundary now would be building ahead of
> its proof. The design is written when the trigger fires, not on this ADR's momentum.

Status: **Proposed (parked)** — 2026-07-23. **Trigger: after [ADR-0043](ADR-0043-model-call-chokepoint.md)
S3 lands and its load test has run.** Downstream of ADR-0043 (it lifts ADR-0043's mechanism); the actual
package decision, once ratified, is recorded in `~/code/jon-platform` — the home for shared-package calls —
the same way [ADR-0007](ADR-0007-web-recipe-capture-engine.md) is a Yes Chef ADR that sequences a jon-platform
convergence.

## Context

**The problem ADR-0043 solved is not Yes-Chef-specific.** ADR-0043 diagnosed the onboard surface — 17
`ModelRequest(` construction sites, each independently deciding tier resolution, context layers, budget and
effort, with the forensics cost ("which model does this call use, and what context does it get") and the user
opacity ("did it silently degrade") both falling out of one provenance record. That description is a
description of *any* multi-surface LLM app.

**Galavant is a real second consumer with the identical disease (verified 2026-07-23).** Not hypothetical:

- **6 `ModelRequest(` construction sites across 4 files** — `GalavantChat/ChatModel.swift`,
  `GalavantPlaces/PlaceDiscoveryClient.swift`, `GalavantPlaces/EvaluationExtractor.swift`,
  `GalavantPlaces/HoursExtractor.swift` — each deciding tier/context/budget on its own.
- Its own AI settings (provider preference), a **travel profile** (the taste-profile analogue, the
  [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) layer under a different name), and a chat panel.
- **Zero** provenance/record/sink/inventory concept. Same forensics + opacity costs, none of the cure.

So Galavant has ADR-0043's problem and would benefit from ADR-0043's solution wholesale — it just can't reach
it, because the solution currently lives in `YesChefCore`.

**`LLMClientKit` is already the shared boundary, and a clean one.** It owns `ModelClient`, `ModelTier`,
`FrontierProvider`, `ModelRequest`/`ModelResponse`, `TieredModelClient`, `FrontierResolver`, and the wire
clients; it depends only on `swift-custom-dump` and `swift-dependencies` — nothing app-ish. Both Yes Chef and
Galavant consume it as an external package. It is the natural host for a provenance engine, and hosting one
would not drag any domain vocabulary into it (see the seam below).

**This is [ADR-0007](ADR-0007-web-recipe-capture-engine.md) run in the opposite direction.** Yes Chef
*harvested Galavant's* web-capture parser and deferred convergence on a shared package
([[galavant-capture-engine-reuse]], harvest-now/converge-later). Here Galavant would harvest *Yes Chef's*
provenance engine. The house pattern already covers this; naming the symmetry is most of the argument for
doing it deliberately rather than by copy-paste.

## Decision (provisional — the seam, not the API)

**The engine is generic and lifts; the taxonomy is app-specific and stays.**

| Reusable → `LLMClientKit` | App-specific → stays in each app |
|---|---|
| The chokepoint mechanism: construct `ModelRequest` → emit a provenance record | `ModelCallSurface` — Yes Chef's surfaces (grocery/menu/recipe/…); Galavant's are places/chat/trips |
| `ModelCallRecordSink`, `ModelCallRecordCollector`, `ModelCallInventory` | `ModelCallTask` — each app's verbs |
| The record's generic fields: tier, budget, effort, input size, *declared layers* | `ModelCallContextLayer` **cases** — each app's context vocabulary |
| The `included`/`omitted` layer **concept** (the D6 legibility mechanism) | The enforcement test's **scan roots** and the construction sites themselves |

The generic form is likely `ModelCall<Surface, Task, Layer>` over app-supplied `RawRepresentable` enums (or a
small protocol), so the record carries each app's taxonomy without `LLMClientKit` knowing any of it.

**The most-package-shaped piece is the one S3 delivers anyway: resolution truth.** The gap S2 surfaced —
"tier/model **requested** vs **actually used**" — cannot be closed at construction, but it is *known inside
the package*, in `TieredModelClient.backend(for:)` and `FrontierResolver`. ADR-0043 S3 unifies `resolveTier()`
and adds resolved-tier reporting; a "what did this request resolve to?" capability is unambiguously
`LLMClientKit`'s to own, and every consumer benefits. **This is the seam where platform reuse and Yes Chef S3
are the same work** — which is exactly why the trigger is S3, not now.

## Why not now — the trigger is ADR-0043 S3 + its load test

1. **The record's shape is unvalidated.** ADR-0043's load test (the three stranded advisory verbs) is
   *defined as* the thing that proves whether S1 modeled the record right — and it names
   `contextLayers.omitted`, which has **zero** production call sites today, as the specific thing to prove.
   Lifting the type into a shared boundary before that runs risks versioning a wrong abstraction across two
   apps. Reversing a `YesChefCore` type is a local edit; reversing an `LLMClientKit` type is a cross-app
   migration.
2. **[[withdraw-not-defer-orphaned-schema]] / don't build on ADR momentum.** S2 shipped hours ago; S3 has not
   started. A real second consumer makes convergence a *scheduled target*, not a licence to front-run the
   proof.
3. **The trigger is concrete and near.** When S3 lands, the record is load-tested *and* the resolution-truth
   capability is already moving into the package. That is the cheapest, best-proven moment to draw the line.

## Open questions (for the scoping session when the trigger fires — not decided here)

- **OQ1 — the generic mechanism.** `ModelCall<Surface, Task, Layer>` over `RawRepresentable` enums, a
  protocol the app conforms its enums to, or `String` raw values at the boundary? Type safety vs. package
  simplicity.
- **OQ2 — where does the enforcement test live?** The scan roots are app-specific (`YesChefPackage/Sources` +
  `YesChefApp`; Galavant's are different), so the *test* almost certainly stays per-app even though the
  *mechanism* lifts. Confirm the package can expose a testable "did this bypass the chokepoint" hook without
  owning the roots.
- **OQ3 — is the inventory *view* shared or per-app?** The `ModelCallInventory` model can lift; the SwiftUI
  dev pane is app chrome. Does Galavant want the dev inventory at all, or only the record?
- **OQ4 — does the lift wait for ADR-0032's reference-material layer?** That is the first genuinely new
  context layer ADR-0043's record must express (ADR-0043 OQ3); if it reshapes `ModelCallContextLayers`, the
  generic type wants to absorb that shape before it crosses into the package.

## Related

- [ADR-0043](ADR-0043-model-call-chokepoint.md) — the mechanism this lifts; its **D5** (unify last), **D6**
  (declared layers, not centralized prompts), and **load test** are this ADR's gating logic; its **S3**
  (resolved-tier reporting) is the trigger and carries the most-reusable piece.
- [ADR-0007](ADR-0007-web-recipe-capture-engine.md) — the harvest-now/converge-later precedent, run the other
  direction ([[galavant-capture-engine-reuse]]).
- [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) (tier + effort, the recorded fields),
  [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) (the taste-profile / travel-profile layer both
  apps have), [ADR-0032](ADR-0032-workbench-reference-material-fetch.md) (the unbuilt layer, OQ4).
- Memory: [[withdraw-not-defer-orphaned-schema]] (why the trigger is a real gate, not ceremony),
  [[galavant-capture-engine-reuse]], [[actionable-chat-effort]] (the LLMClientKit lift precedent),
  [[yeschef-onbard-model-tier]] (on-device is the shared degradation target both apps inherit).
