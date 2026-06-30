# Effort: Refresh the library list after a Share Extension import (cross-process observation)

**Type:** Defect fix (M2 — Web Recipe Capture)
**Owner:** Codex (implement) · Jon (architect/review)
**Status:** Ready to implement

## Symptom

Sharing a recipe into YesChef from a browser on iPad: the share sheet appears, the
parsed data looks correct, you tap **Save**, the sheet dismisses — but the recipe does
**not** appear in the library list. Quitting and relaunching the app surfaces it.

The console line some users see —
`Failed to terminate process: …extensionKit… Code=18 … "No such process found"` — is
unrelated RunningBoard teardown noise, not the cause.

## Root cause (verified)

The write is correct and durable. This is purely a **cross-process database-observation
gap**.

- The app and the Share Extension are **separate processes** that each open the *same*
  App Group database file (`group.com.jonphillips.yeschef/SQLiteData.db`) through
  independent `SQLiteData.defaultDatabase(path:)` connections:
  - App: `DependencyValues.bootstrapDatabase()` — `YesChefPackage/Sources/YesChefCore/Schema.swift:6`
  - Extension: `DependencyValues.bootstrapDatabaseForShareExtension()` — `Schema.swift:18`
  - Shared path: `YesChefDatabaseStorage` (`DatabaseStorage.swift`), App Group
    `group.com.jonphillips.yeschef`, file `SQLiteData.db`. Both entitlements grant the group.
- The extension commits the recipe graph in
  `ShareCaptureModel.saveButtonTapped()` →
  `database.write { RecipeRepository.importCapturedRecipe(...) }`
  (`YesChefShareExtension/ShareViewController.swift:97`).
- The library list observes via
  `@Fetch(RecipeListRequest(), animation: .default) var recipeRows`
  in `RecipeLibraryModel` (`YesChefApp/RecipeModels.swift:33`). This is backed by GRDB
  `ValueObservation` through Sharing's `SharedReader`.
- **GRDB `ValueObservation` only re-fetches for commits made on its own process's writer
  connection.** A commit from the extension's separate connection raises no commit hook in
  the app, so no observed query re-runs. On next launch the query runs fresh and the
  recipe appears — which confirms the data was written and visible; only the *notification*
  was missing.
- SQLiteData ships **no** cross-process/Darwin change bridge (verified against the vendored
  checkout). It does expose a parameterless reload on the projected value —
  `public func load() async throws` on both `@Fetch` and `@FetchAll`
  (`FetchAll.swift:66`, `Fetch.swift:64`) — which re-runs the existing query against current
  on-disk state. That is the reload lever this effort uses.

## Goal

When the Share Extension commits an import, the app's library list (and other
DB-observing models) reflect it without a relaunch — both when the app is live in the
foreground (iPad Split View / Stage Manager alongside Safari) and when the user returns to
the app after sharing.

## Design

Two complementary triggers, because each covers a case the other misses:

1. **Darwin notification beacon** (covers app-visible-in-foreground, e.g. iPad
   multitasking). The extension posts a Darwin notification after its write commits; the app
   observes it and reloads.
2. **Scene-activation reload** (covers the common "share, then switch back to the app"
   flow, and any beacon missed while the app was suspended). On `scenePhase` → `.active`,
   reload. `scenePhase` is currently unused in the app.

### 1. Shared beacon in YesChefCore

Add a small, dependency-free type to `YesChefCore` (both targets already import it). Keep
the C bridge minimal and centralized.

```swift
// YesChefPackage/Sources/YesChefCore/DatabaseChangeBeacon.swift
import Foundation

public enum DatabaseChangeBeacon {
  // Must be a constant string shared by both processes; scope it to the app group.
  private static let darwinName = "group.com.jonphillips.yeschef.databaseDidChange"

  /// A NotificationCenter name the app side can subscribe to in-process.
  public static let didChange = Notification.Name("YesChefDatabaseDidChange")

  /// Call from the writing process (the Share Extension) AFTER a successful commit.
  public static func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(darwinName as CFString),
      nil, nil, true
    )
  }

  /// Call once, early in app launch. Re-broadcasts the cross-process Darwin signal onto
  /// the in-process NotificationCenter so SwiftUI can consume it ergonomically.
  public static func startObserving() {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterAddObserver(
      center,
      nil,                              // observer ptr unused; callback is context-free
      { _, _, _, _, _ in
        NotificationCenter.default.post(name: DatabaseChangeBeacon.didChange, object: nil)
      },
      darwinName as CFString,
      nil,
      .deliverImmediately
    )
  }
}
```

Notes for the implementer:
- The Darwin callback is a C function pointer and **cannot capture context** — it must
  reference only static/global symbols. Re-broadcasting onto `NotificationCenter.default`
  (as above) is the standard bridge.
