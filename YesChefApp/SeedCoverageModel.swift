import Dependencies
import Observation
import SQLiteData
import YesChefCore

@Observable
@MainActor
final class SeedCoverageModel {
  var errorMessage: String?
  var isShowingError = false

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  func correctionButtonTapped(
    assignment: GroceryAreaAssignment,
    area: String
  ) -> Bool {
    do {
      try database.write { db in
        try GroceryStoreAreaCache.applyUserCorrection(
          canonicalName: assignment.canonicalName,
          area: area,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      errorMessage = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }
}
