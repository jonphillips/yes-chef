import Foundation

public struct Measure: Equatable, Sendable {
  public enum Dimension: Equatable, Sendable {
    case volume
    case weight
    case count
  }

  public enum Comparison: Equatable, Sendable {
    case over
    case underOrEqual
    case incomparable
  }

  public var quantity: Double
  public var unit: String?

  public init(quantity: Double, unit: String? = nil) {
    self.quantity = quantity
    self.unit = unit
  }

  public var dimension: Dimension? {
    Self.unitDefinition(for: unit)?.dimension
  }

  public func merged(with other: Measure) -> Measure? {
    if Self.normalizedUnit(unit) == Self.normalizedUnit(other.unit) {
      return Measure(quantity: quantity + other.quantity, unit: unit)
    }

    guard let lhsDefinition = Self.unitDefinition(for: unit),
          let rhsDefinition = Self.unitDefinition(for: other.unit),
          lhsDefinition.dimension == rhsDefinition.dimension
    else { return nil }

    let lhsBaseQuantity = quantity * lhsDefinition.factor
    let rhsBaseQuantity = other.quantity * rhsDefinition.factor
    return Measure(
      quantity: (lhsBaseQuantity + rhsBaseQuantity) / lhsDefinition.factor,
      unit: unit
    )
  }

  public func compare(to threshold: Measure) -> Comparison {
    if Self.normalizedUnit(unit) == Self.normalizedUnit(threshold.unit) {
      return quantity > threshold.quantity ? .over : .underOrEqual
    }

    guard let lhsDefinition = Self.unitDefinition(for: unit),
          let rhsDefinition = Self.unitDefinition(for: threshold.unit),
          lhsDefinition.dimension == rhsDefinition.dimension
    else { return .incomparable }

    let lhsBaseQuantity = quantity * lhsDefinition.factor
    let rhsBaseQuantity = threshold.quantity * rhsDefinition.factor
    return lhsBaseQuantity > rhsBaseQuantity ? .over : .underOrEqual
  }

  private struct UnitDefinition: Equatable {
    var dimension: Dimension
    var factor: Double
  }

  private static func unitDefinition(for unit: String?) -> UnitDefinition? {
    guard let unit = normalizedUnit(unit) else {
      return UnitDefinition(dimension: .count, factor: 1)
    }
    return unitDefinitions[unit]
  }

  private static func normalizedUnit(_ unit: String?) -> String? {
    guard let unit else { return nil }
    let normalized = unit
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .replacingOccurrences(of: ".", with: "")
      .replacingOccurrences(of: "-", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private static let unitDefinitions: [String: UnitDefinition] = [
    "teaspoon": UnitDefinition(dimension: .volume, factor: 1),
    "teaspoons": UnitDefinition(dimension: .volume, factor: 1),
    "tsp": UnitDefinition(dimension: .volume, factor: 1),
    "tablespoon": UnitDefinition(dimension: .volume, factor: 3),
    "tablespoons": UnitDefinition(dimension: .volume, factor: 3),
    "tbsp": UnitDefinition(dimension: .volume, factor: 3),
    "fluid ounce": UnitDefinition(dimension: .volume, factor: 6),
    "fluid ounces": UnitDefinition(dimension: .volume, factor: 6),
    "fl oz": UnitDefinition(dimension: .volume, factor: 6),
    "cup": UnitDefinition(dimension: .volume, factor: 48),
    "cups": UnitDefinition(dimension: .volume, factor: 48),
    "pint": UnitDefinition(dimension: .volume, factor: 96),
    "pints": UnitDefinition(dimension: .volume, factor: 96),
    "pt": UnitDefinition(dimension: .volume, factor: 96),
    "quart": UnitDefinition(dimension: .volume, factor: 192),
    "quarts": UnitDefinition(dimension: .volume, factor: 192),
    "qt": UnitDefinition(dimension: .volume, factor: 192),
    "gallon": UnitDefinition(dimension: .volume, factor: 768),
    "gallons": UnitDefinition(dimension: .volume, factor: 768),
    "gal": UnitDefinition(dimension: .volume, factor: 768),
    "milliliter": UnitDefinition(dimension: .volume, factor: 0.202884),
    "milliliters": UnitDefinition(dimension: .volume, factor: 0.202884),
    "ml": UnitDefinition(dimension: .volume, factor: 0.202884),
    "liter": UnitDefinition(dimension: .volume, factor: 202.884),
    "liters": UnitDefinition(dimension: .volume, factor: 202.884),
    "l": UnitDefinition(dimension: .volume, factor: 202.884),

    "ounce": UnitDefinition(dimension: .weight, factor: 1),
    "ounces": UnitDefinition(dimension: .weight, factor: 1),
    "oz": UnitDefinition(dimension: .weight, factor: 1),
    "pound": UnitDefinition(dimension: .weight, factor: 16),
    "pounds": UnitDefinition(dimension: .weight, factor: 16),
    "lb": UnitDefinition(dimension: .weight, factor: 16),
    "lbs": UnitDefinition(dimension: .weight, factor: 16),
    "gram": UnitDefinition(dimension: .weight, factor: 0.035274),
    "grams": UnitDefinition(dimension: .weight, factor: 0.035274),
    "g": UnitDefinition(dimension: .weight, factor: 0.035274),
    "kilogram": UnitDefinition(dimension: .weight, factor: 35.274),
    "kilograms": UnitDefinition(dimension: .weight, factor: 35.274),
    "kg": UnitDefinition(dimension: .weight, factor: 35.274),

    "each": UnitDefinition(dimension: .count, factor: 1),
    "count": UnitDefinition(dimension: .count, factor: 1),
    "item": UnitDefinition(dimension: .count, factor: 1),
    "items": UnitDefinition(dimension: .count, factor: 1),
    "piece": UnitDefinition(dimension: .count, factor: 1),
    "pieces": UnitDefinition(dimension: .count, factor: 1),
    "clove": UnitDefinition(dimension: .count, factor: 1),
    "cloves": UnitDefinition(dimension: .count, factor: 1),
    "can": UnitDefinition(dimension: .count, factor: 1),
    "cans": UnitDefinition(dimension: .count, factor: 1),
    "bunch": UnitDefinition(dimension: .count, factor: 1),
    "bunches": UnitDefinition(dimension: .count, factor: 1),
    "package": UnitDefinition(dimension: .count, factor: 1),
    "packages": UnitDefinition(dimension: .count, factor: 1),
    "pkg": UnitDefinition(dimension: .count, factor: 1),
  ]
}
