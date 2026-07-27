import SwiftUI

/// The established transient-attention treatment, centralized so every caller keeps the same visual contract.
/// Folding in `RecipeDetailView` intentionally changes its variation note from 12-point padding without a frame
/// to this treatment's 10-point, full-width presentation.
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
