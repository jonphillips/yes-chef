import Foundation
import SQLiteData

@Table("recipeDeliberationLog")
public struct RecipeDeliberationLogEntry: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var variationID: RecipeVariation.ID?
  public var body: String
  public var dateCreated: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    variationID: RecipeVariation.ID? = nil,
    body: String,
    dateCreated: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.variationID = variationID
    self.body = body
    self.dateCreated = dateCreated
  }
}

extension RecipeRepository {
  public static func addDeliberationLogEntry(
    body: String?,
    recipeID: Recipe.ID,
    variationID: RecipeVariation.ID? = nil,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard let body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    try RecipeDeliberationLogEntry.insert {
      RecipeDeliberationLogEntry(
        id: uuid(),
        recipeID: recipeID,
        variationID: variationID,
        body: body,
        dateCreated: now
      )
    }
    .execute(db)
  }
}