- Darwin notifications carry no payload; the signal is "something changed, re-read." That's
  all we need.
- No forced WAL checkpoint is required: the processes share the `-wal` file and the app's
  reads already see committed frames (proven by relaunch working). Leave checkpointing
  alone; just note it as a watch-item if visibility ever regresses.

### 2. Extension posts after commit

In `ShareCaptureModel.saveButtonTapped()` (`ShareViewController.swift`), after the
`database.write { ... }` returns successfully and before/after `completeRequest`, post the
beacon:

```swift
_ = try await database.write { db in
  try RecipeRepository.importCapturedRecipe(draft, in: db, now: importDate, uuid: { makeUUID() })
}
DatabaseChangeBeacon.post()
didSave = true
extensionContext?.completeRequest(returningItems: nil)
```

`database.write` returns after the transaction commits, so posting immediately after is
correct ordering.

### 3. App subscribes and reloads

- Register the observer once at launch. Add `DatabaseChangeBeacon.startObserving()` inside
  the `prepareDependencies` block / `init` of `YesChefApp` (`YesChefApp.swift`), after
  `bootstrapDatabase()`.
- Give each DB-observing model a reload entry point that re-runs its `@Fetch`/`@FetchAll`
  via the parameterless `load()`. At minimum `RecipeLibraryModel`; apply the same pattern to
  the other models owned by `AppContainer` for consistency and future-proofing:

```swift
// RecipeLibraryModel
@MainActor func reloadAfterExternalChange() async {
  try? await $recipeRows.load()
}
```

  (Models with multiple observed queries reload each one.)

- In `AppContainer` (`RecipeLibraryView.swift`, owns `recipeModel`, `browserModel`,
  `mealCalendarModel`, `menuModel`, `groceryModel` as `@State`), wire both triggers:

```swift
@Environment(\.scenePhase) private var scenePhase
// ...
.task {
  for await _ in NotificationCenter.default.notifications(named: DatabaseChangeBeacon.didChange) {
    await reloadObservingModels()
  }
}
.onChange(of: scenePhase) { _, phase in
  if phase == .active { Task { await reloadObservingModels() } }
}
```

  where `reloadObservingModels()` awaits `reloadAfterExternalChange()` on the relevant
  models. A Share import only writes the recipe graph + `recipeImportRef`, so
  `recipeModel` is mandatory; reloading the others is cheap and harmless — keep it simple.

## Scope decisions

- **In scope:** the Share Extension → app refresh path described above.
- **Out of scope / explicitly not needed:** any change to the write path, WAL config, or
  schema; a general file-watcher; reloading on every DB mutation (in-process writes already
  observe correctly).
- **Sync-safety (forward note, do not build now):** when `SyncEngine`/iCloud lands, remote
  CloudKit changes are applied by SQLiteData *within the app's own process/connection*, so
  `ValueObservation` will fire for them normally — they do **not** need this Darwin bridge.
  This effort is specifically the cross-*process* (extension) case and does not overlap with
  or pre-empt the sync work. The `reloadAfterExternalChange()` entry points are reusable but
  nothing here should be generalized toward sync yet.

## Verification

Manual (primary — this is a multi-process behavior that unit tests can't fully cover):
1. iPad, app open in the foreground (ideally Split View beside Safari). Share a recipe →
   Save. **Expect:** the new recipe animates into the library list with no relaunch.
2. iPhone/iPad, app backgrounded. Share from Safari → Save → switch back to the app.
   **Expect:** recipe present immediately (scene-activation path).
3. Confirm no duplicate insert when both triggers fire (reload is read-only, so this is just
   confirming the list shows one row).
4. Sanity: in-process create/edit/delete in the app still updates the list as before (no
   regression from the added reload paths).

Automated (where feasible):
- A `YesChefCore` unit test that `DatabaseChangeBeacon.post()` results in a
  `DatabaseChangeBeacon.didChange` NotificationCenter post when `startObserving()` is active
  (in-process round-trip; Darwin delivery is same-machine and observable in a test host).
- Existing `DatabaseStorageTests` already cover the shared-store path; no change expected.

## Open questions for the implementer to confirm

- Whether Sharing's `SharedReader`/GRDB `ValueObservation` already performs any refresh on
  app foreground. If it does, the `scenePhase` backstop is partly redundant but still
  harmless; if not (likely), it's load-bearing. Verify empirically and keep the backstop
  either way.
- Confirm `NotificationCenter.default.notifications(named:)` consumed in `AppContainer`'s
  `.task` is the cleanest subscription site, vs. an `AsyncStream` exposed from the beacon.
  Either is acceptable; prefer the one that reads most idiomatically against the
  jon-platform house style.
