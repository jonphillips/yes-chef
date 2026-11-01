# Effort — `testflight` refuses a build whose synced fields Production lacks

Status: Ready
Summary: `testflight` checks that Development and Production match, but not that the app's schema is in either one.
Commit the list of CloudKit fields the app writes, keep it current with a Core test, and have `testflight` refuse
to upload when Production is missing any of them.

Schema-free. No app behavior change. Two PRs, jon-platform first, the same shape as
[archive/testflight-app-groups.md](archive/testflight-app-groups.md).
Related: [`PROD-CUTOVER.md`](../PROD-CUTOVER.md) Step 13 (the schema-deploy rule) and Reference A (the manual
diff this automates) · jon-platform `scripts/testflight` (`schema_gate`) and `docs/ios/testflight.md` ·
`YesChefPackage/Tests/YesChefCoreTests/SchemaColumnTests.swift` ·
[ADR-0059 Amendment 2](../decisions/ADR-0059-yes-chef-dev-variant.md) (Development is kept)

## Why

`testflight`'s schema gate exports the Development and Production schemas and refuses to continue if they differ.
It has no bypass. That catches a field someone created in Development and forgot to deploy.

It doesn't catch a field nobody created. Development only gets a field when a record with a value in it is
uploaded there, or when someone adds it in the console. Suppose a slice adds a synced column and nobody does
either. Development and Production both lack the field, so they match, and the gate passes. The build ships, and
every upload of that record type fails in Production. The Sync screen only shows it later, as rows not uploaded.

So far the defense is a habit: the manual Reference A diff, and the Step 13 rule that "`testflight` enforces
this". `testflight` doesn't enforce that part.

**Baseline (2026-11-01).** The architect checked the app schema in the iPhone's 2026-11-01 TestFlight backup against a Production export,
using the rules below. All 34 synced tables were present, with every expected field. So the gate starts green,
and the rules don't produce false alarms against today's Production.

## Design

### The expected-fields file (Yes Chef)

`cloudkit-expected-fields.txt` at the repo root, committed. It has one line per field, `<recordType> <field>`,
sorted, with nothing else in it. For each table in `YesChefCloudSync.syncedTables.recordTypes`, on a fully
migrated database, it lists:

- each column (`pragma_table_info`);
- `sqlitedata_icloud_userModificationTime`, once per record type;
- `sqlitedata_icloud_userModificationTime_<column>` for each column;
- `<column>_hash` for each `BLOB` column (SQLiteData stores those as assets).

These are Reference A's rules. The baseline check above used them.

Fields only, not CloudKit types. Mapping SQLite types onto CloudKit types isn't one-to-one: dates are stored as
`TEXT` and become `TIMESTAMP`, and a `BLOB` becomes an `ASSET`. A missing field is the failure that actually
happens, so presence is what's worth gating.

Committing the file has a side benefit: every synced-schema change now shows up as a diff line in its PR, so
review sees it.

### The Core test that keeps it current

Add `CloudKitExpectedFieldsTests` in `YesChefCoreTests`. Build the list from a migrated path-backed database, the
same way `SchemaColumnTests` does, and compare it with the committed file, found from `#filePath`.

- If they differ, fail with the added and removed lines, plus how to regenerate: run the test with
  `YESCHEF_RECORD_CLOUDKIT_FIELDS=1`, which writes the file and then fails once so the run isn't mistaken for a
  pass.
- `scripts/check-drift.sh` already runs the Core tests, so a stale file fails verification. Nothing new is needed
  there.

### The gate (jon-platform `scripts/testflight`)

- **Config.** Add an optional `EXPECTED_SCHEMA_FIELDS` key: a path relative to the repo root. If it's empty, the
  check is skipped, so Galavant is unaffected until it opts in. If it's set and the file is missing or empty, exit
  10.
- **Check.** In `schema_gate`, after the Development-vs-Production comparison passes, parse the Production export
  that's already downloaded into `<recordType> <field>` lines.
  - The cktool format is `RECORD TYPE <name> (`, then one field per line (`<field>  [ENCRYPTED] <TYPE>,` or a
    quoted name), then `)`.
  - Skip the `___` system fields.
  - Compare with the expected file using `comm -23`.
- **Failure.** Any line left over means Production lacks a field this build writes. Exit 11 and list every missing
  `<recordType> <field>`, grouped by record type, followed by:
  `Create these in the CloudKit Console (Development), deploy Development → Production, then re-run.`
  A whole record type that's missing fails the same way. There's no bypass, like the existing gate.
- **No extra exports.** Reuse the Production export `schema_gate` already downloads. Don't fetch another.
- **`--dry-run`** runs this check too, because it runs `schema_gate`.

## PR 1 — jon-platform

- `scripts/testflight`: the config key, the parser and the check, as above.
- `scripts/test-testflight`: use the real cktool export format in the fixtures. Cover:
  - every expected field present passes;
  - a missing field fails with exit 11 and names the type and field;
  - a missing record type fails;
  - `___` fields and quoted names parse correctly;
  - with the key unset, the check is skipped;
  - with the key set and the file missing, exit 10.
- `docs/ios/testflight.md`: a row for the key in the config table and a row for the new failure in the
  troubleshooting table.
- `SEAM-LEDGER.md`: append a row for the code-vs-CloudKit schema gate. Yes Chef is the one consumer, and
  Galavant's trigger is its next schema change. Append only; don't design it there.

## PR 2 — Yes Chef (after PR 1 merges)

- `cloudkit-expected-fields.txt`, generated by the new test, plus `CloudKitExpectedFieldsTests`.
- `testflight.conf`: `EXPECTED_SCHEMA_FIELDS=cloudkit-expected-fields.txt`.
- `docs/PROD-CUTOVER.md` Step 13: reword the schema-deploy rule. `testflight` now refuses both an undeployed
  Development change and a field missing from both environments. Reference A's manual diff is now only for
  reviewing dead fields before a deploy.
- Closeout per ADR-0005 D16.

## Not in scope

- **Checking CloudKit field types.** See above.
- **Flagging dead fields in Production.** A deploy can't remove a field, so failing on one would block every
  build forever. Reference A covers reviewing dead fields before a deploy.
- **Creating fields automatically.** `cktool` can import a schema into Development. Creating fields stays a
  deliberate console step, because a deploy is permanent.

## Done when

- **PR 1:** `scripts/test-testflight` passes with the new cases, and the existing schema-parity cases still pass.
- **PR 2:** `CloudKitExpectedFieldsTests` passes against the committed file. Running it with
  `YESCHEF_RECORD_CLOUDKIT_FIELDS=1` on a clean tree produces no diff. Deleting a line from the file makes the
  test fail with that line named.
- **Verification** per [`verification.md`](../verification.md): `scripts/check-drift.sh`. No simulator run is
  needed, since there's no app-target change.
- **Jon's check (added to `device-passes.md` by PR 2):** run `testflight --dry-run` from a clean `main`. The
  schema gate passes, and its output shows the expected-fields check ran. The executor can't reach CloudKit.
