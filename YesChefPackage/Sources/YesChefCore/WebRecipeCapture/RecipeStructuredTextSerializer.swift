import Foundation
import SwiftSoup

/// A compact, structure-preserving representation of a cleaned recipe page for
/// fallback extraction. Unlike `ParsedRecipePage.bodyText`, lists and headings
/// survive so the model can distinguish recipe boundaries from ordinary prose.
public enum RecipeStructuredTextSerializer {
  public static func serialize(html: String, sourceURL: URL? = nil) -> String? {
    guard let document = try? SwiftSoup.parse(html, sourceURL?.absoluteString ?? "") else { return nil }
    RecipePageDocumentCleaner.clean(document)
    return serialize(document: document)
  }

  static func serialize(document: Document) -> String? {
    guard let body = document.body() else { return nil }
    let blocks = (try? body.select("h1, h2, h3, h4, h5, h6, p, li"))?.array().compactMap { element in
      block(for: element)
    } ?? []

    if !blocks.isEmpty {
      return blocks.joined(separator: "\n\n")
    }

    guard let text = try? body.text() else { return nil }
    let collapsed = text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return collapsed.isEmpty ? nil : collapsed
  }

  private static func block(for element: Element) -> String? {
    let tagName = element.tagName().lowercased()
    // Publishers such as Substack commonly wrap each list item in a paragraph
    // (`<li><p>…</p></li>`). `ownText()` sees no direct text in that shape,
    // which silently removes the entire ingredient list from the model prompt.
    // `text()` preserves the item contents; nested-list duplication is less
    // harmful than dropping a recipe's only ingredients.
    let rawText = try? element.text()
    guard let text = normalized(rawText), !text.isEmpty else { return nil }

    switch tagName {
    case "h1", "h2", "h3", "h4", "h5", "h6":
      return "## \(text)"
    case "li":
      let marker = element.parent()?.tagName().lowercased() == "ol" ? "1. " : "- "
      return marker + text
    case "p":
      // A paragraph inside a list item is already represented by that item.
      guard element.parent()?.tagName().lowercased() != "li" else { return nil }
      return text
    default:
      return text
    }
  }

  private static func normalized(_ text: String?) -> String? {
    guard let text else { return nil }
    let value = text.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return value.isEmpty ? nil : value
  }
}
