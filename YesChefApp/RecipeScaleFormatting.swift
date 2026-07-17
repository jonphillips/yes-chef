import Foundation

enum ScaleFraction: String, CaseIterable, Identifiable {
  /// Jon's dogfood maximum for a single-serving cocktail batch.
  static let maximumWholeMultiplier = 30

  case none
  case oneHalf
  case oneThird
  case oneFourth
  case oneFifth
  case oneEighth
  case threeEighths
  case fiveEighths
  case sevenEighths
  case twoThirds
  case threeFourths

  var id: Self { self }

  var label: String {
    switch self {
    case .none: "-"
    case .oneHalf: "½"
    case .oneThird: "⅓"
    case .oneFourth: "¼"
    case .oneFifth: "⅕"
    case .oneEighth: "⅛"
    case .threeEighths: "⅜"
    case .fiveEighths: "⅝"
    case .sevenEighths: "⅞"
    case .twoThirds: "⅔"
    case .threeFourths: "¾"
    }
  }

  var value: Double {
    switch self {
    case .none: 0
    case .oneHalf: 1.0 / 2.0
    case .oneThird: 1.0 / 3.0
    case .oneFourth: 1.0 / 4.0
    case .oneFifth: 1.0 / 5.0
    case .oneEighth: 1.0 / 8.0
    case .threeEighths: 3.0 / 8.0
    case .fiveEighths: 5.0 / 8.0
    case .sevenEighths: 7.0 / 8.0
    case .twoThirds: 2.0 / 3.0
    case .threeFourths: 3.0 / 4.0
    }
  }

  /// The nine glyphs shared by multiplier rendering and ingredient authoring.
  static let ingredientInputCases: [Self] = [
    .oneFourth,
    .oneHalf,
    .threeFourths,
    .oneThird,
    .twoThirds,
    .oneEighth,
    .threeEighths,
    .fiveEighths,
    .sevenEighths,
  ]

  static func appending(_ fraction: Self, to ingredientText: String) -> String {
    ingredientText + fraction.label
  }

  static func nearestSelection(to value: Double) -> (whole: Int, fraction: ScaleFraction) {
    var bestWhole = 1
    var bestFraction = ScaleFraction.none
    var bestDistance = Double.greatestFiniteMagnitude

    for whole in 0...maximumWholeMultiplier {
      for fraction in ScaleFraction.allCases {
        let candidate = Double(whole) + fraction.value
        guard candidate >= minimumScale else { continue }
        let distance = abs(candidate - value)
        if distance < bestDistance {
          bestWhole = whole
          bestFraction = fraction
          bestDistance = distance
        }
      }
    }

    return (bestWhole, bestFraction)
  }

  static var minimumScale: Double { oneThird.value }
}

enum ScaleText {
  static func factor(_ factor: Double) -> String {
    "×\(mixedNumber(factor))"
  }

  static func number(_ value: Double) -> String {
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  static func mixedNumber(_ value: Double) -> String {
    let whole = Int(value.rounded(.down))
    let fractionValue = value - Double(whole)
    let fraction = ScaleFraction.allCases
      .filter { $0 != .none }
      .min { lhs, rhs in
        abs(lhs.value - fractionValue) < abs(rhs.value - fractionValue)
      }

    guard let fraction, abs(fraction.value - fractionValue) < 0.01 else {
      return number(value)
    }
    if whole == 0 {
      return fraction.label
    }
    return "\(whole) \(fraction.label)"
  }

  static func servingUnit(_ value: Double) -> String {
    value == 1 ? "serving" : "servings"
  }

}
