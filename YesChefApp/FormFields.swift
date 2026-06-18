import SwiftUI

struct StackedTextField: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var prompt: LocalizedStringKey?
  var axis: Axis = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      FormFieldLabel(title: title)
      if let prompt {
        TextField(title, text: $text, prompt: Text(prompt), axis: axis)
      } else {
        TextField(title, text: $text, axis: axis)
      }
    }
    .padding(.vertical, 4)
  }
}

struct StackedTextEditor: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var minHeight: CGFloat
  var font: Font = .body

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      FormFieldLabel(title: title)
      TextEditor(text: $text)
        .frame(minHeight: minHeight)
        .font(font)
    }
    .padding(.vertical, 4)
  }
}

private struct FormFieldLabel: View {
  let title: LocalizedStringKey

  var body: some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
