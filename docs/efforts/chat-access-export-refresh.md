# Effort — The chat-access export refresh moves into ChatAccessKit

Status: Ready
Summary: Lift the export refresh lifecycle (when to export, the background task, cancelling when background time runs
out) into `ChatAccessKit`, and adopt it here. The behavior change is that Yes Chef stops running an export past its
background time. No schema, sync, or export-format change.

Implements: [jon-platform ADR-0011](../../../jon-platform/docs/adr/0011-chat-access-export-refresh.md). Galavant and Fit
Happens adopt the kit later, from their own briefs (`chat-access-export-refresh-adoption` in each).

## Why Yes Chef goes first

`YesChefApp/ChatAccessExportModel.swift`'s `BackgroundTaskLease` ends the background task when time runs out, but nothing
cancels the export. The export keeps reading the App Group store and encoding after iOS may have suspended the app, and a
suspended app holding a SQLite lock is the `0xdead10cc` kill. Galavant's and Fit Happens' copies cancel on expiry.
Galavant's is the most complete and the only one with expiry tests, so it's the source for the kit.

## Part 1 — jon-platform package PR (first)

Per jon-platform `docs/agent-collaboration.md` § Dispatches whose code lands in jon-platform. Title it for this effort and
link this brief.

1. **A main-actor, `@Observable` refresh type in `packages/ChatAccessKit`** that owns what ADR-0011 D1 lists. Name it and
   shape its signatures as you see fit. It takes:
   - the `ChatAccessExportWriter`,
   - a folder resolver (`ChatAccessContainerClient`'s `resolveFolder`, or a closure of that shape),
   - an `isEnabled` closure,
   - a build closure that is given the export time and device name (`"iPhone"` or `"iPad"`) and returns encoded bytes.
     The kit runs it off the main actor and passes cancellation into it, as Galavant's `withTaskCancellationHandler` does.

   It exposes `isRefreshing`, the writer's `lastExport`, and the last outcome as an enum: written, throttled, already
   writing, couldn't start the background task, or failed with an error. It has two entry points:
   `appDidEnterBackground()`, which exports only when enabled and due, and `refresh()`, which always does. It runs one
   export at a time. The kit doesn't word messages.
2. **The background-task client** (ADR-0011 D3): begin with a name and an expiry handler, returning an identifier, and
   end. The live value calls `UIApplication` under `canImport(UIKit)`. On expiry the type cancels its task, then ends
   the background task. Galavant's `ChatExportBackgroundTaskClient` and `ExportAssertion`
   (`Galavant/ChatAccess/ChatExportModel.swift`) are the model.
3. **The device name** comes from a small client too (Galavant's `ChatExportDeviceClient`), so the tests run on the macOS
   host.
4. **Tests** in `ChatAccessKitTests`, moved from `GalavantTests/ChatExportModelTests.swift` and widened:
   - a disabled or throttled background call does no folder work and begins no background task;
   - `refresh()` writes while throttled;
   - expiry cancels the build, ends the background task, and clears `isRefreshing`;
   - a background task that can't begin reports that and starts no work;
   - a second call while one export runs does nothing.
5. **Housekeeping in the same PR:**
   - move the seam from `SEAM-LEDGER.md` ("Chat-access export read models") to `EXTRACTION-NOTES.md` (ledger rule 5),
     noting that Galavant's and Fit Happens' adoptions are still owed;
   - in `docs/adr/0011-chat-access-export-refresh.md` and `docs/adr/README.md`, record ADR-0011 as accepted and built in
     this PR.

**Verification, listed in the PR body:**
- `scripts/quiet-run swift test --package-path packages/ChatAccessKit`;
- an iOS compile of the package, from `packages/ChatAccessKit`:
  `../../scripts/quiet-run xcodebuild -scheme ChatAccessKit -destination 'generic/platform=iOS Simulator' build`;
- a build of Yes Chef, Galavant, and Fit Happens, the kit's three consumers (`scripts/build <app>`). The change is
  additive, so they build unchanged.

## Part 2 — Yes Chef PR (after Part 1 merges)

1. **`ChatAccessExportModel`** keeps its name and Settings surface, and hands the lifecycle to the kit. Its build
   closure keeps what it does today: `ChatAccessExportBuilder.build(in:generatedAt:device:)` inside a `database.read`,
   then `ChatAccessExportCoding.encode`. Yes Chef has no chat-access switch, so `isEnabled` is always `true`.
2. **Delete `BackgroundTaskLease`** and the hand-rolled `isRefreshing` and throttle logic.
3. **`RecipeLibraryView`'s background `scenePhase` branch** calls the kit's background entry point in place of
   `exportIfDue()`. Settings' Refresh calls `refresh()`.
4. **Settings (`SettingsViews.swift` § Chat Access)** reads the last export date and size, and `isRefreshing`, as now.
   It words the outcome with today's messages ("The Yes Chef export wasn't written because this refresh was throttled.
   Try Refresh again.", and the others).
5. **Tests:** `YesChefAppTests/ChatAccessExportModelTests.swift` keeps its two cases (the throttle is checked before
   the folder is resolved, and a refresh writes through the injected folder), adjusted to the new entry points. The
   lifecycle cases live in the kit.

**Verification:** `scripts/check-drift.sh`, per `docs/verification.md`.

**Done when:** the package PR is merged, Yes Chef has no `BackgroundTaskLease`, its tests pass, and closeout runs
(ADR-0005 D16), appending the device gate below. The architect then flips the Galavant and Fit Happens adoption briefs to
Ready.

## Device gate (Jon)

On the iPhone, once Settings → Chat Access shows a last export more than 15 minutes old: open Yes Chef, then send it to
the background. Ask chat for something Yes Chef's read tools answer, and the export it reads is from just now. Then
Settings → Refresh shows a new Last export time at once.
