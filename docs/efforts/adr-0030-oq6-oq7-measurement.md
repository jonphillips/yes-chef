# ADR-0030 OQ6 + OQ7 — the measurement that gates the real-device restore pass

> **One-line:** Two open questions, one experiment, on two simulators that are already standing in an
> isolated CloudKit container. **OQ6:** after a restore converges, the peer that performed the original
> delete keeps `_isDeleted = 1` on rows that are alive again — can a later re-push act on those flags and
> silently re-delete restored data? **OQ7:** every image BLOB syncs as a CKAsset, and
> [ADR-0030](../decisions/ADR-0030-local-backup-and-restore.md) Amendment 2 means a restore re-pushes
> *every* row — do images survive that, on **both** devices?

Status: **open, architect-owned.** Written 2026-07-29 so a cold session can run it without the originating
conversation. Spec: ADR-0030 Amendments 1–2, OQ6, OQ7.

## The one rule for this work

**Measurement first. A code reading may *explain* a measured result here; it must never predict one.**
Reading SQLiteData's `CloudKit/SyncEngine.swift` produced two confident, wrong answers about restore↔cloud
semantics — ADR-0030 D2's original "never risks a restore stomping the cloud," and the withdrawn Amendment 1's
exact inverse. Both were careful readings of the right code path. The measured answer (Amendment 2) is the
opposite of the second and closed OQ1. Do not re-derive it.

**Never run any of this against the live zone.** A restore re-pushes the whole library; on the real library
that is ~44k records **plus every image asset**, with no undo for the cloud half, and it resurrects rows
deleted since the backup. The isolated container is the entire reason being wrong has been cheap so far.

## The rig

Two booted simulators, fresh Apple ID, container `iCloud.com.jonphillips.yescheftest`:

| Role | Device | App-group container |
| --- | --- | --- |
| **A** — gets restored | iPhone 17 – Dad `428115C8-3AB5-49B3-9FFA-3A789D5077FF` | `8EF5C725-05C1-42CC-8A17-E64EF4920EA1` |
| **B** — authoritative peer, holds the tombstones | iPad Air – Dad `C770DA07-B2EC-4146-85BD-E08B5AC968DE` | `7F9DC57A-61F3-46F6-9A57-0ACFF33FE78B` |

Each holds `SQLiteData.db` and `.SQLiteData.metadata-iCloud.com.jonphillips.yescheftest.sqlite`.
**Read them `-readonly`; never write to them outside the designed steps.** A third sim
(`11F8A1E5-…`) holds the *real* library on the real container — **off limits.**

Two standing simulator facts: sims get **no CloudKit pushes**, and the app's foreground hook is upload-only
(`redrainPendingRecordZoneChangesIfManuallyEnabled` early-returns when nothing is pending), so **a cold launch
is the only fetch trigger** — force-quit and relaunch wherever a step says "let it sync." Launching needs
signing left **on** (`CODE_SIGNING_ALLOWED=NO` strips the app-group entitlement and the app dies instantly),
per [[simulator-run-needs-signing]].

**Temporary and not to be committed:** the test container is swapped into `YesChefCloudSync.configuration`
and **both** `YesChefApp/YesChef.entitlements` and `YesChefShareExtension/YesChefShareExtension.entitlements`.
The extension constructs an engine too, so a missing container entitlement **crashes** it
([[extension-sync-construct-not-run]]). Revert all three before any real build.

## The status script

Save as `yc-sync-status.sh`, `chmod +x`. Read-only. Run it at every checkpoint.

```bash
#!/bin/bash
CONTAINER="iCloud.com.jonphillips.yescheftest"
A="/Users/jon/Library/Developer/CoreSimulator/Devices/428115C8-3AB5-49B3-9FFA-3A789D5077FF/data/Containers/Shared/AppGroup/8EF5C725-05C1-42CC-8A17-E64EF4920EA1"
B="/Users/jon/Library/Developer/CoreSimulator/Devices/C770DA07-B2EC-4146-85BD-E08B5AC968DE/data/Containers/Shared/AppGroup/7F9DC57A-61F3-46F6-9A57-0ACFF33FE78B"
q() { sqlite3 -readonly "$1" "$2" 2>/dev/null || echo "?"; }

for entry in "A|iPhone 17|$A" "B|iPad Air |$B"; do
  IFS='|' read -r tag name dir <<< "$entry"
  db="$dir/SQLiteData.db"; md="$dir/.SQLiteData.metadata-$CONTAINER.sqlite"
  echo "════ Sim $tag ($name) ════"
  [ -f "$db" ] || { echo "  no store file"; continue; }
  echo "  recipes:"
  q "$db" "SELECT '    '||substr(id,1,8)||'  '||title FROM recipes ORDER BY title;"
  # Image fingerprint: length + first 16 bytes. Detects a different image, an empty
  # asset, or a truncated BLOB — the OQ7 failure modes — without dumping megabytes.
  echo "  photos (id / recipe / displayLen / thumbLen / first16):"
  q "$db" "SELECT '    '||substr(id,1,8)||'  '||substr(recipeID,1,8)||'  '||
             COALESCE(length(displayData),-1)||'  '||COALESCE(length(thumbnailData),-1)||'  '||
             COALESCE(hex(substr(displayData,1,16)),'NULL')
           FROM recipePhotos ORDER BY id;"
  echo "    (count: $(q "$db" 'SELECT count(*) FROM recipePhotos;'))"
  if [ ! -f "$md" ]; then
    echo "  metadatabase: ABSENT — fresh peer (or just restored)"
  else
    echo "  metadatabase:"
    echo "    recordTypes ........... $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_recordTypes;')   <- 0 => every table looks new => full re-push on start()"
    echo "    metadata rows ......... $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_metadata;')"
    echo "    with server record .... $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_metadata WHERE lastKnownServerRecord IS NOT NULL;')"
    echo "    with ALL-FIELDS base .. $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_metadata WHERE _lastKnownServerRecordAllFields IS NOT NULL;')"
    echo "    marked deleted ........ $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_metadata WHERE _isDeleted = 1;')   <- OQ6 lives here"
    echo "    pending zone changes .. $(q "$md" 'SELECT count(*) FROM sqlitedata_icloud_pendingRecordZoneChanges;')"
    echo "    tombstoned records:"
    q "$md" "SELECT '      '||recordType||'  '||substr(recordPrimaryKey,1,8)||'  serverRec='||(lastKnownServerRecord IS NOT NULL) FROM sqlitedata_icloud_metadata WHERE _isDeleted=1;"
  fi
  echo
done
echo "pre-restore / staging files in Sim A:"
ls -1 "$A/Pre-Restore Backups" 2>/dev/null | sed 's/^/    /' || echo "    (none)"
```

