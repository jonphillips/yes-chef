import Foundation

enum RecipeDurationParser {
  static func minutes(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let iso = iso8601Minutes(trimmed) { return iso }
    return looseMinutes(trimmed)
  }

  private static func iso8601Minutes(_ text: String) -> Int? {
    let pattern = #"^P(?:T)?(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?$"#
    guard let match = firstMatch(pattern, in: text.uppercased()) else { return nil }
    let hours = match(1).flatMap(Double.init) ?? 0
    let minutes = match(2).flatMap(Double.init) ?? 0
    let total = Int((hours * 60 + minutes).rounded())
    return total == 0 ? nil : total
  }

  private static func looseMinutes(_ text: String) -> Int? {
    let lower = text.lowercased()
    let pattern = #"(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
    let matches = regex.matches(in: lower, range: range)
    guard !matches.isEmpty else { return Int(lower.trimmingCharacters(in: .letters.union(.whitespaces))) }
    let total = matches.reduce(0.0) { result, match in
      guard
        let valueRange = Range(match.range(at: 1), in: lower),
        let unitRange = Range(match.range(at: 2), in: lower),
        let value = Double(lower[valueRange])
      else { return result }
      let unit = lower[unitRange]
      return result + (unit.hasPrefix("h") ? value * 60 : value)
    }
    return total == 0 ? nil : Int(total.rounded())
  }

  private static func firstMatch(
    _ pattern: String,
    in text: String
  ) -> ((Int) -> String?)? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range) else { return nil }
    return { index in
      guard match.range(at: index).location != NSNotFound,
        let range = Range(match.range(at: index), in: text)
      else { return nil }
      return String(text[range])
    }
  }
}
