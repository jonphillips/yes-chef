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
    (try? AttributedString(markdown: text)) ?? AttributedString(text)
  }
}

/// Keeps ingredient lines structural while making bracketed author annotations visibly secondary.
struct IngredientLineText: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    renderedText
  }

  private var renderedText: Text {
    IngredientAuthorNote.segments(in: text).reduce(Text("")) { rendered, segment in
      switch segment {
      case let .text(value):
        rendered + Text(value)
      case let .authorNote(value):
        rendered + Text(value).foregroundStyle(.secondary)
      }
    }
  }
}
