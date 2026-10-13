# ADR-0010 — CloudKit sync enablement: assets, provenance, dedup, and cutover

Status: Accepted - 2026-06-30

## Context

[ADR-0002](ADR-0002-cloudkit-sync-no-server.md) settled the sync *decision* — CloudKit **private
database** via SQLiteData's `SyncEngine`, no server, no auth, with the binding schema laws (UUID PKs,
no unique indexes, plan for offline duplicate inserts). What it left open were the concrete calls
that must be settled **before** the flip, because CloudKit's first sync and its Production schema are
one-way doors: the first `SyncEngine` start uploads every existing local row into the zone, and once
a record field is deployed to Production it **cannot be deleted**. A planning session (2026-06-30)
audited the solo-built schema and resolved those calls. This ADR records them; the build order lives
in [`../milestones/M4-icloud-sync.md`](../milestones/M4-icloud-sync.md).

The audit found the schema **already conformant**: single UUID text PKs everywhere
(`DEFAULT (uuid())`), no unique or compound indexes, and no reserved-keyword column collisions (it
uses `dateCreated`/`dateModified`, not CloudKit's forbidden `creationDate`/`modificationDate`/
`recordID`/etc.). So M4 is **enablement + hygiene + cutover, not remodeling.**

## Decision

1. **Image/BLOB bytes need no schema change.** SQLiteData (verified in the 1.6.6 source, `setBytes`)
   promotes **every** BLOB column to a `CKAsset` unconditionally — hashed, written to a file, stored
   as an asset. CloudKit's ~1 MB per-record limit applies to a record's own fields, **not** assets.
   So `recipePhotos` bytes and `originalSnapshot` sync correctly as-is; we do **not** externalize
   image storage or change the photo schema.

2. **The "original" is a frozen structured blob, not a `Recipe` row — and it's leaned.** Keep
   `originalSnapshot` (a versioned `RecipeBundle` JSON) as an inert attachment that rehydrates into
   the same model structs the views already use. We reject modeling the original as a suppressed
   `Recipe` row: it would impose a permanent `WHERE NOT isOriginal` filter on every recipe query,
   double the synced relational graph and assets, and require identity/lifecycle guards everywhere.
   Two byte-hygiene calls, because drift is about **text, not pixels**, and the assets already sync:
   - **Strip embedded photo bytes** (`displayData`/`thumbnailData`) from the **snapshot** encoder
     (not the transfer `RecipeBundle`, which legitimately carries them for import/export).
   - **Stop persisting raw import HTML** (`originalImportText`, read only by a DEBUG DOM-export tool)
     in release builds.
   Both are prerequisites of the Production schema deploy (the synced-record column shape is one-way).

3. **Logical uniqueness is upsert + dedup-on-read.** With no unique indexes, two offline devices can
   each insert a row for the same logical key. Import is an **upsert**, and reads **dedup
   deterministically** (pick one row per key; a cleanup pass deletes the losers and re-points
   references). This binds `recipeImportRef`'s composed identity first, and any other logically-unique
   data (default grocery list, tags/categories by name) per a documented per-entity call.

4. **Clean cutover against an empty store.** Exercise sync in the CloudKit **dev** environment, then
   **deploy schema to Production** (one-way), **wipe local**, start `SyncEngine` against the empty
   store, and **re-import** the real library. The pipeline is the asset; local data is disposable.
   First sync is asset-heavy (each photo is a separate `CKAsset` upload) — a wifi/bulk operation.

5. **Sync is opt-in and degrades gracefully.** `SyncEngine(startImmediately: false)` plus a launch
   gate so the app runs **local-only** with no iCloud account (no login prompt, no crash). There is
   **no column-level** sync exclusion — the engine takes a table list; to keep data local, split it
   into a table not handed to the engine.

## Consequences

- The schema audit means no pre-flip migration of primary keys or column names — the risky,
  irreversible work is already done. `originalSnapshot` leaning is the only synced-record shape
  change, and it must land before the Production deploy.
- The **share extension is a second writer** into the App Group store. It may construct a
  `SyncEngine(startImmediately: false)` only to install SQLiteData's sync triggers and write
  `SyncMetadata`; it must never start the engine or perform CloudKit network work. The **main app
  owns sync upload/download** and picks up extension-written metadata.
- Verification is **eventual-consistency-on-real-devices** (two devices, one iCloud account) with no
  server logs; simulator iCloud is unreliable.
- **Sharing stays out** (Family Cookbook, [ADR-0003](ADR-0003-private-libraries-recipe-transfer.md)):
  `Recipe` is a clean FK-free root record so recipe sharing is viable later, but the six-FK
  `groceryItemSource` won't participate in record sharing — grocery sharing must not be designed
  around it. Curated collections ([ADR-0008](ADR-0008-curated-collections.md)) remain post-sync.
- **Modeling stays deferred and sync-safe:** canonical ingredient names (and any other new column or
  synced table) are additive and go in **after** the flip, backfilled lazily — not front-loaded.

## Amendment 1 — Raw import HTML is not kept in any build (2026-10-13)

**Decision (Jon, 2026-10-13).** D2's "stop persisting raw import HTML in release builds" now covers **every** build
configuration. `Recipe.originalImportText` is removed, and its column and data are dropped before the Production
deploy. No export or debug store replaces it. Brief: [`efforts/raw-import-html-drop.md`](../efforts/raw-import-html-drop.md).

**Why.**
- *The DEBUG exception leaked into the real library.* The DOM-export revival (PR #51) kept writing the page in
  DEBUG, and Jon dogfoods DEBUG: 2,143 recipes, 36 MB. Nine captures are over CloudKit's 1 MB per-record limit,
  since TEXT is inline and only BLOBs become assets. They never uploaded, and SQLiteData 1.9 swallows
  `.limitExceeded` without a word. A child saved later then gets `.referenceViolation`, and SQLiteData applies the
  FK's `ON DELETE` locally. `SET NULL` broke three calendar rows. On a `CASCADE` child the same path deletes the row.
- *It has no reader and no future reader.* Its only consumer was the DEBUG DOM export. No re-parse path was ever
  built, and none will be: Jon accepts a capture at review or debugs it live, and never redoes a recipe.
  Provenance is `originalSnapshot`, the `RecipeSource` URL and each `IngredientLine.originalText`.

**Rejected.**
- A synced BLOB column: it uploads about 1 MB per capture for a debug button.
- A local BLOB table: a store nobody reads.
- Keeping only the JSON-LD: the snapshot already holds what the app uses from it.
- Stripping scripts: that removes `ld+json` and `__NEXT_DATA__`, the only parts with any value.

**Consequences.** Data Preservation Rule 1 ("never discard original imported text") means the snapshot plus each
line's original text, not the raw page (`docs/AGENTS.md` now says so). `IMPORT_EXPORT.md` and `DATA_MODEL.md` drop
the "preserve raw HTML for later re-parse" intent. ADR-0054's deferred "Create Recipe retains
`originalImportText`" P1 is moot. Raw page storage is a standing guard.
