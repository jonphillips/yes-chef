import Foundation
import SQLiteData

extension RecipeRepository {
  /// Updates the text of a reader-feedback note, bumping its modified date.
  /// No-op if the note is missing or is not a `.readerFeedback` note, or if the new text is blank
  /// (callers delete instead of blanking). Scoped to reader-feedback notes so it can never touch
  /// canonical general/adaptation notes.
  public static func updateReaderFeedbackNote(
    id: RecipeNote.ID,
    text: String,
    in db: Database,
    now: Date
  ) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard var note = try RecipeNote.find(id).fetchOne(db), note.noteType == .readerFeedback else {
      return
    }
    note.text = trimmed
    note.dateModified = now
    try RecipeNote.upsert { note }.execute(db)
  }

  /// Deletes a single reader-feedback note. No-op if the note is missing or is not a
  /// `.readerFeedback` note.
  public static func deleteReaderFeedbackNote(
    id: RecipeNote.ID,
    in db: Database
  ) throws {
    guard let note = try RecipeNote.find(id).fetchOne(db), note.noteType == .readerFeedback else {
      return
    }
    try RecipeNote.find(id).delete().execute(db)
  }
}
