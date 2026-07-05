# ADR-0017 — Frontier model default (GPT-5.5) + per-feature reasoning effort

Status: **Accepted** (2026-07-05, resolved in design session with Jon). Binds jon-platform
`docs/ios/ai-model-access.md` and the shared **`LLMClientKit`** package (path-dep). This is the
first ADR to change a *shared-package default*, so it is **cross-repo**: the wire change lands in
`jon-platform/packages/LLMClientKit` and affects every app that consumes it — make it deliberately.
Paired with **ADR-0018** (prompt customization); the two share the same files and ship as one dispatch.

## Context

The OpenAI backend defaulted to `gpt-5.2-chat-latest` — the *chat-optimized, non-reasoning* variant,
originally picked to keep the live chat responsive. Jon's push exposed that this optimizes the wrong
variable: `gpt-5.5` is strictly newer and better, and there is **no Yes Chef task where 5.2 returns a
better answer than 5.5.** "Keep 5.2 for latency" protects responsiveness by *downgrading the brain*.

The correct decomposition separates two knobs that were conflated:

- **Model = the capability floor.** Pick the best one and never look back.
- **`reasoning_effort` = the depth/latency/cost dial.** The *only* thing tuned per task.

Once separated, the design collapses: **one model everywhere, effort varies by task.** The tasks
cluster cleanly:

- **Lookup-shaped** (ingredient substitution, capture parsing, scaling) — correctness is *recall*,
  not deliberation. Thinking longer doesn't make "buttermilk or milk+lemon" more right.
- **Judgment-shaped** (Chef It Up, Serve With, make-ahead / prep-plan sequencing, complements) —
  the model reasons over constraints (what's in the dish, technique, timing, what pairs). Extended
  reasoning materially improves the answer, and **every one of these sits behind a loading state, not
  a live token stream** — so the added latency is invisible. Jon: "I certainly don't mind waiting
  another 10 seconds."

Effort down on lookups is a **cost** optimization (reasoning tokens are billed), not a quality one.

### What exists today (verified at session start)

- `OpenAIWire.defaultModel = "gpt-5.2-chat-latest"`; `AnthropicWire.defaultModel = "claude-opus-4-8"`
  (already correct — no change). The wire is **Chat Completions**, not the Responses API.
- `ModelRequest` has **no reasoning field**. The "tiered" system routes *on-device vs frontier vs
  which-provider* only — nothing to do with task complexity. The complexity-router we once discussed
  was never built; this ADR deliberately does **not** build an auto-router — each call site *declares*
  its effort.
- Every AI call assembles a `ModelRequest` at a known call site (`RecipeChat`, `MenuPrepPlan`,
  `MenuComplement`, `MealPlanComplement`, `MakeAheadPlan`, `MealPlanMakeAheadStrategy`,
  `RecipeEnrichment`).

## Decision

Default the frontier OpenAI backend to **`gpt-5.5`**, add a **provider-agnostic `reasoningEffort`
field** to `ModelRequest`, and **assign effort per feature**. Retire `gpt-5.2-chat-latest`. Surface the
active model read-only in Settings.

### Resolved decisions (D1–D5, ratified by Jon 2026-07-05)

- **D1 — `gpt-5.5` is the sole OpenAI default; `gpt-5.2-chat-latest` is deleted.** There is no task
  that wants the older model. Anthropic stays `claude-opus-4-8`.
- **D2 — Add `reasoningEffort` to `ModelRequest`** (new enum `ReasoningEffort`: `none / low / medium /
  high / xhigh`, mirroring OpenAI's set; **`nil` = provider default**, which is `medium` for 5.5). The
  OpenAI wire emits it as a **top-level `reasoning_effort` string** (Chat Completions shape — *not* the
  Responses-API `reasoning: {effort}` nesting; verify the field name against current OpenAI docs at
  build, per the file's existing convention). Anthropic **ignores** it for now — its symmetric knob is
  extended-thinking budget, a later follow-on (D2a). On-device ignores it (already the pattern).
- **D3 — Effort is assigned per feature, not auto-inferred.** The standing policy table (new features
  inherit it):

  | Call site | Shape | Effort |
  |---|---|---|
  | `RecipeChat` live/streaming chat | conversational, **extract-ready** | `medium` |
  | `RecipeChat` substitution verb | lookup | `low` |
  | `RecipeEnrichment` (capture parse) | extraction | `low` (`none` acceptable) |
  | `RecipeChat` Chef It Up / Serve With | generative judgment | `high` |
  | `MakeAheadPlan` / `MealPlanMakeAheadStrategy` | multi-constraint sequencing | `high` |
  | `MenuPrepPlan` extraction | plan orchestration | `high` |
  | `MenuComplement` / `MealPlanComplement` | judgment | `medium` |

  The live *streaming* chat is the only place reasoning latency is truly visible (medium effort adds a
  brief think before tokens start). Jon accepts that trade **deliberately**: he wants chat answers smart
  enough to **extract straight into a verb** (make-ahead, Chef It Up, …) without re-asking the question —
  so live chat is `medium`, not `low`. The knob is still effort, never an older model.
- **D4 — The active model is shown read-only in Settings** (`AISettingsView`), one row per provider
  ("Model: gpt-5.5" / "Model: claude-opus-4-8"). Confidence about who you're talking to; no per-chat
  clutter. No auto-router status to show — effort is a build-time policy (D3), not user-facing here.
- **D5 — Cross-repo discipline.** The model default + `reasoning_effort` wire change lives in
  `LLMClientKit` (shared). Update jon-platform `docs/ios/ai-model-access.md` in the same change and
  note the sibling-app impact in the PR. The Yes Chef side is only the D3 call-site assignments + D4.

### Why not

- **Why not an auto-complexity router?** It guesses; declared effort is explicit, testable, and free.
  The router was the thing we deliberately stepped back from — this ADR does not resurrect it.
- **Why not keep a fast chat model for streaming?** `gpt-5.5` at `low`/`none` *is* the fast path, on a
  better model. No reason to keep two models.
- **Why not wire Anthropic thinking now?** Opus 4.8 without thinking is fine for our tasks; the field
  is provider-agnostic so the budget mapping can be added later without touching call sites.

## Slice plan (one dispatch with ADR-0018)

- **S1 — Package: model + effort knob** (`LLMClientKit`). `defaultModel → "gpt-5.5"`; add
  `ReasoningEffort` + `ModelRequest.reasoningEffort`; `OpenAIWire` emits `reasoning_effort` when set,
  omits when `nil`. One wire test (present-when-set / absent-when-nil). Update `ai-model-access.md`.
- **S2 — Effort per feature** (Yes Chef call sites, per the D3 table).
- **S3 — Model shown in Settings** (`AISettingsView`, D4).

## Related

- **ADR-0018** (prompt customization — taste profile + per-task preferences; same dispatch).
- ADR-0011 (actionable chat — lifted `LLMClientKit`), ADR-0012 (menu chat; its context fix rides the
  menu overhaul, not this dispatch).
- jon-platform `docs/ios/ai-model-access.md` (multi-provider amendment — this ADR bumps §2 defaults).
- Memory: `actionable-chat-effort`, `llm-curation-not-synthesis`.
