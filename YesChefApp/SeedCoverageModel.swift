import Dependencies
import Observation
import SQLiteData
import YesChefCore

@Observable
@MainActor
final class SeedCoverageModel {
  private(set) var report = SeedCoverageReport()
  private(set) var errorMessage: String?

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  func refresh() async {
    do {
      report = try await database.read { db in
        try GroceryStoreAreaCache.seedCoverage(in: db)
      }
      errorMessage = nil
    } catch is CancellationError {
      // SwiftUI cancels this view's refresh task when the pane disappears.
    } catch {
      errorMessage = String(describing: error)
    }
  }
}
