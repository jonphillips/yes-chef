# Next Up — Chat access over MCP (S1: `stage_recipe` and the app's inbox)

**Slices:** effort `chat-access-mcp`, S1
**Briefs:** docs/efforts/chat-access-mcp.md § S1 (S0 results above it explain why)
**Done when:** per § S1 "Done when"; verification per § S1 and `docs/verification.md`.
**Owed:** Jon's sync failure status pass and raw-HTML repair pass in `docs/device-passes.md`.
**Notes:** One dispatch, two PRs. Land the `LLMHandoffKit` change (colon-free staging names, both-form parsing,
coordinated stage/move, `alreadyClaimed`) in jon-platform first, then the Yes Chef PR that links it. No export,
no read tools, no Dev-variant helper; those are S2 and ADR-0059. The probe screen and probe tools are deleted, not
kept. Start from a fresh `main` in both repos.
