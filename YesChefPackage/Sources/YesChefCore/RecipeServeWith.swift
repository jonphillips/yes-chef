import Foundation
import SQLiteData

@Table("recipeServeWith")
public struct RecipeServeWith: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var title: String
  public var note: String?
  public var sortOrder: Int
  public var provenance: ServeWithProvenance
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    title: String,
    note: String? = nil,
    sortOrder: Int,
    provenance: ServeWithProvenance,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.title = title
    self.note = note
    self.sortOrder = sortOrder
    self.provenance = provenance
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }

  public var item: ServeWithItem {
    ServeWithItem(id: id, title: title, note: note)
  }
}

public enum ServeWithProvenance: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case model
  case handAuthored
}
