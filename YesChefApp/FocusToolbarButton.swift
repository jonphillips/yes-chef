import SwiftUI

struct FocusToolbarButton: View {
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(
        isActive ? "Exit Focus" : "Focus",
        systemImage: isActive
          ? "arrow.up.left.and.arrow.down.right.circle.fill"
          : "arrow.up.left.and.arrow.down.right"
      )
    }
    .tint(isActive ? .accentColor : .primary)
    .accessibilityValue(isActive ? "Focused" : "Split view")
  }
}
