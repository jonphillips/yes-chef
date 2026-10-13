# ADR-0059 — Yes Chef Dev: after the cut, Debug builds get their own app identity, and backups say which build made them

> **One-line:** After the ADR-0056 cutover, Xcode Run builds **Yes Chef Dev**. It has its own bundle IDs,
> app group, URL scheme, name and icon, so it can sit next to TestFlight Yes Chef on the same device. It
> shares the CloudKit container, which puts it on Development. This is Galavant's ADR-0050
> (`galavant/docs/decisions/0050-galavant-dev-variant.md`) ported, with three
> Yes Chef differences: **the split comes after the cut, not before** (D1); **Yes Chef Dev stays out of
> the Cockpit pair** (D5); and it **answers Galavant ADR-0050 OQ2**: backups record which build exported
> them, and the production app refuses a development backup (D6).

Status: **Proposed** — 2026-10-10. Origin: Jon, asking for Galavant's Dev/Prod split before Yes Chef moves to
production, with Galavant ADR-0050 OQ2 to be dealt with. Builds on
[ADR-0056](ADR-0056-move-to-production-and-data-carry.md) (the cutover),
[ADR-0030](ADR-0030-local-backup-and-restore.md) (backup and restore; Amd 2, *restore is authoritative*, is
why D6 exists) and [ADR-0058](ADR-0058-cockpit-find-referral-transport.md) (the Cockpit pair D5 keeps Dev
out of). The backup code is jon-platform `CloudSyncKit` (jon-platform ADR-0006). Effort:
[`efforts/yes-chef-dev-variant.md`](../efforts/yes-chef-dev-variant.md).

## Context

