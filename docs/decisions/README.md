# Decision Log (ADRs)

Settled architecture choices for Yes Chef. **Check these before proposing
architecture changes; don't re-litigate them.** General "how Jon builds software"
decisions live in `~/code/jon-platform`; these record how those bind to Yes Chef
plus any app-specific calls.

One line per ADR: its own title and the status its header states. Amendment history lives in the
ADR, not here (jon-platform ADR-0005 D14). Add the line when you write the ADR.

- [ADR-0001](ADR-0001-persistence-sqlitedata.md) — Persistence is SQLiteData, not SwiftData/Core Data *(Accepted)*
- [ADR-0002](ADR-0002-cloudkit-sync-no-server.md) — Sync is CloudKit via SQLiteData; no server, no auth *(Accepted)*
- [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) — Private libraries with recipe transfer (not a co-edited shared library) *(Accepted)*
- [ADR-0004](ADR-0004-structured-recipe-editor.md) — MVP editor uses text entry with structured, non-destructive persistence *(Accepted)*
- [ADR-0005](ADR-0005-image-storage-and-processing.md) — Image storage and processing *(Accepted, 2026-06-16)*
- [ADR-0006](ADR-0006-taxonomy-source-and-library-placement.md) — Taxonomy, source metadata, and library placement *(Accepted, 2026-06-17)*
- [ADR-0007](ADR-0007-web-recipe-capture-engine.md) — Web recipe capture engine harvest and convergence *(Accepted, 2026-06-28)*
- [ADR-0008](ADR-0008-curated-collections.md) — Curated collections (editorial recipe indexes) *(Proposed, 2026-06-30)*
- [ADR-0009](ADR-0009-in-app-authenticated-browser-capture.md) — In-app authenticated browser capture via WebExtractorKit *(Accepted, 2026-06-30)*
- [ADR-0010](ADR-0010-cloudkit-sync-enablement.md) — CloudKit sync enablement: assets, provenance, dedup, and cutover *(Accepted, 2026-06-30)*
- [ADR-0011](ADR-0011-actionable-chat-make-ahead.md) — Actionable chat, first verb: make-ahead distillation *(Accepted, 2026-07-02)*
- [ADR-0012](ADR-0012-menu-actionable-chat.md) — Menu actionable chat: composite-subject verbs + staged prep plan *(Accepted, 2026-07-03)*
- [ADR-0013](ADR-0013-meal-planner-actionable-chat.md) — Meal-Planner actionable chat: day-scoped complement verb *(Accepted, 2026-07-04)*
- [ADR-0014](ADR-0014-recipe-text-editing-model.md) — Recipe text editing model (header toggles vs. rich text) *(Accepted, 2026-07-04)*
- [ADR-0015](ADR-0015-chat-persistence.md) — Chat persistence / history (currently ephemeral) *(Accepted, 2026-07-04)*
- [ADR-0016](ADR-0016-multi-recipe-cook-session.md) — Multi-recipe cook session (Reader-hosted, not Cooking Mode) *(Accepted, 2026-07-05)*
- [ADR-0017](ADR-0017-llm-model-and-reasoning-effort.md) — Frontier model default (GPT-5.5) + per-feature reasoning effort *(Accepted, 2026-07-05)*
- [ADR-0018](ADR-0018-prompt-customization-taste-profile.md) — Prompt customization: a layered taste profile + per-task preferences *(Accepted, 2026-07-05)*
- [ADR-0019](ADR-0019-recipe-design-studies.md) — Recipe Workbench (durable design workspace → working recipe) *(Proposed, 2026-07-05)*
- [ADR-0020](ADR-0020-chat-ui-harvest.md) — Chat UI harvest: a shared `LLMChatUI` package above LLMClientKit *(Proposed, 2026-07-06)*
- [ADR-0021](ADR-0021-recipe-variations.md) — Recipe variations (named deltas on a base recipe, selected in the reader) *(Shipped)*
- [ADR-0022](ADR-0022-llm-aligned-compare-matrix.md) — LLM-aligned Compare matrix (semantic row alignment + role ordering) *(Accepted, 2026-07-07)*
- [ADR-0023](ADR-0023-recipe-edit-proposals.md) — Recipe edit proposals (the "Adjust this recipe" verb, non-destructive by construction) *(Proposed, 2026-07-07)*
- [ADR-0024](ADR-0024-editable-proposal-preview.md) — Editable proposal preview (the apply-action review becomes a roomy, editable sheet) *(Accepted, 2026-07-09)*
- [ADR-0025](ADR-0025-reader-comment-ingestion.md) — Reader Feedback: NYT comment harvest → LLM curation → distinct recipe notes *(Accepted, 2026-07-09)*
- [ADR-0026](ADR-0026-review-collection-sheet.md) — The LLM-review collection is a sheet (the universal "evaluate content from the LLM" surface) *(Accepted, 2026-07-10)*
- [ADR-0027](ADR-0027-harvest-chat-into-notes.md) — Harvest chat into notes: a capture verb (extraction, not generation), selection-scoped *(Accepted, 2026-07-10)*
- [ADR-0028](ADR-0028-multi-foreign-key-sync-loss.md) — Sync status indicator lies during a throttled bulk initial sync (and the multi-FK false lead) *(Accepted, 2026-07-10)*
- [ADR-0029](ADR-0029-main-thread-write-and-fetch-cost.md) — Main-thread DB writes and an over-heavy list fetch cause the UI stalls *(Accepted, 2026-07-11)*
- [ADR-0030](ADR-0030-local-backup-and-restore.md) — Local backup & restore: a CloudKit-independent durability net *(Accepted, 2026-07-12)*
- [ADR-0031](ADR-0031-llmclientkit-responses-api-migration.md) — Migrate the OpenAI backend of LLMClientKit to the Responses API *(Proposed, 2026-07-12)*
- [ADR-0032](ADR-0032-workbench-reference-material-fetch.md) — Workbench reference material (app-side fetch, provider-agnostic context) *(Accepted, 2026-07-23)*
- [ADR-0033](ADR-0033-recipe-detail-polish.md) — Recipe-detail polish: metadata chips + servings-attached scaler *(Accepted, 2026-07-12)*
- [ADR-0034](ADR-0034-prep-plan-work-session-timeline.md) — The prep plan is one weaveable, work-session timeline *(Accepted, 2026-07-12)*
- [ADR-0035](ADR-0035-grocery-store-area-grouping.md) — Group the grocery list by store area, categorized on-device *(Accepted, 2026-07-12)*
- [ADR-0036](ADR-0036-promote-note-to-recipe.md) — Promote a recipe-shaped note into a real recipe *(Accepted, 2026-07-12)*
- [ADR-0037](ADR-0037-grocery-seed-coverage-diagnostic.md) — Seed-coverage diagnostic: a review queue for grocery store-area misses *(Accepted, 2026-07-13)*
- [ADR-0038](ADR-0038-external-llm-handoff.md) — External-LLM handoff: a trackable session, routed by App Intents *(Proposed, 2026-07-13)*
- [ADR-0039](ADR-0039-playbook-column-thinking-vs-doing.md) — The Playbook column: separating *thinking* from *doing* *(Proposed, 2026-07-14; Amendments 4–5 accepted 2026-09-22)*
- [ADR-0040](ADR-0040-editable-at-the-grain-it-is-stored.md) — LLM-populated content is human-editable **at the grain it is stored** *(Accepted, 2026-07-14)*
- [ADR-0041](ADR-0041-playbook-section-toolbar-and-scoped-handoff.md) — Playbook sections become self-serve units: a per-section toolbar and a section-scoped hand-off *(Accepted, complete 2026-07-19)*
- [ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) — The workbench hands off: deliberation outboards, structured writes stay in, and the return block is a terminal turn *(Accepted, 2026-07-20)*
- [ADR-0043](ADR-0043-model-call-chokepoint.md) — Every model call declares itself: one `ModelRequest` chokepoint, test-enforced, with the inventory derived from it *(Accepted, 2026-07-23)*
- [ADR-0044](ADR-0044-provenance-engine-to-llmclientkit.md) — The model-call provenance engine belongs in `LLMClientKit`; Yes Chef keeps the taxonomy — lift after ADR-0043 S3, validated by Galavant *(Proposed, 2026-07-23)*
- [ADR-0045](ADR-0045-onboard-path-stays-viable.md) — The onboard path stays viable: a **seeded, section-scoped Ask**, finalize parity, and the frontier model becomes a **setting** *(Accepted, 2026-07-24)*
- [ADR-0046](ADR-0046-sidebar-adaptable-app-shell.md) — The app shell becomes a **sidebar-adaptable `TabView`**: one taxonomy, one container, a user-switchable first column *(Accepted, 2026-07-25)*
- [ADR-0047](ADR-0047-llm-capture-fallback.md) — Capture escalates to an **LLM extractor** when the page carries no machine contract; capture pills are rejected *(Accepted, 2026-07-26)*
- [ADR-0048](ADR-0048-playbook-edit-grain.md) — Playbook edit affordances are a **readout of storage grain**, not chrome drift; Serve With decomposes to rows *(Accepted, 2026-07-26)*
- [ADR-0049](ADR-0049-unified-labels-and-assisted-tagging.md) — One **hierarchical label** system, and the LLM **proposes** labels against your existing tree *(Accepted, 2026-07-30)*
- [ADR-0050](ADR-0050-recipe-power-browser.md) — The Power Browser is a **contextual faceted query**, and its gate is **coverage**, not code *(Proposed, 2026-08-01)*
- [ADR-0051](ADR-0051-text-to-recipe-extraction-strategy.md) — Text → recipe: one sink, plural front-ends, one extraction engine *(Accepted, 2026-08-05)*
- [ADR-0052](ADR-0052-grocery-learned-area-table.md) — Grocery store-area placement gets a **persistent, synced learned table**; corrections stick, and the LLM **auto-promotes** into it while losing to both the seed and you *(Accepted, 2026-08-05)*
- [ADR-0053](ADR-0053-create-recipe-destination.md) — **Create Recipe** is a destination, not an Add dialog: material in, one reviewed recipe out *(Proposed, 2026-08-07)*
- [ADR-0054](ADR-0054-extraction-preserves-structure-and-identity.md) — Extraction preserves recipe structure and identity: losses at the builder boundary are surfaced, never silent *(Proposed, 2026-08-10)*
- [ADR-0055](ADR-0055-drag-and-drop-on-the-sanctioned-reorder-path.md) — Drag-and-drop belongs on the sanctioned reorder path, and beta parks belong in a standing file *(Proposed, 2026-08-19)*
- [ADR-0056](ADR-0056-move-to-production-and-data-carry.md) — Moving to production: the dogfood library crosses in place, and backup→restore is the verified re-seed *(Accepted, 2026-08-24)*
- [ADR-0057](ADR-0057-prepared-components.md) — Prepared Components are **recipes with a `kind`**, linked to the dishes that use them by a **directional recipe-grain edge**; the flavor vocabulary is **one new facet surfaced as "Dimension"**; inventory stays out *(Accepted, 2026-09-17)*
- [ADR-0058](ADR-0058-cockpit-find-referral-transport.md) — Cockpit Find referrals travel through a **pair-scoped App Group mailbox**, opened by a **single-purpose `yeschef://find-referral` door**; the verdict returns silently *(Accepted, 2026-09-24)*
- [ADR-0059](ADR-0059-yes-chef-dev-variant.md) — Yes Chef Dev: after the cut, Debug builds get their own app identity, and backups say which build made them *(Accepted, 2026-11-01)*
- [ADR-0060](ADR-0060-chat-access-over-mcp.md) — Chat assistants reach Yes Chef through a local MCP server, and an iCloud Drive folder carries the inbox and the read data to and from the phone *(Accepted, 2026-10-22)*
