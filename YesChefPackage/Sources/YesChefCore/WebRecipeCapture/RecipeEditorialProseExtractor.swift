import Foundation
import SwiftSoup

enum RecipeEditorialProseExtractor {
  /// ATK-shaped editorial sections. This intentionally keys on display headings
  /// instead of attempting a general prose-section heuristic.
  static let recognizedHeadings = [
    "Why This Recipe Works",
    "Before You Begin",
  ]

  static func extract(from document: Document, into builder: inout RecipeParseBuilder) {
    let headings = (try? document.select("h1, h2, h3, h4, h5, h6").array()) ?? []
    for label in recognizedHeadings {
      for heading in headings where recognizedHeading(for: heading) == label {
        let paragraphs = followingParagraphs(after: heading)
        guard !paragraphs.isEmpty else { continue }
        builder.addEditorialBlock(label: label, text: paragraphs.joined(separator: "\n\n"))
      }
    }
  }

  private static func recognizedHeading(for element: Element) -> String? {
    guard let text = try? element.text() else { return nil }
    let normalized = collapsedWhitespace(in: text)
    return recognizedHeadings.first {
      normalized.localizedCaseInsensitiveCompare($0) == .orderedSame
    }
  }

  private static func followingParagraphs(after heading: Element) -> [String] {
    var paragraphs: [String] = []
    var sibling = nextElementSibling(of: heading)
    while let element = sibling {
      if isHeading(element) { break }
      paragraphs.append(contentsOf: proseLines(in: element))
      sibling = nextElementSibling(of: element)
    }
    return paragraphs
  }

  private static func proseLines(in element: Element) -> [String] {
    if isProseElement(element) {
      return elementText(element).map { [$0] } ?? []
    }
    return (try? element.select("p, li").array())?.compactMap(elementText) ?? []
  }

  private static func elementText(_ element: Element) -> String? {
    guard let text = try? element.text() else { return nil }
    let normalized = collapsedWhitespace(in: text)
    return normalized.isEmpty ? nil : normalized
  }

  private static func nextElementSibling(of element: Element) -> Element? {
    guard let siblings = element.parent()?.children().array(),
      let index = siblings.firstIndex(where: { $0 === element }),
      siblings.indices.contains(index + 1)
    else { return nil }
    return siblings[index + 1]
  }

  private static func isHeading(_ element: Element) -> Bool {
    ["h1", "h2", "h3", "h4", "h5", "h6"].contains(element.tagName().lowercased())
  }

  private static func isProseElement(_ element: Element) -> Bool {
    ["p", "li"].contains(element.tagName().lowercased())
  }

  private static func collapsedWhitespace(in text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
