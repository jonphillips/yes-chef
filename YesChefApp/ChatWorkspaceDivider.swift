import SwiftUI

struct ChatWorkspaceDivider: View {
  static let dividerWidth: CGFloat = 22

  let detent: ChatWorkspaceDetent
  let cycle: () -> Void
  let decrement: () -> Void
  let increment: () -> Void

  var body: some View {
    Button(action: cycle) {
      ZStack {
        Rectangle()
          .fill(.separator)
          .frame(width: 1)
        Capsule()
          .fill(.secondary.opacity(0.55))
          .frame(width: 5, height: 48)
      }
      .frame(minWidth: Self.dividerWidth, maxWidth: Self.dividerWidth, maxHeight: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Recipe and chat split"))
    .accessibilityValue(Text(detent.title))
    .accessibilityHint(Text("Cycles between reader only, balanced, and chat dive."))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        increment()
      case .decrement:
        decrement()
      @unknown default:
        break
      }
    }
  }
}
