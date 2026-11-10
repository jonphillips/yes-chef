import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeDetailRowNoteTests {
  @Test
  func observesTheOpeningMenuRowNoteButNotALibraryNote() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 841_200_000)
    let recipeID = SampleUUIDSequence.uuid(62_101)
    let menuID = SampleUUIDSequence.uuid(62_102)
    let menuItemID = SampleUUIDSequence.uuid(62_103)

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Souvlaki", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Menu.insert {
          Menu(id: menuID, title: "Mediterranean Dinner", dayCount: 1, dateCreated: now, dateModified: now)
        }
        .execute(db)
        try MenuItem.insert {
          MenuItem(
            id: menuItemID,
            menuID: menuID,
            kind: .recipe,
            recipeID: recipeID,
            title: "Souvlaki",
            dayOffset: 0,
            mealSlot: .dinner,
            notes: "Serve the tahini-butter sauce on the side.",
            sortOrder: 0,
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
      }

      let menuModel = RecipeDetailModel(recipeID: recipeID, scaleContext: .menuItem(menuItemID))
      try await menuModel.$rowNote.load()
      expectNoDifference(
        menuModel.rowNote,
        RecipeRowNote(
          text: "Serve the tahini-butter sauce on the side.",
          origin: .menu(title: "Mediterranean Dinner")
        )
      )

      let libraryModel = RecipeDetailModel(recipeID: recipeID)
      try await libraryModel.$rowNote.load()
      #expect(libraryModel.rowNote == nil)
    }
  }
}
