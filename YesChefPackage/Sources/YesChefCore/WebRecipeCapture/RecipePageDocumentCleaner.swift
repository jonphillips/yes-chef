import SwiftSoup

enum RecipePageDocumentCleaner {
  static func clean(_ document: Document) {
    for selector in [
      "script", "style", "noscript", "nav", "header", "footer", "aside",
      "[class*=cookie]", "[class*=consent]", "[class*=breadcrumb]",
    ] {
      _ = try? document.select(selector).remove()
    }
    removeLinkDenseBlocks(in: document)
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
}
