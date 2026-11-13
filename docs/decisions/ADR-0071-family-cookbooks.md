# ADR-0071 — Family cookbooks: browse someone's recipes read-only, copy one into yours

> **One-line:** Each person can share their recipe library, read-only, with the family. Anyone they invite can
> browse it with the same list, filters, sorts and reader they use on their own library, and copy a recipe into
> their own library as an independent copy. Nothing else is shared, nothing is co-edited, and no synced table
> changes.

Status: **Accepted** — 2026-11-13, after the S0 transport spike passed on Jon's and Wendy's devices
([S0 result](#s0-result-2026-11-13)). Scopes [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md) Phase 2
("Family Cookbook"), which [ADR-0070](ADR-0070-what-you-teach-reaches-everyone.md) D2 left unscoped.
Origin: Jon, 2026-11-13: *"let people view another user's recipes (sort, filter, all that stuff) and then copy a
recipe to their own stash."* The users are Jon, Wendy, and maybe the boys: a handful of people who know each other.
Builds on: ADR-0003 (private libraries, transfer = copy; reaffirmed) · ADR-0070 D1 (household state never shared) ·
[ADR-0050](ADR-0050-recipe-power-browser.md) (the browser being reused) ·
[ADR-0049](ADR-0049-unified-labels-and-assisted-tagging.md) (labels) ·
[ADR-0059](ADR-0059-yes-chef-dev-variant.md) (D4: the Dev variant shares the container and uses its Development environment) · guardrail #6 (the canonical
recipe-transfer bundle).

## Context

Each library lives in its owner's private iCloud database (ADR-0003). Nothing crosses between people. Wendy now uses
the app, and the first thing she'll want from Jon's ~2000 recipes is to look through them the way he does — by label,
time, rating, source — and take the ones she likes.

ADR-0003 settled the rules: read then copy, never co-edit, and copies get fresh IDs so an edit to one never touches
another. It sketched "one shared CloudKit zone" and stopped there. What's left is how the recipes get from Jon's iCloud
to Wendy's device, where they live once there, and how the existing browsing screens show them without learning a
second data model.

Three things in the codebase shape the answer:

- **The browsing screens already exist** and read the database through `@Dependency(\.defaultDatabase)`. If someone
  else's recipes sit in a database with the same schema, those screens work on it unchanged.
- **The recipe bundle already exists** (`RecipeBundleCoding.RecipeBundle`, guardrail #6). It's the right payload for a
  published recipe, but today it carries only categories by name, and no serve-with links or variations.
- **Copy detection already exists.** `RecipeImportRef` matches recipes by normalized source URL and title on import, and
  `RecipeSource.importedFrom` holds a provenance string. Neither needs a schema change to serve a copy.

## Decisions

### D1 — Only recipes are shared, read-only, and only when their owner invites someone

A person shares their recipe library from Settings › Family Cookbook › **Share My Recipes**, which sends an invitation
(Messages, by default) to the people they pick. The invitee taps it once, and that cookbook appears in their app.
Viewers can read; they can never write to the owner's recipes.

What's shared is the recipes, the labels and facets they carry, and the owner's rating and favorite on each. Archived
recipes are left out. Pantry, grocery lists, menus, the calendar, prep plans, chats, workbenches, deliberation logs,
AI settings, learnings and saved lenses are never shared (ADR-0070 D1).

It's the whole library or nothing. There's no per-recipe "don't share" switch in this ADR; if one turns out to be
needed, it's easy to add later because the publisher decides what to upload (D3), so it would be real rather than
cosmetic.

### D2 — Viewers see someone's cookbook through the screens they already use

On the viewer's device, each cookbook is a **local mirror**: its own SQLite file with exactly the app's schema, filled
only by the cookbook fetcher (D4). The recipe list, the Power Browser and the recipe reader run against the mirror by
swapping the database dependency for that screen tree. Search, sort, labels, facets, time filters and source filters
all come for free, with the same semantics as on your own library, because it's the same query code (ADR-0050 D1, "one
boundary owns the semantics").

One mirror per cookbook, at `Application Support/Cookbooks/<owner-zone>.sqlite`, excluded from device backup. It holds
the owner's own IDs, which can't collide with yours because it's a separate file.

**The mirror is a disposable cache.** Nothing in it is user data on the viewer's device, so it never needs a migration:
when the app's schema version changes, the mirror is deleted and fetched again. That keeps it out of the
never-rewrite-a-migration rules and the backup/restore story (ADR-0030).

### D3 — Transport: one record per recipe in a shared zone, in a separate CloudKit container

Each publisher writes one `CookbookRecipe` record per recipe into a `Cookbook` zone in their private database, plus one
`CookbookProfile` record (display name, recipe count, payload version). The zone is shared with a **zone-wide
`CKShare`** whose public permission is none and whose participants are read-only.

This lives in a **separate container**, `iCloud.com.jonphillips.yeschef.cookbook`, not
the library's container. SQLiteData's `SyncEngine` runs `CKSyncEngine` over the library container's private and shared
databases. A custom zone or an accepted share in that container would land in front of it, and this project has lost
data to sync surprises before. A second container keeps the cookbook code where the sync engine can't see it.

Both app variants list the cookbook container. Yes Chef Dev uses its Development environment, as ADR-0059 D4 does for
the library container. A separate Dev container would have a schema that could never be deployed.

Rejected:

- **SQLiteData's own sharing.** It shares a root record and its single-FK children *into the viewer's own tables*, so
  Jon's recipes would be mixed into Wendy's library and every query in the app would need an owner filter. It also
  needs one root for the whole library and can't carry `RecipeCategory` (two parents). Wrong tool for read-then-copy.
- **The public database.** No invitation step, but any install of the app can read every published recipe, and the
  notes in these recipes are personal. Invitations are cheap at this scale.
- **A snapshot file through iCloud Drive or the share sheet** (ADR-0070's route for knowledge). Workable and simpler,
  but the cookbook would be as stale as the last time its owner remembered to export. It's the fallback if the S0
  spike fails, and it reuses everything except S3–S4.

### D4 — Freshness: the publisher uploads what changed; the viewer fetches what changed

**Publisher.** On launch and foreground, after recipe edits (debounced), and from **Publish Now**, the app builds each
recipe's payload (D5), hashes it, and compares against the `contentHash` field on the records already in its zone.
It uploads only records whose hash differs and deletes records for recipes that are gone or archived. The zone is the
state: there's no local "what did I publish" table, and any of the owner's devices can publish without coordinating
(a save conflict just re-compares). The first publish of ~2000 recipes is the slow one; S0 measures it.

**Viewer.** On opening a cookbook and on foreground, the app fetches zone changes from the shared database with a
change token stored in the mirror, and applies them to the mirror in one write per batch. A recipe deleted by its
owner disappears from the mirror; any copy you made is yours and stays.

**Failures are loud** ([[no-dead-data]] rule: sync status never stays quietly green). Settings › Family Cookbook
shows "Shared with Wendy · 1,982 recipes · published 3 min ago" or the error. The viewer's cookbook header shows when
it last updated, and a payload version newer than the viewer understands is counted and shown ("12 recipes need a
newer Yes Chef"), never silently skipped.

### D5 — The published payload is the canonical bundle, version 2

The `CookbookRecipe` payload is `RecipeBundle` (guardrail #6) at `version: 2`, which adds what the browser and reader
need and the bundle lacks today:

- labels as facet + path, not bare names (ADR-0049), so filtering by Jon's labels works in the mirror;
- serve-with rows and related-recipe links (they point at the owner's recipe IDs, which exist in the same mirror);
- variations (ADR-0021), which are deltas on the recipe and belong with it;
- photos: thumbnails inside the payload, the display image as a separate `CKAsset` field that the viewer's change
  fetch skips (`desiredKeys`) and fetches when a recipe is opened. ~2000 display images at ~300 KB (ADR-0005) is too
  much to download just to browse.

`originalSnapshot` travels as is. The rating and favorite are the owner's and show as theirs.

Version 2 is a superset of version 1 and decodes version 1, so the existing snapshot reader keeps working.

### D6 — Visiting is read-only by construction

The feature models for the list, browser and reader take a `LibraryScope`:

```swift
enum LibraryScope: Hashable {
  case mine
  case cookbook(Cookbook)   // owner display name + mirror location
}
```

In `.cookbook`, write affordances (edit, rate, favorite, label, chat, adjust, add to menu, delete) aren't shown, and
the one action is **Copy to My Recipes**. The screens get the mirror through a **read-only** connection, so a write
path that slips through throws instead of quietly changing a cache that the next fetch would overwrite. Only the
fetcher holds a writable connection.

Cooking from someone's cookbook without copying (the reader, scaling, cook mode) is allowed: it reads. Anything that
needs the recipe in *your* data — a menu, the grocery list, a chat — asks you to copy it first.

### D7 — Copy is the transfer import: fresh IDs, provenance kept, opinions dropped

Copying runs the ADR-0003 transfer import on the payload:

- every row gets a fresh UUID; `originalSnapshot`, ingredient original text and the source URL are kept verbatim
  (Data Preservation Rules 1–4);
- `RecipeSource.importedFrom` records "Copied from Jon's cookbook" and the date; no new column;
- rating and favorite are reset (they were Jon's opinion); notes and variations come along;
- labels are found or created by facet + path in your tree (ADR-0003's find-or-create). Your organization wins where
  names match;
- serve-with and related-recipe links point at your copy of the target if you have one (matched the way
  `RecipeImportRef` matches), and otherwise stay as text with a visible note on the copy, never silently dropped;
- the copy writes a `RecipeImportRef`, so the cookbook marks the recipe **In My Recipes** afterwards, and copying it
  again asks **Open Mine / Copy Anyway**.

Your copy never changes when the owner edits theirs. There's no "update my copy" in this ADR.

### D8 — No synced schema change

No synced table gains or loses a column. The new state is all outside the library's sync: a second CloudKit container
and its two record types, the mirror files (a cache), and the fetch change token inside each mirror. The list of
cookbooks you can see comes from the cookbook container's shared database, not a local table.

That's the Persistent Model Change Rule's answer: existing data isn't affected and nothing needs migrating.

## What this costs

- Custom CloudKit code (a publisher, a fetcher, share invitation and acceptance) outside SQLiteData. It's the first in
  the app, and the reason for S0.
- A second container, set up in the developer portal and in both variants' entitlements, with its schema deployed to
  Production before the first TestFlight build that uses it.
- A pass through the list, browser and reader models to thread `LibraryScope` and hide write affordances.
- Viewers need iCloud and the invite link. With four people, that's at most a handful of one-time taps.

## Order

Each slice is one dispatch; S1 and S2 need no CloudKit and can ship to TestFlight unused.

| Slice | What | Proves |
|---|---|---|
| **S0** — spike, device gate | Second container; zone-wide read-only share from Jon's account, accepted on Wendy's; one record round-trips; `SyncEngine` logs show nothing from the cookbook container; time a 2000-record publish. | The transport works and leaves sync alone. Fail → fall back to the snapshot file (D3). |
| **S1** — payload and copy | `RecipeBundle` v2 (D5) with v1 decode; build a payload from a library recipe; copy-import (D7). Package tests: fresh IDs, snapshot and original text kept, labels find-or-create, link re-pointing and text fallback, duplicate detection. | Copy is correct before any UI or network. |
| **S2** — mirror and visiting | Mirror file from the app's migrator, read-only connection, apply-payloads-to-mirror (tested); `LibraryScope` through the list, browser and reader; **Copy to My Recipes**. DEBUG-only "Load cookbook from file" feeds the mirror for the device pass. | Browse, sort, filter, read, copy all work, against Jon's real library on Wendy's device. |
| **S3** — publish | Publisher (D4), Settings › Family Cookbook with Share My Recipes, status, Publish Now. | Jon's library reaches the zone and stays current. |
| **S4** — view | Accept the invite, fetch changes into the mirror, cookbooks in the sidebar, loud staleness and version counts. | The end-to-end feature. Device pass: Jon publishes, Wendy browses and copies, edits on either side stay put. |

Phase 1 "Send a copy" (a single recipe file through the share sheet) is S1's payload and import plus a share-sheet
action. Not in this plan; it's cheap after S1 if wanted.

## S0 result (2026-11-13)

**Pass.** The D3 transport stands, and the snapshot-file fallback isn't needed. Jon's device published from his
library, which holds 2,223 recipes, and Wendy's iPhone viewed it. Both ran Yes Chef Dev against the cookbook
container's Development environment. The spike merged as [#512](https://github.com/jonphillips/yes-chef/pull/512).

| Step | Result |
|---|---|
| Share | Zone-wide share created on Jon's device; Wendy's iPhone accepted it a minute later. (The "Share ready" log line lists only the owner, Jon: role 1 is owner, permission 3 is read-write. It was written before Wendy joined. Her read-only permission is shown by Try to Write.) |
| Publish 2,000 + profile | 86.8 s total: five 400-record batches at 16–18 s each, then the profile at 1.4 s (about 23 records/s) |
| First fetch | 2,002 changed, 0 deleted, in 42.7 s |
| Republish one | Wendy's next fetch: 1 changed in 2.4 s |
| Try to Write | `CKError` 10 (`permissionFailure`): "CREATE operation not permitted" |
| Library sync | Unaffected on both devices. The cookbook container's Development schema has only `CookbookProfile`, `CookbookRecipe`, `Users` and `cloudkit.share` |

What S3 and S4 take from it:

- **The share is a record in the zone.** The first fetch counted 2,002 records, not 2,001, because the spike counts
  every changed record, and the zone-wide share itself (`cloudkit.zoneshare`) is one of them. The S4 fetcher applies
  `CookbookRecipe` and `CookbookProfile` records and skips every other type, so the share can never count as an
  unreadable recipe ("needs a newer Yes Chef", D4).
- **The first publish takes about 90 seconds**, without photos. Thumbnails make the payloads bigger and display images
  add assets, so S3 should expect several minutes. Because the zone is the state (D4), an interrupted publish costs
  nothing: the next one compares hashes and uploads only what's left. S3 doesn't need to finish in one sitting, but
  its status has to say "Published 1,200 of 2,223" rather than look done.
- **A full fetch takes about 40 seconds** for 2,000 records. S4 shows progress on the first visit, and the browser
  works on what's arrived.
- **Log enum names, not raw values.** S3's sharing status names each participant and their permission in words. The
  spike's raw values were easy to misread.
- **Accepting from a cold launch wasn't shown.** The log has one acceptance, with no note of whether the app was
  running. S0's acceptance code is disposable, so S4's device pass checks both ways an invitation arrives.
- **Production schema.** The two record types exist only in the cookbook container's Development schema. They're
  deployed to Production before the first TestFlight build that publishes (What this costs).

## Open questions

- **OQ1 — times cooked.** "Jon has made this 12 times" would be the best sort a viewer could have, but it comes from
  his calendar, which is household state. A derived count in the payload shares the number and not the calendar.
  Not in v1; decide after Wendy has browsed.
- **OQ2 — the boys.** Same model: each gets their own library, and the people who share with them invite them. Nothing
  to decide until they use it.
- **OQ3 — "update my copy."** If copies drifting from an improved original becomes a real complaint, a later ADR can
  offer a side-by-side with the source (ADR-0023's review surface), keyed by the import ref. Not now.

## Amendment 1 — Copy details settled while briefing S1 (2026-11-13)

Three points D5 and D7 left open or got slightly wrong, settled in the S1 brief:

- **Unlinked related recipes aren't stored as text.** D7 said links whose target you lack "stay as text with a
  visible note on the copy". That holds for serve-with: a text-only serve-with row is already valid. A related-recipe
  pair can't exist without both recipes, and a generic note would be a new untyped home (notes are being drained,
  not grown). So the copy stores nothing for those. It lists them when you copy and offers to copy them too, which
  is when acting on them is useful.
- **Payloads name their link targets.** A v2 bundle carries `linkTargets` (ID, title, source URL) for every recipe
  its serve-with and related rows point at. Copying needs the target's identity to find your copy of it, and the
  Phase 1 single-recipe file has no mirror to look it up in.
- **Copy remaps variation anchors.** Variation deltas anchor to ingredient lines and steps by ID
  ([ADR-0021](ADR-0021-recipe-variations.md)). Fresh IDs would leave every anchor on its text fallback, which
  picks the wrong line when two lines read the same. The copy maps anchor IDs to the new rows and never drops an op.

"In My Recipes" also matches your recipes by source URL, not only by import ref, because a recipe you captured
from the same page yourself has no ref.
