import SwiftUI
import YesChefCore

/// Renders the additive Markdown convention used by recipe prose while retaining the original
/// `String` value in storage and in editor bindings.
struct RecipeMarkdownText: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(renderedText)
  }

  private var renderedText: AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }
}

/// Keeps ingredient lines structural while making bracketed author annotations visibly secondary.
struct IngredientLineText: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(renderedText)
  }

  private var renderedText: AttributedString {
    IngredientAuthorNote.segments(in: text).reduce(into: AttributedString()) { rendered, segment in
      switch segment {
      case let .text(value):
        rendered += AttributedString(value)
      case let .authorNote(value):
        var note = AttributedString(value)
        note.foregroundColor = .secondary
        rendered += note
      }
    }
  }
}
