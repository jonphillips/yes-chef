import Foundation
import SQLiteData

extension RecipeRepository {
  /// Appends a chat-committed `RecipeNote` to a recipe.
  ///
  /// The shared write primitive for the two chat verbs that deposit intelligence onto a recipe as a
  /// note, never touching the canonical recipe body:
  /// - ADR-0027 S2 "Capture to notes" — a harvested note (`.general`).
  /// - ADR-0027 Amendment 1 S1 "Add to recipe notes" — deposited adaptation intelligence
  ///   (`.adaptation`), pointed at a recipe-kind menu item.
  ///
  /// The caller renders the note's text (title + body, or a single body) before writing. A captured
  /// note surfaces in the recipe's visible notes. No-op on blank text.
  @discardableResult
  public static func appendRecipeNote(
    recipeID: Recipe.ID,
    text: String,
    noteType: RecipeNoteType = .general,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> RecipeNote? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let note = RecipeNote(
      id: uuid(),
      recipeID: recipeID,
      text: trimmed,
      noteType: noteType,
      dateCreated: now,
      dateModified: now
    )
    try RecipeNote.upsert { note }.execute(db)
    return note
  }
}
