import SwiftUI

/// The established transient-attention treatment, centralized so every caller keeps the same visual contract.
/// The padding and corner radius preserve the values already used by the four pre-existing implementations.
private struct AttentionCard: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
  }
}

extension View {
  func attentionCard() -> some View {
    modifier(AttentionCard())
  }
}
