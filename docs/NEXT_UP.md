# Next Up — Chat access over MCP (S0: prove the iCloud Drive transport)

**Slices:** effort `chat-access-mcp`, S0 — probe the transport
**Briefs:** docs/efforts/chat-access-mcp.md § S0
**Done when:** per § S0 and its device pass; verification per `docs/verification.md` and the brief.
**Owed:** Jon's sync failure status pass and raw-HTML repair pass in `docs/device-passes.md`.
**Notes:** S0 results decide whether S1 and S2 proceed; record the five outcomes in the brief before the
architect specifies those slices. Add only the iCloud Documents entitlement, the `ChatAccessFolder` Core
accessor, the DEBUG probe screen, the `YesChefMCP` helper, and its installer. Keep the share extension out of
the entitlement. No `stage_recipe`, inbox, export, or paste-path changes. Start from a fresh `main`.
