import Foundation
import SQLiteData

/// Presence of this deterministic record permanently suppresses re-seeding its matching category.
@Table("categorySeedTombstones")
public struct CategorySeedTombstone: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var dateDeleted: Date

  public init(id: UUID, dateDeleted: Date) {
    self.id = id
    self.dateDeleted = dateDeleted
  }
}
