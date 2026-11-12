import Foundation
import SQLiteData

/// The read-only audit of grocery placements the classifier learned on its own.
public struct SeedCoverageReport: Equatable, Sendable {
  public var unreviewedModelAssignments: [GroceryAreaAssignment]
  public var confirmedModelAssignments: [GroceryAreaAssignment]

  public init(
    unreviewedModelAssignments: [GroceryAreaAssignment] = [],
    confirmedModelAssignments: [GroceryAreaAssignment] = []
  ) {
    self.unreviewedModelAssignments = unreviewedModelAssignments
    self.confirmedModelAssignments = confirmedModelAssignments
  }

  public var modelAssignments: [GroceryAreaAssignment] {
    unreviewedModelAssignments + confirmedModelAssignments
  }

  /// Keeps the audit tied to persisted learned rows, rather than deriving another
  /// queue from recipe and grocery-item history.
  public static func make(from assignments: [GroceryAreaAssignment]) -> Self {
    let modelAssignments = assignments
      .filter { $0.source == .model }
      .sorted(by: areModelAssignmentsInAuditOrder)
    return Self(
      unreviewedModelAssignments: modelAssignments.filter { $0.reviewedAt == nil },
      confirmedModelAssignments: modelAssignments.filter { $0.reviewedAt != nil }
    )
  }


}

public struct SeedCoverageReportRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> SeedCoverageReport {
    SeedCoverageReport.make(from: try GroceryAreaAssignment.fetchAll(db))
  }
}

public extension GroceryStoreAreaCache {
  static func seedCoverage(in db: Database) throws -> SeedCoverageReport {
    try SeedCoverageReportRequest().fetch(db)
  }
}

private func areModelAssignmentsInAuditOrder(
  _ lhs: GroceryAreaAssignment,
  _ rhs: GroceryAreaAssignment
) -> Bool {
  if lhs.canonicalName != rhs.canonicalName {
    return lhs.canonicalName < rhs.canonicalName
  }
  if lhs.dateModified != rhs.dateModified {
    return lhs.dateModified > rhs.dateModified
  }
  return lhs.id.uuidString < rhs.id.uuidString
}
