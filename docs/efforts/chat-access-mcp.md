# Effort — Chat access over MCP (S0: prove the iCloud Drive transport)

Status: Designed 2026-10-21, queued after [`sync-failure-surfacing.md`](sync-failure-surfacing.md). Schema-free.
One entitlement change (iCloud Documents on the existing container). S0 is a **probe**: its results decide
whether S1 and S2 go ahead as [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) D2 says, so they're
specified only after S0 reports.
Summary: Make Yes Chef the second consumer of jon-platform ADR-0007, so ChatGPT can stage a recipe into Yes Chef
and look things up in the library instead of Jon pasting in both directions. Yes Chef isn't on the Mac, so an
iCloud Drive folder carries the inbox and the read export between the Mac helper and the phone. S0 proves that
transport end to end with probe tools before anything is built on it.
Related: [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) · jon-platform
`docs/adr/0007-app-data-over-local-mcp.md` and its Amendment 1 · jon-platform `docs/ios/mcp-access.md` (tunnel
ops) · vinyl-fever `docs/milestones/M12-library-context-mcp.md` (the first consumer) ·
[`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md)

## Slices

- **S0 — Probe the transport** (this brief, below). One PR with code plus Jon's device pass. Its results go in
  [§ S0 results](#s0-results).
- **S1 — `stage_recipe` and the app's inbox** (ADR-0060 D3, D5). This is specified after S0.
- **S2 — The export and the read tools** (ADR-0060 D4, D6). This is specified after S0.
- **S3 — Returns that target an existing recipe.** This waits on ADR-0060 OQ3.

## S0 — Probe the transport

**The question:** can a helper on the Mac, launched by `tunnel-client`, write a file that Yes Chef on the
iPhone finds? And can that helper read a file the iPhone wrote? The S0 code is shaped so that S1 can keep it:
the entitlement, the container accessor, and the helper package. Only the two probe tools and the DEBUG probe
screen are thrown away.

### Build

1. **The entitlement.** Add the iCloud Documents service to the app target for the existing container:
   `CloudDocuments` in `com.apple.developer.icloud-services`, plus
   `com.apple.developer.ubiquity-container-identifiers` = `iCloud.com.jonphillips.yeschef`. Don't add an
   `NSUbiquitousContainers` publish entry; the container stays out of Files. The share extension doesn't get
   the entitlement. If `project.yml` owns the entitlements, change it there and regenerate.
2. **A Core accessor, `ChatAccessFolder`.** It resolves `<ubiquity container>/MCP/` (or `MCP-Dev/` in a Yes Chef
   Dev build, per ADR-0060 D5; until ADR-0059 lands, every build is production). It runs
   `FileManager.url(forUbiquityContainerIdentifier:)` off the main actor, since the call can block, and creates
   the folder if it's missing. A `nil` container (iCloud signed out, or Documents turned off) is a typed error,
   never a crash. Pure path logic is tested in Core; the live resolve is app-side.
3. **A DEBUG-only probe screen in Settings** (`#if DEBUG`, removed in S1):
   - **Write probe:** writes `MCP/Probe/from-<device name>-<ISO 8601 time>.txt`, holding the device name and the
     time.
   - **Write large probe:** writes a ~10 MB text file to `MCP/Probe/large-<device name>.txt`. It stands in for an
     export.
   - **The file list:** an `NSMetadataQuery` over `MCP/Probe/` with `NSMetadataQueryUbiquitousDataScope`. For each
     file it shows the name, the download status, and when the device first saw it. It requests the download of
     any file that isn't current, and displays the contents of small files once they've downloaded.
4. **The helper package `YesChefMCP/`** (macOS only), as a new repo-root package. It depends on `YesChefPackage`
   and `../../../jon-platform/packages/MCPServerKit` by path, which is the same relative layout `YesChefPackage`
   already uses. It builds one executable product, `yeschef-mcp`, with two probe tools:
   - `probe_list` (`readOnlyHint: true`) lists `MCP/Probe/` with each file's size, modification time, and whether
     it's materialized on the Mac. For each `.txt` file under 4 KB, it returns the first 200 characters. For the
     large file, it reads the whole file and returns only its byte count and how long the read took. That read
     is the eviction test.
   - `probe_write` (`readOnlyHint: false`) takes a `note` string and writes
     `MCP/Probe/from-mac-<ISO 8601 time>.txt`, then returns the file name.
   - The helper finds the container at `~/Library/Mobile Documents/iCloud~com~jonphillips~yeschef/`. If the
     folder doesn't exist, it returns an `isError` result that names the path, and it **doesn't create the
     container folder itself**: whether iCloud does is one of the things this probe finds out. Server
     `instructions` say only that these are probe tools.
5. **`scripts/install-yeschef-mcp`** builds `yeschef-mcp` in release mode and copies it to
   `~/Library/Application Support/YesChefMCP/yeschef-mcp`. It prints the path so it can go into `mcp-tunnel init`.
   No signing beyond what `swift build` does: if the unsigned helper can't reach the container, that's an S0
   result, not something to engineer around.

**Out of scope:** `stage_recipe`, `HandoffInbox`, the export, the inbox UI, and any change to the paste path.

### Verification (Codex)

- `scripts/check-drift.sh`.
- The elevated generic iOS build from `docs/verification.md`. It's what proves the entitlement change and the
  DEBUG screen compile.
- `quiet-run swift build --package-path YesChefMCP`, plus a test in `YesChefMCP` that uses `MCPServerKit`'s
  in-memory harness against a temporary folder. It runs `tools/list`, then `probe_write`, then `probe_list`, and
  checks the missing-container error. The live path is injected, so the test never touches iCloud.
- `YesChefTests` isn't required, because no app model changes.
- No simulator runs and no device installs. The device part is Jon's (below).

### Jon's device pass (this is where the probe's answers come from)

Setup: install the S0 build on the iPhone (with signing, so the entitlement is real) and on the iPad. Run
`scripts/install-yeschef-mcp`. Make the `yeschef` tunnel and its profile with jon-platform
`scripts/mcp-tunnel` (create the tunnel, `init`, `install-agent`), then add the `Yes Chef` plugin in ChatGPT.
Fill in one row per question in [§ S0 results](#s0-results):

| # | Do this | What it answers |
| - | --- | --- |
| Q1 | iPhone: **Write probe**. On the Mac, wait, then `ls` the container path. | Does the container reach a Mac that has no Yes Chef app on it, and how long does that take? |
| Q2 | ChatGPT (on the iPad, with the Mac awake): ask it to call `probe_list`. Then do the same from a Claude Code session in a scratch folder, and from Terminal by piping an `initialize` and a `tools/call` request into `yeschef-mcp`. | Can the helper read the container when each of the three launches it? Does macOS show a privacy prompt, and to which process? Can it be granted once, for good? |
| Q3 | ChatGPT: call `probe_write`. Watch the iPhone probe screen while the app is in the foreground. Then force-quit and relaunch it. | Does a file written on the Mac reach the iPhone, and how long does it take? Does the metadata query find it in the foreground, and after a relaunch? |
| Q4 | iPhone: **Write large probe**. Once it's on the Mac, evict it (`brctl evict <path>`, or Finder → Remove Download), then call `probe_list` from ChatGPT. | Does reading an evicted file make macOS download it, or does the read fail? How long does it take, and is it within the 120 s tool deadline? |
| Q5 | iPad: the probe screen. | Does the second device see the Mac's file too? (That's the claim race S1 has to handle.) |

### S0 results

*Fill in during the device pass. One line per question: the outcome, any prompt text exactly as shown, and the
timings.*

| # | Result |
| - | --- |
| Q1 | |
| Q2 | |
| Q3 | |
| Q4 | |
| Q5 | |

**How to read them:**
- If Q1–Q3 pass with no prompt, or with one prompt that can be granted for good, ADR-0060 D2 stands, and the
  architect specifies S1 and S2 here.
- If Q2 fails (no access, or a prompt that comes back or can't be answered by a LaunchAgent), D2 reopens. The
  leading fallback is ADR-0060 OQ1's: a small signed Mac app that holds the ubiquity entitlement and runs the
  helper.
- If only Q4 fails, S2's export reader has to trigger the download itself (with `brctl download`, or a
  coordinated read) before it reads.

### Done when

- The code above has merged, and the checks in Verification are green.
- `DONE-LOG.md` has the entry. `NEXT_UP.md` is set to `Nothing dispatched.`, because S1 is specified only from
  the results. The device pass is listed in `device-passes.md`, with a one-line pointer under **Owed**.
- After Jon's pass: the S0 results table is filled in, and ADR-0060 OQ1 is marked answered. Both happen in the
  architect's plan PR that specifies S1.
