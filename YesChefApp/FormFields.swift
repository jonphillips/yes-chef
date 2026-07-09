import SwiftUI

struct StackedFormField<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      FormFieldLabel(title: title)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

struct StackedTextField: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var prompt: LocalizedStringKey?
  var axis: Axis = .horizontal

  var body: some View {
    StackedFormField(title: title) {
      if let prompt {
        TextField(title, text: $text, prompt: Text(prompt), axis: axis)
      } else {
        TextField(title, text: $text, axis: axis)
      }
    }
  }
}

struct StackedTextEditor: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var minHeight: CGFloat
  var font: Font = .body
  @State private var measuredTextHeight: CGFloat = 0

  var body: some View {
    StackedFormField(title: title) {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $text)
          .frame(minHeight: max(minHeight, measuredTextHeight))
          .font(font)

        Text(text.isEmpty ? " " : text + "\n")
          .font(font)
          .padding(.horizontal, 5)
          .padding(.vertical, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .opacity(0)
          .accessibilityHidden(true)
          .background {
            GeometryReader { proxy in
              Color.clear
                .preference(key: StackedTextEditorHeightKey.self, value: proxy.size.height)
            }
          }
      }
      .onPreferenceChange(StackedTextEditorHeightKey.self) { height in
        measuredTextHeight = height
      }
    }
  }
}

private struct StackedTextEditorHeightKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
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
