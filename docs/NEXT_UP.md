# Next Up — TestFlight app groups (PROD-CUTOVER 3a + 3c) and chat-access S2b

**Slices:** effort `testflight-app-groups`, in two PRs: jon-platform `scripts/testflight` first, then Yes Chef.
The Yes Chef PR also carries chat-access-mcp S2b.
**Briefs:** docs/efforts/testflight-app-groups.md · docs/efforts/chat-access-mcp.md § S2b
**Done when:** per each brief's "Done when"; verification per `docs/verification.md`. The Yes Chef PR runs
`scripts/check-drift.sh`, and the jon-platform PR runs `scripts/test-testflight`.
**Owed:** the automatic-backups pass (first TestFlight build); see [device-passes.md](device-passes.md).
**Notes:** Schema-free, so it's allowed during the cut. Start from a fresh `main` in both repos. The Yes Chef PR
merges after the jon-platform PR, because its `testflight.conf` uses the new `EXTRA_APP_GROUPS` key. Completing
it sets this file to `Nothing dispatched.`, because the rest of Step 3 is Jon's.
