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
built by effort [`automatic-backups`](../efforts/archive/automatic-backups.md)): the container's `Documents/` is now
published so automatic backups show in Files. D2's "the container is not published" no longer holds. `MCP/`
sits outside `Documents/`, so it stays hidden.
**[Amendment 1](#amendment-1--a-handoff-return-is-routed-by-its-yc-handoff-token-2026-11-03) — Accepted
2026-11-03:** answers OQ3. A return may carry the app-minted `YC-HANDOFF` token and nothing else that names a
row; `stage_handoff_return` stages the whole return block, and only the device that minted the token opens it.
Origin: Jon, after Vinyl Fever M12 proved ChatGPT → MCP end to end ("we do a
lot of copy/pasting of recipe prompts, and the resulting JSON recipe gets pasted back"). Queued after
[`efforts/archive/sync-failure-surfacing.md`](../efforts/archive/sync-failure-surfacing.md). Effort:
[`efforts/archive/chat-access-mcp.md`](../efforts/archive/chat-access-mcp.md). Builds on: jon-platform ADR-0007 (the kit, the
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

The app gains the **iCloud Documents** service on the existing `iCloud.com.jonphillips.yeschef` container. At
acceptance the container was not published, so nothing showed up in Files. ADR-0008 S1 later published its
`Documents/` scope for backups; `MCP/` remains outside that scope and hidden. One folder carries both directions:

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
decision of its own (OQ3), not something to settle while building. *(Answered by
[Amendment 1](#amendment-1--a-handoff-return-is-routed-by-its-yc-handoff-token-2026-11-03).)*

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

**2026-11-05:** The inbox transport moved to jon-platform's `ChatAccessKit` (ADR-0009). Debug builds and the helper's `--variant dev` now use `MCP-Dev/`, making D5 effective.

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
4. **S3 — returns that target a recipe.** This needs an amendment that answers OQ3 first
   ([Amendment 1](#amendment-1--a-handoff-return-is-routed-by-its-yc-handoff-token-2026-11-03)).

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

- **OQ1 — answered 2026-10-22 by S0** ([§ S0 results](../efforts/archive/chat-access-mcp.md#s0-results)). **D2 stands.**
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
- **OQ3 — answered 2026-11-03 by
  [Amendment 1](#amendment-1--a-handoff-return-is-routed-by-its-yc-handoff-token-2026-11-03): yes, and the handle
  already exists.** It's the `YC-HANDOFF` token, which the app mints and resolves on the device that minted it.
  The original question, kept for the record: Returns that target an existing recipe (D3): whether a tool call
  may carry an opaque, short-lived handle that the app resolves back to a recipe, and how that fits ADR-0042 D2
  and ADR-0007 D5. Not needed until S3.

## Amendment 1 — A handoff return is routed by its YC-HANDOFF token (2026-11-03)

Status: **Accepted** — 2026-11-03 (proposed the same day, #431). Answers OQ3 and unblocks S3. Schema-free. No
contract bump. Read with the [notes at acceptance](#amd-1--notes-at-acceptance-2026-11-03), which correct D2's
premise about the shipped inbox and narrow D3 for ADR-0061's `.recipe` task type.

### Context

OQ3 asked whether a tool call may carry something the app resolves back to a recipe, given two rules:
ADR-0042 Amd 1-D2 ("the paste door never carries identity") and jon-platform ADR-0007 D5 (tools never return
"internal IDs the model doesn't need"). The code already answers most of it. As of `origin/main` 614ee59:

- **The model already carries a handle.** Every routed handoff prompt carries a `YC-HANDOFF: <uuid>` line
  (`AIHandoffToken.header`), and the return contract makes the model echo it as the return's first line
  (`AIHandoffReturnContract.projectInstructions`). The UUID is the `AIHandoff` row's id. It isn't the
  recipe's, the menu's, or any line's.
- **A return already finds its handoff without a screen.** The **Import Handoff Result** App Intent passes the
  text to `AIHandoffIntentImport.stageReview(handoffID: nil, result:)`. That reads the token from the text,
  loads the row, and stages the review that the row's source and task call for. That's the path a Shortcut
  uses, and it's the one an inbox item needs.
- **The token resolves only where it was minted.** `AIHandoff` is device-local: it isn't in `CloudSync`'s
  synced tables, and ADR-0042's storage sketch says so. A handoff started on the iPhone has no row on the iPad.
- **The read tools already hand the model opaque refs.** `search_recipes` returns `<generation>.r<index>`, and
  a ref from an older export fails with "search again." So D5 already means a handle the model can't misuse,
  not "nothing that names a row."

On the paste door, the token is a **check**. The door is opened from the recipe or menu screen, so the target
is known already, and the token only confirms the match (`HandoffInAppTransport`'s unmatched-result prompt).
An inbox has no screen, so for an inbox item the token becomes the **router**. That's the only real change
here, and the App Intent already made it.

Amd 1-D2 was about what the return **contains**: no anchors, no line IDs, no rewritten recipe. A revision
returns a prose brief, and the structured change is derived in-app against live rows. None of that moves.

### Amd 1-D1 — A return may carry the app-minted token, and nothing else that names a row

- **The handle is the existing `YC-HANDOFF` UUID.** No recipe, menu, variation, section, or line id ever
  crosses, and there's no new handle type. The token can't address anything except its own row on the device
  that minted it, and it resolves only to a **review**, never to a write.
- **It's short-lived in practice.** The row's status (`awaitingReturn` → `imported`) and its device-locality
  bound it. A token from a reset device, or one the app no longer has, resolves to nothing.
- **ADR-0007 D5 holds.** The model needs the token to route the return, and the token gives it no reach.
- **ADR-0042 Amd 1-D2 holds.** The payload is the same return the paste door takes: a revision is still a
  prose brief, and a riff is still one JSON-LD Recipe (ADR-0042 Amd 4). Save, or the brief sheet's **Draft the
  revision**, is still the only write.

### Amd 1-D2 — One tool, `stage_handoff_return`, stages the whole return block

- **Input: `text`,** exactly what the model would print at finalize. That's the token line, the `YC-CONTRACT`
  marker, the deliverable, and the `YC-LEARNINGS:` section. **One tool, not one per task.** Every routed return
  shares `AIHandoffReturnContract`, and the app already routes by task. Tools like `stage_revision` or
  `stage_prep_plan` would restate thirteen task types in the server, and the two lists would drift.
- **The helper checks the envelope; the app checks the body.** The helper runs the Core functions the paste
  door runs first: `AIHandoffReturnContract.strippingMarker` and `AIHandoffToken.stripping`. A missing or
  malformed token, or a **newer** marker, returns `isError` with the reason so the model can correct itself.
  An older or missing marker stages with a warning, as on the paste door (ADR-0042 Amd 5-D2). The body's parse
  depends on the task type, and the task type is on the device-local row, so the body is checked when the item
  is opened and its errors show in the app. **This is a named gap against ADR-0007 D3** ("checked by the same
  decoder before it's written"): the envelope is checked before writing, the body after.
- **The file:** `HandoffInbox(root: …/MCP/Inbox, fileExtension: "ycreturn")`, with the token UUID as the slug.
  The distinct extension keeps builds that list only `json` recipes from opening a return as a recipe. *(Shipped
  builds don't yet list only `json`; S3a makes them. See the notes at acceptance.)* The
  slug lets the app group items by token without reading them.
- **Annotations:** `readOnlyHint: false, destructiveHint: false`, so ChatGPT asks before staging (D3's second
  checkpoint).
- **The result tells the model where it went:** staged for review on the device that started the handoff.
  The model says that, not "saved."

**Rejected: a pending-handoffs manifest that the app writes to `MCP/`, so the helper can resolve tokens.** It
would let the helper check the body too, and it would support a `get_handoff(token)` read tool. But it adds a
second iCloud Drive hop in the outbound direction, at the moment Jon moves fastest: tap, paste, start talking.
The prompt already carries the context (ADR-0042 D4: token, context, ask), so `get_handoff` would add nothing
the model doesn't have. **Revisit** if body errors found only in-app turn out to be common.

### Amd 1-D3 — Only the device that minted the token opens the item

This narrows D3's claim rule for `.ycreturn` items. `json` recipe items are unchanged.

- **The row is on this device:** the item appears under **From Chat** with its handoff title (for example
  "Adjust Recipe: Absurdly Addictive Asparagus"). Opening it claims it (moves it to `Processed/`) and calls
  `stageReview(handoffID: token, result: text, in:, now:, allowRestage: true)`, the same call the paste
  transports make. The existing review follows: the brief sheet, the section review, the prep-plan review, or
  Create Recipe for a riff.
- **The row isn't on this device:** the item belongs to another device, or its row is gone. This device
  doesn't claim it and doesn't hide it. It lists it as **Started on another device**, with **Copy**. Pasted on
  the right screen, it goes through the existing unmatched-result review.
- **A capture-sourced token** (Reader Feedback) returns only to the open capture editor
  (`AIHandoffSourceType.capture`), so it gets the same **Copy** treatment.
- **The same token staged more than once:** a later finalize, after more discussion, is a real new answer.
  The app shows the newest file for a token, and claiming it also moves the older ones to `Processed/`. *(Not for
  a task type that takes repeat returns, ADR-0061's `.recipe`. See the notes at acceptance.)*
  `allowRestage: true` means a return for an already-imported handoff reopens a review, as a re-paste does.
- **Orphans expire.** During its usual maintenance, any device moves an unclaimed `.ycreturn` item older than
  the `Processed/` retention (30 days) to `Processed/`. That's the one exception to "only the minting device
  moves it." An item from a reset device doesn't sit in the inbox for good.

### Amd 1-D4 — The return contract travels with the server, so a routed handoff no longer needs the Project

- `ChatAccessServerInstructions` gains the routed-return rules, built from
  `AIHandoffReturnContract.projectInstructions`, the same Core constant as
  `docs/chatgpt/PROJECT-INSTRUCTIONS.md`. A test fails if they drift, as D6 already requires for the recipe
  contract.
- **The opening of the instructions names both tools,** so the first 512 characters still stand alone
  (ADR-0007 D1). A conversation with a `YC-HANDOFF:` line finalizes through `stage_handoff_return`. That
  includes a riff into a new recipe, so its handoff is closed. `stage_recipe` is for conversations with no
  token.
- **If the tool fails or times out,** the model prints the return block for Jon to paste. That's D6's
  existing rule, extended.
- **What this changes for Jon:** with the plugin on, a handoff pasted into **any** ChatGPT chat returns
  correctly, not only in the `Yes Chef` Project. The Project stays as the home for chats without the tools
  (D6: nothing is retired).
- **This decides where the rules live today, not forever.** If ChatGPT plugin skills turn out to load on iOS
  for a tunnel plugin (unverified as of 2026-11-03), the handoff workflow could move into a skill, and
  ADR-0042 D4's premise that "the iOS app cannot take a skills file" would need revisiting. The tool and
  D1–D3 wouldn't change.

### Amd 1-D5 — Out: revising a recipe from a chat that started in ChatGPT

A chat that starts in ChatGPT and finds a recipe with `search_recipes` holds a read ref, not a token. If
`stage_handoff_return` accepted read refs, the export's index would become a write target, and nothing on the
device would confirm the target. Not here (OQ4).

Until OQ4 is answered, such a chat can still do either of two things. It can stage a **new** recipe with
`stage_recipe`. Or Jon taps **Adjust Recipe** on that recipe in Yes Chef and pastes the prompt into the
**same** chat. The conversation goes on, now with a token, and its next finalize routes.

### Amd 1 — slices (the architect specifies S3 in the effort brief)

- **S3a — helper:** `stage_handoff_return`, envelope checks, the `.ycreturn` file, the instructions from
  D4, and tests. Tests cover the 512-character opening, drift against `PROJECT-INSTRUCTIONS.md`, a missing
  token, a newer marker, and an older marker staging with its warning.
- **S3b — app:** listing `.ycreturn` items, the claim rule in D3, routing through `stageReview`, the **Copy**
  fallback, newest-per-token, and orphan expiry.
- **Device pass:** on the iPhone, start **Adjust Recipe**, paste it into a ChatGPT chat **outside** the
  `Yes Chef` Project, discuss, and finalize. The item opens the brief sheet on the iPhone. The iPad shows
  **Started on another device**. Repeat with a riff, which should open Create Recipe and mark the handoff
  imported.

### Amd 1 — notes at acceptance (2026-11-03)

Found while specifying S3a and S3b against `origin/main` 0c383cb. Jon accepted this amendment and ADR-0061 the
same day, and the two meet in S3b.

- **D2's extension premise isn't true of shipped builds yet.** `ChatAccessInbox.rows(from:)` lists any file
  whose name `StagedHandoff` parses, whatever its extension, and the app's metadata query matches by path
  alone. A `.ycreturn` staged against today's build would list under **From Chat** as a recipe. Opening it
  would send the return block to Create Recipe and move the file to `Processed/` renamed `.json`, from
  whichever device got there first. S3a filters recipe rows to `json`. Jon installs the S3a helper only once
  both devices run a build with that filter.
- **D3's newest-per-token rule is narrowed by ADR-0061 D4.** A `.recipe` token takes several returns, and each
  can be a different deliverable: a make-ahead plan first, then a revision. Keeping only the newest would move
  the make-ahead to `Processed/` without anyone seeing it. For a task type that takes repeat returns, every
  file stays its own item, and claiming one claims only that one. Every other task type keeps D3 as written.
  ADR-0061 S1 states the rule on the task type in Core, so S3b reads it instead of restating it.
- **The device pass starts from ADR-0061's one door.** After ADR-0061 D1 the toolbar **Hand off** mints
  `.recipe`, not `.adjustRecipe`, so the pass below starts there. The effort brief holds the revised pass.

### Amd 1 — note: the prompt also carries the finalize routing (2026-11-03)

Found in the S3 device pass, and this narrows D4. In ChatGPT's Mac app with the plugin on, the first finalize of a
`.recipe` hand-off printed a block with no token and made no tool call, and nothing reached the helper. Asked to
send it through the tool in the same chat, ChatGPT asked permission, Jon allowed it, and the file staged. Jon's
next hand-off, from the iPad, staged with no nudge. Whether that first permission caused the miss is unproven, and
Jon chose not to measure how often it happens.

D4's rules stay on the server, but a tool's description isn't enough to get it called. So every routed prompt now
also says, right after its token: call `stage_handoff_return` if the chat has it, and otherwise start the reply with
the `YC-HANDOFF:` line (`AIHandoffToken.finalizeInstruction`). A printed return then still routes when it's pasted.

- **No contract bump.** The marker stays out of every prompt, and the Project's instructions don't change.
- **Capture hand-offs leave the line out,** because their returns go back only to the open capture editor (D3).

### Amd 1 — consequences

- The last copy-paste in the recipe loop goes: out is still a copied prompt, but back is a confirmation tap.
- The `Yes Chef` Project is no longer needed for routed handoffs in chats that have the tools.
- A body error (say, an empty brief) now shows in the app, after the model has moved on. Jon asks the chat to
  try again, or pastes.
- No lift into `LLMHandoffKit`. Token routing over an inbox is Yes Chef's alone. It's evidence for
  jon-platform's `SEAM-LEDGER.md` row "LLM handoff envelope," whose trigger hasn't fired.

### Amd 1 — open questions

- **OQ4 — revisions from chats that start in ChatGPT (D5).** One shape: the app resolves a read ref against the
  export it wrote, and asks Jon to confirm the target recipe before the review. Decide when dogfooding shows
  that tapping **Adjust Recipe** to mint a token costs something real.
