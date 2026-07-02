import Observation
import SwiftUI
import UIKit

struct AppToastMessage: Identifiable, Equatable {
  enum Style: Equatable {
    case success
  }

  let id: UUID
  var text: String
  var style: Style
}

@Observable
@MainActor
final class AppToastCenter {
  var message: AppToastMessage?
  var feedbackTrigger = 0

  @ObservationIgnored private var dismissTask: Task<Void, Never>?

  func postSuccess(_ text: String) {
    let message = AppToastMessage(id: UUID(), text: text, style: .success)
    dismissTask?.cancel()
    self.message = message
    feedbackTrigger += 1
    UIAccessibility.post(notification: .announcement, argument: text)
    dismissTask = Task { [weak self, messageID = message.id] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard self?.message?.id == messageID else { return }
        self?.message = nil
      }
    }
  }

  func dismiss() {
    dismissTask?.cancel()
    dismissTask = nil
    message = nil
  }
}

struct AppToastOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let toastCenter: AppToastCenter

  var body: some View {
    ZStack(alignment: .top) {
      if let message = toastCenter.message {
        AppToastView(message: message)
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
          .onTapGesture {
            toastCenter.dismiss()
          }
          .gesture(
            DragGesture(minimumDistance: 12)
              .onEnded { _ in
                toastCenter.dismiss()
              }
          )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(toastCenter.message != nil)
    .animation(.snappy(duration: 0.22), value: toastCenter.message)
  }
}

private struct AppToastView: View {
  let message: AppToastMessage

  var body: some View {
    Label(message.text, systemImage: systemImage)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.primary)
      .multilineTextAlignment(.leading)
      .lineLimit(3)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(.separator.opacity(0.5), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
      .frame(maxWidth: 520, alignment: .leading)
      .accessibilityAddTraits(.isStaticText)
  }

  private var systemImage: String {
    switch message.style {
    case .success: "checkmark.circle.fill"
    }
  }
}
