import SwiftUI
import UIKit

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
  var focusedSectionID: FocusState<UUID?>.Binding? = nil
  var focusedSectionValue: UUID? = nil
  var onSubmit: (() -> Void)?

  var body: some View {
    StackedFormField(title: title) {
      textField
        .modifier(
          OptionalTextFieldFocus(
            focusedSectionID: focusedSectionID,
            focusedSectionValue: focusedSectionValue
          )
        )
        .onSubmit { onSubmit?() }
    }
  }

  @ViewBuilder
  private var textField: some View {
    if let prompt {
      TextField(title, text: $text, prompt: Text(prompt), axis: axis)
    } else {
      TextField(title, text: $text, axis: axis)
    }
  }
}

private struct OptionalTextFieldFocus: ViewModifier {
  let focusedSectionID: FocusState<UUID?>.Binding?
  let focusedSectionValue: UUID?

  @ViewBuilder
  func body(content: Content) -> some View {
    if let focusedSectionID, let focusedSectionValue {
      content.focused(focusedSectionID, equals: focusedSectionValue)
    } else {
      content
    }
  }
}

struct StackedTextEditor: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var caretUTF16Offset: Binding<Int?>? = nil
  var focusedSectionID: FocusState<UUID?>.Binding? = nil
  var focusedSectionValue: UUID? = nil
  var minHeight: CGFloat
  var font: Font = .body
  /// UIKit-backed editors require an explicit UIFont rather than silently ignoring `font`.
  var textViewFont: UIFont? = nil
  @State private var measuredTextHeight: CGFloat = 0

  var body: some View {
    StackedFormField(title: title) {
      if let caretUTF16Offset {
        UTF16TrackingTextEditor(
          text: $text,
          caretUTF16Offset: caretUTF16Offset,
          focusedSectionID: focusedSectionID,
          focusedSectionValue: focusedSectionValue,
          font: textViewFont ?? UIFont.preferredFont(forTextStyle: .body)
        )
        .frame(minHeight: minHeight)
      } else {
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
}

private struct UTF16TrackingTextEditor: UIViewRepresentable {
  @Binding var text: String
  @Binding var caretUTF16Offset: Int?
  var focusedSectionID: FocusState<UUID?>.Binding?
  var focusedSectionValue: UUID?
  var font: UIFont

  func makeUIView(context: Context) -> UITextView {
    let textView = GrowingTextView()
    textView.delegate = context.coordinator
    textView.text = text
    textView.font = font
    textView.adjustsFontForContentSizeCategory = true
    textView.backgroundColor = .clear
    textView.isScrollEnabled = false
    return textView
  }

  func updateUIView(_ textView: UITextView, context: Context) {
    context.coordinator.parent = self
    if textView.text != text {
      textView.text = text
      textView.invalidateIntrinsicContentSize()
    }
    let shouldFocus = focusedSectionID?.wrappedValue == focusedSectionValue
    if shouldFocus, !textView.isFirstResponder {
      context.coordinator.claimFirstResponder(on: textView)
    } else if !shouldFocus, textView.isFirstResponder {
      textView.resignFirstResponder()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: UTF16TrackingTextEditor
    private var isClaimingFirstResponder = false

    init(parent: UTF16TrackingTextEditor) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text
      textView.invalidateIntrinsicContentSize()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
      let location = textView.selectedRange.location
      parent.caretUTF16Offset = location == NSNotFound ? nil : location
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.focusedSectionID?.wrappedValue = parent.focusedSectionValue
      textViewDidChangeSelection(textView)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      guard parent.focusedSectionID?.wrappedValue == parent.focusedSectionValue else { return }
      parent.focusedSectionID?.wrappedValue = nil
    }

    func claimFirstResponder(on textView: UITextView) {
      guard !isClaimingFirstResponder else { return }
      isClaimingFirstResponder = true
      attemptFirstResponderClaim(on: textView, attempt: 0)
    }

    private func attemptFirstResponderClaim(on textView: UITextView, attempt: Int) {
      guard attempt < 20 else {
        isClaimingFirstResponder = false
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textView] in
        guard let self else { return }
        guard let textView,
          self.parent.focusedSectionID?.wrappedValue == self.parent.focusedSectionValue,
          !textView.isFirstResponder
        else {
          self.isClaimingFirstResponder = false
          return
        }
        guard textView.window != nil, textView.becomeFirstResponder() else {
          self.attemptFirstResponderClaim(on: textView, attempt: attempt + 1)
          return
        }
        self.isClaimingFirstResponder = false
        textView.selectedRange = NSRange(location: 0, length: 0)
        self.textViewDidChangeSelection(textView)
      }
    }
  }
}

private final class GrowingTextView: UITextView {
  override var intrinsicContentSize: CGSize {
    let size = sizeThatFits(
      CGSize(width: max(bounds.width, 1), height: .greatestFiniteMagnitude)
    )
    return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    invalidateIntrinsicContentSize()
  }
}

private struct StackedTextEditorHeightKey: PreferenceKey {
  static var defaultValue: CGFloat { 0 }

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
