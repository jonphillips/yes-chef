# Decision Log (ADRs)

Settled architecture choices for Yes Chef. **Check these before proposing
architecture changes; don't re-litigate them.** General "how Jon builds software"
decisions live in `~/code/jon-platform`; these record how those bind to Yes Chef
plus any app-specific calls.

- [ADR-0001](ADR-0001-persistence-sqlitedata.md) — Persistence is SQLiteData (not SwiftData/Core Data)
- [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) — Sync is CloudKit via SQLiteData; no server, no auth
- [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) — Private per-person libraries; recipes move by transfer (copy), not co-editing
- [ADR-0004](ADR-0004-structured-recipe-editor.md) — MVP editor uses text entry with structured, non-destructive persistence
- [ADR-0005](ADR-0005-image-storage-and-processing.md) — Recipe images use a pure processing pipeline and recipe-owned storage rows
- [ADR-0006](ADR-0006-taxonomy-source-and-library-placement.md) — Categories stay flexible; source, author, placement, and recipe families are typed concepts
- [ADR-0007](ADR-0007-web-recipe-capture-engine.md) — Web recipe capture harvests Galavant's parser now and converges on a shared package later
- [ADR-0008](ADR-0008-curated-collections.md) — Curated collections are a new sibling of Menu (editorial indexes); reserved now, built post-sync (Proposed)
- [ADR-0009](ADR-0009-in-app-authenticated-browser-capture.md) — In-app authenticated browser capture (rendered logged-in DOM) via WebExtractorKit; never store credentials
- [ADR-0010](ADR-0010-cloudkit-sync-enablement.md) — CloudKit sync enablement specifics: BLOB→CKAsset, lean original-provenance, upsert + dedup-on-read, clean cutover
- [ADR-0011](ADR-0011-actionable-chat-make-ahead.md) — Actionable chat (first cross-app instance): seeded recipe chat + typed `(extract → commit)` apply-action catalog; first verb make-ahead → new `Recipe.makeAhead` field; lifts `GalavantAI` → shared `LLMClientKit` (Accepted)
- [ADR-0012](ADR-0012-menu-actionable-chat.md) — Menu actionable chat: extends ADR-0011 to a composite subject (a whole menu); staged prep plan on `Menu` + complement verb → `MenuItem` + advisory chat; `Menu` scope first, planner-day later (Accepted; shipped PRs #81–#83)
- [ADR-0013](ADR-0013-meal-planner-actionable-chat.md) — Meal-Planner actionable chat: extends ADR-0012 to the absolute-date planner; day-scoped complement verb → `MealPlanItem` + advisory chat; no schema change (Accepted)
- [ADR-0016](ADR-0016-multi-recipe-cook-session.md) — Multi-recipe cook session: cook a planner day's (or menu's) recipes together in the existing Reader with a chip-strip switcher + session-only "done"; not Cooking Mode, no voice, no schema change (Accepted)
- [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) — Frontier default → `gpt-5.5`; add provider-agnostic `reasoningEffort` to `ModelRequest` (OpenAI `reasoning_effort`); effort assigned per feature (lookup=low, judgment=high); model shown in Settings; cross-repo (shared `LLMClientKit`) (Accepted)
- [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) — Prompt customization: layered global **taste profile** injected at the `LLMClientKit` boundary (reaches every generative call, fixing the recipe-chat-only gap) + optional per-task preferences on generative-judgment tasks; never expose raw task prompts (Accepted)
- [ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) — LLM-aligned Compare matrix: semantic row alignment (chicken breast ≡ thigh; chile spellings; morita ≈ chipotle) + role ordering ("protein at top") for the Workbench Compare surface; boundary — LLM drives *presentational* alignment, grocery consolidation stays deterministic; structured-out/verbatim-cells, cached per candidate-set, deterministic `comparisonKey` fallback (Proposed)
