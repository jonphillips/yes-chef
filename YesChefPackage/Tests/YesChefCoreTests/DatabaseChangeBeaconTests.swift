import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DatabaseChangeBeaconTests {
    @Test
    func notificationNameIncludesConfiguredAppGroupAndReleaseNameIsStable() {
      #expect(
        DatabaseChangeBeacon.notificationName(appGroupIdentifier: "group.example.dev")
          == "group.example.dev.databaseDidChange"
      )
      #expect(
        DatabaseChangeBeacon.notificationName(appGroupIdentifier: "group.com.jonphillips.yeschef")
          == "group.com.jonphillips.yeschef.databaseDidChange"
      )
    }

    @Test
    func postingRebroadcastsChangeNotification() async throws {
      let appGroupIdentifier = "group.com.jonphillips.yeschef"
      DatabaseChangeBeacon.startObserving(appGroupIdentifier: appGroupIdentifier)

      let notifications = NotificationCenter.default.notifications(named: DatabaseChangeBeacon.didChange)
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          for await _ in notifications {
            return
          }
        }
        group.addTask {
          try await Task.sleep(for: .seconds(2))
          throw NotificationTimeout()
        }

        await Task.yield()
        DatabaseChangeBeacon.post(appGroupIdentifier: appGroupIdentifier)

        try await group.next()
        group.cancelAll()
      }
    }
  }
}

private struct NotificationTimeout: Error {
}
