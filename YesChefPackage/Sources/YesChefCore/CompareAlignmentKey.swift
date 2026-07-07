import CryptoKit
import Foundation

/// Identifies a Compare-alignment cache slot and detects when its stored alignment has gone stale.
///
/// Two fingerprints, deliberately separate:
/// - `identity` changes only when the *set* of recipes changes (a candidate added/removed/reordered,
///   or the working recipe swapped). It is the cache slot — stable across ingredient-text edits so an
///   edit reuses the same slot rather than orphaning the prior alignment.
/// - `contentSignature` fingerprints the actual ingredient text. When it no longer matches the stored
///   alignment's signature, the alignment is *stale* — surfaced as "refresh to update", never an
///   automatic re-align (ADR-0022 open-Q4, resolved: manual refresh, not auto-recompute on edits).
public struct CompareAlignmentKey: Hashable, Sendable {
  public let identity: String
  public let contentSignature: String

  public init(working: RecipeDetailData?, candidates: [RecipeDetailData]) {
    let sources = Self.orderedSources(working: working, candidates: candidates)
    self.identity = Self.identity(sources)
    self.contentSignature = Self.contentSignature(sources)
  }

  private static func identity(
    _ sources: [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)]
  ) -> String {
    let columns = sources.map { source in
      IdentityColumn(
        role: source.role == .working ? "working" : "candidate",
        recipeID: source.detail.recipe.id.uuidString
      )
    }
    return digest(columns, prefix: "id-v1")
  }

  private static func contentSignature(
    _ sources: [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)]
  ) -> String {
    let columns = sources.map { source in
      SignatureColumn(
        role: source.role == .working ? "working" : "candidate",
        lines: nonHeaderLines(in: source.detail).map {
          SignatureLine(
            lineID: $0.id.uuidString,
            text: $0.originalText.compareAlignmentNormalizedText
          )
        }
      )
    }
    return digest(columns, prefix: "content-v1")
  }

  private static func digest<T: Encodable>(_ value: T, prefix: String) -> String {
    let data = (try? JSONEncoder.signatureEncoder.encode(value)) ?? Data()
    let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(hex)"
  }

  private static func orderedSources(
    working: RecipeDetailData?,
    candidates: [RecipeDetailData]
  ) -> [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)] {
    var sources: [(role: IngredientMatrixColumn.Role, detail: RecipeDetailData)] = []
    if let working {
      sources.append((.working, working))
    }
    sources.append(contentsOf: candidates.map { (.candidate, $0) })
    return sources
  }

  private static func nonHeaderLines(in detail: RecipeDetailData) -> [IngredientLine] {
    detail.ingredientLines.enumerated()
      .filter { !$0.element.isHeader }
      .sorted {
        if $0.element.sortOrder == $1.element.sortOrder {
          $0.offset < $1.offset
        } else {
          $0.element.sortOrder < $1.element.sortOrder
        }
      }
      .map(\.element)
  }
}

private struct IdentityColumn: Codable {
  var role: String
  var recipeID: String
}

private struct SignatureColumn: Codable {
  var role: String
  var lines: [SignatureLine]
}

private struct SignatureLine: Codable {
  var lineID: String
  var text: String
}

private extension JSONEncoder {
  static var signatureEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

private extension String {
  var compareAlignmentNormalizedText: String {
    folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .lowercased()
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}
