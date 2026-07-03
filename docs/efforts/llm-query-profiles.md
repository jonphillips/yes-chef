# Effort: LLM query profiles — retired (pointer)

**Status:** **Retired 2026-07-03.** The `QueryProfile` catalog this doc proposed was **dropped
as premature abstraction** once the first grounded consumer (Vinyl Fever's setlist normalizer)
turned out not to want it. This file is a tombstone + pointer.

## What happened

The catalog idea — a typed `QueryProfile` bundling model/tokens/tier per task kind — was
designed in Yes Chef against zero real headless consumers. Vinyl Fever's setlist normalizer
(PR #24, corpus-grounded) is the actual first consumer, and it uses the existing house pattern
instead: copy Galavant's `HoursExtractor` (build a `ModelRequest` inline, `modelClient.complete`,
defensively parse JSON), and defer any shared lift to **rule-of-three** (`HoursExtractor` +
`EvaluationExtractor` + Normalizer) — a sharper version of "don't pre-extract against zero
consumers." So the catalog had no forcing consumer and was retired. The M5 draft is preserved on
Vinyl Fever's `M5-setlist-norm` branch; it is **not** built.

## What survived, and where it lives

- **Provider resolution (Policy A) — kept, and now earned.** Provider is always the user's
  choice, resolved from configured keys + preference, never hardcoded (`FrontierResolver`,
  `TierIntent`). Yes Chef chat and the Vinyl Fever normalizer (**any-frontier**, Jon 2026-07-03)
  both need it, so it becomes a shared `LLMClientKit` piece when the normalizer forces it; Yes
  Chef's `RecipeChatModel.defaultProvider()` folds in then.
- **The structured-extraction pattern** (copy `HoursExtractor`, lift at rule-of-three).

Both now live as boundary law in jon-platform
`docs/ios/ai-model-access.md` → **Provider resolution and structured extraction**. Read it there.

## Yes Chef's own status (unchanged)

Chat and make-ahead already respect the user's provider by threading `chatModel.activeTier`
(`MakeAheadPlan.swift`, `RecipeModels.swift`). Nothing to build here now; Yes Chef adopts the
shared `FrontierResolver` opportunistically when it lands for Vinyl Fever.

---
*Retired 2026-07-03. Superseded by Vinyl Fever PR #24 (grounded normalizer) and jon-platform
`ai-model-access.md` → Provider resolution and structured extraction.*