## Experiment 1 — OQ7, images through the re-push

The sharp version mirrors the text conflict that produced Amendment 2: make the backup and the cloud hold
**different images for the same recipe**, then see which survives — and critically, whether **B** ends up with
intact bytes.

1. **Sim A** — attach photo **P1** to a recipe. Relaunch both; confirm the script shows the same
   `displayLen`/`first16` on A and B. *This is the control: normal image sync works.*
2. **Sim A** — Settings → Import & Export → **Export a Backup** (save inside the sim). The backup now freezes
   P1. Verify with:
   `sqlite3 -readonly "<backup>.sqlite" "SELECT length(displayData), hex(substr(displayData,1,16)) FROM recipePhotos;"`
3. **Sim B** — replace that recipe's photo with a **visibly different** image **P2**. Relaunch both; confirm A
   shows P2's fingerprint. The backup is now stale *in its image bytes*.
4. **Sim B** — also **delete** a photo from a second recipe (leave the recipe). Tests asset-level
   resurrection separately from record-level.
5. **Sim A** — **Restore from a Backup**, confirm, relaunch. Run the script. Expect A to show **P1** again and
   the deleted photo back, `recordTypes` **0**, all-fields baselines **0**. ⛔ **Stop here** — last reversible
   moment.
6. **Sim A** — turn iCloud sync back on, confirm the "Turn On iCloud Sync?" dialog. No relaunch.
7. Relaunch **Sim B**. Run the script.

**Read the result.** Amendment 2 predicts the restored library wins, so:

| Observation | Meaning |
| --- | --- |
| A **and B** both show P1's `displayLen` + `first16` | ✅ images survive the re-push; OQ7 closes clean |
| A shows P1, **B shows `displayLen = -1`, `0`, or a different `first16`** | ⚠️ **the asymmetric failure** — asset push mangled or emptied; local fine, peer broken. This is the one to hunt for |
| A reverts to P2 | CKAsset collisions resolve *unlike* scalar fields — Amendment 2 is field-type-dependent, which is a new finding |
| deleted photo reappears on both | asset-level resurrection confirmed, consistent with Amendment 2 |

**What this cannot answer:** volume. One asset says nothing about ~2,163 recipes of assets re-uploading at
once (the CKError 429 shape of 2026-07-10). That stays a real-device unknown and belongs in the device pass,
not here.

## Experiment 2 — OQ6, the tombstone contradiction

Sim B currently holds `_isDeleted = 1` for six records that are alive locally and carry a
`lastKnownServerRecord` (`recipes/63a6f904` + five children). The question is whether those flags are inert
bookkeeping or a live re-deletion path.

**Force a full re-push on B — the peer holding the tombstones — and see whether the rows die.** The cheapest
trigger is the one already understood: a restore empties `sqlitedata_icloud_recordTypes`, so `start()` treats
every table as new and re-pushes everything. So: export a backup **from B**, restore it **on B**, re-enable
sync, then check both sims for the six records.

- **Rows survive on both, tombstones cleared** → inert bookkeeping; OQ6 downgrades to a cosmetic note.
- **Rows disappear anywhere** → confirmed data-loss path. Capture which side lost them and whether the delete
  originated from B's stale flags.

Only after a measured result: read `SyncEngine.swift` to *explain* it — every path that reads `_isDeleted`,
and whether `upsertFromServerRecord` should be clearing it when it writes a record back and sets
`lastKnownServerRecord` (the reset looks simply absent). Then decide **ours vs upstream**: we do not own that
file, and if it is upstream the deliverable is a bug report to pointfree, not a patch. Any fix of ours must not
write to synced tables from a migrator ([[migration-writes-bypass-sync-triggers]]).

## Exit criteria

Both experiments produce a written result in ADR-0030 (OQ6/OQ7 closed or converted to defects), and only then
does the **real-device** restore pass get unblocked — because a restore on real devices now rewrites the live
zone and every peer by design.
