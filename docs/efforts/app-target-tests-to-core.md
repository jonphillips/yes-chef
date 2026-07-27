# Effort: The app test target runs nothing — move the logic, not the tests

**Type:** Test-coverage recovery by relocating pure logic to Core. **No schema, no UI, no behavior
change, no new test written.**
**Status:** **Ready** — written 2026-07-26 from the architect review of PR
[#240](https://github.com/jonphillips/yes-chef/pull/240).
**Summary:** `YesChefAppTests` holds **23 tests that are compiled and executed by nothing**. Only 4 of them
are stranded by the test target; the other **19 are stranded by pure logic living in `YesChefApp/`**. Move
five files/types to `YesChefCore` and those 19 run in `scripts/check-drift.sh` on every dispatch, with no
cross-repo work and no simulator.
**Related:** `CURRENT_HANDOFF` § Verification Pattern — the standing *"keep pure logic out of the App layer"*
corollary; this is that rule arriving from the other direction. The same corollary already has one scar
(PR #185's `.full` `DateStyle` break in `HandoffIntents.swift`) and one repayment (PR #240's `DeletionCopy`
move).
**Owner:** Codex (implement) · Claude (architect/review) · Jon (**no device pass needed** — nothing user-facing
changes).

---

## The finding

Nothing builds or runs `YesChefAppTests`:

- `scripts/check-drift.sh` ends in `swift test --package-path YesChefPackage` — package only.
- `.github/workflows/ci.yml` runs the same command.
- The standing verification build (`-destination 'generic/platform=iOS' … build`) never compiles a test
  target; the string `YesChefAppTests` appears zero times in its log.

So the seven files below have been accumulating since they were written without once being executed, and
they are **not even known to compile**.

| File | Tests | What it actually needs from `YesChefApp` |
|---|---|---|
| `WorkbenchCompareAlignmentModelTests` | 7 | `WorkbenchCompareAlignmentModel` — SwiftUI-free |
| `RecipeScaleFormattingTests` | 4 | `ScaleFraction` / `ScaleText` — `Foundation` only |
| `HandoffSectionRoutingTests` | 3 | `HandoffExportSource` — pure over Core types |
| `MenuWideColumnLayoutTests` | 3 | `MenuWideColumnLayout` — `CGFloat` geometry |
| `ChatAssistantSelectionTests` | 2 | `ChatAssistantSelection` — `@Observable`, no SwiftUI |
| `AIHandoffMenuPasteTests` | 2 | **`MenuDetailModel`** — genuinely app-layer |
| `OnboardChatFinalizationTests` | 2 | **chat finalization on app models** — genuinely app-layer |

**Nineteen of twenty-three are testing code that has no business being in the app target in the first
place.** The test target is not the problem for those; it is where they ended up because the code did.

## The target itself is broken, and fixing it is *not* this effort

With DerivedData deleted, `build-for-testing` against a simulator still fails — so this is a real
configuration defect, not a stale-artifact fluke:

```
CloudSyncKitdynamic-product: ld: warning: Could not parse or use implicit file '…/SwiftUICore.tbd':
  cannot link directly with 'SwiftUICore' because product being built is not an allowed client of it
CloudSyncKitdynamic-product: clang: error: linker command failed with exit code 1
```

Building a test bundle makes SwiftPM emit **dynamic** products; a dynamic library that pulls SwiftUI
transitively hits Apple's restricted-client list for `SwiftUICore`. The regular app build links statically
and never sees it. **The fix is a linkage change to CloudSyncKit in `jon-platform`** — a shared package, for
the benefit of four tests, plus a commitment to run a simulator inside a loop that is deliberately
simulator-free ([[lean-verification-default]]). Not worth it now. S3 below makes the four honest instead.

## What this effort is *not*

- **Not a rewrite of any test.** Each moved test keeps its name, its assertions, and its intent. If a moved
  test needs its logic changed to pass, **stop and report it** — that is a real bug the target's silence has
  been hiding, and it wants its own decision, not a quiet edit.
- **Not a behavior change.** Every moved type keeps its semantics; only its module changes. Access levels
  become `public` where the app still calls in.
- **Not a CloudSyncKit fix**, and not an attempt to make `check-drift.sh` run a simulator.
- **Not a general sweep of `YesChefApp/` for movable logic.** Scope is exactly the types the existing 23
  tests touch. The broader sweep is a different, larger conversation.

---

## S1 — the two whole-file moves (11 tests)

Both files move to `YesChefPackage/Sources/YesChefCore/` unchanged apart from access levels.

- **`WorkbenchCompareAlignmentModel.swift`** (141 lines) → **7 tests**. It imports `Dependencies`,
  `Foundation`, `LLMClientKit`, `Observation`, `YesChefCore` and **nothing from SwiftUI or UIKit**. Every one
  of those is already a `YesChefCore` dependency, so this is a drop-in. `@Observable @MainActor` is fine in
  the package. This is the single biggest block of stranded coverage (327 lines of tests).
- **`RecipeScaleFormatting.swift`** (128 lines) → **4 tests**. `import Foundation`, two enums, no
  dependencies at all.

Move the two test files to `YesChefPackage/Tests/YesChefCoreTests/`, swapping `@testable import YesChef` for
`import YesChefCore` and nesting each suite under `extension RecipeCoreTests { … }` the way
`DeletionCopyTests` does. `WorkbenchCompareAlignmentModelTests` also imports `LLMClientKit` and
`DependenciesTestSupport` — the latter is already a test-target dependency; **confirm the former resolves
transitively** through `YesChefCore` rather than assuming it.

## S2 — the three extractions (8 tests)

Each pulls a pure type out of a file that cannot move as a whole.

- **`RecipePlaybookColumnLayout.swift`** → **3 tests.** Lines 1–158 (the preference/metric/detent enums plus
  `RecipeWideColumnLayout` and `MenuWideColumnLayout`) are pure `CGFloat` geometry. The two `View` structs
  from line 159 (`RecipeWideColumnSeparator`, `RecipePlaybookResizeHandle`) stay in the app and keep the
  `import SwiftUI`. Split the file; do not move the views.
- **`HandoffExportSource` + `WorkbenchHandoffTask`** out of `HandoffIntents.swift` (744 lines, `import
  AppIntents`) → **3 tests.** Both are `Sendable` enums whose every case and helper is a Core type, so they
  move cleanly. **One piece must stay behind:** `init(_ source: HandoffSource)` — `HandoffSource` is an
  AppIntents entity in `HandoffEntities.swift` — so leave that initializer in the app as an
  `extension HandoffExportSource`. This is the file PR #185 broke on for exactly this reason; getting these
  two types out is worth slightly more than the three tests suggests.
- **`ChatAssistantSelection`** out of `RecipeChatWorkspace.swift` (line 867) → **2 tests.** `@MainActor
  @Observable final class`, `Foundation` + `Observation` only, despite living in the app's largest SwiftUI
  file. It is held with `@State` at the call site, which works unchanged with a Core type. Keep its existing
  doc comment about per-`UITextView` ownership — it explains a non-obvious invariant.

## S3 — make the remaining four honest (0 tests recovered)

`AIHandoffMenuPasteTests` and `OnboardChatFinalizationTests` drive `MenuDetailModel` and the chat
finalization path; those are genuinely app-layer and stay put.

Give each file a header comment stating that **this target is not built or run by any command in the
project**, why (the CloudSyncKit dynamic-product link failure above), and what would have to change. **A test
that looks like coverage and never executes is worse than no test** — the point of S3 is that the next person
to open these files learns that in the first three lines rather than after a review round.

Do not delete them. They encode real expectations about two models, and they become live the day the target
does.

---

## Sequencing

**One dispatch, S1 → S2 → S3**, but sliced so S2 stalling cannot block S1. S1 is two file moves and recovers
the majority of the coverage; S2 is surgery on three larger files and is where a surprise would come from. If
S2 turns up an entanglement not listed above, ship S1 + S3 and report the blocker rather than forcing it.

No dependency on ADR-0032 S2 in either direction; this can take whichever slot Jon prefers.

## Verification

- `swift test --package-path YesChefPackage` — **the number must go up.** It is 457 today; S1 + S2 should
  land it at **476**. A green run at 457 means the moved suites are not being discovered, which is the exact
  failure this effort exists to end. State the final count in the PR.
- **The elevated generic app build is required evidence**, despite the payoff being package-side: every slice
  removes types from `YesChefApp/` files, so the app target must be shown still compiling.
  `scripts/xcodebuild-summary.sh -scheme YesChef -destination 'generic/platform=iOS' -skipMacroValidation CODE_SIGNING_ALLOWED=NO build`
- `xcodegen generate` after adding/removing Swift files in the app target, then `scripts/check-drift.sh`.
- **No device pass.** Nothing user-facing changes; if anything looks different on device, that is a
  regression, not a win.

## Open for Jon

- **The four stranded tests.** S3 marks them. The alternatives are deleting them or fixing CloudSyncKit's
  product linkage in `jon-platform`. Recommendation is to mark and revisit when something else forces a
  CloudSyncKit change; say so if you'd rather settle it now.
- **Whether `YesChefAppTests` should exist at all afterwards.** With 19 of 23 moved, the target holds four
  tests that cannot run. Keeping it is a bet that the linkage gets fixed eventually; removing it makes the
  app layer explicitly untestable-by-policy, which is at least honest. Not urgent either way.
