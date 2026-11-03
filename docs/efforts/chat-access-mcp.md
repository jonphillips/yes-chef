# Effort — Chat access over MCP

Status: Ready — S3a shipped. S3b waits on the [one-recipe-handoff](archive/one-recipe-handoff.md) dispatch.
Schema-free throughout.
Summary: S3 lets a ChatGPT return target an existing recipe: S3a adds the helper's `stage_handoff_return`, and S3b
opens those returns on the device that started the hand-off. S0–S2b shipped.

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

Decided by [ADR-0060 Amendment 1](../decisions/ADR-0060-chat-access-over-mcp.md#amendment-1--a-handoff-return-is-routed-by-its-yc-handoff-token-2026-11-03)
(accepted 2026-11-03), read with its
[notes at acceptance](../decisions/ADR-0060-chat-access-over-mcp.md#amd-1--notes-at-acceptance-2026-11-03).
Schema-free, and no contract bump. Code references are to `origin/main` 0c383cb.

### Build order

- [x] **S3a — the helper's `stage_handoff_return`.** Shipped; Jon's device gate is owed in
  [`device-passes.md`](../device-passes.md).
- The [one-recipe-handoff](archive/one-recipe-handoff.md) dispatch (ADR-0061 S1 + S2) goes next. It's that brief's
  index row, above this one.
- [ ] **S3b — the app's token-routed inbox items**, after the ADR-0061 dispatch merges.

**S3a doesn't depend on ADR-0061.** The helper checks only the envelope: the token line and the contract marker
(Amd 1-D2). ADR-0061 changes neither (its D6: no contract bump). A `YC-NEW-RECIPE:` block, or any other label, is
body, which the helper doesn't read.

**S3b does depend on ADR-0061, for two reasons:**

1. **Only the paste door routes a riff today.** `HandoffInAppTransport.stageReview` classifies an `.adjustRecipe`
   payload (`RecipeAdjustmentFinalize.classify`) and sends JSON-LD to Create Recipe. Core's
   `AIHandoffIntentImport.stageReview` doesn't, so through Core an Adjust riff stages as a prose brief. (The
   **Import Handoff Result** intent has that gap now.) Amd 1's device pass needs a riff to open Create Recipe.
   ADR-0061 D3 moves the detection into Core for every door. If S3b came first, it would copy the app-layer
   branch, and ADR-0061 would then have to move both copies.
2. **ADR-0061 D4 conflicts with Amd 1-D3's newest-per-token rule.** A `.recipe` token takes several returns,
   and each can be a different deliverable, so keeping only the newest would hide a real answer. Built after
   ADR-0061, S3b writes that rule once, against D4.

**Records.** S3a's PR ticks its box above and runs closeout (ADR-0005 D16) with `--keep-brief`, because S3b is
still here. Closeout then advances to the first Ready brief in index order, which is the ADR-0061 dispatch.
S3b's PR ticks its box and runs closeout without the flag, which archives this brief.

### S3a — the helper's `stage_handoff_return`

**Scope:** `YesChefMCP/`, plus two Core files the helper is built from (`ChatAccessServerInstructions`,
`ChatAccessInbox`). No app UI and no schema.

1. **The tool** (Amd 1-D2) goes in `YesChefMCPServer.make`, beside `stage_recipe`.
   - **Input:** `{ "text": string }`, required, with `additionalProperties: false`. The description says it's
     for a conversation that began with a Yes Chef hand-off prompt (one with a `YC-HANDOFF:` line), and that
     `text` is the whole return block exactly as it would be printed.
   - **Annotations:** `readOnly: false, destructive: false, openWorld: false`, so ChatGPT asks before staging.
   - **Envelope checks, in the paste door's order:** `AIHandoffReturnContract.strippingMarker(from:)`, then
     `AIHandoffToken.stripping(from:)` on the text it returns.
     - A **newer** marker returns `.error` saying this Yes Chef build reads contract v3. Nothing is staged.
     - A **missing or malformed** token returns `.error` saying the first line must be the exact `YC-HANDOFF:`
       line from the prompt, and that a conversation with no token uses `stage_recipe`. Nothing is staged.
     - If nothing but whitespace follows the token and marker, it returns `.error`. There's nothing to stage.
     - An **older or missing** marker stages, and the result carries the warning (ADR-0042 Amd 5-D2).
   - **The file:** check the container exists as `stage_recipe` does (the helper never creates it), then
     `HandoffInbox(root: folder.inboxURL, fileExtension: "ycreturn").stage(text, slug: <token UUID>, now:)`.
     It stages the **original `text`**, unchanged. The app strips the marker and token again when it opens the
     file, the same way it handles a paste. `stage_recipe` and the new tool share one container and folder
     helper rather than each keeping a copy.
   - **The result:** what was staged and `next`: *"Staged for review on the device that started this hand-off.
     Jon opens it from From Chat there."*, plus `warning` when there is one. The model says that, not "saved."
2. **Server instructions** (Amd 1-D4), in `ChatAccessServerInstructions.text`:
   - The opening paragraph names both tools within the first 512 characters (ADR-0007 D1). A conversation with
     a `YC-HANDOFF:` line finalizes through `stage_handoff_return`, including a riff into a new recipe.
     `stage_recipe` is only for a conversation with no token.
   - It includes `AIHandoffReturnContract.projectInstructions` verbatim, beside
     `RecipeJSONLDContract.projectSource`. `projectInstructions` already carries the "check the Yes Chef library
     with the read tools" sentence, so drop the server text's own copy. The sentence should appear once.
   - The fallback covers both tools. If a tool call fails or times out, print the return block, or the JSON-LD
     object, for Jon to paste.
3. **Recipe rows list only `json` files.** This is the one change S3a makes outside the helper, and it's a
   prerequisite. Shipped builds list a `.ycreturn` as a recipe, as the ADR's acceptance notes explain.
   `ChatAccessInbox.rows(from:)` keeps only snapshots whose extension is `json`. This is Core, not UI. The app
   lists nothing for `.ycreturn` files until S3b.
4. **Docs:** the MCP section of [`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md) lists `stage_handoff_return`. It also
   says that with the plugin on, a hand-off pasted into any chat returns through the tool, and the `Yes Chef`
   Project is still the home for chats without the tools.

**Tests.** In `YesChefMCPTests`:
- The tool list is `stage_recipe`, `stage_handoff_return`, and the read tools. Update the existing
  `listsOnlyStageRecipe…` test to match.
- A return with the current marker stages one `.ycreturn` file in `MCP/Inbox/`. Its name is colon-free, its slug
  is the token's UUID, its contents match the input byte for byte, and the result has no warning.
- A missing token, a malformed token, and a token with an empty body each return `isError` and stage nothing.
- A newer marker (`YC-CONTRACT: v4`) returns `isError` and stages nothing.
- An older marker and a missing marker each stage, and the result carries the warning.
- A missing container returns `isError` and isn't created (mirror `missingContainerReturnsError…`).
- The same token staged twice gives two files. Both stay.

In `YesChefCoreTests`:
- The first 512 characters of the server instructions name both tools. The instructions contain
  `AIHandoffReturnContract.projectInstructions`, the fallback sentence, and the library-check sentence exactly
  once. The existing `projectDocumentsMatchTheirCanonicalSources` already pins that constant to
  `docs/chatgpt/PROJECT-INSTRUCTIONS.md`, so together these are Amd 1's drift test.
- `rows(from:)` drops a `.ycreturn` snapshot and keeps a `json` one.

**Verification:** `scripts/check-drift.sh`, plus the helper package's own tests
(`swift test --package-path YesChefMCP` through `quiet-run`, elevated from the first attempt per
[`verification.md`](../verification.md)). No `YesChefApp/` change, so no generic device build.

**Done when:** the tool, the instructions, the filter and the doc change are in, the tests above pass, S3a's box
is ticked, and closeout runs with `--keep-brief`.

**Jon's check (the S3a gate).** Install the helper only after the iPhone and the iPad both run a build that
includes S3a. The filter in item 3 is what keeps older builds from opening a return as a recipe. Then run
`scripts/install-yeschef-mcp` and restart the tunnel (`CHATGPT-SETUP.md` § After a helper update). In a ChatGPT
chat outside the `Yes Chef` Project, paste a recipe's **Hand off** prompt and finalize. Confirm that ChatGPT asks
before calling `stage_handoff_return`, that a `.ycreturn` file appears in `MCP/Inbox/` on the Mac, and that
**From Chat** on both devices doesn't list it. The file waits there for S3b.

### S3b — the app's token-routed inbox items

**Precondition:** the [one-recipe-handoff](archive/one-recipe-handoff.md) dispatch has merged. S3b uses three things it
adds: Core's new-recipe routing, the single app entry that presents a staged recipe return, and the repeat-return
rule on `AIHandoffTaskType`.

**Scope:** `ChatAccessInboxModel`, `ChatAccessInboxFileClient` and `ChatAccessInboxView` in the app, and the
`ChatAccessInbox` projections in Core. Schema-free.

1. **Return rows.** The existing metadata query already finds `.ycreturn` files and asks iCloud to download them.
   A pure Core projection builds return rows from those snapshots and a resolver that the model supplies. The
   resolver looks up the slug's UUID in the local `aiHandoffs` table, so grouping doesn't read any file. Each
   file resolves to one of these:
   - **Openable:** this device has the row, and its source isn't `.capture`. The label is the hand-off's title,
     the `<Task>: <Object>` line its prompt opened with, and the staged time.
   - **Started on another device:** this device has no row for the token, because another device minted it or
     this one was reset.
   - **Capture:** a `.capture` source. Its return goes back only to the open capture editor (Amd 1-D3).
   - **Unreadable:** a slug that isn't a UUID. It's listed with **Copy**, never dropped (lossless or loud).
2. **Which files show.** This is Amd 1-D3, narrowed by ADR-0061 D4 as the acceptance notes say.
   - An **Openable** token whose task type takes one return shows only its newest file. Opening or discarding it
     also claims that token's older files.
   - An **Openable** token whose task type takes repeat returns (ADR-0061's `.recipe`) shows every file as its
     own row, oldest first. Claiming one claims only that one.
   - **Started on another device**, **Capture** and **Unreadable** files each show as their own row. This device
     can't know the task type, and **Copy** acts on one file. They're never claimed or hidden here, except by
     orphan expiry (item 6).
3. **Opening an Openable row:**
   1. Do a coordinated read of the file, as `read` does today.
   2. Call `HandoffAppOperations.stageReview(handoffID: <token>, result: text, …)`, which strips the marker and
      passes `allowRestage: true`.
   3. Present the result through the entry the paste door uses after ADR-0061. Review items come first, then the
      brief's side-by-side. A new recipe goes to Create Recipe, and the hand-off is marked imported. A contract
      warning shows the same way it does for a paste.
      **Except a missing marker** (decided 2026-11-03, Jon, from the S3a gate): an inbox return with no
      `YC-CONTRACT:` line shows no warning. ChatGPT's MCP returns drop that line even when the tool description
      asks for it, and the warning's remedy ("re-copy your project instructions") doesn't apply to a chat that has
      the tools. An older marker still warns, as it does for a paste. (The helper already refuses a newer one.)
      Paste keeps its missing-marker warning. Test both: an inbox return with no marker opens with no warning,
      and one with `YC-CONTRACT: v2` keeps the warning.
   4. **Claim the file, and any older files it supersedes, only after staging succeeds.** If staging fails (an
      archived recipe, an empty brief), the error stays on the row with **Copy** and **Discard**, and the file
      stays in `Inbox/`. That's the order this spec puts on Amd 1-D3's "opening claims it and calls
      `stageReview`". Only the minting device opens a `.ycreturn`, so staging first opens no claim race, and a
      body error never moves the only copy out of sight.
4. **Actions:**
   - **Copy** on every return row copies the file's text unchanged, to paste on the right screen. There the
     existing unmatched-result review takes it.
   - **Discard** on Openable rows claims the file and any it supersedes, without staging. Other-device rows have
     no Discard (Amd 1-D3: this device doesn't claim them).
5. **Claim with the right extension.** Claim through `HandoffInbox(root:, fileExtension: "ycreturn")`. The `json`
   inbox the file client uses today would rename the file `.json` in `Processed/`. `alreadyClaimed` is quiet,
   as it is for recipes.
6. **Orphan expiry.** `maintain` also moves any `.ycreturn` in `Inbox/` whose staged time is older than
   `ChatAccessInbox.processedRetentionInterval` to `Processed/`, on any device. A pure Core function picks the
   URLs, and the file client moves them. The existing `Processed/` pruning then removes them 30 days later.
7. **Counts.** `inboxCount`, which drives the tab badge and Settings, counts recipe rows and **Openable** return
   rows only. A return from the iPhone shouldn't badge the iPad for a month. Other-device rows still list.
8. **The view.** **From Chat** lists recipe rows as today, then Openable return rows. Rows that can only be
   copied go under a **Started on another device** subheading. Capture rows go there too, with a footnote that
   they return only to the open capture editor. Use the shared row treatments (`.attentionCard()`). Jon does the
   UI pass.

**Tests.** In `YesChefCoreTests` (the projections):
- A single-return Openable token with two files gives one row, the newest, carrying the older URL as superseded.
- A repeat-return token with two files gives two rows, oldest first.
- An unknown token gives one other-device row per file. A capture token gives copy-only rows. A slug that isn't a
  UUID gives an Unreadable row, not a dropped one.
- Recipe rows are unchanged, and S3a's `json` filter test still passes.
- Orphan expiry picks only `.ycreturn` files in `Inbox/` older than 30 days. It leaves `json` items and younger
  returns.

In `YesChefTests` (required: this changes app model code), with a fake file client and an in-memory database:
- Opening a row stages with the token, presents the review, and claims the file and its superseded files.
- A staging failure (an archived recipe throws `wrongTask`) puts the error on the row and claims nothing.
- An `.adjustRecipe` token whose payload is JSON-LD stages Create Recipe, marks the hand-off imported, and claims
  the file. So does a `.recipe` token carrying `YC-NEW-RECIPE:`.
- An other-device row can't be opened or discarded, and it's still unclaimed after a metadata refresh.
- Discard leaves the file in `Processed/` with its `.ycreturn` extension.
- `inboxCount` excludes other-device rows.

**Verification:** `scripts/check-drift.sh`, the generic device build, and `YesChefTests` on a simulator
(guardrail #9; the exact commands are in [`verification.md`](../verification.md)).

**Done when:** items 1–8 are in, the tests above pass, S3b's box is ticked, and closeout runs (without
`--keep-brief`), with the device pass below as its gate.

### S3 device pass (Jon, after S3b)

Amd 1's pass, started from ADR-0061's one **Hand off** door, plus the cases that S3b's rules add. Use a ChatGPT
chat **outside** the `Yes Chef` Project, with the plugin on.

1. **A revision.** On the iPhone, tap a recipe's **Hand off**, paste the prompt, discuss, and finalize a
   revision. On the iPhone the item opens the brief sheet. On the iPad it's listed under **Started on another
   device** with **Copy**, and the badge doesn't count it.
2. **Several returns on one token.** In the same chat, finalize Make-ahead and Chef It Up together, then a
   revision. The iPhone lists both items (they aren't collapsed), and each opens its own review.
3. **A riff.** Finalize a new recipe. It opens Create Recipe, and the hand-off no longer awaits a return.
4. **A single-return task type.** Hand off a menu prep plan and finalize twice. Only the newer return shows, and
   opening it moves both files to `Processed/`.
5. **Copy across devices.** On the iPad, **Copy** a return from item 1 and paste it on that recipe's **Paste**.
   It takes the unmatched-result review.
6. **Discard.** Discard an item on the iPhone. It goes from both devices.

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
| Orphaned `.ycreturn` expiry | 30 days | The `Processed/` retention. An item from a reset device or a lost row shouldn't sit in the inbox for good (Amd 1-D3). |
