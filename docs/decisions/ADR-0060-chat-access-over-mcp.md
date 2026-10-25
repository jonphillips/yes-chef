# ADR-0060 — Chat assistants reach Yes Chef through a local MCP server, and an iCloud Drive folder carries the inbox and the read data to and from the phone

> **One-line:** Yes Chef becomes the second consumer of jon-platform
> [ADR-0007](../../../../jon-platform/docs/adr/0007-app-data-over-local-mcp.md) (app data over a local stdio MCP
> server). The pasted JSON becomes a `stage_recipe` tool call, and the prompts we copy out become read
> tools. **One thing differs from Vinyl Fever: Yes Chef doesn't run on the Mac.** So the helper can't read
> the database, and a Mac inbox folder would never reach the phone. Both the inbox and the read data move
> to Yes Chef's iCloud Drive container. That needs ADR-0007 Amendment 1, which is argued below and proposed
> in jon-platform alongside this ADR.

Status: **Accepted** — 2026-10-22, after S0's device pass confirmed D2 (OQ1 answered below). Proposed 2026-10-21.
**Amended by jon-platform [ADR-0008](../../../../jon-platform/docs/adr/0008-automatic-scheduled-backups.md)** (2026-10-25,
built by effort [`automatic-backups`](../efforts/automatic-backups.md)): the container's `Documents/` is now
published so automatic backups show in Files. D2's "the container is not published" no longer holds. `MCP/`
sits outside `Documents/`, so it stays hidden.
Origin: Jon, after Vinyl Fever M12 proved ChatGPT → MCP end to end ("we do a
lot of copy/pasting of recipe prompts, and the resulting JSON recipe gets pasted back"). Queued after
[`efforts/sync-failure-surfacing.md`](../efforts/sync-failure-surfacing.md). Effort:
[`efforts/chat-access-mcp.md`](../efforts/chat-access-mcp.md). Builds on: jon-platform ADR-0007 (the kit, the
inbox, and the tunnel ops) and its Amendment 1 (proposed with this ADR);
[ADR-0042](ADR-0042-workbench-handoff-and-the-return-block.md) (deliberation happens in the chat app; a
pinned contract carries the result back); [ADR-0053](ADR-0053-create-recipe-destination.md) Amd 2-D3 (one
text → recipe operation, no new parser); [ADR-0051](ADR-0051-text-to-recipe-extraction-strategy.md) (no new
bespoke parser); [ADR-0059](ADR-0059-yes-chef-dev-variant.md) (Yes Chef Dev shares the iCloud container);
[ADR-0030](ADR-0030-local-backup-and-restore.md) Amd 3 (every sync peer must be quiesced before a restore).

## Context

The ChatGPT round trip today ([`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md)):

1. **Out.** Jon copies a prompt from Yes Chef (a workbench hand-off, a revision ask, or the thin **Copy
   Recipe Capture Request**) and pastes it into a chat in the `Yes Chef` Project. Any recipe or menu the
   model needs travels inside that prompt.
2. **Back.** ChatGPT prints one JSON-LD object (`YC-RECIPE-CONTRACT: v2`) or a `YC-HANDOFF` return block. Jon
   copies it, switches apps, and pastes it into Create Recipe (or runs the **Send to Yes Chef** Shortcut).

Both directions are manual. The model knows only what was pasted in, so it can't check the library ("do I
already have a braise like this?"). Vinyl Fever M12 removed both pastes with a local stdio MCP server that
ChatGPT reaches through OpenAI's Secure MCP Tunnel. Jon has used it from ChatGPT on desktop and on iPad since
2026-10-17. ADR-0007 already names Yes Chef as the likely second consumer.

ADR-0007 assumes the app's data is on the Mac. D1 embeds the helper in the app bundle. D2's first branch has
the helper open "the app's own database, opened read-only", with "Yes Chef's recipes, menus, and pantry" as
the example. D3 stages proposals into a local inbox that the app surfaces. **None of that holds for Yes
Chef:**

- The app shell is iOS/iPadOS only (`SDKROOT = iphoneos`). There is no Mac app to embed a helper in.
- This Mac has no Yes Chef app container and no Yes Chef group container, so there's no database to read.
  Checked 2026-10-21: neither `~/Library/Containers` nor `~/Library/Group Containers` has an entry.
- Jon reviews and saves recipes on the iPhone and iPad. A staged recipe in a Mac folder would never reach
  them.

The helper still has to run on the Mac, because that's where `tunnel-client`, Claude Code, and Codex run it.
So Yes Chef needs a transport between the Mac and its devices that isn't the database. The transport also
can't make the Mac a sync peer.

There is one strong candidate. iCloud Drive syncs an app's ubiquity container to every Mac on the account,
even when that Mac has never installed the app. Containers for iPhone-only apps (Overcast, WhatsApp,
Downcast, and others) are already in `~/Library/Mobile Documents` on this Mac. Yes Chef's container,
`iCloud.com.jonphillips.yeschef`, has only the CloudKit service enabled today. Adding iCloud Documents to it
is an entitlement change, not a schema change.

## Decisions

### D1 — Yes Chef ships a `yeschef-mcp` stdio helper built on `MCPServerKit`, as a standalone macOS executable

The helper is built from Yes Chef's own Core, so the tools and the app share their decoders and contract
text (ADR-0007 D1's "can't drift" reason holds). It lives in a **separate macOS-only package**,
`YesChefMCP/`, which depends on `YesChefPackage` and `MCPServerKit` by path. It doesn't go into
`YesChefPackage` itself: `MCPServerKit` is macOS-only, and keeping it out of the package graph the iOS app
resolves avoids a platform mismatch.

There's no app bundle to embed the helper in, so a repo script builds it and installs it to a stable path.
`scripts/mcp-tunnel init yeschef …` registers that path. [`CHATGPT-SETUP.md`](../CHATGPT-SETUP.md) gains an
MCP section that covers only the Yes Chef specifics (the path and the tools); jon-platform
`docs/ios/mcp-access.md` stays the ops recipe. (This is ADR-0007 Amd 1-D1. "Embedded in the bundle" applies
only to an app that has a Mac bundle.)

### D2 — The Mac ↔ device transport is Yes Chef's iCloud Drive container, not the database

The app gains the **iCloud Documents** service on the existing `iCloud.com.jonphillips.yeschef` container. The
container is not published, so nothing shows up in Files. One folder carries both directions:

```
<ubiquity container>/MCP/
  Inbox/              ← the helper stages here; any of Jon's devices picks it up
  Inbox/Processed/    ← HandoffInbox's move-on-consume
  Exports/            ← each device writes its read export here; the helper reads the newest
```

The helper reaches the container through its Mac path, `~/Library/Mobile Documents/iCloud~com~jonphillips~yeschef/`.
The app reaches it through `FileManager.url(forUbiquityContainerIdentifier:)`, off the main actor. It uses an
`NSMetadataQuery` to discover files and asks for each one to be downloaded, because iOS doesn't download
iCloud Drive files eagerly.

**Rejected: run Yes Chef on the Mac ("Designed for iPad") so the helper can read a synced database.** This
would satisfy ADR-0007 D2's first branch on paper. But:

1. It makes the Mac a full CloudKit sync peer, and one that's often asleep. ADR-0030 Amd 3 measured that a
   peer's held delete, synced after a restore, silently re-deletes the restored record everywhere. The
   restore procedure has to quiesce *every* peer, and a peer that's half-forgotten in a closed laptop is the
   one most likely to be missed.
2. The database is only fresh while the Mac app runs and syncs, so it's no fresher than an export.
3. It doesn't solve the write direction: the inbox would still be on the Mac, away from the phone.

**Also rejected:**
- **The helper as its own CloudKit client.** It would be a third sync participant, outside SQLiteData, and it
  would have to decode the synced schema separately.
- **An App Group container.** It's device-local. The Cockpit mailbox (ADR-0058) works only because both of
  its apps are on the same device.

**Revisit** this when the macOS app ([[macos-longterm-target]]) is real. Then the database is on the Mac for
its own reasons, and ADR-0007 D2's first branch may apply.

### D3 — Writes stage only: `stage_recipe` stages a recipe, and Save in Create Recipe is still the only write

This is ADR-0007 D3, unchanged except for where the inbox is:

- `stage_recipe` takes the JSON-LD Recipe object the model would otherwise have printed. It serializes the
  object to wire text and checks it with the **same deterministic JSON-LD path** that a paste goes through
  (`RecipeJSONLDExtractor`, `YC-RECIPE-CONTRACT: v2`). That's no second parser (ADR-0051's guardrail). If
  the check fails, the tool returns the error with `isError: true` so the model can correct itself. If it
  succeeds, the tool writes the text with `HandoffInbox(root: …/MCP/Inbox)`.
- The tool carries `readOnlyHint: false, destructiveHint: false`, so ChatGPT asks for confirmation. That's the
  second checkpoint (ADR-0007 D3).
- The app lists inbox items. Opening one calls `CreateRecipeCoordinator.stage(text:)`, the same seam that
  paste and the Shortcuts door use (ADR-0053 Amd 2-D3). The ordinary editable review follows, and **Save is
  the only write to the library.**
- **Claiming an item:** both the iPhone and the iPad see the inbox. Moving an item to `Processed/` is how a
  device claims it. If a device's move fails because the file is already gone, another device took it, and
  this device drops the item quietly. Discarding an item also moves it to `Processed/`.

**Out of scope here: returns that target an existing recipe** (a revision brief, learnings, `YC-HANDOFF`
blocks). A paste never carries a recipe's identity (ADR-0042 D2 and Amd 1-D2). A tool call could carry an
identifier back, but ADR-0007 D5 keeps internal IDs away from the model. How these two rules meet is a
decision of its own (OQ3), not something to settle while building.

### D4 — Reads come from an export each device writes, not from the database

This is ADR-0007 D2's second branch, the derived export, chosen here because the data isn't on the Mac (Amd
1-D2):

- **Each device writes its own file**, `MCP/Exports/<installation id>.json`, atomically and off the main
  actor. It writes when the scene goes to the background and on an explicit **Refresh** in Settings. The
  helper reads the file with the newest `generatedAt`. One file per device avoids iCloud Drive conflict
  copies when the iPhone and the iPad both write.
- **Recipes use the existing recipe-transfer shape** (`RecipeBundleCoding`, guardrail #6), so there's no new
  recipe format. Menus and meal plans get a small derived shape, specified in S2. Under ADR-0007 D5,
  **images, `originalSnapshot`, and sync metadata are left out.** Only text crosses.
- **The export has a version, and a newer version fails loudly.** The helper returns a typed error rather than
  reading a format it doesn't know (`semantic-fidelity.md`). Every read tool reports the export's age, the
  same way Vinyl Fever's `library_overview` reports its snapshot's age.
- The starting tools are `search_recipes`, `get_recipe`, `list_menus`, and `get_menu`. S2 fixes the list
  and the result caps.

### D5 — Yes Chef Dev gets its own MCP folder

ADR-0059 D4 keeps one iCloud container for both variants, and iCloud Drive has no Development/Production
split. Without a separate folder, Yes Chef Dev and TestFlight Yes Chef on one device would claim each
other's staged recipes and overwrite each other's exports. So Yes Chef Dev uses `MCP-Dev/`. The helper takes
a `--variant dev` flag and defaults to production. A Dev helper is a second `tunnel-client` profile, made
only when it's needed.

### D6 — The contract travels with the server, and paste stays the fallback

- **The server's `instructions` carry the recipe contract** (ADR-0007 D6). They're generated from the same
  Core text as `docs/chatgpt/RECIPE-CONTRACT.md` and `PROJECT-INSTRUCTIONS.md`, and a test fails if the two
  drift. A chat that has the tools needs no Project source.
- **The instructions tell the model what to do when a tool isn't reachable:** if a tool call fails or times
  out (the Mac is asleep, or `tunnel-client` is down), print the contract output for Jon to paste instead.
- **Nothing is retired.** The `Yes Chef` Project, the Copy actions, Create Recipe's paste, and the **Send to
  Yes Chef** Shortcut all stay. They're the path for any chat without the tools.

### D7 — Slice order: the transport is proven first

1. **S0 — spike.** Prove the transport end to end with throwaway probe tools, on real devices. This is a
   discriminating probe, not a build slice. It answers OQ1 and either confirms D2 or reopens it.
2. **S1 — `stage_recipe` and the inbox in the app** (D3). This retires the paste-back.
3. **S2 — the export and the read tools** (D4, D6). This retires the copy-out.
4. **S3 — returns that target a recipe.** This needs an amendment that answers OQ3 first.

S1 and S2 are specified after S0 reports. The whole effort is **schema-free**. Its one platform change is the
iCloud Documents entitlement.

## Consequences

- With the tools, Jon stops pasting in both directions. ChatGPT can also check the library before it
  suggests something ("you already have three short-rib braises").
- The capability needs the Mac awake and `tunnel-client` running, the same as Vinyl Fever. When they aren't,
  the paste path still works.
- iCloud Drive adds latency: the time from staging an item to its appearing on the phone. A personal app can
  tolerate that ([[personal-app-latency-tolerance]]). S0 measures it.
- An export is stale until a device writes a new one. The tools report its age, so the model can say so.
- `MCP/Inbox/Processed/` grows in a synced folder, and the rule against dead data ([[no-dead-data]]) applies.
  Amd 1-D3 lets an app prune items it has already consumed, and S1 sets the retention.
- More ops: one Platform tunnel, profile, and login item for Yes Chef, made with `scripts/mcp-tunnel`.

## Open questions

- **OQ1 — answered 2026-10-22 by S0** ([§ S0 results](../efforts/chat-access-mcp.md#s0-results)). **D2 stands.**
  The container reached the Mac without a Mac app, and iCloud created the folder itself. A helper launched by
  `tunnel-client` raised **one** iCloud Drive prompt, and macOS attributes that grant to `tunnel-client`, so it
  survives restarts and helper rebuilds. Launches from Claude Code and Terminal worked. A helper-written file
  reached the iPhone in about 7 s in the foreground and was still found after a relaunch. No signed Mac app is
  needed. Two constraints came out of the pass, and they bind every slice:
  - **The Mac evicts container files within minutes, and a `tunnel-client` child can't read a dataless file.**
    Every Mac-side read materializes the file first (S2 builds it).
  - **Colons in file names arrive on iOS as slashes.** Container file names are colon-free, so S1 changes
    `HandoffInbox` naming.

  The original question, kept for the record: Can a helper launched by `tunnel-client` (a LaunchAgent), Claude Code, and Terminal
  read and write `~/Library/Mobile Documents/iCloud~com~jonphillips~yeschef/` without a privacy prompt, or
  with a prompt that can be granted once? Does the container appear on the Mac with no Mac app, once a device
  has written to it? How long does a helper-written file take to reach the iPhone, and does the app find it
  while in the foreground and after a relaunch? Can the helper read a phone-written file that macOS has
  evicted to a placeholder? **If the Mac side fails,** D2 reopens. The leading fallback is a small signed Mac
  app that holds the ubiquity entitlement and runs the helper. It isn't a sync peer.
- **OQ2 — answered 2026-10-22: 30 days.** S1 prunes consumed items from `Processed/` on foreground.
- **OQ3.** Returns that target an existing recipe (D3): whether a tool call may carry an opaque, short-lived
  handle that the app resolves back to a recipe, and how that fits ADR-0042 D2 and ADR-0007 D5. Not needed
  until S3.
