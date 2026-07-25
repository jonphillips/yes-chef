import LLMClientKit
import SwiftUI
import YesChefCore

struct ChatFinalizeConfiguration {
  let title: String
  let source: HandoffExportSource
  let actionID: AnyChatApplyAction.ID

  static func recipe(recipeID: Recipe.ID, section: PlaybookSectionKind) -> Self {
    let actionID: AnyChatApplyAction.ID
    switch section {
    case .makeAhead: actionID = "Create Prep Plan"
    case .chefItUp: actionID = "Chef It Up"
    case .serveWith: actionID = "Capture Side Dishes"
    }
    return Self(
      title: "Finalize \(section.chatMenuTitle)",
      source: .recipeSection(recipeID, section),
      actionID: actionID
    )
  }

  static func menu(menuID: YesChefCore.Menu.ID) -> Self {
    Self(
      title: "Finalize Prep Plan",
      source: .menu(menuID),
      actionID: "Build prep plan -> Prep Plan section"
    )
  }
}

/// Runs the terminal turn for an onboard discussion. A model failure removes its empty placeholder,
/// so an existing assistant reply must never be mistaken for the terminal deliverable.
@MainActor
enum OnboardChatFinalizer {
  static func finalize(
    using chatModel: RecipeChatModel,
    stage: @escaping @MainActor (String) async throws -> Void
  ) async -> String? {
    let priorReplyID = chatModel.messages.last(where: { $0.role == .assistant })?.id
    guard await chatModel.send("Finalize.") else { return nil }
    guard
      chatModel.errorText == nil,
      let reply = chatModel.messages.last(where: { $0.role == .assistant }),
      reply.id != priorReplyID,
      !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      reply.text != "(No response.)"
    else {
      return chatModel.errorText ?? "Finalize didn't return a result. Try again."
    }

    do {
      try await stage(reply.text)
      return nil
    } catch {
      return RecipeChatErrorText.describe(error)
    }
  }
}

struct ChatContextHeader: View {
  let chatModel: RecipeChatModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(chatModel.context.seededContextDescription)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ChatTierMenu: View {
  let chatModel: RecipeChatModel

  var body: some View {
    @Bindable var chatModel = chatModel

    Menu {
      Button {
        chatModel.useFrontier = false
      } label: {
        Label("On-device (private)", systemImage: "iphone")
        if !chatModel.sendsToProvider {
          Image(systemName: "checkmark")
        }
      }

      ForEach(FrontierProvider.allCases) { provider in
        Button {
          chatModel.selectedProvider = provider
          chatModel.useFrontier = true
        } label: {
          Label("\(provider.displayName) (sends data off device)", systemImage: "network")
          if chatModel.sendsToProvider, chatModel.selectedProvider == provider {
            Image(systemName: "checkmark")
          }
        }
        .disabled(!chatModel.availableProviders.contains(provider))
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: chatModel.sendsToProvider ? "network" : "iphone")
          .foregroundStyle(chatModel.sendsToProvider ? .blue : .green)
        Text(chatModel.sendsToProvider ? chatModel.selectedProvider.displayName : "On-device")
          .font(.subheadline)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityHint(Text("Choose whether recipe context stays on device or is sent to a configured provider."))
  }
}

struct ChatActionSubject: Equatable {
  enum Source {
    case selection
    case latestReply

    var logDescription: String {
      switch self {
      case .selection: "explicit-selection-subject-chip"
      case .latestReply: "latestReplySubject-fallback"
      }
    }
  }

  var source: Source
  var text: String

  var label: String {
    switch source {
    case .selection: "Acting on your selection"
    case .latestReply: "Acting on latest reply"
    }
  }

  var snippet: String {
    let flattened = text
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flattened.count > 120 else { return flattened }
    return "\(flattened.prefix(120))..."
  }
}

struct ChatActionSubjectView: View {
  let subject: ChatActionSubject
  var onClear: (() -> Void)?

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(subject.label)
          .font(.caption.bold())
          .foregroundStyle(.secondary)
        Text(subject.snippet)
          .font(.caption)
          .lineLimit(2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let onClear {
        Button(action: onClear) {
          Label("Clear selection", systemImage: "xmark.circle.fill")
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear selection"))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
