import Foundation

public struct RecipeImportIdentityKey: Equatable, Hashable, Sendable {
  public static let contractDescription = "normalized(sourceURL)+normalized(title); fallback normalized(title)"

  public var normalizedSourceURL: String?
  public var normalizedTitle: String

  public init(sourceURL: String?, title: String) {
    self.normalizedSourceURL = Self.normalizedSourceURL(sourceURL)
    self.normalizedTitle = Self.normalizedTitle(title)
  }

  public var isTitleOnly: Bool {
    normalizedSourceURL == nil
  }

  public static func normalizedTitle(_ value: String) -> String {
    let folded = value
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    let words = folded.unicodeScalars.reduce(into: [String]()) { words, scalar in
      if CharacterSet.alphanumerics.contains(scalar) {
        if words.isEmpty || words[words.count - 1] == " " {
          words.append(String(scalar))
        } else {
          words[words.count - 1].append(String(scalar))
        }
      } else if words.last != " " {
        words.append(" ")
      }
    }
    return words
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func normalizedSourceURL(_ value: String?) -> String? {
    guard var value = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(),
      !value.isEmpty
    else { return nil }

    if let url = URL(string: value),
       let strippedURL = URLProvenanceNormalization.strippingTrackingParametersAndFragment(from: url)
    {
      value = strippedURL.absoluteString
    }

    while value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
