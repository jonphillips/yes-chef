# ADR-0056 — Moving to production: the dogfood library crosses in place, and backup→restore is the verified re-seed

> **One-line:** The real ~2,100-recipe dogfood library must survive the move from a dev-signed build on
> CloudKit **Development** to a TestFlight/App Store build on CloudKit **Production** — Jon should not
> re-import anything. The bundle id and CloudKit container id do not change, so the *local* SQLite store
> carries across the update in place. What does **not** obviously carry is the *Production private zone*:
> it starts empty, and the sync **metadatabase is keyed by container id, not environment**, so it may
> report every row as "already synced" (to Dev) and suppress the very upload that would seed Production.
> The mechanism that reliably re-seeds a fresh zone already exists and is device-confirmed — **restore**,
> which begins as a new sync peer and re-pushes the entire library as authoritative (ADR-0030 Amd 2).
> This ADR makes **backup→restore the primary, known-good re-seed and the rollback**, treats in-place
> auto-seed as an *unproven optimization the dry run may bless*, and puts a DB-preserving baseline squash
> and a single-device dry run in front of the cut so nothing irreversible happens on a guess.

Status: **Accepted** — 2026-08-24 (proposed and accepted same day, Jon's explicit call; the load-bearing
decision is D1, restore-as-primary re-seed). Origin: Jon, asking whether we have a real move-to-production
plan and whether he can leverage his local database instead of re-importing. Extends
**[ADR-0001](ADR-0001-persistence-sqlitedata.md)** (SQLiteData persistence),
**[ADR-0002](ADR-0002-cloudkit-sync-no-server.md)** (CloudKit sync, no server), and depends directly on
**[ADR-0030](ADR-0030-local-backup-and-restore.md)** (local backup & restore; its Amendment 2 — *restore is
authoritative* — is the load-bearing mechanism here). Sequences the held **Prod-schema promotion list** in
`docs/CURRENT_HANDOFF.md` into a full cutover, executed via the companion runbook
[`docs/PROD-CUTOVER.md`](../PROD-CUTOVER.md). Cautionary context that shaped the hazards below:
[[migration-writes-bypass-sync-triggers]], [[debug-erase-vs-sync-triggers]], [[squash-migrations-at-prod-baseline]],
[[never-rewrite-shipped-migration]], [[restore-is-authoritative]], [[sqlitedata-single-fk-sync-limit]] (the
throttled ~44k-row initial sync).

**Cross-repo — this is a shared platform seam, not a yes-chef invention.** The *mechanism* (CloudSyncKit /
SQLiteData behaviour at the Dev→Prod boundary) is jon-platform's, and its house doc
`jon-platform/docs/ios/persistence-and-sync.md` already owns the pieces this ADR builds on: the metadatabase
coverage diagnostic (D4 below), the migration-writes-behind-the-engine trap (D4), the one-way Dev→Prod schema
deploy, and the dashboard verification gotchas (D5). What that doc does **not** yet cover is *carrying an
existing populated library across the boundary* — its Rollout step 4 says "wipe local to an empty store,"
which assumes no precious data. This ADR and its runbook are the **app-specific execution** (yes-chef's
bundle/container ids, promotion list, squash, ~2,100-recipe library); the shared *finding* (metadatabase is
container-keyed not environment-keyed → in-place carry may not seed Prod → restore is the re-seed) is
recorded in `jon-platform/SEAM-LEDGER.md` and is **lifted into the house doc only once this ADR's dry run
proves it** (OQ1) — Galavant inherits the identical hazard but is not yet at its own cutover.

## Context — what "move to production" actually threatens

Sync is done — the library round-trips end-to-end across two physical devices (M4). We have deliberately
stayed in the CloudKit **Development** environment so the schema can keep evolving. "Move to production" is
therefore three transitions stacked in one moment, and only the first is written down:

1. **A migration-baseline squash** collapses the accumulated migrations to a single baseline before the
   schema is frozen for prod (the standing pre-prod plan). This is where the dead `Recipe.lastCookedAt` /
   `Recipe.timesCooked` columns get dropped ([[withdraw-not-defer-orphaned-schema]]).
2. **A CloudKit Development→Production schema deploy** — additive-only, and it **permanently locks** those
   record types. This is the existing promotion list, and it is the only step we had planned.
3. **The distribution channel flips the CloudKit environment.** There is no
   `com.apple.developer.icloud-container-environment` entitlement pinning us, so the environment follows the
   signing channel: dev-signed builds talk to **Development**, a TestFlight/App Store build talks to
   **Production**. Nobody flips a switch — installing the distribution build *is* the flip.

The favorable facts: bundle id is `com.jonphillips.yeschef` (store-ready, no rename) and the CloudKit
container is a single hardcoded `iCloud.com.jonphillips.yeschef` (`CloudSync.swift`). Same bundle id →
**the app's local container, and its SQLite store, survive the update in place.** So Jon's library is not
lost locally by the update itself.

### The non-obvious hazard: in-place carry may not seed Production

The Production private zone starts **empty**. The intuitive path — "SyncEngine sees local rows, uploads them
to seed Prod" — is not guaranteed, for one concrete reason:

- The sync **metadatabase is a separate attached database keyed by container id, not environment**
  (`DatabaseStorage.swift`: `metadata-<containerIdentifier>.sqlite`; `VACUUM INTO` backups deliberately
  exclude it — `DatabaseBackup.swift`). The container id is identical across Dev and Prod, so after the
  environment flips, the SyncEngine reads a metadatabase whose change-tokens and per-row sync state were
  **issued by the Development zone**. Two outcomes are possible and we do not know which occurs:
  - the metadata reports rows as already-synced and the engine uploads **nothing** → Production stays empty,
    the data lives only locally on that one device, and a second device pulls an empty library; **or**
  - CloudKit rejects the stale Dev tokens against the Prod zone and the engine re-bootstraps → a full
    re-upload seeds Production.

