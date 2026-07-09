import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct ReaderFeedbackNoteEditingTests {
    private static let recipeID = SampleUUIDSequence.uuid(1)
    private static let readerFeedbackNoteID = SampleUUIDSequence.uuid(2)
    private static let generalNoteID = SampleUUIDSequence.uuid(3)
    private static let created = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func seed(in db: Database) throws {
      try Recipe.insert {
        Recipe(id: Self.recipeID, title: "Soup", dateCreated: Self.created, dateModified: Self.created)
      }
      .execute(db)
      try RecipeNote.insert {
        RecipeNote(
          id: Self.readerFeedbackNoteID,
          recipeID: Self.recipeID,
          text: "Salt the cukes.",
          noteType: .readerFeedback,
          dateCreated: Self.created,
          dateModified: Self.created
        )
      }
      .execute(db)
      try RecipeNote.insert {
        RecipeNote(
          id: Self.generalNoteID,
          recipeID: Self.recipeID,
          text: "My own note.",
          noteType: .general,
          dateCreated: Self.created,
          dateModified: Self.created
        )
      }
      .execute(db)
    }

    @Test
    func updateChangesTextAndModifiedDateForReaderFeedbackOnly() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

      try database.write { db in
        try seed(in: db)
        try RecipeRepository.updateReaderFeedbackNote(
          id: Self.readerFeedbackNoteID,
          text: "  Salt AND drain the cukes.  ",
          in: db,
          now: now
        )
      }

      let updated = try database.read { db in
        try RecipeNote.find(Self.readerFeedbackNoteID).fetchOne(db)
      }
      expectNoDifference(updated?.text, "Salt AND drain the cukes.")
      expectNoDifference(updated?.dateModified, now)
      expectNoDifference(updated?.noteType, .readerFeedback)
    }

    @Test
    func updateIsScopedToReaderFeedbackAndSkipsBlankText() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 810_000_000)

      try database.write { db in
        try seed(in: db)
        // Wrong note type: no-op.
        try RecipeRepository.updateReaderFeedbackNote(
          id: Self.generalNoteID,
          text: "hijacked",
          in: db,
          now: now
        )
        // Blank text: no-op (callers delete instead of blanking).
        try RecipeRepository.updateReaderFeedbackNote(
          id: Self.readerFeedbackNoteID,
          text: "   ",
          in: db,
          now: now
        )
      }

      let notes = try database.read { db in
        try RecipeNote.fetchAll(db).sorted { $0.dateCreated < $1.dateCreated }
      }
      expectNoDifference(notes.map(\.text), ["Salt the cukes.", "My own note."])
      expectNoDifference(notes.map(\.dateModified), [Self.created, Self.created])
    }

    @Test
    func deleteRemovesOnlyTheTargetedReaderFeedbackNote() throws {
      @Dependency(\.defaultDatabase) var database

      try database.write { db in
        try seed(in: db)
        // Wrong note type: no-op.
        try RecipeRepository.deleteReaderFeedbackNote(id: Self.generalNoteID, in: db)
        try RecipeRepository.deleteReaderFeedbackNote(id: Self.readerFeedbackNoteID, in: db)
      }

      let remaining = try database.read { db in
        try RecipeNote.fetchAll(db)
      }
      expectNoDifference(remaining.map(\.id), [Self.generalNoteID])
    }
  }
}
