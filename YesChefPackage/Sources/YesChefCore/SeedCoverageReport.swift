import Foundation
import SQLiteData

/// The read-only, derived review queue for canonical grocery names that do not have
/// a deterministic store-area seed.
public struct SeedCoverageReport: Equatable, Sendable {
  public struct Gap: Equatable, Sendable, Identifiable {
    public var canonicalName: String
    public var occurrences: Int
    public var suggestedArea: GroceryStoreArea?

    public var id: String { canonicalName }

    public init(
      canonicalName: String,
      occurrences: Int,
      suggestedArea: GroceryStoreArea?
    ) {
      self.canonicalName = canonicalName
      self.occurrences = occurrences
      self.suggestedArea = suggestedArea
    }
  }

  public var uncovered: [Gap]
  public var coveredElsewhere: [Gap]

  public init(uncovered: [Gap] = [], coveredElsewhere: [Gap] = []) {
    self.uncovered = uncovered
    self.coveredElsewhere = coveredElsewhere
  }

  /// Folds durable observations into the deterministic-seed review queue. An aisle
  /// on any occurrence puts a name in `coveredElsewhere`; otherwise it is uncovered.
  public static func make(from observations: [(canonicalName: String?, aisle: String?)]) -> Self {
    struct Coverage {
      var occurrences = 0
      var areaOccurrences: [GroceryStoreArea: Int] = [:]
    }

    var coverageByCanonicalName: [String: Coverage] = [:]
    for observation in observations {
      guard let canonicalName = CanonicalIngredient.canonicalName(observation.canonicalName) else { continue }

      var coverage = coverageByCanonicalName[canonicalName, default: Coverage()]
      coverage.occurrences += 1
      if let area = GroceryStoreArea.normalized(observation.aisle) {
        coverage.areaOccurrences[area, default: 0] += 1
      }
      coverageByCanonicalName[canonicalName] = coverage
    }

    var uncovered: [Gap] = []
    var coveredElsewhere: [Gap] = []
    for (canonicalName, coverage) in coverageByCanonicalName where GroceryStoreArea.seed(for: canonicalName) == nil {
      if let suggestedArea = mostCommonArea(in: coverage.areaOccurrences) {
        coveredElsewhere.append(
          Gap(
            canonicalName: canonicalName,
            occurrences: coverage.occurrences,
            suggestedArea: suggestedArea
          )
        )
      } else {
        uncovered.append(
          Gap(
            canonicalName: canonicalName,
            occurrences: coverage.occurrences,
            suggestedArea: nil
          )
        )
      }
    }

    return Self(
      uncovered: sorted(uncovered),
      coveredElsewhere: sorted(coveredElsewhere)
    )
  }

  /// Produces paste-ready entries for `GroceryStoreArea.seedAreas` in review-priority order.
  public static func swiftLiteralEntries(for gaps: [Gap]) -> String {
    sorted(gaps)
      .map { gap in
        let area = gap.suggestedArea?.swiftLiteral ?? ".other"
        return "\(gap.canonicalName.debugDescription): \(area),"
      }
      .joined(separator: "\n")
  }

  private static func mostCommonArea(in occurrences: [GroceryStoreArea: Int]) -> GroceryStoreArea? {
    occurrences.max { lhs, rhs in
      if lhs.value != rhs.value {
        return lhs.value < rhs.value
      }
      return lhs.key.title > rhs.key.title
    }?.key
  }

  private static func sorted(_ gaps: [Gap]) -> [Gap] {
    gaps.sorted { lhs, rhs in
      if lhs.occurrences != rhs.occurrences {
        return lhs.occurrences > rhs.occurrences
      }
      return lhs.canonicalName < rhs.canonicalName
    }
  }
}

public extension GroceryStoreAreaCache {
  static func seedCoverage(in db: Database) throws -> SeedCoverageReport {
    let ingredientObservations = try IngredientLine.fetchAll(db).map {
      (canonicalName: $0.canonicalIngredientName, aisle: $0.shoppingCategory)
    }
    let groceryObservations = try GroceryItem.fetchAll(db).map {
      (canonicalName: $0.canonicalIngredientName, aisle: $0.aisle)
    }
    return SeedCoverageReport.make(from: ingredientObservations + groceryObservations)
  }
}

private extension GroceryStoreArea {
  var swiftLiteral: String {
    switch self {
    case .produce: ".produce"
    case .bakery: ".bakery"
    case .deli: ".deli"
    case .cannedAndDry: ".cannedAndDry"
    case .condimentsAndOils: ".condimentsAndOils"
    case .spices: ".spices"
    case .baking: ".baking"
    case .beverages: ".beverages"
    case .meatAndSeafood: ".meatAndSeafood"
    case .household: ".household"
    case .dairy: ".dairy"
    case .frozen: ".frozen"
    case .other: ".other"
    case let .custom(title): ".custom(\(title.debugDescription))"
    }
  }
}
