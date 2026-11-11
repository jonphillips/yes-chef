import Foundation
import SQLiteData

public enum GroceryTrip: String, CaseIterable, Codable, Hashable, QueryBindable, QueryDecodable, Sendable {
  case advance
  case fresh

  public var title: String {
    switch self {
    case .advance: "Advance"
    case .fresh: "Fresh"
    }
  }

  public var other: Self { self == .advance ? .fresh : .advance }
}

@Table("groceryTripAssignments")
public struct GroceryTripAssignment: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var canonicalName: String
  public var trip: GroceryTrip
  public var dateModified: Date

  public init(id: UUID, canonicalName: String, trip: GroceryTrip, dateModified: Date) {
    self.id = id
    self.canonicalName = canonicalName
    self.trip = trip
    self.dateModified = dateModified
  }
}

public enum GroceryTripRule {
  private static let keepers: Set<String> = [
    "onion", "garlic", "shallot", "potato", "sweet potato", "yam", "carrot", "celery", "beet",
    "parsnip", "turnip", "rutabaga", "cabbage", "ginger", "lemon", "lime", "orange", "apple",
    "cranberry", "butternut squash", "acorn squash", "kabocha squash", "delicata squash",
    "spaghetti squash", "pumpkin",
  ]

  private static let advanceAreas: Set<String> = [
    "Canned & Dry", "Condiments & Oils", "Spices", "Baking", "Beverages", "Dairy", "Frozen", "Household",
  ]

  public static func defaultTrip(canonicalName: String, area: String?) -> GroceryTrip {
    let name = CanonicalIngredient.canonicalName(canonicalName) ?? canonicalName
    let lastWord = name.split(separator: " ").last.map(String.init) ?? name
    let isOnionThatWilts = ["green onion", "green onions", "spring onion", "spring onions"].contains(name)
    if !isOnionThatWilts && (keepers.contains(name) || keepers.contains(lastWord)) { return .advance }
    if let area, advanceAreas.contains(area) { return .advance }
    return .fresh
  }
}

public enum GroceryTripRepository {
  public static func trips(forCanonicalNames names: [String], in db: Database) throws -> [String: GroceryTrip] {
    let normalizedNames = Set(names.compactMap(CanonicalIngredient.canonicalName))
    let saved = try GroceryTripAssignment.fetchAll(db).filter { normalizedNames.contains($0.canonicalName) }
    var savedByName: [String: GroceryTripAssignment] = [:]
    for assignment in saved {
      if let existing = savedByName[assignment.canonicalName], existing.dateModified > assignment.dateModified { continue }
      savedByName[assignment.canonicalName] = assignment
    }
    let areas = try GroceryStoreAreaCache.resolvedAreas(for: Array(normalizedNames), in: db)
    return Dictionary(uniqueKeysWithValues: normalizedNames.map { name in
      (name, savedByName[name]?.trip ?? GroceryTripRule.defaultTrip(canonicalName: name, area: areas[name]?.title))
    })
  }

  public static func recordSwitches(_ trips: [String: GroceryTrip], in db: Database, now: Date) throws {
    for (name, trip) in trips {
      guard let canonicalName = CanonicalIngredient.canonicalName(name) else { continue }
      try GroceryTripAssignment.upsert {
        GroceryTripAssignment(
          id: DeterministicID.groceryTrip(canonicalName: canonicalName),
          canonicalName: canonicalName,
          trip: trip,
          dateModified: now
        )
      }.execute(db)
    }
  }
}
