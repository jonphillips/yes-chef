# Effort: The app test target runs — 26 of 26 pass

**Type:** Test-coverage recovery. **Complete** apart from one optional follow-on.
**Status:** **Done 2026-07-27.** Supersedes the 2026-07-26 version, whose central claim ("the target
is broken and fixing it is not this effort") was wrong.
**Summary:** `YesChefAppTests` went from *compiled and executed by nothing* to **26/26 green**, gated
in `scripts/check-drift.sh`. Three defects were behind it: undeclared GRDB/SQLiteData dependencies
(the target could not link), a duplicated `Dependencies` runtime in the test bundle (every
`withDependencies` override silently did nothing), and — once those were out of the way — three stale
expectations plus **one live user-visible bug in recipe scaling**.
**Related:** `CURRENT_HANDOFF` § Verification Pattern; [[lean-verification-default]].
**Owner:** Claude. No decisions outstanding.

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
0.6s. An unattended gate cannot depend on that. The suite is green, so the only thing still standing
between opt-in and mandatory is that hang.

---

## The failures — 14, then 5, then 0

The first pass through this inventory blamed "drifted expectations". **That was wrong for 11 of the
14**, and partly wrong again about the 5 that survived. Recording both corrections, because the
pattern is the point: a suite nothing has run accumulates several unrelated defects at once, and the
loudest theory is rarely the whole story.

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

Two probes pinned it: an `@Observable @MainActor` model declared *in the test target* sees the
override fine, while the real model — identical declaration, compiled into `YesChef.debug.dylib` —
never called the stub aligner even with the disk cache stubbed out. That ruled out the three theories
that came first (escaped `withDependencies` scope, a stale disk-cache hit, mismatched framework
linkage) and left binary layout; `nm` confirmed it.

Dropping `DependenciesTestSupport` — nothing here used its API, and `Dependencies` detects `.test`
context at runtime on its own — takes duplicate symbols to **0** and failures from 14 to 5.

> **Generalises past this repo:** any test target linking a static-only package product alongside
> dynamic frameworks of the same package can silently lose its dependency overrides. It presents as
> wrong *behavior*, never as a link error.

### `RecipeYieldScaler` dropped the leading anchor — a live user-visible bug (2 tests)

The only one of the five that was a product defect, and git dates it exactly:

- **Jul 12** (`cf44929`) — `ScaleText.scaledServingsSummary(servingsText:baseServings:factor:)` lands
  with an *unanchored* regex and a `baseServings` fallback. These tests are written against it.
- **Jul 16** (`bd7cafb`, "Dogfood polish batch") — production switches to
  `RecipeYieldScaler.scaledText`, which keeps the recipe's own phrasing instead of normalising to
  "N servings". Better design, but it also swapped the unanchored search for
  `QuantityParser.leadingQuantity`, which anchors at `text.startIndex`.
- **Jul 18** (`e452044`) — the test is mechanically re-pointed at the new API with its **old expected
  strings left untouched**. Nothing runs it. Nine days later, nobody knows.

Net effect in the app: `"4–6 servings"` scaled correctly while `"Serves 2"`, `"Serves 2 to 4"`,
`"Makes 4 dozen"` and `"Yield: 6"` **silently did not scale at all**.

Fixed by giving `QuantityParser` a `firstQuantity(in:)` search entry point and using it from
`RecipeYieldScaler` only. **`leadingQuantity` is unchanged and must stay that way** — `IngredientScaler`
depends on the anchor so that "onions, about 2 handfuls" does not scale off the 2. Corroboration that
searching is the right semantics for yield text: `ServingParser.servings(from:)`, sitting three
functions away, already scanned rather than anchored.

Coverage now lives in Core, where the code is: `RecipeYieldScalingTests` gained five cases that run
in `swift test` on every dispatch. The two app-layer assertions were re-baselined to the
preserve-phrasing contract ("Serves 2" ×3 → "Serves 6") and are now redundant — candidates for the
sweep below.

### Three stale expectations (3 tests)

- Two missing dependency overrides (`\.uuid`, `\.date`) — the standard "unimplemented dependency
  accessed in a test" report. A sibling test in the same file already did it correctly.
- `advisoryNotesStayOutOfEditablePrepTextAndDoNotBlockSaving` — **not** the open product question an
  earlier revision of this doc claimed. The advisory behavior it guards is correct and its assertions
  pass: advisories stay out of `editableText`, surface as `supportingEvidenceRows`, and do not block
  the commit. The single mismatch was `sourceDish`, which the commit **preserves** and the expectation
  did not carry. Preserving it is right — `droppedSourceDishEvidence` exists precisely to warn when a
  returned plan loses that link. Expectation updated.

## What happened to the "move the logic to Core" plan

The 2026-07-26 plan was to move five types to `YesChefCore` so 19 stranded tests would run under
`swift test`. Its premise — *the target cannot run, so relocate the tests somewhere that can* — is
gone: the target runs. Its second argument, that app-layer models holding `@Fetch` are inherently
awkward to test in place, is gone too; that was the duplicated `Dependencies` runtime wearing a
costume, and those suites now pass untouched.

**One argument survives, on its own merits and unhurried:** `WorkbenchCompareAlignmentModel` and
`RecipeScaleFormatting` are SwiftUI-free logic sitting in the app layer, which the standing "keep pure
logic out of the App layer" corollary says they should not be. Worth doing for that reason, not for
testability. Two small pieces of evidence for whoever picks it up:

- The scaling fix landed its real coverage in `YesChefCoreTests` because that is where the code lives,
  which left the two app-layer assertions redundant. That is the sweep making its own case.
- Adding a Swift file to `YesChefAppTests` without re-running `xcodegen generate` silently excludes it
  from the bundle — the build stays green and the test never runs. Found the hard way while probing.
  Fewer files in that target is fewer chances to hit it.

## Verification

- `scripts/check-drift.sh` — green, including the new app-test stage.
- `swift test --package-path YesChefPackage` — **476 tests, green** (was 468; +5 yield-scaling cases).
- `xcodebuild -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build` — green.
- `xcodebuild build-for-testing -scheme YesChef -destination 'platform=iOS Simulator,name=iPhone 17 Pro' …` — **TEST BUILD SUCCEEDED**, reproduced from cleared DerivedData.
- `YESCHEF_RUN_APP_TESTS=1 scripts/check-drift.sh` — **26 tests, 26 pass.**
- **Device pass wanted for the scaling fix.** Everything else here is build plumbing, but
  `RecipeYieldScaler` is a real behavior change on a visible surface: open a recipe whose servings
  text leads with a word ("Serves 4", "Makes 4 dozen") and scale it. Before this change the line sat
  unchanged; it should now track the scale factor while keeping its own wording.
