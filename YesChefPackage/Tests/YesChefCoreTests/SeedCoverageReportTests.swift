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
    func excludesSeedHitsAndSeparatesUncoveredFromCoveredElsewhere() {
      let report = SeedCoverageReport.make(
        from: [
          (canonicalName: "Milk", aisle: "Dairy"),
          (canonicalName: "sumac", aisle: nil),
          (canonicalName: "harissa", aisle: "Condiments & Oils"),
          (canonicalName: "harissa", aisle: nil),
        ]
      )

      expectNoDifference(
        report.uncovered,
        [
          .init(canonicalName: "sumac", occurrences: 1, suggestedArea: nil),
        ]
      )
      expectNoDifference(
        report.coveredElsewhere,
        [
          .init(canonicalName: "harissa", occurrences: 2, suggestedArea: .condimentsAndOils),
        ]
      )
    }

    @Test
    func foldsCanonicalNamesCountsAndSortsByPriority() {
      let report = SeedCoverageReport.make(
        from: [
          (canonicalName: " Zaatars ", aisle: nil),
          (canonicalName: "ZAATAR", aisle: nil),
          (canonicalName: "sumac", aisle: nil),
          (canonicalName: "harissa", aisle: "Spices"),
          (canonicalName: "Harissas", aisle: "Condiments & Oils"),
          (canonicalName: "harissa", aisle: "Spices"),
        ]
      )

      expectNoDifference(
        report.uncovered,
        [
          .init(canonicalName: "zaatar", occurrences: 2, suggestedArea: nil),
          .init(canonicalName: "sumac", occurrences: 1, suggestedArea: nil),
        ]
      )
      expectNoDifference(
        report.coveredElsewhere,
        [
          .init(canonicalName: "harissa", occurrences: 3, suggestedArea: .spices),
        ]
      )
    }

    @Test
    func anyStoredAisleWinsTheSplitAndUsesADeterministicSuggestedAreaTieBreak() {
      let report = SeedCoverageReport.make(
        from: [
          (canonicalName: "gochujang", aisle: nil),
          (canonicalName: "gochujang", aisle: "Spices"),
          (canonicalName: "gochujang", aisle: "Condiments & Oils"),
        ]
      )

      expectNoDifference(report.uncovered, [])
      expectNoDifference(
        report.coveredElsewhere,
        [
          .init(canonicalName: "gochujang", occurrences: 3, suggestedArea: .condimentsAndOils),
        ]
      )
    }

    @Test
    func exportsSortedPasteReadySwiftLiteralEntries() {
      let entries = SeedCoverageReport.swiftLiteralEntries(
        for: [
          .init(canonicalName: "sumac", occurrences: 1, suggestedArea: nil),
          .init(canonicalName: "harissa", occurrences: 2, suggestedArea: .condimentsAndOils),
          .init(canonicalName: "zucchini blossom", occurrences: 2, suggestedArea: .custom("Flower Market")),
        ]
      )

      expectNoDifference(
        entries,
        "\"harissa\": .condimentsAndOils,\n\"zucchini blossom\": .custom(\"Flower Market\"),\n\"sumac\": .other,"
      )
    }

    @Test
    func gathersIngredientLinesAndGroceryItemsWithoutWriting() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_000_000)
      let recipeID = SampleUUIDSequence.uuid(90_001)
      let sectionID = SampleUUIDSequence.uuid(90_002)
      let listID = SampleUUIDSequence.uuid(90_003)

      try database.write { db in
        try insertRecipeFixture(
          recipeID: recipeID,
          sectionID: sectionID,
          title: "Harissa dinner",
          lines: [
            IngredientLine(
              id: SampleUUIDSequence.uuid(90_004),
              recipeID: recipeID,
              sectionID: sectionID,
              originalText: "harissa",
              canonicalName: "harissa",
              shoppingCategory: "Condiments & Oils",
              sortOrder: 0
            ),
          ],
          now: now,
          in: db
        )
        try GroceryList.insert {
          GroceryList(
            id: listID,
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
            id: SampleUUIDSequence.uuid(90_005),
            groceryListID: listID,
            title: "sumac",
            canonicalName: "sumac",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        expectNoDifference(
          try GroceryStoreAreaCache.seedCoverage(in: db),
          SeedCoverageReport(
            uncovered: [
              .init(canonicalName: "sumac", occurrences: 1, suggestedArea: nil),
            ],
            coveredElsewhere: [
              .init(canonicalName: "harissa", occurrences: 1, suggestedArea: .condimentsAndOils),
            ]
          )
        )
      }
    }
  }
}
