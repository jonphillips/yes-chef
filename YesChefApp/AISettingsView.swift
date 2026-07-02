import SwiftUI

struct AISettingsView: View {
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
        Text("Stored in iCloud Keychain and used only for direct Claude API calls from this device.")
      }

      if let status {
        Section {
          Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status.foregroundStyle)
        }
      }
    }
    .navigationTitle("AI")
    .task {
      loadAPIKey()
    }
  }

  private func loadAPIKey() {
    do {
      apiKey = try ClaudeAPIKeyStorage.apiKey() ?? ""
      status = apiKey.isEmpty ? nil : .saved
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func saveAPIKey() {
    do {
      try ClaudeAPIKeyStorage.saveAPIKey(apiKey)
      apiKey = try ClaudeAPIKeyStorage.apiKey() ?? ""
      status = apiKey.isEmpty ? .cleared : .saved
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func clearAPIKey() {
    do {
      try ClaudeAPIKeyStorage.deleteAPIKey()
      apiKey = ""
      status = .cleared
    } catch {
      status = .failed(error.localizedDescription)
    }
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
