# Effort — Rebase the vendored SQLiteData onto 1.12.1

Status: Blocked on the `sqlite-data-parked-retry` device pass (the iPhone's first sync completes on the patched build)
Summary: `Vendor/sqlite-data` is upstream 1.8.2 plus our patches, four minor releases behind 1.12.1; re-vendor
1.12.1 with the same patches so we carry our changes on a current base, and lift the StructuredQueries cap.
Related: [archive/sqlite-data-reference-violation-patch.md](archive/sqlite-data-reference-violation-patch.md)
(first patch, the vendor setup) · [sqlite-data-parked-retry.md](sqlite-data-parked-retry.md) (second patch;
archived once it completes) · `Vendor/sqlite-data/YESCHEF-PATCH.md` · the monthly "SQLiteData upstream watch"
scheduled task (reports drift and exit conditions) · jon-platform `SEAM-LEDGER.md` § Patched SQLiteData

Schema-free, but **replaces the sync engine's code**: the architect escalates the PR to Jon before merge.

## Why

Every month on 1.8.2 makes the eventual return to upstream harder, and we're about to carry two patches instead
of one. Upstream since 1.8.2 (release notes, 2026-08-03 → 2026-10-09):

- **1.9.0:** new platform and StructuredQueries floors; in-memory metadatabase fix.
- **1.10.0:** `@FetchOne` observes primary-keyed records; opt-in `StrictDecoding` trait.
- **1.11.0:** `@Fetch*` state wrapped in SwiftUI `@State`; cached `@FetchAll`/`@FetchOne` statements; faster
  `String`/`Date`/`UUID` encoding and decoding; NUL-in-string fix.
- **1.11.1:** shared-database resolution fix for shared records; temporary-database cleanup; moves to
  swift-issue-reporting 2.1.
- **1.11.2:** StructuredQueries 0.38 support. **1.12.0:** user-defined collations. **1.12.1:** visionOS fix.

None of it fixes either of our patches' bugs (the watch checks that each month). Two things make 1.12 the right
base rather than a later one: the cap in `project.yml` (#407) exists only because 1.8.2 breaks on StructuredQueries
0.38, and upstream's proposed #547 fix, [#548](https://github.com/pointfreeco/sqlite-data/pull/548), is written
against 1.12.

Galavant isn't affected: it resolves upstream SQLiteData itself (pinned at 1.6.6), and `CloudSyncKit`'s ranges
(`sqlite-data` from 1.0.0, StructuredQueries from 0.31.0) admit both.

## Shape: one Yes Chef PR, commits in this order

1. **Pristine 1.12.1.** Replace `Vendor/sqlite-data/` with upstream tag 1.12.1 (commit
   `aa613accbe882b561f26e37a348a8f42e92cd398`): `Package.swift`, any `Package@swift-*.swift`, `LICENSE`, `Sources/`,
   `Tests/`; no `Examples/`. Take it from the tag, not from `~/code/sqlite-data` (Jon's fork, on another branch).
2. **The reference-violation patch, re-applied.** Same behavior as today's
   `handleSentRecordZoneChanges` patch. First read #548: if its keep-children change is equivalent for our case
   (keep a child whose parent exists locally with no server-confirmed change tag, re-queue both), port **only**
   that part, so the patch matches what upstream may merge; otherwise re-apply ours. Either way, don't port #548's
   `quotaExceeded` retry. Say which in the PR.
3. **The parked-retry patch, re-applied,** with its tests.
4. **Manifest and pins.** Drop the vendored platform-floor raise if 1.12.1's own floors already cover it (it
   declares iOS 16 / macOS 13; the raise was for StructuredQueries 0.35's iOS 17 `octetLength()`, so check before
   dropping). Lift the StructuredQueries cap in `project.yml` to 1.12.1's floor (0.39.1) and remove its comment.
   Re-resolve and commit the app's `Package.resolved`.
5. **`YESCHEF-PATCH.md`:** the new base tag and commit, both patches, their upstream links, and the exit
   conditions.

Don't edit `YesChefPackage/Package.swift` or jon-platform's `CloudSyncKit/Package.swift`, as with the first patch.
If resolution can't be satisfied without editing either, stop and ask.

## Risks to check, not assume

- **IssueReporting identity.** 1.11.1 moves SQLiteData from `xctest-dynamic-overlay` to `swift-issue-reporting`.
  Yes Chef has hit duplicate-IssueReporting link failures before (the app `Package.resolved` drift, fixed by #407).
  The resolved set must contain the IssueReporting module once. `YesChefTests` is the check: it's where the
  duplicate showed up.
- **Stored values.** 1.11.0 changed `String`/`Date`/`UUID` encoding and decoding. On-disk values and the values
  sent to CloudKit must not change form. A backup exported from the current build restores under the new one,
  and its dates, UUIDs and strings compare equal after the round trip; add that as a test against a fixture
  made by the current build if no existing test covers it.
- **`@Fetch*` behavior.** 1.11.0 wraps `@Fetch*` state in SwiftUI `@State` and caches statements. Yes Chef moved
  whole-library reads off `@Fetch` (the writer-convoy fix), so the exposure should be small; the device pass
  covers it.
- **Don't enable new traits** (`StrictDecoding`, `ColumnCoding`). This is a rebase, not an adoption.

## Not in this effort

- **Galavant's SQLiteData version.** Its own effort, in its own repo, once this has run on Yes Chef's devices.
- **Moving the vendor copy into jon-platform** so both apps share it: the `SEAM-LEDGER.md` row's trigger decides
  that.
- **Upstreaming.** The architect files and tracks the issues; `YESCHEF-PATCH.md` links them.

## Done when

- Commits 1–5 as above, with the pristine import on its own so each patch reads as one diff.
- `swift test --package-path Vendor/sqlite-data` passes in full, including both patches' tests.
- The stored-values round-trip check passes.
- `scripts/check-drift.sh`, the generic iOS build, and `YesChefTests` pass, and the app's `Package.resolved` has
  one IssueReporting provider and no `sqlite-data` pin.
- The completing PR appends this gate to `device-passes.md`:
  > **SQLiteData 1.12.1 rebase** ([effort brief](efforts/archive/sqlite-data-vendor-rebase.md), schema-free).
  > On the first TestFlight build with it, on both devices, installed as an update: the library opens with
  > counts unchanged; an edit on each device arrives on the other; Power Browser, the recipe list and the
  > calendar update when rows change; export a backup and restore it on Yes Chef Dev.
- Closeout per ADR-0005 D16, advancing `NEXT_UP.md` per ADR-0005 D12.

## Verification

- `scripts/quiet-run swift test --package-path Vendor/sqlite-data` (if the CloudKit tests can't run on macOS,
  `xcodebuild test` on an iOS simulator, and say so).
- `scripts/check-drift.sh`, the generic iOS build, `YesChefTests`.
- No simulator installs or screenshots. **Fail fast:** if a build or package resolution fails, paste the error
  and stop; don't retry with variations.
