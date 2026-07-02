import Foundation
import SwiftSoup

public struct RawComment: Equatable, Sendable {
  public var text: String
  public var helpfulCount: Int

  public init(text: String, helpfulCount: Int) {
    self.text = text
    self.helpfulCount = helpfulCount
  }
}

public enum RecipeReaderCommentExtractor {
  public static func extract(html: String, sourceURL: URL?) -> [RawComment] {
    guard supports(sourceURL: sourceURL),
      let document = try? SwiftSoup.parse(html, sourceURL?.absoluteString ?? "")
    else { return [] }
    return extractNYTCookingComments(from: document)
  }

  private static func supports(sourceURL: URL?) -> Bool {
    guard let host = sourceURL?.host()?.lowercased() else { return false }
    return host == "cooking.nytimes.com"
  }

  private static func extractNYTCookingComments(from document: Document) -> [RawComment] {
    guard let notesSection = try? document.select("#notes_section").first() else { return [] }
    return descendants(of: notesSection, whoseClassHasPrefix: "note_note__").compactMap { comment in
      guard let body = firstDescendant(of: comment, whoseClassHasPrefix: "note_noteBody__") else {
        return nil
      }
      let text = commentText(in: body)
      guard !text.isEmpty else { return nil }
      return RawComment(
        text: text,
        helpfulCount: helpfulCount(in: comment)
      )
    }
  }

  private static func commentText(in body: Element) -> String {
    let paragraphs = ((try? body.select("p").array()) ?? []).compactMap(elementText)
    return paragraphs.joined(separator: "\n\n")
  }

  private static func helpfulCount(in comment: Element) -> Int {
    guard let countElement = firstDescendant(
      of: comment,
      whoseClassHasPrefix: "noteactions_recommendationsCount__"
    ),
      let countText = elementText(countElement)
    else { return 0 }
    let digits = countText.filter(\.isNumber)
    return Int(digits) ?? 0
  }

  private static func descendants(
    of element: Element,
    whoseClassHasPrefix prefix: String
  ) -> [Element] {
    ((try? element.getAllElements().array()) ?? []).filter {
      hasClass(withPrefix: prefix, element: $0)
    }
  }

  private static func firstDescendant(
    of element: Element,
    whoseClassHasPrefix prefix: String
  ) -> Element? {
    descendants(of: element, whoseClassHasPrefix: prefix).first
  }

  private static func hasClass(withPrefix prefix: String, element: Element) -> Bool {
    (try? element.className().split(separator: " "))?.contains {
      $0.hasPrefix(prefix)
    } ?? false
  }

  private static func elementText(_ element: Element) -> String? {
    guard let text = try? element.text() else { return nil }
    let normalized = collapsedWhitespace(in: text)
    return normalized.isEmpty ? nil : normalized
  }

  private static func collapsedWhitespace(in text: String) -> String {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
