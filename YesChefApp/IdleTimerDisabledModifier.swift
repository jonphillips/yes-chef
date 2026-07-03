import SwiftUI
import UIKit

private struct IdleTimerDisabledModifier: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
      .onAppear {
        updateIdleTimer(for: scenePhase)
      }
      .onChange(of: scenePhase) { _, phase in
        updateIdleTimer(for: phase)
      }
      .onDisappear {
        UIApplication.shared.isIdleTimerDisabled = false
      }
  }

  private func updateIdleTimer(for phase: ScenePhase) {
    UIApplication.shared.isIdleTimerDisabled = phase == .active
  }
}

extension View {
  func keepsScreenAwakeWhilePresented() -> some View {
    modifier(IdleTimerDisabledModifier())
  }
}
