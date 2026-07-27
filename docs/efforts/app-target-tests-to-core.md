# Effort: The app test target runs — 21 of 26 pass, 5 real issues remain

**Type:** Test-coverage recovery. The target is **fixed, wired in, and mostly green**; what remains
is two harness nits, one live scaling bug, and one product question.
**Status:** **Re-scoped 2026-07-27** after the target was fixed. Supersedes the 2026-07-26 version,
whose central claim ("the target is broken and fixing it is not this effort") turned out to be wrong.
**Summary:** `YesChefAppTests` compiles, links and runs: **26 tests, 21 pass, 5 issues in 3 suites.**
The build-and-link half is a hard gate in `scripts/check-drift.sh` as of this change. Two separate
linkage defects were behind everything — undeclared GRDB/SQLiteData dependencies (which stopped the
target building at all) and a duplicated `Dependencies` runtime in the test bundle (which silently
voided every `withDependencies` override).
**Related:** `CURRENT_HANDOFF` § Verification Pattern; [[lean-verification-default]].
**Owner:** Claude (diagnosis + target fix, done) · Jon (**the 3 decisions below**) · Codex (the work
they turn into).

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
| `project.yml` → `YesChefTests` | `Dependencies`, `SQLiteData`, `GRDB` — and **removed** `DependenciesTestSupport`, see below |

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
0.6s. An unattended gate cannot depend on that. Make it mandatory once the 5 below are green and the
teardown hang is understood.

---

## The failures — 14 became 5

The first pass through this inventory blamed "drifted expectations". **That was wrong for 11 of the
14.** They were failing because of a second, statically-linked copy of the `Dependencies` runtime in
the test bundle.

### The duplicated Dependencies runtime (11 tests)

Xcode builds every package product in this graph as a dynamic framework — except
`DependenciesTestSupport`, which only ever appears as `DependenciesTestSupport-product`, never
`…dynamic-product`. Linking it pulled a second static copy of the entire `Dependencies` target into
the test bundle: `nm -gU` counted **401 Dependencies symbols defined inside `YesChefTests`** while
`Dependencies.framework` sat right next to it in `YesChef.app/Frameworks`, including a second
`DependencyValues.$_current`.

Task-local identity is the *address* of the `TaskLocal` object. Two copies means two unrelated
task-locals, so `withDependencies { }` written in a test set the test bundle's copy while app-module
code (`MenuDetailModel`, `WorkbenchCompareAlignmentModel`) read the framework's copy and got the
**live** dependency. Overrides silently did nothing.

Two probes pinned it down: an `@Observable @MainActor` model declared *in the test target* sees the
override fine, while the real model — identical declaration, but compiled into `YesChef.debug.dylib`
— never called the stub aligner even with the disk cache stubbed out. That ruled out the three
theories that came first (escaped `withDependencies` scope, a stale disk-cache hit, and mismatched
framework linkage) and left binary layout as the only candidate; `nm` confirmed it.

Dropping `DependenciesTestSupport` (nothing here uses its API; `Dependencies` detects the `.test`
context on its own at runtime) removes the duplicate — **0** duplicate symbols — and takes the suite
from 14 failures to 5. `WorkbenchCompareAlignmentModelTests`, `ChatSurfaceTests` and
`ChatAssistantSelectionTests` now pass in full.

**The lesson generalises past this repo:** any test target linking a static-only package product
alongside dynamic frameworks of the same package can silently lose its dependency overrides. It
fails as wrong *behavior*, never as a link error.

### What actually remains (5 issues, 3 suites)

**1. Two missing dependency overrides — trivial, no judgment needed.**

- `duplicatePasteInformsWithoutReplacingTheImportedPlan` reads `\.uuid` without overriding it
  (`UUID.swift:67`). The sibling test in the same file already does `$0.uuid = .incrementing`.
- `everyOnboardFinalizerActionResolvesInItsActualCatalog` reads `\.date` without overriding it
  (`Date.swift:37`).

Both are the standard "unimplemented dependency accessed in a test" report. Add the overrides.

**2. `RecipeYieldScaler` drops the leading anchor — a live user-visible bug.**

Git settles this one. On **Jul 12** (`cf44929`) `ScaleText.scaledServingsSummary(servingsText:baseServings:factor:)`
was added with an unanchored regex plus a `baseServings` fallback, and these tests were written
against it. On **Jul 16** (`bd7cafb`, "Dogfood polish batch") production switched to
`RecipeYieldScaler.scaledText(_:factor:)`, which preserves the source phrasing instead of normalising
to "N servings" — a deliberate, better design. But it also swapped the unanchored search for
`QuantityParser.leadingQuantity`, which anchors at `text.startIndex`. On **Jul 18** (`e452044`) the
test was mechanically re-pointed at the new API with its **old expected strings left untouched**.
Nothing ever ran it.

Today: `"4–6 servings"` scales correctly, `"Serves 2 to 4"` and `"Serves 2"` **silently do not
scale at all**. `QuantityParser.rangeStart` already handles both `to` and dashes, so the anchor is
the only thing in the way.

Fix in two parts, in this order:
- Give `QuantityParser` a *search* entry point and use it from `RecipeYieldScaler` only. **Do not
  change `leadingQuantity` itself** — `IngredientScaler` relies on the anchor for ingredient lines
  ("1 cup onions"), where matching a later number would be wrong.
- Then re-baseline the two assertions to the preserve-phrasing contract: `"Serves 2 to 4"` ×3 →
  `"Serves 6 to 12"`, `"Serves 2"` ×3 → `"Serves 6"`. That is a deliberate re-baseline with a reason,
  not a match-to-behavior edit.

**3. `advisoryNotesStayOutOfEditablePrepTextAndDoNotBlockSaving` — one real behavior question.**

Committing the reviewed plan should drop the step the model omitted; both steps remain. This is the
only one of the original 14 that is still an open product question. Worth answering directly rather
than adjusting the test.

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
- `YESCHEF_RUN_APP_TESTS=1 scripts/check-drift.sh` — 26 tests, 21 pass, 5 issues as inventoried above.
- **No device pass.** Nothing user-facing changed.
