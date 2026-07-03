# Effort: LLM query profiles — pointer

**Type:** Cross-app AI-boundary design (LLMClientKit).
**Status:** **Design record promoted to jon-platform.** This file is a pointer, not the source
of truth.

The query-profile decision — a typed `QueryProfile` catalog, `TierIntent` + a shared
`FrontierResolver`, **Policy A** (provider is always the user's choice; workers never override
it), and the FUTURE seam extensions (`effort`, per-task model) — now lives as the **Query
profiles** section of jon-platform `docs/ios/ai-model-access.md`, alongside the ModelClient
boundary law it extends. Read it there; keep it current there.

## Why it's not built in Yes Chef

Yes Chef's only LLM consumers are **chat** and **make-ahead extraction**, and both already
respect the user's provider by threading `chatModel.activeTier`
(`MakeAheadPlan.swift:44` extract takes `tier`; `RecipeModels.swift:931` threads the chat tier).
There is **no headless worker** here — nothing that needs a provider without a conversation to
thread one from — so building the catalog in Yes Chef would be scaffolding against zero new
consumers (the pattern ADR-0011 rejected).

The catalog is built at its **first headless consumer: Vinyl Fever's LLM setlist normalization**
(structured extraction over messy show notes, deterministic parser kept as validator). That's
where `TierIntent` / `FrontierResolver` / `QueryProfile` land in `LLMClientKit` and
`.structuredExtraction` is first consumed.

## What Yes Chef does when the catalog exists

Adopt it **opportunistically**, not as a reason to build:
- Lift `RecipeChatModel.defaultProvider()`/`activeTier` resolution onto the shared
  `FrontierResolver` so chat and workers share one algorithm (keep chat's live
  `useFrontier`/`selectedProvider` override — that's chat-only UI state).
- Optionally re-point make-ahead onto `QueryProfile.structuredExtraction` for consistency (its
  tier still comes from chat).

---
*Design captured 2026-07-03; promoted to jon-platform `ai-model-access.md` → Query profiles the
same day when Vinyl Fever surfaced as the first headless consumer.*
