import Foundation
import SQLiteData

@Table("categories")
public struct Category: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var color: String?
  public var facetID: Facet.ID?
  public var hidden: Bool
  public var parentCategoryID: Category.ID?
  public var sortOrder: Int
  public var dateCreated: Date

  public init(
    id: UUID,
    name: String,
    color: String? = nil,
    facetID: Facet.ID? = nil,
    hidden: Bool = false,
    parentCategoryID: Category.ID? = nil,
    sortOrder: Int,
    dateCreated: Date
  ) {
    self.id = id
    self.name = name
    self.color = color
    self.facetID = facetID
    self.hidden = hidden
    self.parentCategoryID = parentCategoryID
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }
}
