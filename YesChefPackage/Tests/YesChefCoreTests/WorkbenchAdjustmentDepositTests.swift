import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchAdjustmentDepositTests {
    @Test
    func committedAdjustmentRationaleDepositsOnlyOnItsWorkingRecipeWorkbench() throws {
      @Dependency(\.defaultDatabase) var database
      let recipeID = SampleUUIDSequence.uuid(21_400)
      let workbenchID = SampleUUIDSequence.uuid(21_401)
      let unrelatedWorkbenchID = SampleUUIDSequence.uuid(21_402)
      let now = Date(timeIntervalSinceReferenceDate: 806_255_000)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Brown Butter Cookies",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try Workbench.insert {
          Workbench(
            id: workbenchID,
            title: "Cookies",
            draftRecipeID: recipeID,
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try Workbench.insert {
          Workbench(
            id: unrelatedWorkbenchID,
            title: "Cakes",
            sortOrder: 1,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)

        let entryID = try #require(
          try WorkbenchRepository.addRationaleForCommittedAdjustment(
            recipeID: recipeID,
            rationale: "Use browned butter for a deeper flavor.",
            in: db,
            now: now,
            uuid: { SampleUUIDSequence.uuid(21_403) }
          )
        )

        expectNoDifference(
          try WorkbenchLogEntry.find(entryID).fetchOne(db),
          WorkbenchLogEntry(
            id: entryID,
            workbenchID: workbenchID,
            kind: .rationale,
            body: "Use browned butter for a deeper flavor.",
            relatedRecipeID: recipeID,
            sortOrder: 0,
            dateCreated: now
          )
        )
        #expect(
          try WorkbenchLogEntry
            .where { $0.workbenchID.eq(unrelatedWorkbenchID) }
            .fetchAll(db)
            .isEmpty
        )
      }
    }
  }
}
