import Dependencies
import LLMClientKit
import YesChefCore
import SwiftUI

struct AISettingsView: View {
  @Dependency(\.apiKeyStore) private var apiKeyStore

  @AppStorage(recipeChatCustomInstructionsKey) private var chatInstructions = ""
  @State private var apiKey = ""
  @State private var status: AISettingsStatus?

  var body: some View {
    Form {
      Section {
        SecureField("Claude API Key", text: $apiKey)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .privacySensitive()

        Button {
          saveAPIKey()
        } label: {
          Label("Save Claude API Key", systemImage: "key")
        }

        Button(role: .destructive) {
          clearAPIKey()
        } label: {
          Label("Clear Claude API Key", systemImage: "trash")
        }
        .disabled(apiKey.isEmpty)
      } footer: {
        Text("Stored in iCloud Keychain and used only for direct frontier model calls from this device.")
      }

      if let status {
        Section {
          Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status.foregroundStyle)
        }
      }

      Section {
        TextEditor(text: $chatInstructions)
          .frame(minHeight: 120)
      } footer: {
        Text("Added to the recipe chat system prompt before each conversation.")
      }
    }
    .navigationTitle("AI")
    .task {
      loadAPIKey()
    }
  }

  private func loadAPIKey() {
    apiKey = apiKeyStore.key(.anthropic) ?? ""
    status = apiKey.isEmpty ? nil : .saved
  }

  private func saveAPIKey() {
    apiKeyStore.setKey(apiKey, for: .anthropic)
    apiKey = apiKeyStore.key(.anthropic) ?? ""
    status = apiKey.isEmpty ? .cleared : .saved
  }

  private func clearAPIKey() {
    apiKeyStore.setKey(nil, for: .anthropic)
    apiKey = ""
    status = .cleared
  }
}

private enum AISettingsStatus: Equatable {
  case saved
  case cleared
  case failed(String)

  var title: String {
    switch self {
    case .saved:
      "Claude API key saved."
    case .cleared:
      "Claude API key cleared."
    case let .failed(message):
      message
    }
  }

  var systemImage: String {
    switch self {
    case .saved:
      "checkmark.circle"
    case .cleared:
      "minus.circle"
    case .failed:
      "exclamationmark.triangle"
    }
  }

  var foregroundStyle: Color {
    switch self {
    case .saved:
      .green
    case .cleared:
      .secondary
    case .failed:
      .red
    }
  }
}
