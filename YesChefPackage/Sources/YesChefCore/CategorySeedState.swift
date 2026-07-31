import Foundation
import SQLiteData

/// Synced mapping from a fixed starter seed to the category that currently represents it.
///
/// `isDeleted` and `dateModified` are retained only to migrate libraries that may have opened
/// the first S2 dogfood schema. Tombstones, not these legacy fields, decide current deletion.
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
