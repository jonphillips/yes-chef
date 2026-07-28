import Foundation

/// The bracket convention for author annotations in ingredient lines. The source text remains
/// authoritative; this type only separates annotation spans from the text the ingredient parser
/// should interpret.
public enum IngredientAuthorNote {
  public enum Segment: Equatable, Sendable {
    case text(String)
    case authorNote(String)
  }

  /// Splits complete `[author note]` spans from surrounding text. An unmatched `[` is ordinary
  /// ingredient text so a partially typed editor value never loses content.
  public static func segments(in text: String) -> [Segment] {
    var segments: [Segment] = []
    var textBuffer = ""
    var noteBuffer = ""
    var isReadingNote = false

    func appendTextBuffer() {
      guard !textBuffer.isEmpty else { return }
      segments.append(.text(textBuffer))
      textBuffer = ""
    }

    for character in text {
      if isReadingNote {
        if character == "]" {
          segments.append(.authorNote("[\(noteBuffer)]"))
          noteBuffer = ""
          isReadingNote = false
        } else {
          noteBuffer.append(character)
        }
      } else if character == "[" {
        appendTextBuffer()
        isReadingNote = true
      } else {
        textBuffer.append(character)
      }
    }

    if isReadingNote {
      textBuffer.append("[")
      textBuffer.append(noteBuffer)
    }
    appendTextBuffer()
    return segments
  }

  static func parsingText(from segments: [Segment]) -> String {
    let text = segments.reduce(into: "") { result, segment in
      if case let .text(value) = segment { result += value }
    }
    return text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .replacingOccurrences(of: " ,", with: ",")
      .replacingOccurrences(of: " ;", with: ";")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func comment(from segments: [Segment]) -> String? {
    let comments = segments.compactMap { segment -> String? in
      guard case let .authorNote(value) = segment else { return nil }
      let content = value.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
      return content.isEmpty ? nil : content
    }
    return comments.isEmpty ? nil : comments.joined(separator: "; ")
  }
}
