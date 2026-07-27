# Effort: The app test target runs — and 14 of its 26 tests fail

**Type:** Test-coverage recovery. The target itself is **fixed and wired in**; what remains is
adjudicating the assertions that drifted while nothing executed them.
**Status:** **Re-scoped 2026-07-27** after the target was fixed. Supersedes the 2026-07-26 version,
whose central claim ("the target is broken and fixing it is not this effort") turned out to be wrong.
**Summary:** `YesChefAppTests` now compiles, links, and runs: **26 tests, 12 pass, 14 fail.** The
build-and-link half is a hard gate in `scripts/check-drift.sh` as of this change. The 14 failures are
the accumulated interest on months of silence, and each is a real question about which side — test or
product — is wrong.
**Related:** `CURRENT_HANDOFF` § Verification Pattern; [[lean-verification-default]].
**Owner:** Claude (diagnosis + target fix, done) · Jon (**the 14 decisions below**) · Codex (whatever
those decisions turn into).

---

## What was actually wrong (the stale diagnosis, corrected)

The previous version of this doc recorded the failure as:

```
CloudSyncKitdynamic-product: ld: warning: Could not parse or use implicit file '…/SwiftUICore.tbd':
  cannot link directly with 'SwiftUICore' because product being built is not an allowed client of it
```

and concluded that a dynamic library pulling SwiftUI transitively hits Apple's restricted-client list,
that the fix was a linkage change to a shared package, and that it was not worth it.

**That line is a `warning`.** It still appears, in builds that now succeed. It was never the error.
The error, four lines below it, was:

```
Undefined symbols for architecture arm64:
  "protocol descriptor for GRDB.DatabaseWriter", referenced from: … in CloudSyncKit.o
  "protocol conformance descriptor for Swift.Int : StructuredQueriesCore.QueryRepresentable" …
  "StructuredQueriesCore.QueryFragment.init(stringLiteral:)" …
ld: symbol(s) not found for architecture arm64
```

### The real defect: `@_exported import` is a compile-time re-export, not a link-time one

`CloudSyncKit` writes `import SQLiteData` and then freely uses `Database`, `DatabaseWriter`,
`QueryFragment` and `SQLQueryExpression`. It can, because sqlite-data's `Internal/Exports.swift`
`@_exported`-re-exports them. Same story for `YesChefCore`, the app target, the share extension, and
the test target — none of them declared GRDB or SQLiteData, all of them used those types.

That works perfectly under **static** linking: every transitive archive lands on the same link line
anyway, so the symbols resolve no matter who declared what. `swift build`, `swift test`, and the
standing `-destination 'generic/platform=iOS'` app build are all static, which is why all three were
green the whole time.

The moment a **test bundle** enters the build graph, Xcode rebuilds every SwiftPM product as a
**dynamic framework** (17 `…dynamic-product` targets in the log). Now each framework links only what
its own manifest declares. `SQLiteData.framework` does not vend GRDB's symbols on a dependent's
behalf — `@_exported` has no `-reexport_framework` equivalent — so every consumer that used GRDB
without declaring it failed to link, one after another, in dependency order: CloudSyncKit, then
YesChefCore, then the share extension, then the test bundle itself.

**It was never a platform restriction. It was four undeclared dependencies.**

### The fix

Declare what the source actually uses, at each level the failure walked through:

| Where | Added |
|---|---|
| `jon-platform/packages/CloudSyncKit/Package.swift` | `GRDB`, `StructuredQueriesCore` |
| `YesChefPackage/Package.swift` | `GRDB` |
| `project.yml` → `YesChef` (app) | `Dependencies`, `SQLiteData`, `GRDB` |
| `project.yml` → `YesChefShareExtension` | `Dependencies`, `SQLiteData`, `GRDB` |
| `project.yml` → `YesChefTests` | `Dependencies`, `SQLiteData`, `GRDB` |

Plus one genuine compile error in `AIHandoffMenuPasteTests.swift`: two `database.write`/`read` calls
inside an **async** `withDependencies` operation resolve to the async overload and need `await`. The
file had never been compiled, so nobody had seen it.

`swift test --package-path YesChefPackage` (468 tests) and the elevated generic app build are both
still green — verified after the change, not assumed.

**The `CloudSyncKit` half is a `jon-platform` change** and lands in that repo, not this one. Galavant
consumes the same package and carries the same latent defect the moment it grows a test bundle; the
manifest comment explains the trap in place.

## What check-drift.sh now does

`scripts/check-drift.sh` gained an app-test stage after `swift test`:

- **Wiring guards (free, always run).** The scheme must contain a `YesChefTests.xctest` testable
  reference, and `YesChefAppTests` must contain at least one Swift source. Zero hits fails the run —
  the same "refusing to report success on a check that inspected nothing" idiom the bundle-id and
  `ChatSurface` guards already use. A build that builds nothing exits 0, so build status alone could
  never have caught the state this repo was actually in.
- **`build-for-testing` (hard gate, ~10s incremental).** Compiles and links the bundle. Needs a
  simulator destination but never boots one.
- **Execution is opt-in** via `YESCHEF_RUN_APP_TESTS=1`, and the block **always prints** whether the
  tests ran. `YESCHEF_SKIP_APP_TEST_BUILD=1` skips the stage and prints a loud banner saying the
  target was not verified. The gap can no longer be silent in either direction.

`.github/workflows/ci.yml` is deliberately **not** touched. It already skips `swift test` because
hosted runners do not carry the Xcode 27 / Swift 6.4 beta, and the app targets additionally need the
sibling `jon-platform` checkout that CI does not have. Adding an app-test job there today would only
add a second thing that skips itself. `scripts/check-drift.sh` is the real gate.

