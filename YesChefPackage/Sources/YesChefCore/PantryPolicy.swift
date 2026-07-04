import Foundation

public enum PantryPolicy: Equatable, Sendable {
  case unlimited
  case threshold(quantity: Double, unit: String)
  case alwaysConfirm

  public static func normalized(
    isUnlimited: Bool,
    thresholdQuantity: Double?,
    thresholdUnit: String?
  ) -> PantryPolicy {
    if isUnlimited {
      return .unlimited
    }

    guard let thresholdQuantity, thresholdQuantity > 0,
          let thresholdUnit = normalizedThresholdUnit(thresholdUnit),
          canUseThreshold(unit: thresholdUnit)
    else {
      return .alwaysConfirm
    }

    return .threshold(quantity: thresholdQuantity, unit: thresholdUnit)
  }

  public static func thresholdOrAlwaysConfirm(
    quantity: Double,
    unit: String?
  ) -> PantryPolicy {
    normalized(isUnlimited: false, thresholdQuantity: quantity, thresholdUnit: unit)
  }

  public static func canUseThreshold(unit: String?) -> Bool {
    switch Measure.recognizedDimension(for: normalizedThresholdUnit(unit)) {
    case .volume, .weight:
      return true
    case .count, nil:
      return false
    }
  }

  public var storageValues: (isUnlimited: Bool, thresholdQuantity: Double?, thresholdUnit: String?) {
    switch self {
    case .unlimited:
      return (true, nil, nil)
    case let .threshold(quantity, unit):
      guard quantity > 0,
            let unit = Self.normalizedThresholdUnit(unit),
            Self.canUseThreshold(unit: unit)
      else {
        return (false, nil, nil)
      }
      return (false, quantity, unit)
    case .alwaysConfirm:
      return (false, nil, nil)
    }
  }

  private static func normalizedThresholdUnit(_ unit: String?) -> String? {
    let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }
}
