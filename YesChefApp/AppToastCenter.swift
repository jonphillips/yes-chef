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
  var actionTitle: String?
  var action: AppToastAction?
}

enum AppToastAction: Equatable {
  case openRecipe(UUID)
}

@Observable
@MainActor
final class AppToastCenter {
  var message: AppToastMessage?
  var feedbackTrigger = 0

  @ObservationIgnored private var dismissTask: Task<Void, Never>?

  func postSuccess(_ text: String, actionTitle: String? = nil, action: AppToastAction? = nil) {
    let message = AppToastMessage(id: UUID(), text: text, style: .success, actionTitle: actionTitle, action: action)
    dismissTask?.cancel()
    self.message = message
    feedbackTrigger += 1
    let announcement = actionTitle.map { "\(text), \($0)" } ?? text
    UIAccessibility.post(notification: .announcement, argument: announcement)
    dismissTask = Task { [weak self, messageID = message.id] in
      try? await Task.sleep(nanoseconds: actionTitle == nil ? 2_000_000_000 : 5_000_000_000)
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
  var onAction: (AppToastAction) -> Void = { _ in }

  var body: some View {
    ZStack(alignment: .top) {
      if let message = toastCenter.message {
        AppToastView(message: message, onDismiss: toastCenter.dismiss) { action in
          onAction(action)
          toastCenter.dismiss()
        }
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
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
  let onDismiss: () -> Void
  let onAction: (AppToastAction) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onDismiss) {
        Label(message.text, systemImage: systemImage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if let title = message.actionTitle, let action = message.action {
        Button(title) { onAction(action) }
          .font(.subheadline.weight(.semibold))
          .accessibilityLabel(title)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(.separator.opacity(0.5), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    .frame(maxWidth: 520, alignment: .leading)
  }

  private var systemImage: String {
    switch message.style {
    case .success: "checkmark.circle.fill"
    }
  }
}