Execution is opt-in for two reasons: it boots a simulator, which is exactly the loop the Verification
Pattern keeps Codex out of ([[lean-verification-default]]); and `xcodebuild test-without-building`
**hung past 10 minutes in teardown on 2 of 3 local runs** even though the tests themselves finished in
0.6s. An unattended gate cannot depend on that. Make it mandatory once the 14 below are green and the
teardown hang is understood.

---

## The 14 failures — Jon's decisions

Run them with:

```bash
YESCHEF_RUN_APP_TESTS=1 scripts/check-drift.sh
```

**Do not quietly edit these assertions to match today's behavior.** Each is a claim somebody wrote
deliberately, and the product may be the side that regressed. That is the entire reason they are worth
having.

### A. Escaped dependency scope — 4 tests, one shared cause

`ChatSurfaceTests.menuToolIsTheOnlyChatPresentationState`,
`ChatAssistantSelectionTests.captureToMenuActionDoesNotRequireASubject`,
`OnboardChatFinalizationTests.everyOnboardFinalizerActionResolvesInItsActualCatalog`, and part of
`AIHandoffMenuPasteTests`.

Every `#expect` in the first two **passes**; the tests fail only on
`SQLiteData/DefaultDatabase.swift:85: Issue recorded` — the "no database configured" warning.
`MenuDetailModel.init` starts a `@Fetch` observation, that observation outlives the `withDependencies`
scope, and when it later reads `\.defaultDatabase` the task-local override is gone.

No `await` fixes this. `withDependencies` is task-local and escaping observation tasks do not inherit
it; `prepareDependencies` is process-global and would hand the observation a *different* database than
the one the test wrote to — very likely why `duplicatePasteInformsWithoutReplacingTheImportedPlan`
sees `model.information != .alreadyImported`.

**This is the strongest surviving argument for the original plan**: app-layer models holding `@Fetch`
are genuinely awkward to test in place, and moving the pure logic to Core sidesteps the problem rather
than solving it. Decision: fix the harness, or move the logic?

### B. Behavior drift — 10 tests

| Suite | Tests | The gap |
|---|---|---|
| `WorkbenchCompareAlignmentModelTests` | 6 | The model's caching/fallback/refresh behavior no longer matches. `alignmentModelFallsBackToDeterministicWhenAlignerThrows` asserts `currentOutcome == nil` after a throw; the model now stores a `.aligned` deterministic outcome. `refreshBypassesCachesAndOverwritesPersistedAlignedOutcome` expects one aligner call and gets zero — refresh does not appear to re-run the aligner at all. **That test's name and its assertion already disagree with each other**, which points at the test as the stale side — but "refresh never calls the aligner" is worth confirming against intent before assuming so. |
| `RecipeScaleFormattingTests` | 2 | `RecipeYieldScaler.scaledText("Serves 2", factor: 3)` returns `"Serves 2"` unchanged; the test expects `"6 servings"`. `QuantityParser.leadingQuantity` requires the number to *lead* the string, so any servings text phrased `"Serves N"` scales to nothing. This one **looks like a live user-visible bug**, not a stale test: scaling a recipe silently leaves such a servings line alone (`RecipeModels.swift:931`). Check real library data for how `servingsText` is actually phrased. |
| `AIHandoffMenuPasteTests` | 2 | `duplicatePasteInformsWithoutReplacingTheImportedPlan` — probably cause A. `advisoryNotesStayOutOfEditablePrepTextAndDoNotBlockSaving` asserts the omitted step is dropped after commit; both steps remain. |
| `OnboardChatFinalizationTests` | 1 | `failedTerminalTurnStagesNothingAndSurfacesTheModelError` — a failed terminal turn stages results, surfaces no error, and replaces the last assistant reply. If that is real it is a user-facing defect in the chat error path. |

### Passing today (12) — real coverage, now protected

`HandoffSectionRoutingTests` (3) and `MenuWideColumnLayoutTests` (3) pass entirely.
`ChatSurfaceTests` (2 of 3), `WorkbenchCompareAlignmentModelTests` (1 of 7),
`ChatAssistantSelectionTests` (1 of 2) and `RecipeScaleFormattingTests` (2 of 4) pass in part.

---

## What happened to the "move the logic to Core" plan

The 2026-07-26 plan was to move five types to `YesChefCore` so 19 of the tests would run under
`swift test`. Its premise — *the target cannot run, so relocate the tests to somewhere that can* — is
gone. Two of its arguments survive on their own merits, and neither is urgent:

- `WorkbenchCompareAlignmentModel` and `RecipeScaleFormatting` are SwiftUI-free logic sitting in the
  app layer. Worth fixing for the standing "keep pure logic out of the App layer" corollary and its
  scar (PR #185) — **not** for the test target's sake any more.
- Cause A is a real, recurring tax on testing anything holding a `@Fetch`.

Recommended order: **decide the 14 first.** Moving a test that encodes a wrong expectation just
relocates the wrong expectation, and moving one that fails for reason A hides the harness problem
instead of settling it.

## Verification

- `scripts/check-drift.sh` — green, including the new app-test stage.
- `swift test --package-path YesChefPackage` — 468 tests, green.
- `xcodebuild -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build` — green.
- `xcodebuild build-for-testing -scheme YesChef -destination 'platform=iOS Simulator,name=iPhone 17 Pro' …` — **TEST BUILD SUCCEEDED**, reproduced from cleared DerivedData.
- `YESCHEF_RUN_APP_TESTS=1 scripts/check-drift.sh` — 26 tests, 12 pass, 14 fail as inventoried above.
- **No device pass.** Nothing user-facing changed.
