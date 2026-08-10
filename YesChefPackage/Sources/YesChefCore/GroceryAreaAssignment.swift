import Foundation
import SQLiteData

@Table("groceryAreaAssignments")
public struct GroceryAreaAssignment: Codable, Identifiable, Equatable, Sendable {
  public enum Source: String, Codable, QueryBindable, QueryDecodable, Sendable {
    case model
    case user
  }

  public let id: UUID
  public var canonicalName: String
  public var area: String
  public var source: Source
  public var reviewedAt: Date?
  public var dateModified: Date

  public init(
    id: UUID,
    canonicalName: String,
    area: String,
    source: Source,
    dateModified: Date,
    reviewedAt: Date? = nil
  ) {
    self.id = id
    self.canonicalName = canonicalName
    self.area = area
    self.source = source
    self.reviewedAt = reviewedAt
    self.dateModified = dateModified
  }
}
