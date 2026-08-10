import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct SeedCoverageReportTests {
    @Test
    func auditsOnlyPersistedModelAssignmentsInStableOrder() {
      let older = Date(timeIntervalSinceReferenceDate: 900_000_000)
      let newer = older.addingTimeInterval(1)
      let report = SeedCoverageReport.make(
        from: [
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_001),
            canonicalName: "sumac",
            area: "Spices",
            source: .model,
            dateModified: older
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_002),
            canonicalName: "harissa",
            area: "Condiments & Oils",
            source: .model,
            dateModified: older
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_003),
            canonicalName: "sumac",
            area: "Canned & Dry",
            source: .model,
            dateModified: newer
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_004),
            canonicalName: "miso",
            area: "Frozen",
            source: .user,
            dateModified: newer
          ),
        ]
      )

      expectNoDifference(
        report.modelAssignments,
        [
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_002),
            canonicalName: "harissa",
            area: "Condiments & Oils",
            source: .model,
            dateModified: older
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_003),
            canonicalName: "sumac",
            area: "Canned & Dry",
            source: .model,
            dateModified: newer
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_001),
            canonicalName: "sumac",
            area: "Spices",
            source: .model,
            dateModified: older
          ),
        ]
      )
    }

    @Test
    func separatesConfirmedModelAssignmentsFromUnreviewedAssignments() {
      let now = Date(timeIntervalSinceReferenceDate: 900_050_000)
      let report = SeedCoverageReport.make(
        from: [
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_051),
            canonicalName: "sumac",
            area: "Spices",
            source: .model,
            dateModified: now
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_052),
            canonicalName: "harissa",
            area: "Condiments & Oils",
            source: .model,
            dateModified: now,
            reviewedAt: now.addingTimeInterval(1)
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_053),
            canonicalName: "miso",
            area: "Frozen",
            source: .user,
            dateModified: now,
            reviewedAt: now.addingTimeInterval(1)
          ),
        ]
      )

      expectNoDifference(
        report.unreviewedModelAssignments.map(\.canonicalName),
        ["sumac"]
      )
      expectNoDifference(
        report.confirmedModelAssignments.map(\.canonicalName),
        ["harissa"]
      )
    }

    @Test
    func adapterReadsTheAssignmentTableNotTheDerivedIngredientCorpus() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_100_000)
      let modelAssignment = GroceryAreaAssignment(
        id: SampleUUIDSequence.uuid(90_101),
        canonicalName: "harissa",
        area: "Condiments & Oils",
        source: .model,
        dateModified: now
      )

      try database.write { db in
        try GroceryAreaAssignment.insert { modelAssignment }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_102),
            canonicalName: "sumac",
            area: "Spices",
            source: .user,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryList.insert {
          GroceryList(
            id: SampleUUIDSequence.uuid(90_103),
            title: "Shopping",
            sortOrder: 0,
            isDefault: true,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try GroceryItem.insert {
          GroceryItem(
            id: SampleUUIDSequence.uuid(90_104),
            groceryListID: SampleUUIDSequence.uuid(90_103),
            title: "Za'atar",
            canonicalName: "zaatar",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        expectNoDifference(
          try GroceryStoreAreaCache.seedCoverage(in: db).modelAssignments,
          [modelAssignment]
        )
      }
    }

    @Test
    func exportsOptionalSeedPromotionEntriesInAuditOrder() {
      let now = Date(timeIntervalSinceReferenceDate: 900_200_000)
      let entries = SeedCoverageReport.swiftLiteralEntries(
        for: [
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_201),
            canonicalName: "sumac",
            area: "Spices",
            source: .model,
            dateModified: now
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_202),
            canonicalName: "harissa",
            area: "Condiments & Oils",
            source: .model,
            dateModified: now
          ),
          GroceryAreaAssignment(
            id: SampleUUIDSequence.uuid(90_203),
            canonicalName: "miso",
            area: "Frozen",
            source: .model,
            dateModified: now.addingTimeInterval(1)
          ),
        ]
      )

      expectNoDifference(
        entries,
        "\"harissa\": .condimentsAndOils,\n\"miso\": .frozen,\n\"sumac\": .spices,"
      )
    }
  }
}
