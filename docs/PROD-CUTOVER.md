# Production Cutover Runbook

**Purpose.** The ordered, reversible procedure for taking Yes Chef from a dev-signed build on CloudKit
**Development** to a TestFlight/App Store build on CloudKit **Production** — **without re-importing the
dogfood library.** This is the ops companion to
[ADR-0056](decisions/ADR-0056-move-to-production-and-data-carry.md); read the ADR first for *why* each step
is shaped this way. It absorbs and sequences the **Prod-schema promotion list** in
[`CURRENT_HANDOFF.md`](CURRENT_HANDOFF.md).

**Shared platform guidance lives up in jon-platform** — `jon-platform/docs/ios/persistence-and-sync.md`
owns the CloudSyncKit-level pieces this runbook leans on (the metadatabase coverage diagnostic, the
migration-behind-the-engine trap, the one-way Dev→Prod schema deploy, dashboard verification). This runbook
is the yes-chef-specific execution on top of it; the shared *data-carry* finding is tracked in
`jon-platform/SEAM-LEDGER.md` and lifts into that house doc once the dry run (Phase 4) proves it.

**Not a dispatch.** These are ops steps Jon runs (with the architect), each gated on the one before. The
build/schema/CloudKit actions are not Codex work; the squash's *code* (D2) is the one part that ships as a
normal reviewed slice.

**The spine (ADR-0056):** the local SQLite store carries across the update in place (same bundle id), but
the **Production private zone starts empty and may not auto-seed** (the sync metadatabase is keyed by
container id, not environment). So the **known-good re-seed is backup→restore** — restore begins as a fresh
sync peer and re-pushes the whole library as authoritative. In-place auto-seed is an optimization the dry
run may bless, never the plan's assumption.

---

## Preconditions (before anything below)

- [ ] `main` is green: package build + `check-drift` + `YesChefTests`/`YesChefCoreTests`.
- [ ] The calendar-derived cook fields have landed (ADR-0056 references), so nothing reads
      `Recipe.lastCookedAt` / `Recipe.timesCooked` — grep both symbols; only model storage + Codable remain.
- [ ] **Do not change** the bundle id (`com.jonphillips.yeschef`) or container id
      (`iCloud.com.jonphillips.yeschef`). Local-container carry depends on both being stable.
- [ ] Schedule a window with slack — the first Production sync is large and will throttle (see Phase 4).

---

## Phase 1 — DB-preserving baseline squash  *(ships as a reviewed slice; ADR-0056 D2)*

Collapse the accumulated migrations to one baseline and drop the dead cook columns, **without erasing any
existing device's data.**

- [ ] Author the squash so a device that has already applied the old migrations keeps its data and schema,
      and only a *fresh install* sees the clean baseline. **No erase-on-schema-change path** — it has wiped
      the dogfood library before ([[debug-erase-vs-sync-triggers]]).
- [ ] Omit `lastCookedAt` and `timesCooked` from the squashed `CREATE TABLE "recipes"`; remove the fields +
      CodingKeys from the `Recipe` model. Old backup JSON carrying those keys still decodes (unknown keys
      ignored) — no backup-compat migration needed.
- [ ] **Test on a byte copy of Jon's real dogfood database**, not a seeded sample store: apply the squashed
      build to the copy and confirm zero row loss, no schema drift, and a clean sync-trigger install. A
      sample-store pass does **not** count ([[squash-migrations-at-prod-baseline]], [[never-rewrite-shipped-migration]]).
- [ ] Never rewrite a migration body that already ran on a device; the squash presents a new baseline, it
      does not edit history in place.

**Gate:** the squash is proven data-preserving on a copy of the real DB. Do not proceed otherwise.

---

## Phase 2 — SyncMetadata coverage check  *(ADR-0056 D4)*

Every row that should sync must be *uploadable*; a row with no sync metadata seeds neither zone.

- [ ] For each synced table, compare row count to the count the engine will push; investigate any gap.
      Migration-inserted or pre-engine rows are the usual orphans ([[migration-writes-bypass-sync-triggers]]).
- [ ] Remediate orphans **deterministically** (deterministic-UUID, post-engine), never with a fresh-UUID
      migration write.
- [ ] Verify the **promotion list against `makeSyncEngine` in `CloudSync.swift`, in both directions** — a
      synced-table column is on the list; a column on an unregistered (local) table belongs nowhere near it.

**Gate:** coverage is clean, or the remaining gaps are understood and intentional.

---

## Phase 3 — Take the authoritative backup  *(ADR-0056 D3)*

