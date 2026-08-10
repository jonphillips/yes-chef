import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct LearnedAreaAuditModelTests {
  @Test
  func correctionPromotesAModelPlacementToAUserPlacement() throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_300_000)
    let assignment = GroceryAreaAssignment(
      id: SampleUUIDSequence.uuid(90_301),
      canonicalName: "sumac",
      area: "Spices",
      source: .model,
      dateModified: now
    )

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try GroceryAreaAssignment.insert { assignment }.execute(db)
      }

      let model = SeedCoverageModel()

      #expect(model.correctionButtonTapped(assignment: assignment, area: "Canned & Dry"))
      #expect(model.errorMessage == nil)
      let correctedAssignments = try database.read { db in
        try GroceryAreaAssignment.fetchAll(db)
      }
      #expect(correctedAssignments.count == 1)
      let correctedAssignment = try #require(correctedAssignments.first)
      expectNoDifference(correctedAssignment.canonicalName, "sumac")
      expectNoDifference(correctedAssignment.area, "Canned & Dry")
      expectNoDifference(correctedAssignment.source, .user)
    }
  }
}
