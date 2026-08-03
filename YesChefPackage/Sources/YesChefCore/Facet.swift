import Foundation
import SQLiteData

@Table("facets")
public struct Facet: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var sortOrder: Int
  public var hidden: Bool
  public var dateCreated: Date

  public init(
    id: UUID,
    name: String,
    sortOrder: Int,
    hidden: Bool = false,
    dateCreated: Date
  ) {
    self.id = id
    self.name = name
    self.sortOrder = sortOrder
    self.hidden = hidden
    self.dateCreated = dateCreated
  }
}