- [ ] From the current dev-signed build, export a full backup (`VACUUM INTO` snapshot — images ride along as
      in-DB BLOBs).
- [ ] Verify the file opens and is complete (not a truncated/partial write).
- [ ] Store it off-device (Files / iCloud Drive) **and** a second location. **This file is the re-seed
      source and the rollback.** Nothing after this point is trusted until this exists.

**Gate:** a verified pre-cut backup exists in two places.

---

## Phase 4 — Deploy the Production schema, then dry-run the cut on ONE device  *(ADR-0056 D5)*

Do these in order on a **single** device. The Development environment stays live and untouched as a
fallback throughout.

**4a — Deploy schema to Production.**
- [ ] Deploy the Development schema to **Production** in the CloudKit dashboard (additive-only; **this
      permanently locks the record types** — confirm the promotion list is complete and the dropped columns
      are absent *before* deploying).

**4b — Distribution build config  (ADR-0056 D6).**
- [ ] Shipping build has dogfood scaffolding OFF: no seed-sample-data, no erase-on-schema-change, and sync
      enablement goes through the **persistent** path, not a volatile Xcode launch argument.
- [ ] Entitlements intact on **both** the app and the share extension: app-group + iCloud container.

**4c — Install over the dev build; re-seed via restore.**
- [ ] Install the distribution (TestFlight) build over the dev build on the one device. Confirm the **local
      library is intact** after the update + squash.
- [ ] Restore the Phase 3 backup on this build (restore begins as a new peer; sync stays held by
      `disableForRestore` until you enable it).
- [ ] Enable sync. The whole library re-pushes into the empty Production zone as authoritative.
- [ ] **Expect throttling.** The initial push of the full library will hit CloudKit 429s and take a while
      ([[sqlitedata-single-fk-sync-limit]]). **Do not intervene, do not wipe** — let it drain.

**4d — Confirm the zone is actually seeded (server-side, not the in-app indicator).**
- [ ] Check the **Production private zone** record counts in the CloudKit dashboard — "up to date" in-app has
      lied before, so confirm against the zone (ADR-0056 OQ3).

**4e — Confirm a fresh device pulls the full library.**
- [ ] On a **second, fresh** install of the distribution build, sign into the same iCloud account and
      confirm the entire library (recipes + images) arrives from Production.

**Gate (the real one):** 4d and 4e both pass. Only now is the cut real.

> **Optional — bless in-place carry (ADR-0056 D1 optimization).** Before the restore in 4c, you may first
> enable sync *without* restoring and observe whether the local rows upload to Production on their own
> (watch 4d). If they seed the zone cleanly, in-place carry works on this device and the restore is
> unnecessary going forward. If nothing uploads, fall back to the restore path above. Never skip the backup
> (Phase 3) to try this.

---

## Rollback

- **Before the cut is proven (through 4e):** the Development environment and its data are untouched.
  Reinstall the dev-signed build (or restore the Phase 3 backup on a dev build) to return to the working
  Development library. Nothing is lost.
- **After Production is proven but something is wrong later:** restore the pre-cut backup — restore is
  authoritative and re-establishes the library as the source of truth for iCloud and every peer
  ([[restore-is-authoritative]]). Quiesce other peers first so a held peer delete cannot re-delete a
  restored record (ADR-0030 Amd 3).

---

## Post-cut

- [ ] Keep the **Development** zone as a cold archive through at least one confirmed two-device Production
      round-trip before deciding whether to reset it (ADR-0056 OQ2).
- [ ] In `CURRENT_HANDOFF.md`, retire the **Prod-schema promotion list** section once deployed (it is a
      one-time ops step, not standing guidance) and note the cut in `DONE-LOG.md`.

---

## Condensed checklist

1. [ ] Preconditions: green main, cook columns unread, ids unchanged, window with slack.
2. [ ] Phase 1 — squash proven data-preserving **on a copy of the real DB**; cook columns dropped.
3. [ ] Phase 2 — SyncMetadata coverage clean; promotion list verified both directions vs `CloudSync.swift`.
4. [ ] Phase 3 — verified pre-cut backup in two places.
5. [ ] Phase 4a — Production schema deployed (list complete, dropped columns absent).
6. [ ] Phase 4b — distribution build: scaffolding off, entitlements intact.
7. [ ] Phase 4c — install over dev build, library intact, restore + enable sync, let throttling drain.
8. [ ] Phase 4d — Production zone seeded, **confirmed server-side**.
9. [ ] Phase 4e — fresh device pulls the full library. **← cut is real here.**
10. [ ] Post-cut — Development kept as archive; handoff/DONE-LOG updated.
