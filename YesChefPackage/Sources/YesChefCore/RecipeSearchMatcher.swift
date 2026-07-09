import Foundation

public enum RecipeSearchMatcher {
  public static func matches(query: String, in fields: [String]) -> Bool {
    let tokens = normalizedTokens(query)
    guard !tokens.isEmpty else { return true }

    let searchableFields = fields
      .map(normalizedText)
      .filter { !$0.isEmpty }

    return tokens.allSatisfy { token in
      searchableFields.contains { $0.contains(token) }
    }
  }

  public static func matches(query: String, in fields: String?...) -> Bool {
    matches(query: query, in: fields.compactMap(\.self))
  }

  private static func normalizedTokens(_ query: String) -> [String] {
    normalizedText(query)
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
  }

  private static func normalizedText(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
  }
}
