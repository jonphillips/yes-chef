import SwiftUI

private struct WorkbenchCompletedSearch: ViewModifier {
  let isEnabled: Bool
  @Binding var text: String

  @ViewBuilder
  func body(content: Content) -> some View {
    if isEnabled {
      content.searchable(
        text: $text,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Search completed workbenches"
      )
    } else {
      content
    }
  }
}

extension View {
  func completedWorkbenchSearch(isEnabled: Bool, text: Binding<String>) -> some View {
    modifier(WorkbenchCompletedSearch(isEnabled: isEnabled, text: text))
  }
}