ADR-0056 moves Jon's iPhone and iPad to the TestFlight build on CloudKit **Production**. From then on, an
Xcode Run makes a development-signed build with the **same** bundle ID and app group, and that build talks
to CloudKit **Development**. Installing one over TestFlight puts the real local store behind the other
environment. The sync metadatabase is keyed by container, not environment, so its bookkeeping goes wrong
in exactly the way ADR-0056 exists to avoid. Galavant hit this on 2026-10-08 and fixed it with a
Debug-only app identity (Galavant ADR-0050, built in galavant#171).

Yes Chef needs the same fix, and needs it soon after the cut: every post-cut slice that adds a synced
column (ADR-0057's `Recipe.kind` and `RecipeComponentLink` are first in line) has to push that column from
a development build to the Development schema before the Production deploy. Only the simulator can do that
safely today, and the simulator has no Apple Intelligence.

Yes Chef is not Galavant in three ways:

1. **It hasn't cut over yet.** Galavant split after its cut. The SEAM-LEDGER row recorded "adopt before Yes
   Chef's main devices move to TestFlight". D1 reverses that.
2. **It's half of the Cockpit pair.** ADR-0058 gives it a `yeschef://find-referral` door and a second app
   group, `group.com.jonphillips.cockpit-yeschef`. Two installed apps that both claim `yeschef` would let
   iOS pick either one.
3. **Galavant ADR-0050 left OQ2 for Yes Chef** ("refuse cross-environment restores outright?"). Read
   literally, a refusal would block Yes Chef's own cutover, because ADR-0056 D1 re-seeds Production by
   restoring a backup *exported from a development-signed build* into the TestFlight build.

## Decision

**D1 — Cutover first, split second.** The split is dispatched once ADR-0056 Phase 4e passes (the cut is
real), not before. Three reasons, the first decisive:

- **Before the cut, the Development zone is the real library.** A Yes Chef Dev with sync on would be a third
  peer writing test data into the library that becomes the Phase 3 backup and then the Production seed.
- **The existing install still needs development builds before the cut.** The Phase 1 device pass is
  owed, and Phase 2's orphan remediation may be code. Once Debug builds `….dev`, Xcode Run can no longer
  reach `com.jonphillips.yeschef`.
- **The one legitimate cross-environment restore happens at the cut.** That's ADR-0056's re-seed. With it
  behind us, D6 doesn't have to work around it (it stays safe anyway; see D6).

*Cost:* between Phase 4e and this split merging, **nothing gets an Xcode Run onto a device that has
TestFlight Yes Chef.** Use the simulator only. Galavant lived with the same window for two days.
`PROD-CUTOVER.md` says so at Phase 4c and Post-cut.

**D2 — The Debug configuration builds "Yes Chef Dev". Release builds don't change.**

| | Release (TestFlight) | Debug (Yes Chef Dev) |
| --- | --- | --- |
| App bundle ID | `com.jonphillips.yeschef` | `com.jonphillips.yeschef.dev` |
| Share extension | `com.jonphillips.yeschef.share-extension` | `com.jonphillips.yeschef.dev.share-extension` |
| App group | `group.com.jonphillips.yeschef` | `group.com.jonphillips.yeschef.dev` |
| Cockpit pair group | `group.com.jonphillips.cockpit-yeschef` | **none** (D5) |
| URL scheme | `yeschef` | `yeschef-dev` (D5) |
| iCloud container | `iCloud.com.jonphillips.yeschef` | **same** (D4) |
| CloudKit environment | Production | Development (development signing selects it) |
| Display name | Yes Chef · share sheet: Save to Yes Chef | Yes Chef Dev · Save to Yes Chef Dev |
| Icon | `AppIcon` | `AppIcon-Dev` (same art, orange DEV banner) |
| Backups | "Yes Chef", `YesChef-Backup-…`, marked production | "Yes Chef Dev", `YesChef-Dev-Backup-…`, marked development (D6) |

The exported UTIs (`…database-backup`, `…menu-recipe`) are **identical in both** builds. A backup has to
open in either app, because D6 lets Yes Chef Dev restore a production backup.

**D3 — The app group isolates the data, so it must differ, and it is read, never defaulted.** The SQLite
store, the metadatabase beside it and the share extension's handoff all live in the app group. The group
reaches runtime through an `Info.plist` key (`YesChefAppGroupID`) set from a build setting. **A missing or
empty key fails loudly; nothing falls back to `group.com.jonphillips.yeschef`.** A Debug build that fell
back would silently share TestFlight's store, which is the collision this ADR prevents. The cross-process
change beacon's Darwin name is derived from the group too. Otherwise the two apps on one device would
trigger each other's reloads. Release's derived name is the exact string used today.

**D4 — The container stays the same, and Release identity is frozen.** Yes Chef Dev writes the
*Development* environment of the real container, and that schema is the one that deploys to Production. A
`….dev` container would have a schema that could never be deployed. No Release identifier changes, so
ADR-0056's precondition and failure-list item 4 ("do not change the bundle id or container id") still hold.
They are about the identity the library carries across, and that identity is Release.

**D5 — Yes Chef Dev is outside the Cockpit pair.** ADR-0058's mailbox is a frozen contract between two
specific apps. If both Yes Chef apps registered `yeschef`, a Cockpit referral could open Yes Chef Dev, which
has no mailbox access, and the referral would be lost. So Debug registers `yeschef-dev`, which nothing
opens, and doesn't carry the Cockpit group entitlement. The Find code paths don't change: they still name
the literal Cockpit group and `yeschef` scheme, and in Debug they are simply never reached. Cockpit
handoff testing happens on TestFlight Yes Chef, which is where ADR-0058's device pass is owed anyway. If
someone later wants to test Cockpit against Yes Chef Dev, that is a Cockpit-side change and reopens this
decision.

**D6 — Answers Galavant ADR-0050 OQ2: backups record which build exported them. The production app refuses
a development backup. Everything else is accepted.**

| Backup ↓ / restoring app → | Production (TestFlight) | Development (Yes Chef Dev) |
| --- | --- | --- |
| Marked **development** | **Refused**, with a clear message | Accepted |
| Marked **production** | Accepted | Accepted |
| **Unmarked** (every backup made before this ships) | Accepted | Accepted |

- **The hazard runs one way.** Restore is authoritative (ADR-0030 Amd 2). A development backup restored
  into TestFlight Yes Chef pushes test data over the real library on every peer. The pre-restore snapshot
  can undo that, but only with another authoritative restore. Going the other way is useful: restoring the
  real library into Yes Chef Dev lets Jon reproduce a bug against real data, and it touches only the
  Development zone.
- **Unmarked backups must stay accepted.** ADR-0056's Phase 3 pre-cut backup is unmarked, and it is the
  post-cut rollback. Refusing unmarked backups would brick the rollback and every older backup.
- **The marker is the build variant, not the CloudKit environment.** No supported runtime API reports the
  environment. It follows the signing, with no entitlement to pin it. After D2 the variant and the
  environment correspond one to one, so the variant is the honest proxy. It comes from the Debug/Release
  configuration (`#if DEBUG`, as Galavant does for its backup naming).
- **Mechanism: CloudSyncKit, additive.** `DatabaseBackupConfiguration` gains an optional variant. `nil`
  keeps today's behavior, so Galavant builds unchanged. Export stamps the variant into the snapshot's SQLite
  header (`PRAGMA application_id`) next to the existing `user_version` stamp. Restore reads it before the
  confirm alert and clears it on the store it installs, so the marker only ever means "exported by". The
  shapes are in the effort.
- **Galavant adopts on its own schedule.** It passes its variant and closes its OQ2 by pointing here. That's
  a one-line Galavant change and isn't part of this dispatch.

## Consequences

- **Device roles.** TestFlight Yes Chef is for real use and every device pass. Yes Chef Dev is for the schema
  loop, on-device model checks (Apple Intelligence, which the simulator lacks) and pre-release checks.
- **Yes Chef Dev starts empty.** With sync on, it downloads the Development zone, which holds the pre-cut
  library: about 44k rows, with the throttled first sync M4 measured. Its edits land in that archive. That's
  acceptable because the rollback is the Phase 3 backup *file*, not the zone. See OQ1.
- **Device-local state starts fresh** in Yes Chef Dev: BYO-key API keys (separate Keychain), sync
  enablement, settings. That's expected, and it's useful.
- **Shortcuts lists both apps' App Intents.** Each app's intents write into its own store.
- **Tooling follows the identity.** `check-drift.sh`'s bundle-ID allowlist gains the two `.dev` IDs.
  `facet-taxonomy-report.sh` resolves the Debug (simulator) identity by default.
- **Portal work:** Jon has registered the `.dev` App IDs and app group. The iCloud container must be
  assigned to both `.dev` App IDs. The Cockpit group must **not** be assigned to them (D5).
- **Seam ledger:** Yes Chef is the second adopter, so the "Post-cutover dev variant" row's harvest trigger
  has fired (per-configuration XcodeGen, entitlements and `Info.plist` key, written into `docs/ios/`). The
  dispatch updates the row. The harvest itself is separate jon-platform docs work.

## Open questions

- **OQ1 — When to reset the Development environment.** This is ADR-0056 OQ2, sharpened. Keep Development
  as the cold archive until a two-device Production round trip is confirmed. *Recommendation:* reset it at
  that point, **before** turning sync on in Yes Chef Dev for the first time. Yes Chef Dev then starts light,
  and its experiments never touch the archive. The reset also returns the Development schema to
  Production's, which is harmless because deploys only add. If the schema loop needs Yes Chef Dev syncing
  before the gate, accept the throttled download.
