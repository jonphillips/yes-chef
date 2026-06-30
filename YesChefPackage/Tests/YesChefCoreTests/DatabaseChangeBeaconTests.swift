import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DatabaseChangeBeaconTests {
    @Test
    func postingRebroadcastsChangeNotification() async throws {
      DatabaseChangeBeacon.startObserving()

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
        DatabaseChangeBeacon.post()

        try await group.next()
        group.cancelAll()
      }
    }
  }
}

private struct NotificationTimeout: Error {
}