We refuse to bet the library on which. Separately, even if a re-upload happens, any row inserted by a
migration or before the engine existed may carry **no sync metadata at all** and silently never upload —
the documented [[migration-writes-bypass-sync-triggers]] trap.

### The mechanism that is known-good already exists

**Restore** (ADR-0030) does precisely what seeding a fresh Production zone requires: it replaces the local
store with a snapshot, **begins as a brand-new sync peer** (`disableForRestore` holds sync off until Jon
re-enables it), and on re-enable **re-pushes the entire restored library, winning every collision**
(Amendment 2, device-confirmed). It is environment-agnostic by construction because it discards the old
sync metadata. That is the reliable re-seed — we already built and tested it for a different reason.

## Decision

**D1 — Backup→restore is the primary, known-good re-seed into Production; in-place auto-seed is not relied
upon.** The cutover seeds the Production zone by restoring the dogfood backup on the distribution build and
enabling sync, which re-pushes the whole library as authoritative into the fresh zone. If the dry run
(D5) proves in-place carry *does* re-upload correctly on this device, we may skip the restore and let it
ride — but that is an optimization the dry run must earn, never an assumption the plan starts from.

**D2 — The baseline squash must preserve an existing local store, and is proven on a copy of the real
dogfood DB before it runs for real.** No erase-on-schema-change path (it has wiped the dogfood library
before — [[debug-erase-vs-sync-triggers]]). The squash preserves already-applied migration state on a live
device and only presents a clean baseline to fresh installs. It is tested by pointing a build at a **copy**
of Jon's actual database and confirming zero data loss and no schema drift — not against a seeded sample
store ([[squash-migrations-at-prod-baseline]], [[never-rewrite-shipped-migration]]). The
`lastCookedAt` / `timesCooked` drop lands here.

**D3 — A full backup is taken immediately before the cut and is the rollback.** Because restore is
authoritative, a pre-cut snapshot is both the re-seed source (D1) and the way back: if anything downstream
is wrong, restoring the pre-cut backup on a dev-signed build re-establishes the Development library. Nothing
in the cut is trusted until this backup exists and has been verified openable.

**D4 — SyncMetadata coverage is a precondition, checked before the cut.** Whichever re-seed path runs, every
row that should sync must actually be uploadable — a row with no sync metadata uploads to neither Dev nor
Prod. Before the cut we verify coverage (rows present in synced tables vs. rows the engine will push) and
remediate any migration-orphaned rows deterministically. The promotion list is checked **in both
directions** against the `makeSyncEngine` registration in `CloudSync.swift`, per the existing handoff rule.

**D5 — A single-device dry run is the gate; nothing irreversible precedes it.** On one device, install the
prod-configured build over the dev build and confirm, in order: (a) the local library is intact after the
squash; (b) the chosen re-seed path actually populates the Production zone (observed server-side, not
inferred from the local UI's "up to date"); (c) a *second* fresh install pulls the full library from
Production. Only after (c) do we treat the cut as real. The **Development environment is not reset** until
production is proven — it remains a live fallback.

**D6 — The distribution build ships with the dogfood scaffolding off.** No seed-sample-data, no
erase-on-schema-change, no volatile sync launch-argument gating enablement — the shipping build must enable
sync through the persistent path, not an Xcode launch arg ([[extension-sync-construct-not-run]] enablement
lesson). Entitlements (app-group + iCloud container) intact on both the app and the share extension.

## Consequences

- **Jon does not re-import.** His library crosses via restore (or blessed in-place carry), images included
  — they are BLOBs inside the DB file, so the snapshot is byte-exact ([[sqlitedata-blob-cloudkit-asset]]).
- **The first Production sync is large and slow.** Expect CloudKit 429 throttling on the initial push of the
  whole library ([[sqlitedata-single-fk-sync-limit]]); the failure mode to avoid is panicking mid-sync and
  wiping. The runbook budgets time and says explicitly: do not intervene.
- **The Production schema is locked the moment it deploys.** Anything not on the promotion list — including
  the two cook columns and the already-dropped `Menu.prepPlan` BLOB — must be *absent* before the deploy,
  because additive-only means a mistake is permanent. This is why the squash precedes the deploy.
- **Restore-as-primary means the cut has a rehearsed, authoritative re-seed** rather than a hopeful one; the
  cost is one deliberate export/restore/enable sequence instead of a silent automatic upload.

## What would force a re-import (the failure list the plan exists to prevent)

1. The squash erases the local store (D2 prevents).
2. In-place carry uploads nothing to Prod **and** no backup was taken (D1 + D3 prevent).
3. Migration-orphaned rows never upload and are noticed only after the Dev environment is gone (D4 + D5
   prevent — Dev stays live until Prod is proven).
4. The bundle id or container id changes, breaking local-container carry (out of scope: **do not change
   either**; both are already store-ready).

## Open questions

- **OQ1 — Does in-place carry actually re-seed Prod on this device?** Resolved empirically by D5(b). If yes,
  D1's optimization is available; if no, restore is the path. Either way the plan is safe.
- **OQ2 — Keep the Development zone and its data as a cold archive post-cut, or reset it?** Default: keep it
  untouched as a fallback through at least one confirmed Production round-trip on two devices; decide on
  reset afterward.
- **OQ3 — Is a lightweight server-side inspection (CloudKit dashboard record count in the Prod private zone)
  part of D5(b)?** Proposed yes — "up to date" in-app has lied before ([[sqlitedata-single-fk-sync-limit]]),
  so the re-seed is confirmed against the zone, not the indicator.
