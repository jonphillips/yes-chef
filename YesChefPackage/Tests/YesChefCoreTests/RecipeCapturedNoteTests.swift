import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeCapturedNoteTests {
    private static let recipeID = SampleUUIDSequence.uuid(1)
    private static let noteID = SampleUUIDSequence.uuid(2)
    private static let created = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seedRecipe(in db: Database) throws {
      try Recipe.insert {
        Recipe(id: Self.recipeID, title: "Soup", dateCreated: Self.created, dateModified: Self.created)
      }
      .execute(db)
    }

    @Test
    func appendWritesAGeneralNoteWithTheRenderedText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

      try database.write { db in
        try seedRecipe(in: db)
        try RecipeRepository.appendRecipeNote(
          recipeID: Self.recipeID,
          text: "Roasted Chile-Lime Cauliflower\nToss with lime, chile, roast at 450°.",
          noteType: .general,
          in: db,
          now: now,
          uuid: { Self.noteID }
        )
      }

      let notes = try database.read { db in
        try RecipeNote.fetchAll(db)
      }
      expectNoDifference(notes.map(\.id), [Self.noteID])
      expectNoDifference(notes.first?.text, "Roasted Chile-Lime Cauliflower\nToss with lime, chile, roast at 450°.")
      expectNoDifference(notes.first?.noteType, .general)
      expectNoDifference(notes.first?.dateCreated, now)
      expectNoDifference(notes.first?.dateModified, now)
    }

    @Test
    func appendTrimsAndSkipsBlankText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

      let inserted: RecipeNote? = try database.write { db in
        try seedRecipe(in: db)
        let blank = try RecipeRepository.appendRecipeNote(
          recipeID: Self.recipeID,
          text: "   \n  ",
          noteType: .general,
          in: db,
          now: now,
          uuid: { Self.noteID }
        )
        return blank
      }

      expectNoDifference(inserted, nil)
      let remaining = try database.read { db in
        try RecipeNote.fetchAll(db)
      }
      expectNoDifference(remaining.isEmpty, true)
    }
  }
}
