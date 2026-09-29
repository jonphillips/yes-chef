# Verification

The standing pattern for every dispatch (moved from `CURRENT_HANDOFF.md` on 2026-09-29; jon-platform
ADR-0005). Noisy commands run through `quiet-run` — `scripts/check-drift.sh` and
`scripts/xcodebuild-summary.sh` already do.

⚠️ **A standing Codex-env gotcha:** the simulator-hosted `YesChefTests` target cannot run in Codex's sandbox (no CoreSimulator), so its "couldn't run
the app tests" is structural, not a regression — and it once *masked two genuinely red tests* (missing
`bootstrapDatabase()` → `RecipeEditorModel`'s eager `@Fetch` tripped SQLiteData's blank-DB reporter), fixed by
the architect running the target locally ([[codex-build-excuse-reproduce]]).

Lean by default — the cost center is the build/simulator loop, not the code, and Jon does the device pass
regardless. So verify with **compiler + tests once**, then hand off:

- Run `xcodegen generate` after adding Swift source files — `project.yml` globs the source dirs, so a new
  `.swift` file is invisible to the **app target** until the `pbxproj` is regenerated (hand-editing the
  `pbxproj` is a fragile workaround, not the pattern). **This is a build-claim tripwire:** ADR-0021 V4a's
  first push added two `YesChefApp/` extension files without regenerating, so the app target could not have
  compiled (their symbols would be undefined) — yet the PR claimed a green generic build. A "passing" app
  build that omits newly-added files is proof the build was never actually run ([[codex-build-excuse-reproduce]]);
  the architect re-runs it locally before approving (PR #285, fixed in `5388e31`).
- For package/logic-only changes, `swift build` the package (cheaper than a full app build).
- Otherwise run the app build with **elevated/unsandboxed permissions**, no simulator, no signing identity:
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`.
- Run `scripts/check-drift.sh`.
- **The generic app build is required evidence for `YesChefApp/` changes.** `check-drift.sh` compiles only
  `YesChefPackage`; a green package build and `swiftc -parse` are not App-target evidence. The default Codex
  sandbox can SIGTERM Xcode before compilation by denying user-level service/cache access, so start with the
  elevated command. A sandbox-shaped `143` is not a green result. If the elevated build cannot reach the
  compiler, record the full-log path and **the architect runs the same build locally before approving.**
- **Run the `YesChefTests` app target when a change touches `YesChefApp/` *model* code** (a `@Observable`
  model, its extensions, or a display model — **not** view-only or copy changes). **Run it
  elevated/unsandboxed on the *first* attempt** — the default sandbox has no CoreSimulator service and a
  denied Swift/Clang module cache, so a sandboxed run *cannot* reach the tests. Do not attempt it sandboxed
  first, and do not fall back to a focused `swift test --filter` (it hits the same denied module cache). One
  invocation resolves a udid and runs the target:
  `udid=$(xcrun simctl list devices available | grep -oE '[0-9A-Fa-f-]{36}' | head -1); scripts/xcodebuild-summary.sh -scheme YesChef -destination "platform=iOS Simulator,id=$udid" -skipMacroValidation test`.
  **This is the one sanctioned simulator use** and it is a
  deliberate narrowing of guardrail #8, not a hole in it: it *runs tests*, it does not drive UI, install a
  dogfood build, or take screenshots. Jon still owns the device pass. **Why it earns the ~2 minutes:**
  nothing else executes this target — the generic build only compiles it — so it rots invisibly. Found
  2026-08-06: five tests had been red on `main` for some time (models resolve `@Dependency(\.uuid)` eagerly in
  `init`, so *constructing* one outside a scope fails), and they surfaced only because a V4c review happened
  to write app-level tests. **Gotcha:** the scheme's target is **`YesChefTests`** while the directory is
  `YesChefAppTests/` — `-only-testing:YesChefAppTests/…` fails with a misleading "isn't a member of the
  specified test plan or scheme."
- **The app target is where the model + binding *assembly* is certified.** Core tests certify the parts.
  Two shipped defects lived exactly in that gap — ADR-0030's restore (dead through three reviews and a green
  Core suite) and V4c's inserted-step section drift — so a fix to a model-level defect wants its regression
  test *here*, not only in Core ([[alert-ispresented-destructive-setter]]).
- **Corollary — keep pure logic out of the App layer.** String formatting, serialization, and parsing belong
  in `YesChefPackage` (which Codex *can* compile and test). #185's break was `HandoffIntents.swift` calling
  `date: .full` — logic that belonged in Core, where the package build would have caught it instantly.
- **`YesChefAppTests` compiles and links on every `check-drift.sh` run, but only *executes* behind
  `YESCHEF_RUN_APP_TESTS=1`** (it boots a simulator, and there is a teardown hang). **29 tests in 9 suites
  pass as of 2026-07-29** (the SQLiteData 1.8.2 bump fixed the link wall — see the DONE-LOG arc). So the old
  "a test there counts for nothing" rule is retired — but **Core is still the default home**, because
  `YesChefPackage/Tests/` runs on every dispatch with no flag and no simulator. Put a test in the app target
  only when it genuinely needs the app target, and say in the PR that you ran it with the flag. **If the
  `Ld … SQLiteData.framework` undefined-symbols wall ever returns, `xcodebuild clean` first** — SQLiteData
  links `StructuredQueriesCore` via Swift autolinking against the `PackageFrameworks` search path, not a
  declared dependency, so it is build-order sensitive and a stale eager-linking TBD looks identical
  ([[exported-import-not-link-time]]).
- **Note:** parts of the app target (`PantryViews.swift` / `GroceryViews.swift`) compile only in Jon's device
  pass, not in CI.
- **Do not install/launch on simulators by default** — hand straight to Jon's UI pass. Only boot a simulator
  when a change genuinely can't be confirmed from build + tests, and say why in the PR.
- **Fail fast, without false escape hatches.** No alternate destinations, simulator resets, or install loops.
  An environment failure that prevents the elevated build reaching the compiler is an architect gate, not a
  successful Codex verification.

Jon performs the primary UI testing pass on `iPad Pro 13-inch (M5) (16GB)` and `iPhone 17 Pro`.
