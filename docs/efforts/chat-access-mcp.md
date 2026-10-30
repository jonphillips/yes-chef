# Effort — Chat access over MCP

Status: Blocked — S3 waits on [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) OQ3. Schema-free throughout.
Summary: S3 lets a ChatGPT return target an existing recipe, not only stage a new one; S0–S2b shipped.

Related: [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) · jon-platform
`docs/adr/0007-app-data-over-local-mcp.md` and its Amendment 1 · jon-platform `docs/ios/mcp-access.md` (tunnel
ops) · vinyl-fever `docs/milestones/M12-library-context-mcp.md` (the first consumer) ·
[`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md)

## Shipped

S0 (transport probe, #357), S1 (`stage_recipe` and the app's inbox, #359), S2 (the export and the read tools,
#376) and S2b (search rows show categories, #381) shipped; their records are in [`DONE-LOG.md`](../DONE-LOG.md),
and the S2b device pass is owed in [`device-passes.md`](../device-passes.md). Their full build specs are in git
history (this file before the 2026-10-30 archive sweep). The S0 results and the constants register stay below
because S3 builds on both.

## S3 — Returns that target an existing recipe

Waits on ADR-0060 OQ3. The architect specifies this slice here once OQ3 is answered; until then there is no
next step to dispatch.

## S0 results

Recorded 2026-10-22 on the iPhone 17 Pro, the iPad Pro 13-inch (M5), and Jon's Mac (macOS 26), with the S0 build
from PR #357.

| # | Result |
| - | --- |
| Q1 | **Pass.** A small iPhone file reached the Mac in under a minute; the iPhone wrote it at 20:01:25 and `MCP/` on the Mac changed at 20:02. iCloud created `~/Library/Mobile Documents/iCloud~com~jonphillips~yeschef/` itself, so a Mac with no Yes Chef app gets the container. The helper's rule of never creating the container folder is right. |
| Q2 | **Pass, with one prompt that stays granted.** The first ChatGPT `probe_list` call raised one macOS prompt about accessing iCloud Drive (exact text not captured). macOS attributes the grant to **`tunnel-client`**, not `yeschef-mcp`: System Settings → Privacy & Security → Files & Folders shows `tunnel-client` with iCloud Drive on. The grant held across later calls and across an agent restart, and rebuilding the helper doesn't reopen it. Launched from a Claude Code shell (under the Claude app) and from Terminal.app, the helper listed the folder with no failure. |
| Q3 | **Pass.** A `probe_write` file reached the iPhone in about 6–7 s with the app in the foreground. The metadata query found it, and it was still listed after a force-quit and relaunch. |
| Q4 | **Fail: the helper can't read an evicted file.** Here the Mac evicted files on its own: a 42-byte iPhone file and a 73-byte Mac-written file were both `compressed,dataless` (`ls -lO`) within about 10 minutes. `probe_list` then listed the file (name, size, status) but its read failed with `The file "…" couldn't be opened.`. The same read from a shell (`cat`) downloaded the file and succeeded, and `probe_list` succeeded again afterwards. The 10 MB timing wasn't measured, because the read fails before the download starts. |
| Q5 | **Pass.** The iPad sees the Mac-written file too, so the claim race in ADR-0060 D3 is real. |
| Q6 | **Added during the pass: colons don't survive the trip.** A Mac file named `colon-test-2026-10-23T00:40:00Z.txt` showed on the iPhone as `colon-test-2026-10-23T00/40/00Z.txt`. The probe's own file names had already avoided colons (the #357 review asked for that), and those arrived intact. `LLMHandoffKit.HandoffInbox` names staged files with extended ISO 8601 (`2026-10-22T20:00:00Z-<slug>`), and on the phone its parser would drop those files silently. |

**Verdict.** Q1–Q3 pass with one prompt that a single grant covers, so **ADR-0060 D2 stands**: the helper reads
and writes the container directly, and OQ1's signed Mac app isn't needed. Two requirements follow from Q4 and Q6,
and both were built into S1 and S2:

1. **Never read a container file without making it current first, on either side.** On iOS this was always
   the plan (ADR-0060 D2: metadata query, then a download request). On the Mac it's new. A process launched by
   `tunnel-client` doesn't trigger the download when it reads a dataless file, and on this Mac eviction is
   routine, not an edge case. S1's helper only writes. S2's export reader is the first Mac-side read, so S2
   builds the materialize-then-read path and re-runs Q4 against the real export.
2. **File names in the container are colon-free.** S1 changes `HandoffInbox` to name staged files with basic
   ISO 8601 (`20261022T200000Z-<slug>`) and to parse both forms.

## Constants register

| Constant | Value | Why |
| --- | --- | --- |
| `Processed/` retention | 30 days | Long enough to recover a mistaken Discard. Short enough that consumed items don't build up (OQ2). |
| Export minimum interval | 15 min | Recipes change slowly, and a multi-MB file shouldn't be re-uploaded on every app switch. Refresh overrides it. |
| Meal-plan window in the export | −30 to +60 days | Covers "what did I make last month" and "plan the next few weeks" without exporting the whole calendar. |
| Materialize deadline | 60 s | Half the 120 s tool deadline, leaving room for decoding and the reply. |
| Tool row cap | 20 default, 50 max | Vinyl Fever M12's precedent. The conversation pays for every byte. |
