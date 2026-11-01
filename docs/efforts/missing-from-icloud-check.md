# Effort — Find rows this device thinks are in iCloud but aren't

Status: Designed
Summary: The 24 `recipeSources` from PROD-CUTOVER Step 11 sat behind a green Sync status: the iPad treated them as
uploaded, and Production didn't have them. Extend the on-demand "Check iCloud for leftovers" pass so it also lists
local rows missing from the server, with an **Upload again** action.

Schema-free. Changes CloudSyncKit (jon-platform), which Galavant also uses, so the PRs are escalated to Jon.
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Step 11 (the 24 rows) · jon-platform
`Packages/CloudSyncKit/Sources/CloudSyncKit/CloudSyncLeftoverCheck.swift` (`leftoverCheck`,
`CloudKitLeftoverClient.recordHeaders`) and `SyncFailureReport.swift` (`requeue`) · jon-platform
`docs/ios/persistence-and-sync.md` § SQLiteData fails silently ·
[archive/sync-failure-surfacing.md](archive/sync-failure-surfacing.md)

## Why

**What happened.** After the iPhone's first sync, every table matched the iPad's except `recipeSources`, which was
24 short. All 24 were old rows, present on the iPad since the Step 4 backup. The iPad's Sync screen listed nothing
as not uploaded. Comparing record IDs between the two devices' backups was the only way to find them. Re-saving
each recipe on the iPad put them back. Why they never landed is unknown. Their recipes, alphabetically, form an
unbroken run, which suggests one upload batch.

**Why the status can't see this.** The not-uploaded report (sync-failure surfacing) works from local metadata.
It flags rows with no server change tag, or an edit newer than the cached server record. These 24 rows had a
change tag, so locally they looked confirmed. Whatever happened afterwards, the server didn't have them. Only
asking the server finds that.

**The server listing already exists.** `leftoverCheck` lists every record in the zone with
`recordHeaders(in:)`: a keys-only `recordZoneChanges` from no change token. It uses that listing to find the
opposite case, records in iCloud with no local row. The same listing answers this question for free.

## Design

### CloudSyncKit (jon-platform)

- **The same pass, both directions.** `leftoverCheck` keeps its idle guard (engine running, nothing pending,
  nothing sending) and its one listing. It now also returns **missing rows**: for each table in `SyncedTables`,
  local rows whose metadata has a server change tag and isn't `_isDeleted`, whose record ID is absent from the
  listing, and whose `userModificationTime` is earlier than `fetchStartedAt`. That last condition skips rows edited
  during the check.
  - Rows with **no** change tag are left out: the not-uploaded report already covers them.
  - The result type grows a `missing` list (record type, primary key) and per-table counts, beside `leftovers`.
- **No second fetch.** Unlike leftovers, missing rows need nothing more from the server: their absence from the
  listing is the finding.
- **Repair: `reuploadMissing`.** It touches each listed row's metadata, using the same touch `requeue` already uses
  for rows with a change tag (persistence-and-sync § SQLiteData fails silently). That queues a save of the cached
  record, the server answers `unknownItem`, and the engine clears the cached record and saves it as new. That's the
  path the 24 rows took on 2026-11-01.
  - `requeue` can't be reused as it is, because its classifier skips rows it considers confirmed. Share its touch
    helper instead.
  - Like `deleteLeftovers`, it acts only on the rows the caller passes in.
- **Parents first.** Sort the touched rows so a parent table's rows queue before its children's, using the
  foreign keys SQLiteData already reads. A child that reaches the server before its parent fails with `referenceViolation`.

### Yes Chef

- In Settings → Sync, **Check iCloud for leftovers** becomes **Check iCloud**, and its result has two parts:
  - the existing leftovers review, unchanged;
  - "**N records on this device are missing from iCloud**", grouped by table, with **Upload again**.
- **Upload again** needs no confirmation. Unlike deleting leftovers, it can't lose data: it only sends this device's
  rows.

## Open questions

- **OQ1 — On demand only, or also automatically after a first sync completes?** The listing is keys-only but
  covers the whole zone, about 50,000 records for Yes Chef. *Recommendation:* on demand only. It's the
  conservative choice, and the sync activity log already shows when a first sync ends.
- **OQ2 — Should the status row turn yellow when the last check found missing rows?** *Recommendation:* yes,
  until **Upload again** finishes. A green row with known missing data is the failure this effort exists to fix.

## Not in scope

- **Why the 24 rows never landed.** If this check finds missing rows again, that's the moment to collect the
  device's metadatabase. Backups don't include it.
- **Comparing devices with each other.** The server is the reference: each device checks itself against it.

## Done when

- **CloudSyncKit tests,** using the fake leftover client. Cover:
  - a confirmed row missing from the listing is reported;
  - a row present in the listing isn't;
  - a row with no change tag isn't;
  - a row edited after `fetchStartedAt` isn't;
  - a deleted row isn't;
  - `reuploadMissing` touches exactly the rows passed in, parents first;
  - the idle guard returns `.notIdle` before listing anything.
- **Yes Chef:** `YesChefTests` cover the Sync detail model presenting missing rows and calling the repair.
  Verification per [`verification.md`](../verification.md).
- **Galavant:** builds against the changed CloudSyncKit, with no behavior change until it adopts the UI.
- **Device pass (Jon):** on the iPad, **Check iCloud** reports 0 missing.
