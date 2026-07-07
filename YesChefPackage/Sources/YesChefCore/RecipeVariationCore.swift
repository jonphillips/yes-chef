import Foundation
import SQLiteData

@Table("recipeVariations")
public struct RecipeVariation: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var name: String
  public var note: String?
  public var sortIndex: Int
  public var deltas: Data?
  public var origin: RecipeVariationOrigin?
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    name: String,
    note: String? = nil,
    sortIndex: Int,
    deltas: Data? = nil,
    origin: RecipeVariationOrigin? = nil,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.name = name
    self.note = note
    self.sortIndex = sortIndex
    self.deltas = deltas
    self.origin = origin
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

public enum RecipeVariationOrigin: String, Codable, QueryBindable, QueryDecodable, Sendable {
  case hand
  case chat
  case experiment
}

@Table("recipeActiveVariations")
public struct RecipeActiveVariation: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var recipeID: Recipe.ID
  public var variationID: RecipeVariation.ID
  public var dateModified: Date

  public init(
    id: UUID,
    recipeID: Recipe.ID,
    variationID: RecipeVariation.ID,
    dateModified: Date
  ) {
    self.id = id
    self.recipeID = recipeID
    self.variationID = variationID
    self.dateModified = dateModified
  }
}

extension RecipeRepository {
  public static func fetchDetailApplyingActiveVariation(
    recipeID: Recipe.ID,
    in db: Database
  ) throws -> (detail: RecipeDetailData, variation: RecipeVariation?)? {
    guard let detail = try fetchDetail(recipeID: recipeID, in: db) else { return nil }
    guard let variation = detail.activeVariation else {
      return (detail, nil)
    }
    return (try detail.resolved(applying: variation), variation)
  }
}
