# Effort — Chat access over MCP

Status: Designed 2026-10-21. S0 shipped (#357) and its device pass cleared 2026-10-22: D2 stands (§ S0 results).
S1 shipped (#359) and its device pass cleared 2026-10-23. **S2 shipped (#376) with its badge and Mac materialization device pass owed. S3 waits on ADR-0060 OQ3.** Schema-free throughout.
Summary: Make Yes Chef the second consumer of jon-platform ADR-0007, so ChatGPT can stage a recipe into Yes Chef
and look things up in the library instead of Jon pasting in both directions. S0 proved the iCloud Drive transport;
S1 builds `stage_recipe` and the app's inbox, and S2 builds the library export and the read tools.
Related: [ADR-0060](../decisions/ADR-0060-chat-access-over-mcp.md) · jon-platform
`docs/adr/0007-app-data-over-local-mcp.md` and its Amendment 1 · jon-platform `docs/ios/mcp-access.md` (tunnel
ops) · vinyl-fever `docs/milestones/M12-library-context-mcp.md` (the first consumer) ·
[`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md)

## Slices

- **S0 — Probe the transport** (this brief, below). One PR with code plus Jon's device pass. Its results go in
  [§ S0 results](#s0-results).
- **S1 — `stage_recipe` and the app's inbox** (ADR-0060 D3, D5, D6). [§ S1](#s1--stage_recipe-and-the-apps-inbox).
  Shipped (#359); device pass cleared 2026-10-23.
- **S2 — The export and the read tools** (ADR-0060 D4, D6), plus the S1 badge fix.
  [§ S2](#s2--the-export-and-the-read-tools). Shipped (#376); badge and Mac materialization device pass owed.
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
and both are built into S1 and S2 below:

1. **Never read a container file without making it current first, on either side.** On iOS this was always
   the plan (ADR-0060 D2: metadata query, then a download request). On the Mac it's new. A process launched by
   `tunnel-client` doesn't trigger the download when it reads a dataless file, and on this Mac eviction is
   routine, not an edge case. S1's helper only writes. S2's export reader is the first Mac-side read, so S2
   builds the materialize-then-read path and re-runs Q4 against the real export.
2. **File names in the container are colon-free.** S1 changes `HandoffInbox` to name staged files with basic
   ISO 8601 (`20261022T200000Z-<slug>`) and to parse both forms.

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

## S1 — `stage_recipe` and the app's inbox

**What it retires:** the paste-back. In a chat with the `Yes Chef` plugin, the model calls `stage_recipe`
instead of printing JSON-LD for Jon to copy, and the recipe appears in Create Recipe on the iPhone and iPad.
Save there is still the only write (ADR-0060 D3). The probe tools and the DEBUG probe screen go away.

One dispatch, two PRs: the `LLMHandoffKit` change (step 1) lands first in jon-platform, because Yes Chef builds
against it by path. The Yes Chef PR links it.

### Build

1. **`LLMHandoffKit.HandoffInbox` (jon-platform)** — Q6, and the claim from ADR-0060 D3:
   - `stage` names files with basic ISO 8601, `20261022T200000Z-<slug>.<ext>`, so no colon reaches iCloud
     Drive. The collision suffix is unchanged.
   - The name parser accepts the basic form **and** the extended form, so Vinyl Fever's existing Mac-local items
     still list. Make it public (for example `StagedHandoff.init?(url:)`), so an app that discovers files through
     a metadata query reads the staging time from the name without calling `list()`.
   - `stage` and `markProcessed` go through `NSFileCoordinator` (a coordinated write, and a coordinated move
     with `.forMoving`). Apple requires coordination in a ubiquity container, and it's harmless in a local
     folder.
   - `markProcessed` on an item whose file is gone throws a typed `HandoffInboxError.alreadyClaimed`, not a raw
     Cocoa error, so a caller can tell "another device took it" from a real failure.
   - Tests: a staged name has no colon; both forms parse; `alreadyClaimed` throws on a missing source.
     `swift test` for `LLMHandoffKit`, plus vinyl-fever `swift test --package-path VinylFeverCore` (its
     `PlaylistInboxClient` is the other consumer).
2. **Core (`YesChefPackage`):**
   - `ChatAccessFolder` gains `inboxURL` (`MCP/Inbox/`) and `processedURL` (`MCP/Inbox/Processed/`), and loses
     `probeURL`. Keep the `isDevelopment` parameter. Nothing passes `true` until ADR-0059 lands (ADR-0060 D5).
   - **The contract check**, `RecipeContractStaging.validate(_ jsonLDText:)`: the deterministic JSON-LD tier of
     `CreateRecipeExtraction` and nothing else. It never falls through to the LLM engine, because the helper
     makes no network calls. It returns the extracted recipe, or a typed reason the model can act on: not
     JSON, no `Recipe` node, or no ingredients and no instructions. No second parser (ADR-0051).
   - **The server instructions**, `ChatAccessServerInstructions.text`. The first 512 characters stand alone:
     these are Yes Chef's recipe tools, call `stage_recipe` with one schema.org Recipe object when Jon wants a
     recipe sent to Yes Chef, and Jon reviews and saves it in the app. Then comes `RecipeJSONLDContract
     .projectSource`, then the fallback rule from ADR-0060 D6: if a tool call fails or times out, print the
     JSON-LD object for Jon to paste instead.
   - **The drift test** ADR-0060 D6 requires: `docs/chatgpt/RECIPE-CONTRACT.md` equals
     `RecipeJSONLDContract.projectSource`, and `docs/chatgpt/PROJECT-INSTRUCTIONS.md` equals
     `AIHandoffReturnContract.projectInstructions`, after trimming the trailing newline. No such test exists
     today.
   - **Pure inbox logic**, so it's testable without iCloud: `ChatAccessInbox.rows(from:)`, which turns metadata
     snapshots (name, download status) into rows, sorted newest first and skipping unparseable names, and
     `ChatAccessInbox.expired(_:now:)`, which picks the `Processed/` items older than the retention period.
3. **The helper (`YesChefMCP`):**
   - Remove `probe_list` and `probe_write`. Add **`stage_recipe`** with input `{"recipe": <object>}`, where the
     object is the JSON-LD Recipe. Serialize it to text, check it with `RecipeContractStaging.validate`, and on
     failure return `isError` with the reason, staging nothing. On success, stage it with
     `HandoffInbox(root: inboxURL, fileExtension: "json")`, using the recipe's name as the slug. Return
     `{"staged": "<recipe name>", "next": "Jon reviews and saves it in Yes Chef → Create Recipe."}`, with no
     path (ADR-0007 D5). Annotations: `readOnlyHint: false`, `destructiveHint: false`, `openWorldHint: false`.
   - Keep S0's missing-container `isError`, and keep never creating the container folder. Create `MCP/Inbox/`
     if it's missing.
   - `instructions` = `ChatAccessServerInstructions.text`.
4. **The app:**
   - **The live resolver** moves out of the probe file into its own app-side dependency (`@Dependency`), with
     the typed nil-container error (#357 review). Delete `ChatAccessProbeView.swift` and its Settings link.
   - **The inbox model** (`@Observable @MainActor`) runs an `NSMetadataQuery` over `MCP/Inbox/`'s top level,
     excluding `Processed/`. Its notification observers are bound to **that query object**, not `object: nil`
     (#357 review). It builds rows with `ChatAccessInbox.rows`, asks for any item that isn't current to be
     downloaded, and shows it as downloading until it is.
   - **The UI:** when the inbox has items, Create Recipe shows a **From Chat** list above its paste field. Each
     row has the recipe name and when it was staged, and the actions **Open** and **Discard**. The Create Recipe
     destination shows the item count as a badge.
   - **Open:** a coordinated read once the item is current, then `markProcessed` (the claim), then
     `CreateRecipeCoordinator.stage(text:)`, the same seam as paste and the Shortcut. If the claim throws
     `alreadyClaimed`, drop the row quietly. If the read fails, keep the item and show the error on its row.
     **Discard** is `markProcessed` with no stage. A claim race can still happen: two devices that both open the
     same item within the sync window (S0 Q3 measured about 7 s) both get it. That's acceptable, because Save is
     a human act on one device. Don't build a lock.
   - **Retention (answers ADR-0060 OQ2):** on each foreground, coordinated-delete the `Processed/` items that
     `ChatAccessInbox.expired` returns, meaning those staged more than **30 days** ago. Use the staging time
     from the name, falling back to the modification date. This is the only delete (ADR-0007 Amd 1-D3).
   - **The probe leftovers:** once per install, remove `MCP/Probe/` if it exists (coordinated), so no dead data
     stays in the synced folder.
   - The share extension still gets no ubiquity entitlement.
5. **`scripts/install-yeschef-mcp`** installs to `~/.local/bin/yeschef-mcp`, a path with no spaces, because
   `tunnel-client` splits `--mcp-command` on whitespace (jon-platform #79). It replaces the symlink Jon made
   during S0 and removes the old `~/Library/Application Support/YesChefMCP/` copy. Jon's `yeschef` tunnel
   profile already points at that path, so it doesn't change.
6. **Docs:** [`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md) gains a short MCP section (ADR-0060 D1). It covers
   `scripts/install-yeschef-mcp`, the `yeschef` profile on health port 8081, the one `stage_recipe` tool, the
   one-time iCloud Drive grant that lands on `tunnel-client`, and the rule that the Project and paste stay the
   fallback. jon-platform `mcp-access.md` stays the ops recipe.

**Out of scope:** the export and the read tools (S2), returns that target an existing recipe (S3), a Dev-variant
helper (`--variant dev` waits for ADR-0059), and any change to the paste path or the Shortcut.

### Verification (Codex)

- `scripts/check-drift.sh`, which now also runs `swift test --package-path YesChefMCP` (#357 review). Add it to CI
  too if the reusable workflow accepts a second package. If it doesn't, say so in the PR.
- The elevated generic iOS build.
- `YesChefTests`, because this adds an app model.
- `LLMHandoffKit`'s tests and vinyl-fever `VinylFeverCore`'s tests, in the jon-platform PR.
- Helper tests with the in-memory harness against a temporary container: `tools/list` shows only
  `stage_recipe`. A valid object stages exactly one colon-free `.json` file whose text round-trips through
  `RecipeContractStaging.validate`. An invalid object returns `isError` and stages nothing. The missing-container
  error doesn't create the folder.

### Jon's device pass

Install the build on the iPhone and the iPad, run `scripts/install-yeschef-mcp`, and refresh the plugin in
ChatGPT (plugin page → **Refresh**) so it picks up the new tool list.

1. In a ChatGPT chat **outside** the `Yes Chef` Project, ask for a recipe and to send it to Yes Chef. ChatGPT
   asks for confirmation. The recipe appears under **From Chat** in Create Recipe on the iPhone (note the time it
   takes). Open it, review it, and save it. On the iPad, the row disappears.
2. Ask for a recipe with no ingredients or steps. The tool returns an error, and the model corrects itself or
   says why it can't.
3. Stage one more recipe and **Discard** it.
4. With the `yeschef` agent stopped (`scripts/mcp-tunnel uninstall-agent yeschef`), ask again. The model prints
   the JSON-LD for pasting. Then restart the agent with `install-agent yeschef`.
5. On the Mac, `ls` `MCP/Inbox/Processed/`: it holds the claimed and discarded files, with colon-free names, and
   `MCP/Probe/` is gone.

### Done when

- Both PRs have merged and Verification is green.
- The completing PR adds the `DONE-LOG.md` entry, lists the device pass in `device-passes.md` with the **Owed**
  pointer, and sets `NEXT_UP.md` to `Nothing dispatched.`. S2 is dispatched by the architect after the pass,
  because its read path is the next thing that could be wrong.

## S2 — The export and the read tools

**What it retires:** the copy-out. ChatGPT can search the library and read a recipe or a menu instead of Jon
pasting one in. Specified 2026-10-22; queued after sync-failure-surfacing Slice 5. It starts with S1's one defect.

### Build

0. **Fix S1's Create Recipe badge (it never rendered).** S1 put `.badge(chatAccessInboxModel.inboxCount)` on
   the Create Recipe `Tab` in `AppMainLayout`. In Jon's S1 pass, no count showed on the iPad sidebar or on the
   iPhone, while the From Chat list, which reads the same `inboxCount`, showed its rows. So the count is right
   and the badge isn't drawn.
   - **Find the cause before changing anything**, and name it in the PR. Candidates: the modifier order after
     `.defaultVisibility(.hidden, for: .tabBar)`, a tab hidden from the tab bar not drawing badges in the sidebar
     on iOS 27, or the count read not being tracked from the `TabView` builder. For this item only, you may run
     the app on one iPad simulator with a DEBUG-only stub that forces a non-zero count, and take one screenshot.
     Remove the stub before the PR.
   - **What done looks like:** with at least one item in the inbox, the count shows on the Create Recipe row in
     the iPad sidebar, and on the iPhone it shows on whatever Jon taps to reach Create Recipe from the default
     tab bar. If Create Recipe isn't reachable from the iPhone's default tab bar, say how it's reached in the PR,
     and badge that control. At zero, no badge shows.
   - It's view-only, so it needs no `YesChefTests` of its own.

1. **The export (app):**
   - Each install writes `MCP/Exports/<installation id>.json`. The installation id is a UUID made with
     `@Dependency(\.uuid)` on first use and kept in `UserDefaults`, which isn't synced. It is not a recipe ID and
     never leaves the helper.
   - The format: `{"format": "yc-library-export", "version": 1, "generatedAt", "device": "iPhone" | "iPad",
     "recipes", "menus", "mealPlan"}`.
     - `recipes` holds `RecipeBundle`s (ADR-0060 D4, guardrail #6) with `photos` emptied and
       `recipe.originalSnapshot` set to nil.
     - `menus` holds each menu's title, notes, day count, and items: kind, title, recipe ID, day offset, slot,
       note, and scale.
     - `mealPlan` holds the scheduled items from 30 days back to 60 days ahead.
     - Images, snapshots, and sync metadata never go in (ADR-0007 D5).
   - Write it **off the main actor**, atomically and through a coordinated write, when the scene goes to the
     background if the last export is more than **15 minutes** old (hold a background-task assertion while
     writing). Also write it on **Refresh**.
   - Settings gains a **Chat Access** section: the last export time and size, a **Refresh** button, and the
     inbox count.
2. **The Mac-side read path (helper), from S0 Q4:**
   - Choose the newest export by its file's modification date, read from the directory listing's resource
     values (these work on a dataless file). Materialize only that file.
   - **Materialize, then read.**
     - At startup, the helper opts its process into materializing dataless files:
       `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS,
       IOPOL_MATERIALIZE_DATALESS_FILES_ON)`. This is the likeliest reason a shell read downloads the file and a
       `tunnel-client` child's read doesn't.
     - Before reading, if the file isn't current, the helper does a **coordinated read** (`NSFileCoordinator`),
       which asks iCloud for the download, with a **60 s deadline**. The tool deadline is 120 s.
     - If the deadline passes, return `isError`: "The Yes Chef export is still downloading from iCloud. Try again
       in a minute."
     - Log the materialize time and the read time to stderr, so the device pass can read them.
     - Put the materializer behind an injected seam, so tests drive the timeout and success paths without
       iCloud.
   - Decode with a version check. A newer `version` is a typed `isError` that names both versions, never a
     partial read (`semantic-fidelity.md`). Keep the decoded export in memory, keyed by path and modification
     date, so each call doesn't re-read it.
   - With no export, return `isError`: "No Yes Chef export yet. Open Yes Chef on the iPhone or iPad, or tap
     Refresh in Settings → Chat Access."
3. **The read tools**, all with `readOnlyHint: true` and `openWorldHint: false`:
   - `search_recipes {query, limit}` matches name, ingredients, tags, categories, and notes. It returns `{ref,
     name, cuisine, course, tags, totalTime, yield}` rows: 20 by default, 50 at most.
   - `get_recipe {ref}` returns the name, description, yield, times, ingredients and steps by section, notes,
     tags, categories, and source URL.
   - `list_menus {limit}` returns `{ref, title, dayCount, itemCount, modified}`.
   - `get_menu {ref}` returns the title, notes, and items by day and slot, with each item's recipe name and note.
   - `get_meal_plan {from, to}` takes a window of 31 days at most, inside the export's window, and returns the
     scheduled items.
   - **Every result carries `export: {generatedAt, ageMinutes, device}`.** No result carries a UUID, a path, or
     image data.
   - **Refs are opaque and scoped to one export** (for example `<generation>.<n>`). A ref from a superseded export
     returns `isError`: "That reference is from an older export; search again." Refs are deliberately not recipe
     IDs, so S2 doesn't settle ADR-0060 OQ3 by the back door.
4. **The instructions** add a paragraph on the read tools: check the library before suggesting something, and
   report the export's age when it matters.

**Out of scope:** pantry and grocery data, any write beyond `stage_recipe`, and S3.

### Verification (Codex)

- `scripts/check-drift.sh`, the elevated generic iOS build, and `YesChefTests` (the export writer is app model
  code).
- Core tests: the export round-trips. It carries no photo bytes and no `originalSnapshot`. A newer version
  fails loudly.
- Helper tests against a temporary container:
  - Each tool returns the expected rows, within the caps.
  - A stale ref returns the older-export error.
  - With no export, the tools return the no-export error.
  - The materializer seam drives both the timeout error and the success path.
  - No result contains a UUID. Assert it with a UUID regex over every tool's output.

### Jon's device pass

0. Stage a recipe from ChatGPT without opening it. The count shows on Create Recipe in the iPad sidebar and on
   the iPhone More list row (Create Recipe is hidden from the default tab bar), and it clears after Open or Discard.
1. On the iPhone, tap **Refresh** in Settings → Chat Access. Time how long the export takes to appear on the Mac
   (`ls -lO MCP/Exports/`).
2. In ChatGPT: "Do I have any short-rib braises?" (`search_recipes`), then open one (`get_recipe`). Check that
   the export age is right.
3. **Re-run Q4 against the export.** Run `brctl evict` on the export file, then call `get_recipe`. It succeeds,
   and the stderr log shows the `materialize` and `read` durations. If it fails or passes 60 s, stop and report: the read path
   needs a different mechanism before anything builds on it.
4. Background the iPad app so it writes its own export. The tools report whichever export is newest.
5. Call `get_recipe` with a ref from before step 4. It returns the older-export error.

### S2 results

- **Item 0 (badge) cleared 2026-10-26.** A count shows next to Create Recipe; it renders small, but it renders. The cause was modifier order: S1 put `.badge` after `.defaultVisibility(.hidden, for: .tabBar)` and it never drew. #376 moved `.badge` first, and the device confirmed the fix.
- Items 1–5, including the step 3 materialize result, are still owed.

### Done when

- The PR has merged and the checks in Verification are green. The PR names the badge's cause (item 0).
- The completing PR adds the `DONE-LOG.md` entry, lists the device pass in `device-passes.md` with the **Owed**
  pointer, and advances `NEXT_UP.md` to the queued PROD-CUTOVER Step 1 drop slice. S3 waits on ADR-0060 OQ3.
- After Jon's pass, the architect records the step 3 materialize result here. If step 3 failed, the read path is
  re-planned before anything builds on the export.

## Constants register

| Constant | Value | Why |
| --- | --- | --- |
| `Processed/` retention | 30 days | Long enough to recover a mistaken Discard. Short enough that consumed items don't build up (OQ2). |
| Export minimum interval | 15 min | Recipes change slowly, and a multi-MB file shouldn't be re-uploaded on every app switch. Refresh overrides it. |
| Meal-plan window in the export | −30 to +60 days | Covers "what did I make last month" and "plan the next few weeks" without exporting the whole calendar. |
| Materialize deadline | 60 s | Half the 120 s tool deadline, leaving room for decoding and the reply. |
| Tool row cap | 20 default, 50 max | Vinyl Fever M12's precedent. The conversation pays for every byte. |
