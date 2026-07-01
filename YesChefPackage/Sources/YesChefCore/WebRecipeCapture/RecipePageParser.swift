import Foundation
import SwiftSoup

/// Harvested shape from GalavantCapture's `PageParser`, retargeted to schema.org
/// Recipe. Pure HTML in, `ParsedRecipePage` out; no fetch, WebKit, or database.
public enum WebRecipePageParser {
  public static func parse(
    html: String,
    sourceURL: URL? = nil,
    capturedAt: Date = Date()
  ) -> ParsedRecipePage {
    var builder = RecipeParseBuilder(sourceURL: sourceURL, originalHTML: html)
    guard let document = try? SwiftSoup.parse(html, sourceURL?.absoluteString ?? "") else {
      return builder.build(capturedAt: capturedAt)
    }

    RecipeJSONLDExtractor.extract(from: document, into: &builder)
    RecipeMetaExtractor.extract(from: document, into: &builder)
    RecipeMicrodataExtractor.extract(from: document, into: &builder)
    RecipeBodyImageExtractor.extract(from: document, into: &builder)
    RecipeEditorialProseExtractor.extract(from: document, into: &builder)

    var page = builder.build(capturedAt: capturedAt)
    if let cleaned = cleanedBodyText(from: document) {
      page.bodyText = cleaned
      page.textExcerpt = truncate(cleaned, to: summaryLeadLength)
    }
    return page
  }

  /// Kept aligned with Galavant's parser: a short lead for review/summary surfaces;
  /// full `bodyText` remains uncapped for later fallback extraction.
  private static let summaryLeadLength = 1500

  private static func cleanedBodyText(from document: Document) -> String? {
    for selector in [
      "script", "style", "noscript", "nav", "header", "footer", "aside",
      "[class*=cookie]", "[class*=consent]", "[class*=breadcrumb]",
    ] {
      _ = try? document.select(selector).remove()
    }
    removeLinkDenseBlocks(in: document)
    guard let raw = try? document.body()?.text(), !raw.isEmpty else { return nil }
    let collapsed = raw.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }

  private static func removeLinkDenseBlocks(in document: Document) {
    guard let candidates = try? document.select("ul, ol, div") else { return }
    for element in candidates.array() {
      guard element.parent() != nil else { continue }
      guard
        let links = try? element.select("a"), links.size() >= 4,
        let total = try? element.text(), !total.isEmpty
      else { continue }
      let linkText = links.array().compactMap { try? $0.text() }.joined()
      if Double(linkText.count) / Double(total.count) > 0.6 {
        try? element.remove()
      }
    }
  }

  private static func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    let clipped = text.prefix(limit)
    if let lastSpace = clipped.lastIndex(of: " ") {
      return String(clipped[..<lastSpace])
    }
    return String(clipped)
  }
}
