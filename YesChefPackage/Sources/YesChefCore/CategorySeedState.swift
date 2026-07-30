import Foundation
import SQLiteData

/// Synced installation and deletion state for a fixed starter category. This intentionally has no
/// foreign key so a deletion tombstone can outlive the category it prevents from being re-seeded.
@Table("categorySeedStates")
public struct CategorySeedState: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var categoryID: Category.ID?
  public var isDeleted: Bool
  public var dateModified: Date

  public init(
    id: UUID,
    categoryID: Category.ID? = nil,
    isDeleted: Bool = false,
    dateModified: Date
  ) {
    self.id = id
    self.categoryID = categoryID
    self.isDeleted = isDeleted
    self.dateModified = dateModified
  }
}
