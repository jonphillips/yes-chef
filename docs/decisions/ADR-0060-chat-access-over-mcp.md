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
**[Amendment 2](#amendment-2--a-chat-that-starts-in-chatgpt-can-return-to-a-recipe-and-stage-a-menu-2026-11-10) —
Accepted 2026-11-10 (#471):** answers OQ4. The helper resolves a read ref to its recipe when it stages, so a chat that
started in ChatGPT can return changes to a recipe (`stage_recipe_return`) and stage a new menu (`stage_menu`).
**[Amendment 3](#amendment-3--a-chat-can-replace-one-day-of-a-menu-that-already-exists-2026-11-10) — Accepted
2026-11-10 (#476):** answers OQ6 one day at a time. A menu row's note is where a menu-specific annotation lives, and
`stage_menu_day` replaces one day of an existing menu; a dish that stays keeps its row.
**[Amendment 4](#amendment-4--from-chat-is-its-own-sidebar-destination-2026-11-10) — Accepted on the merge of
its plan PR:** the inbox list moves out of Create Recipe into its own sidebar destination, **From Chat**.
**[Amendment 5](#amendment-5--a-chat-can-replace-the-prep-plan-for-the-dishes-it-names-2026-11-10) — Accepted on the merge
of its plan PR:** `stage_prep_plan` replaces the prep plan for the dishes a chat names, and `get_menu` shows the plan.
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

- **OQ4 — revisions from chats that start in ChatGPT (D5).** *(Answered by
  [Amendment 2](#amendment-2--a-chat-that-starts-in-chatgpt-can-return-to-a-recipe-and-stage-a-menu-2026-11-10):
  the helper resolves the ref, not the app.)* One shape: the app resolves a read ref against the
  export it wrote, and asks Jon to confirm the target recipe before the review. Decide when dogfooding shows
  that tapping **Adjust Recipe** to mint a token costs something real.

## Amendment 2 — A chat that starts in ChatGPT can return to a recipe and stage a menu (2026-11-10)

Status: **Accepted** — 2026-11-10 (#471; proposed the same day). Built by effort
[`chat-started-returns-and-menus`](../efforts/archive/chat-started-returns-and-menus.md). Answers Amd 1 OQ4. Schema-free. No contract bump. Adds two staging tools and
one inbox kind each, and adds the Playbook text that's already in the export to `get_recipe`.

### Context

Origin: Jon, planning a Thanksgiving dinner for his boys in ChatGPT (2026-11-10). The chat talked about the meal
and its dishes in the same breath: two grilled meats, two sauces, a roasted vegetable, a salad, and flatbread.
Jon wanted it to "search to see if I already have recipes like these, … select which recipes we want to use,
what Chat needs to make up on the fly, how to improve the recipes I do have, and then stage the resulting
recipes and a menu."

Mapped onto the tools as of `origin/main` a67b92f:

| Step | Tool | Today |
|---|---|---|
| Find what's already in the library | `search_recipes`, `get_recipe` | Works |
| Choose | the conversation | Works |
| Make up the missing dishes | `stage_recipe`, called once per recipe | Works |
| Improve a recipe Jon already has | — | **Gap: Amd 1-D5** |
| Stage the menu | — | **Gap: no tool** |

The workaround for the first gap is the one Amd 1-D5 names: tap **Hand off** on each recipe in Yes Chef and
paste the prompt into the same chat. A menu chat touches several recipes, so that's one trip out of the chat per
dish. OQ4's trigger was "when dogfooding shows that tapping **Adjust Recipe** to mint a token costs something
real." This is that case. The second gap has no workaround except building the menu by hand.

The code already has most of what's needed:

- **A read ref already pins its target.** `<generation>.r<index>` is checked against the export's generation,
  and a ref from any other export fails with "search again" (`ChatAccessReadTools.resolveIndex`). The export's
  recipe bundles carry the full `Recipe` row, so **the helper can turn a ref into a recipe id**, the id every
  device shares, because recipes sync. It never has to show that id to the model.
- **The return grammar exists.** ADR-0061's `.recipe` task takes labeled deliverables (`YC-REVISION:`,
  `YC-MAKE-AHEAD:`, `YC-CHEF-IT-UP:`, `YC-SERVE-WITH:`, `YC-LEARNINGS:`). They're parsed by
  `labeledRecipeReview` into the existing review sheets, and a revision stays a prose brief that's drafted
  in-app against live rows (ADR-0042 Amd 1-D2).
- **That review needs a handoff row, and only for its id.** `stageReview` loads an `AIHandoff` row by id and
  routes on its source and task. `AIHandoff` is device-local, so the device that opens an item can create one.
- **Menus have a commit path and a note-to-recipe swap.** `MenuRepository.addMenu` creates a menu, and
  `MenuRepository.replaceNoteItemWithRecipe` (ADR-0036 S2) turns a note row into a recipe row. The menu item
  editor already lets Jon pick a recipe for a row.
- **The inbox already sorts by extension.** `ChatInboxItemKind` in jon-platform `ChatAccessKit` matches files by
  extension, and shipped builds list only `json` and `ycreturn`. A new extension is invisible to an older build:
  it isn't opened as the wrong thing.

### Amd 2-D1 — The helper resolves a read ref when it stages, and Jon confirms on the device

Amd 1-D5 kept read refs out because "the export's index would become a write target, and nothing on the device
would confirm the target." Both halves have an answer:

- **The ref resolves once, in the helper, at staging time,** against the same export generation that issued
  it. A stale ref fails the call with "search again," as reads do now. The staged file records the recipe's id
  and its title as the export had it. The model supplies the ref, never the id, so it can't name a recipe it
  wasn't shown. Nothing indexes into an export later.
- **The device confirms the target.** The inbox row names the recipe, and so does the review it opens. Opening
  the row is the confirmation, the same way opening a `json` row is the confirmation for a new recipe. A
  recipe that's gone or archived on this device can't be opened. The row says so and offers **Discard**.
- **jon-platform ADR-0007 D5 holds.** The id goes from the helper to the app in a file. It never reaches the
  model.
- **ADR-0042 Amd 1-D2 holds.** The model supplies prose and labels only: no anchors, no line ids, no rewritten
  recipe. The paste door still never carries identity. This isn't the paste door.

**Rejected: the app resolves the ref** (OQ4's sketch). The app would have to keep every export generation it
wrote. And the ref may have come from the other device's export, since the helper reads the newest file. The
helper already holds the generation the ref came from.

**Rejected: `stage_handoff_return` also accepts a ref** (as Amd 1-D5 already decided). It's a different envelope:
no token line, no marker. One tool with two ways to name a target is harder for the model to use correctly than
two tools with one way each.

### Amd 2-D2 — `stage_recipe_return` returns changes to a recipe found with `search_recipes`

- **Input: `ref`** (a recipe ref from `search_recipes`) **and `text`:** one or more of the `.recipe` task's labeled
  deliverables. They are `YC-REVISION:`, `YC-MAKE-AHEAD:`, `YC-CHEF-IT-UP:`, `YC-SERVE-WITH:`, and
  `YC-LEARNINGS:`. There's no token line and no `YC-CONTRACT` marker.
- **The helper checks the envelope:** the ref resolves to a recipe in the current export, the text isn't empty,
  and it has no `YC-NEW-RECIPE:` block. A new dish goes through `stage_recipe`, and the error says so. As in Amd
  1-D2, the helper doesn't parse the body. The app parses it on open, with the parser the paste door uses.
- **The file:** `HandoffInbox(root: …/MCP/Inbox, fileExtension: "ycrecipereturn")`, with the recipe id as the
  slug. The body is a small JSON envelope written by the helper: format, version, recipe id, the export's
  title, and `text`. The slug lets the app label the row from the live recipe without reading the file.
- **Opening the row:**
  1. Claim the file. Any device may claim it, because the recipe is synced. That's the `json` claim rule
     (D3), not Amd 1-D3's minting-device rule.
  2. Create a device-local `AIHandoff` row: `sourceType .recipe`, `sourceID` the recipe, `taskType .recipe`,
     no variation, and an empty `exportedPrompt`, because nothing was exported.
  3. Call `stageReview(handoffID:, result: text, …)`, and present the review exactly as a pasted `.recipe`
     return would be presented.

  The review rebuilds against live rows, so an edit made after the export was written isn't lost.
- **The base recipe only.** A ref names a recipe, not a variation. This matches ADR-0061's guard: the `.recipe`
  prompt exports the base recipe.
- **More than one return per recipe is fine.** Each call is its own item and opens its own review, as with
  `.recipe`'s `acceptsRepeatReturns`.
- **Annotations:** `readOnlyHint: false, destructiveHint: false`, as for every staging tool.
- **The deliverable grammar travels with the server.** The labeled-deliverable lines in
  `AIHandoffContext.prompt(forTask: .recipe)` become one Core constant. Both the prompt and
  `ChatAccessServerInstructions` read it, and a test fails if they drift (D6's rule).

### Amd 2-D3 — `get_recipe` returns the Playbook text that's already exported

A handoff prompt carries the recipe's Make-ahead and Chef It Up text, so the model refines them and doesn't
start over. `get_recipe` leaves them out today, even though `Recipe.makeAhead` and `Recipe.chefItUp` are already
in the export. `get_recipe` adds `makeAhead` and `chefItUp`. **No export version bump.**

Serve With, learnings, and the taste profile aren't in the export. Adding them is a version bump, and the
helper fails loudly on a newer version (D4), so that's an install-order step. It's left out until it's needed
(OQ5). The reviews already show the current text next to the proposal, and learnings dedupe on ingest.

### Amd 2-D4 — `stage_menu` stages a new menu that Jon reviews before it's created

- **Input:** `title`, optional `days` (default 1), and `items`. Each item has an optional `ref`, a `title`, `day`
  (0-based, the same as `get_menu`'s `day`), `slot` (default `dinner`), an optional short `note`, and an optional
  `scale` (default 1).
  - **An item with a `ref` is a recipe row.** The helper resolves it as in D1 and records the recipe's id and
    title.
  - **An item without one is a note row**, titled with `title`, with `note` as its notes. That's the
    MenuItem invariant: only a resolved recipe gets `kind .recipe`
    ([[menu-item-recipe-id-invariant]]).
- **The helper checks everything it can:** there's a title; there's at least one item; `days` is between 1
  and 14; each `day` is inside `days`; each `slot` is a real `MealPlanItemSlot`; each scale is greater than 0;
  and every ref resolves to a recipe in the current export. Any failure returns `isError` and stages
  nothing, so a menu is never half-resolved.
- **The file:** `HandoffInbox(…, fileExtension: "ycmenu")`, a helper-written JSON envelope with the slug from
  the menu title. Any device may claim it.
- **Opening the row opens a review sheet** (ADR-0026's collection sheet). It has an editable title and one row
  per item, each marked **In your library** or **New dish**, and Jon can drop rows. On this device, an item whose
  recipe is missing or archived becomes a note row with the recorded title, and it's flagged. **Create Menu** writes
  the menu and its items in one transaction through `MenuRepository`. That's the only write. The menu is
  created unplaced. Placing it on the calendar stays in the app, along with ADR-0063's bring-in offer.
- **No menu-level notes.** The reasoning for the menu stays in the chat. `Menu.notes` isn't written. Per-dish
  notes go on the dish's own row, which is their typed home.
- **New menus only.** Adding to an existing menu would make a `list_menus` ref a write target for menus. That's
  D1's argument again, but the review would be a merge, not a create. Out (OQ6).

### Amd 2-D5 — A dish that's both new and on the menu: stage the recipe first, or link it afterward

`stage_recipe` and `stage_menu` don't know about each other. A dish Chat makes up can reach the menu in either of
two ways:

- **Recipe first.** Chat stages the recipe. Jon saves it. Returning to ChatGPT backgrounds the app, which
  writes a fresh export, or Jon taps **Refresh**. Then Chat searches again and stages the menu with refs. The
  server instructions describe this order.
- **Menu first.** The dish goes on the menu as a note row. Once the recipe is saved, Jon picks it for that row in
  the menu item editor.

**Rejected for now: a `stage_menu` item that carries its recipe inline, and links to its row when it's saved.**
Create Recipe would have to carry a menu-row target through the save and then run
`replaceNoteItemWithRecipe`. The referral transport (ADR-0058) is a precedent, but this would be new state
across two reviews. **Revisit** if the recipe-first order turns out to be a real cost in dogfooding.

### Amd 2-D6 — The server's instructions name every tool in their opening

Amd 1-D4 requires the first 512 characters to stand alone. The new opening:

> These are Yes Chef's recipe tools. Read with `search_recipes`, `get_recipe`, `list_menus`, `get_menu`,
> `get_meal_plan`. In a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`. Without
> one: `stage_recipe` stages a new recipe, `stage_recipe_return` returns changes to a recipe found with
> `search_recipes`, and `stage_menu` stages a new menu. Nothing is saved until Jon reviews it in the app.

The test for the 512-character opening gains the two new tool names. The rule for a failed call or a timeout
still applies: print the return for Jon to paste. For a menu, that's a plain list, which Jon builds by hand.

### Amd 2 — slices

Continuing D7's numbering. The two slices are independent and can go out as one dispatch.

- **S4 — recipe returns from a ChatGPT-started chat** (D1–D3, D6).
  - **Helper:** `stage_recipe_return`, ref resolution, envelope checks, the `.ycrecipereturn` file, `get_recipe`'s
    Playbook fields, and the instructions.
  - **Core:** the shared deliverable-label constant and its drift test.
  - **App:** the `ycrecipereturn` inbox kind, rows labeled from the live recipe, opening (claim, create the
    handoff row, `stageReview`), and the row for a missing recipe.
  - **Tests:** a stale ref, a menu ref passed as a recipe ref, `YC-NEW-RECIPE:` rejected, the 512-character
    opening, the app opening against a live recipe, and against an archived one.
- **S5 — `stage_menu`** (D4, D5).
  - **Helper:** the tool, validation, and the `.ycmenu` file.
  - **App:** the `ycmenu` kind, the review sheet, and Create Menu.
  - **Tests:** every validation error, the invariant (no recipe row without a resolved id), a recipe missing on
    the device becoming a note row, and one transaction for the whole menu.
  - Touches `YesChefApp/` model code, so `YesChefTests` runs (guardrail #9).
- **Install order:** update the app on both devices before installing the new helper. An older build ignores the
  new extensions rather than mis-opening them, so getting it wrong costs only the wait.
- **Device pass:** a menu chat in ChatGPT outside the `Yes Chef` Project. Search, pick two library recipes,
  return a revision and a make-ahead for one of them, stage one new recipe, save it, and stage the menu with it
  by ref and one dish as a note. On the iPhone, the revision opens the brief sheet and the menu opens its review.
  On the iPad, the other items are already gone from **From Chat**.

### Amd 2 — consequences

- A menu chat stays in ChatGPT from search to staging. Each write is still a confirmation tap in ChatGPT and a
  review in Yes Chef.
- Refs go stale every time a device writes an export, which happens whenever Yes Chef goes to the background.
  A long chat will see "search again" more often now that refs are write targets. That's the guard working,
  and a search costs a tool call.
- `AIHandoff` gains rows with no exported prompt. They're local, and they go straight to `imported`.
- No lift into `LLMHandoffKit` or `ChatAccessKit` beyond the new item kinds. Resolving a read ref into a write
  target is evidence for jon-platform `SEAM-LEDGER.md`'s "LLM handoff envelope" row, whose trigger hasn't fired.

### Amd 2 — open questions

- **OQ5 — Serve With, learnings, and the taste profile in the export.** Bump the export version and add them to
  `get_recipe` if dogfooding shows returns repeating known learnings or ignoring the taste profile.
- **OQ6 — staging into an existing menu.** Needs a merge review, not a create. Decide when a chat about a menu
  that's already planned wants it.

## Amendment 3 — A chat can replace one day of a menu that already exists (2026-11-10)

Status: **Accepted** — 2026-11-10 (#476). Answers Amd 2 OQ6 for one day at a time. Schema-free. No export change.
Adds one staging tool, one inbox kind and one review sheet. Built by effort [`stage-menu-day`](../efforts/archive/stage-menu-day.md).
The app half that shows a row's note on the recipe screen is effort
[`menu-row-note-on-recipe`](../efforts/archive/menu-row-note-on-recipe.md), which doesn't depend on this amendment.

### Context

Origin: Jon, planning one dinner of a 7-day menu that already exists with ChatGPT (2026-11-10). The chat chose
the dishes for that day. It also decided that Cook's Country's grilled chicken souvlaki, a family favorite, gets
its tahini-butter sauce on the side **for this menu only**, because muhammara and tzatziki are also on the table.

`stage_menu` can't put that day on the existing menu. It only creates menus (Amd 2-D4, "New menus only"), so the
day would arrive as a separate one-day menu, and Jon would rebuild it by hand. OQ6 said this "needs a merge
review, not a create." Jon's call is that **complete replacement of the day is fine**: Chat sends the whole day,
and that's what the day becomes. That's a far smaller review than a merge.

There are three kinds of information in a chat like this, and the app already has a home for each:

| Kind | Example | Home |
|---|---|---|
| The recipe | ingredients, method, refinements | the recipe, changed through `stage_recipe_return` (Amd 2) |
| This dish on this menu | "serve the sauce on the side" | **the menu row's note** (`MenuItem.notes`) |
| The menu's sequencing | make-ahead, work sessions, service order | the menu's prep plan (ADR-0034, ADR-0063) |

What the code already has, as of `origin/main` 9ac187a:

- **Every row has its own note, recipe rows included.** A row's id is separate from its `recipeID`, so the same
  recipe twice in one menu gives two rows with two notes. It syncs with the row. Edit Dish's **Serving Notes**
  edits it, and the menu and calendar rows show it.
- **`get_menu` returns each row's day, slot, note and scale,** and the export's `MenuRecord` carries the menu's id,
  so the helper can resolve a menu ref the way it resolves a recipe ref (Amd 2-D1).
- **Other rows point at a row's id.** `GroceryItemSource.menuItemID` and `PrepPlanStepRecord.sourceDish` both do,
  and so does a row's own scale. So "replace" can't mean delete-all and reinsert: a dish that stays on the day
  must keep its row (AGENTS.md guardrail #4).

### Amd 3-D1 — A menu row's note is where a menu-specific annotation lives

- A contextual decision about one dish on one menu (serving, a substitution, a presentation change, a quantity
  note) goes in **that row's note, as plain text.** The recipe isn't touched.
- **No structured overrides.** No ingredient or step overrides, no automatic application of a note to the recipe,
  no recipe forks, and no grocery effect. Grocery generation keeps ignoring row notes.
- If the decision should change the recipe everywhere, it's a recipe return (`stage_recipe_return`). If it
  sequences several dishes, it's the prep plan. The tool descriptions say so (D5).

### Amd 3-D2 — `stage_menu_day` stages the whole of one day

- **Input:** `menu` (a ref from `list_menus`), `day` (0-based, as in `get_menu`), and `items`, 1 to 40 entries.
  Each item has the same shape as a `stage_menu` item, without `day`: an optional recipe `ref`, a `title`, `slot`
  (default `dinner`), an optional `note`, and an optional `scale`.
- **The items are the whole day, every slot.** Whatever is on that day now and isn't sent goes away. A note or
  scale that isn't sent is gone too: no `note` means no note, and no `scale` means 1. The description tells Chat to
  read the menu with `get_menu` first and to carry over every dish, note and scale that should stay.
- **The day must already exist** (`day` is less than the menu's day count). Adding days stays in the app.
- **Checks**, all-or-nothing, as in Amd 2-D4: the menu ref resolves; `day` is in range; and every item passes
  `stage_menu`'s item checks (slot, the 500-character note cap, scale, the recipe ref resolves and isn't archived,
  a dish without a ref has a title). Any failure stages nothing.
- **The file:** `HandoffInbox(…, fileExtension: "ycmenuday")`, a helper-written JSON envelope with:
  - the menu's id and title, and the day;
  - the proposed items, in the order sent;
  - **the day as the export had it** (`dayAtStage`): each row's kind, title, recipe id, slot, note and scale,
    with no row ids.

  It decodes loudly, like the other envelopes. Any device may claim it.
- **The result** names the menu and the day, counts the dishes, and says Jon reviews it in **From Chat**. No ids.

### Amd 3-D3 — Apply replaces the day, and a dish that stays keeps its row

Apply runs in one transaction. It matches each proposed item to a live row on that day, at most once each:

1. **A recipe item** matches a live recipe row with the same recipe, preferring one in the same slot.
2. **A dish without a ref** matches a live note or reservation row with the same title (trimmed,
   case-insensitive), preferring the same slot. A matched reservation stays a reservation.
3. A **matched** row keeps its id and gets the proposal's slot, note and scale. A recipe item whose recipe is
   missing or archived on this device becomes a note row with its title, as in Amd 2-D4, and it's flagged.
4. An **unmatched** proposed item is added as a new row.
5. An **unmatched** live row is deleted, through the same `MenuRepository.deleteItem` the app uses.
6. Within each slot, rows take the proposal's order.

**A deleted row behaves exactly as if Jon deleted it in the app.** Grocery items and prep steps that pointed at it
are left as they are today. Nothing new cleans them up, and the review says how many dishes go.

If the menu is placed on the calendar, the calendar shows the new day at once. Its rows are a projection of the
menu's.

### Amd 3-D4 — The review shows the day before and after

- **Opening the inbox row** looks up the menu on this device.
  - **Not found:** the row reads **"Menu not found on this device"** and offers **Discard** only. It's never
    claimed automatically; the menu may still be syncing in.
  - **Found:** a review sheet in the house collection-sheet style (ADR-0026), titled with the menu and the day's
    date (or "Day N" for an unplaced menu).
- **The sheet shows the day as it will be, and marks each row:**
  - **Kept**: a matched row whose slot, note and scale don't change.
  - **Changed**: a matched row. It shows each change, such as the new note, "note removed", or "scale 2× → 1×".
  - **New**: an unmatched proposed item, marked **In your library** or **New dish**, as in Amd 2-D4.
- **A "Removed" section** lists the live rows that will be deleted.
- **One flag, never silent:** if the day on this device differs from `dayAtStage`, a banner says **"This day
  changed since Chat read it."** Jon decides.
- Jon can **drop a proposed row**, which means it's not on the day after Apply. A removed row can't be rescued from
  the sheet. To keep it, Jon discards and asks Chat again, or adds it back in the app. That's the cost of complete
  replacement, and Jon accepted it.
- **Apply** writes the day, then claims the file and opens the menu.
- No `AIHandoff` row and no hand-off token. This is a staging inbox kind like `ycmenu`, not a hand-off.

### Amd 3-D5 — The descriptions route between the three kinds

- `stage_menu_day`'s description: use it to replace one day of a menu found with `list_menus`. Read it with
  `get_menu` first. Send every dish for the day, with every note and scale that should stay; anything not sent is
  removed. A row's note is for this dish on this menu only. A change to the recipe itself goes through
  `stage_recipe_return`. The day must exist.
- `stage_menu`'s description: "This creates a new menu; it cannot add to an existing menu" becomes "This creates a
  new menu. To change one day of a menu that already exists, use `stage_menu_day`."
- The instructions' opening (Amd 2-D6) becomes, at 474 characters:

  > These are Yes Chef's recipe tools. Read with `search_recipes`, `get_recipe`, `list_menus`, `get_menu`,
  > `get_meal_plan`. In a conversation with a `YC-HANDOFF:` line, finalize through `stage_handoff_return`. Without
  > one: `stage_recipe` stages a new recipe, `stage_recipe_return` returns changes to a recipe found with
  > `search_recipes`, `stage_menu` stages a new menu, and `stage_menu_day` replaces one day of an existing menu.
  > Nothing is saved until Jon reviews it in the app.

- The `stage_menu` paragraph after the opening gains one sentence for the day: read the menu first, then send the
  whole day.

### Amd 3 — rejected

- **A notes-only tool with row refs** (this amendment's first draft, the same day). It needed row ids in the export
  and a second review sheet, and it only changed notes. Replacing a day covers a note change too: Chat resends the
  day with the new note, the souvlaki's row is matched and kept, and the review shows one **Changed** row.
- **A merge** (OQ6's original framing): Chat sends only additions and changes. It needs a rule for every
  conflict, and Jon doesn't want one.
- **Delete the day, then insert the proposal.** It's simpler, but it breaks grocery sources, prep-step
  links and per-row scale for every dish that stays (guardrail #4).

### Amd 3 — slice

- **S6 — `stage_menu_day`** (D2–D5), one dispatch: effort [`stage-menu-day`](../efforts/archive/stage-menu-day.md).
- **Install order:** the app on both devices first, then the helper, as in Amd 2.

### Amd 3 — consequences

- A chat about a planned menu can rework a day, and annotate its dishes, without leaving ChatGPT. The note reaches
  the cook on the recipe screen through `menu-row-note-on-recipe`.
- A note change costs Chat a resend of the whole day. A day is a handful of rows, and the review shows only what
  changed.
- The recipe is never written by this path.
- Menu refs go stale with every export, like recipe refs. A long chat will see "read the menu again" more often.

### Amd 3 — open questions

- **OQ7 — adding days, or replacing several days at once.** One day per call, inside the existing day count. Revisit
  if a chat keeps making several calls in a row, or needs a day past the end.

## Amendment 4 — From Chat is its own sidebar destination (2026-11-10)

Status: **Accepted** on the merge of its plan PR. Moves where the app lists inbox items (D3's "the app lists inbox
items"); changes no tool, no inbox kind, no review and no write. Schema-free. Built by effort
[`from-chat-destination`](../efforts/archive/from-chat-destination.md).

### Context

D3 had the app list inbox items without saying where. The first build put the list at the top of **Create Recipe**, which was
right when the only item was a staged recipe and opening it meant "fill in Create Recipe's draft." Amendments 1–3
added four kinds, and none of them ends in Create Recipe:

| Item | Kind | Where it ends up |
|---|---|---|
| Staged recipe | `json` | Create Recipe's draft (D3) |
| Handoff return | `ycreturn` | the handoff's review: a recipe, a prep plan (Amd 1) |
| Recipe return | `ycrecipereturn` | that recipe's review (Amd 2-D2) |
| New menu | `ycmenu` | the menu review, then Menus (Amd 2-D4) |
| Menu day | `ycmenuday` | the day review, then that menu (Amd 3) |

So Create Recipe is mostly hosting a list that isn't about creating recipes, and Jon reads its name as "more and
more of a lie" (2026-11-10). Renaming it **Inbox** fixes that for four kinds and breaks it for the fifth: it would
stop saying that this is where you make a recipe. The S6 device pass that evening also showed the cost of hiding
the list in another destination's screen: ChatGPT had staged a menu day, and the first question was where it went.

[ADR-0053](ADR-0053-create-recipe-destination.md) never placed the inbox on Create Recipe; it defines the screen as
the compose material plus the structured draft. This amendment returns the screen to that, so ADR-0053 doesn't change.

### Amd 4-D1 — From Chat is a sidebar destination, and Create Recipe goes back to compose and draft

- A new `AppSection.fromChat`, titled **From Chat**, holds the list that's now `ChatAccessInboxSection`, with its
  review sheets. It sits directly above Create Recipe in both the iPhone and the iPad tab orders, and like Create
  Recipe it's hidden from the compact tab bar (`.defaultVisibility(.hidden, for: .tabBar)`).
- **It's always in the sidebar,** with an empty state when nothing is staged. A destination that appears and
  disappears with its contents moves the sidebar under Jon's finger.
- **The badge moves with the list.** From Chat carries `.badge(inboxCount)`; Create Recipe loses its badge.
- **Create Recipe** shows only the **Source** section and the draft (ADR-0053 D2).

### Amd 4-D2 — Each row still goes where it belongs

Nothing about opening an item changes. From Chat is a triage list, and each row routes to its home through the
path it already uses: a staged recipe through `CreateRecipeCoordinator.stage(text:)`, which selects Create Recipe;
returns through `handoffReviewCoordinator.presentStaged`; a menu or a menu day through its review sheet and then
`onMenuSelected`, which selects Menus. Claiming, discarding, and the cross-device rules (D3, Amd 1-D3) are
unchanged.

### Amd 4-D3 — The name is "From Chat", not "Inbox"

It says where the items come from, and it's already the section's name and the name every tool result uses ("Jon
reviews it in Yes Chef → From Chat."). If a second, non-chat producer ever feeds this list (share-extension captures,
say), widen it to **Inbox** then.

### Amd 4 — rejected

- **Rename Create Recipe to Inbox.** It hides the one job the screen is named for (above).
- **Keep the list in Create Recipe and add a pointer elsewhere** ("3 from Chat →"). That's two homes for one list.
- **Show each kind in the destination it ends up in** (menus in Menus, returns on their recipe). Five places to look
  for one chat's output, and a staged recipe has no subject to sit under.

### Amd 4 — consequences

- One place to look after a chat stages something, with a badge that says so.
- Create Recipe is honest again.
- One more sidebar entry. It's always there, even when it's empty.

## Amendment 5 — A chat can replace the prep plan for the dishes it names (2026-11-10)

Status: **Accepted** on the merge of its plan PR. Adds one staging tool, one inbox kind and one review sheet, and
adds the prep plan to the export's menus (additive, no export version bump). Schema-free. Built by effort
[`stage-prep-plan`](../efforts/stage-prep-plan.md).

### Context

During the S6 device pass (2026-11-10), the chat that planned Thanksgiving Week's Day 3 dinner also worked out a
prep plan for it. Asked to stage it, ChatGPT said there was no tool for that and offered to write the schedule into
the seven dishes' notes instead. That's the wrong home. Amd 3-D1's table puts the menu's sequencing in the **prep
plan**, which is already stored one step per row (`PrepPlanStepRecord`, ADR-0034, ADR-0063). Spread across the
dishes' notes, the schedule would be invisible to the plan's bands and work days, and it would be deleted the next
time a chat restaged the day.

The app-started hand-off already writes a prep plan (Amd 1: Hand off → Menu, then `stage_handoff_return`), but only
for a chat that began with a `YC-HANDOFF` line. It replaces the **whole** plan, and pasted plans can't carry a step's
link to its dish (`AIHandoffReturn.droppedSourceDishEvidence`).

Jon's call (2026-11-10): a chat doesn't need to *add* to a plan, **as long as it can replace the entire plan for only
certain dishes.**

What the code has, as of `origin/main` 5153ee0:

- **A step** (`PrepPlanStepRecord`) has `session` (free-text "when", from which the band is derived), `task`,
  `serves` (free text), `sourceDish` (an optional `MenuItem.ID`) and `workDayOffset` (multi-day menus only).
- **`sourceDish` is usually empty.** Plans arrive as pasted text, and `PrepPlanDishMatcher` only *suggests* a link
  in the step editor for Jon to confirm.
- **`PrepPlanStepRepository.replace`** replaces the whole plan and keeps the id of every step whose content is
  unchanged.
- **The export has no prep plan,** so `get_menu` can't show one.

### Amd 5-D1 — A chat replaces the plan for the dishes it names, and only those

`stage_prep_plan` names a menu and a set of its dishes. For each dish it sends **every** prep step that dish
should have. Apply removes the dish's current steps and puts the new ones in their place. **Steps that belong to
other dishes, and steps that belong to no dish, are untouched.** A dish named with no steps has its steps cleared.

That's Amd 3's replace rule, scoped to dishes instead of a day. The scope is dishes, not days, because prep for
Tuesday's dinner happens on Monday: a step's work day is not its dish's day.

### Amd 5-D2 — Which current steps a dish owns

A current step belongs to a named dish if:

1. **its `sourceDish` is that dish's row**; or
2. **it has no `sourceDish`, and `PrepPlanDishMatcher` matches its `serves` to that dish and no other.** These
   steps are marked **matched by name** in the review, so Jon sees why they're being replaced.

Any other step stays. A dish is resolved to its row the way Amd 3-D3 matches: a recipe ref to a `.recipe` row with
that recipe on that day, or a title to a `.note` or `.reservation` row with that title on that day (trimmed,
case-insensitive).

**New steps arrive linked.** Each staged step names its dish, so Apply sets `sourceDish` to the dish's row and
`serves` to its title. This is the first path into the plan that carries links, and every later
`stage_prep_plan` for the same dish finds its steps by rule 1.

### Amd 5-D3 — The tool

`stage_prep_plan {menu, dishes: [{day, ref | title, steps: [{workDay, session, task}]}]}`:

- **`menu`** is a ref from `list_menus`.
- **Each dish** is one already on the menu: `day` as in `get_menu` (0-based), with a recipe ref from
  `search_recipes` *or* the row's title. It has 0 to 40 steps.
- **Each step** has:
  - `workDay`: 0-based like `day`, and may be negative for days before the menu starts (down to −7). Omit it on a
    one-day menu.
  - `session`: when, in words ("Monday evening", "2 hours before").
  - `task`: one separable task.
- **All-or-nothing checks,** with the read tools' messages where they exist: the ref, each dish existing on that
  day in the export, each `day` and `workDay` in range, 1 to 20 dishes, at most 80 steps in all, and non-empty
  `session` and `task` (`task` at most 500 characters).
- **The staged file** (`.ycprepplan`) carries the menu id, the dishes as sent, and `planAtStage`, the export's whole
  plan for that menu.
- **The result** names the menu and counts the dishes and steps. No ids. Annotations: `readOnly false,
  destructive false, openWorld false`. Nothing is written until Jon applies it.

### Amd 5-D4 — `get_menu` shows the current plan

The export's `MenuRecord` gains `prepPlan`, the menu's steps in plan order. Each step has its work day, session,
task, `serves`, and its dish's index in `items` when it's linked. `get_menu` returns it with each dish as its title
and day, never an id. That lets a chat rework a dish's plan rather than start blind, and it gives the review a
baseline: when the menu's plan differs from `planAtStage` (as a multiset of work day, session, task, serves), the
review shows **"This plan changed since Chat read it."** An export from an older build has no `prepPlan`; the field
is optional, the version stays 1, and the review then reads **"Chat couldn't see the current plan."**

### Amd 5-D5 — The review, and Apply

The review is grouped by dish. Under each dish it shows:

- **New**, the staged steps, each with a keep toggle;
- **Kept**, a current step identical to a staged one (same work day, session and task), which keeps its id;
- **Removed**, the dish's current steps that no staged step matches, with **matched by name** marked.

A dish that's no longer on the menu, or a menu that's gone, makes the review say so, and Apply is unavailable; the
file stays until it's discarded.

**Apply** writes in one transaction: it deletes the removed steps, inserts the kept new steps (linked, per D2),
leaves every other step alone, and touches the menu's `dateModified`. **Ordering:** a new step goes after the last
remaining step with the same work day and session; failing that, after the last step on its work day; failing that,
at the end. Then `sortOrder` is renumbered, writing only the rows whose order changes.

### Amd 5-D6 — The description carries the rules

ChatGPT doesn't show the model the server instructions, so `stage_prep_plan`'s description says it:

- **For each dish, send the whole plan.** Anything not sent for a named dish is removed, and dishes not named are
  untouched. Read the menu with `get_menu` first.
- **Steps are tasks, not choreography.** Use separable tasks ("salt the chicken"), never cooking instructions woven
  across recipes ("sear the beef while the salad rests"). The recipes hold the cooking (ADR-0039 D5).
- **Don't put the schedule in dish notes.** A note is for this dish on this menu (Amd 3-D1); sequencing goes here.
- **A step that serves several dishes** goes under the dish it mostly serves, and its task can name the others.

The opening names `stage_prep_plan`. It must stay within 512 characters, so the opening's list gets shorter.

### Amd 5 — rejected

- **The dish notes** (ChatGPT's offer). Wrong home (Context).
- **Whole-plan replacement only** (the hand-off's rule). One dinner's plan would have to carry every other day's
  steps, or wipe them.
- **Adding steps without replacing.** Restaging a dish would duplicate its plan. Jon doesn't need it (Context).
- **Row ids in the export** to name dishes. ADR-0007 D5 keeps ids away from the model, and Amd 3 already resolves a
  dish by ref or title.

### Amd 5 — consequences

- A chat that plans a dinner can leave its prep plan in the menu, linked to its dishes, without a hand-off token.
- Steps that a chat stages are linked, so the plan gets more linked over time, and later restages find their steps
  without matching by name.
- Steps that belong to no dish are out of reach of this tool; they still go through the hand-off or the editor.
- The export grows by the menus' plans. They're small.

### Amd 5 — open questions

- **OQ8 — steps that serve the whole menu** ("clean the grill", "set the table"). D6 files a multi-dish step under
  one dish, and a step for no dish can't be staged. Revisit if chats keep producing menu-wide steps that end up
  forced under a dish.
