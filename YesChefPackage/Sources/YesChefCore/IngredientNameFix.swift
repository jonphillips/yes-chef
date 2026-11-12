import Foundation
import SQLiteData

@Table("ingredientNameFixes")
public struct IngredientNameFix: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var fromName: String
  public var toName: String
  public var dateModified: Date

  public init(id: UUID, fromName: String, toName: String, dateModified: Date) {
    self.id = id
    self.fromName = fromName
    self.toName = toName
    self.dateModified = dateModified
  }
}

/// A per-operation snapshot of the user's ingredient name fixes.
public struct IngredientNameFixes: Equatable, Sendable {
  private var targetsByName: [String: String]

  public static let empty = IngredientNameFixes(rows: [])

  public init(rows: [IngredientNameFix]) {
    targetsByName = Dictionary(rows.map { ($0.fromName, $0.toName) }, uniquingKeysWith: { _, latest in latest })
  }

  public static func load(in db: Database) throws -> Self {
    Self(rows: try IngredientNameFix.fetchAll(db))
  }

  public func canonicalName(_ text: String?) -> String? {
    guard let baseName = CanonicalIngredient.baseName(text) else { return nil }
    return resolve(baseName)
  }

  public func comparisonKey(_ text: String?) -> String? {
    guard let key = CanonicalIngredient.comparisonKey(text) else { return nil }
    return resolve(key)
  }

  public func displayName(_ text: String) -> String {
    let baseKey = CanonicalIngredient.baseName(text)
    let display = CanonicalIngredient.displayName(text)
    guard let baseKey else { return display }
    let fixedName = resolve(baseKey)
    return fixedName == baseKey ? display : fixedName
  }

  private func resolve(_ name: String) -> String {
    var current = name
    var seen: Set<String> = []
    while seen.insert(current).inserted, let next = targetsByName[current] {
      current = next
    }
    return current
  }
}

public enum IngredientNameFixRepository {
  /// Saves a one-hop fix, flattening existing inbound and outbound links in the same transaction.
  @discardableResult
  public static func save(from: String, to: String, in db: Database, now: Date) throws -> Bool {
    guard let fromName = CanonicalIngredient.baseName(from),
          let requestedTarget = CanonicalIngredient.baseName(to)
    else { return false }

    let rows = try IngredientNameFix.fetchAll(db)
    guard fromName != requestedTarget else { return false }

    let reverseRows = rows.filter { $0.fromName == requestedTarget && $0.toName == fromName }
    for reverse in reverseRows {
      try IngredientNameFix.find(reverse.id).delete().execute(db)
    }
    let rowsWithoutReverse = rows.filter { reverse in !reverseRows.contains(where: { $0.id == reverse.id }) }
    let fixes = IngredientNameFixes(rows: rowsWithoutReverse)
    let toName = fixes.canonicalName(requestedTarget) ?? requestedTarget
    guard fromName != toName else { return false }

    for var row in rowsWithoutReverse where row.fromName != fromName && row.fromName != toName && row.toName == fromName {
      row.toName = toName
      row.dateModified = now
      try IngredientNameFix.upsert { row }.execute(db)
    }

    try IngredientNameFix.upsert {
      IngredientNameFix(
        id: DeterministicID.ingredientNameFix(fromName: fromName),
        fromName: fromName,
        toName: toName,
        dateModified: now
      )
    }.execute(db)
    return true
  }

  public static func delete(fromName: String, in db: Database) throws {
    let normalizedName = CanonicalIngredient.baseName(fromName) ?? fromName
    let id = DeterministicID.ingredientNameFix(fromName: normalizedName)
    try IngredientNameFix.find(id).delete().execute(db)
  }
}

public struct IngredientNameFixListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [IngredientNameFix] {
    try IngredientNameFix.fetchAll(db).sorted { $0.fromName < $1.fromName }
  }
}
