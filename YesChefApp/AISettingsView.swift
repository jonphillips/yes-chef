import Dependencies
import LLMClientKit
import Observation
import YesChefCore
import SwiftUI

struct AISettingsView: View {
  @AppStorage(recipeChatCustomInstructionsKey) private var chatInstructions = ""
  @State private var model = AISettingsModel()

  var body: some View {
    Form {
      modelTierSection

      ForEach(model.providers) { provider in
        keySection(for: provider)
      }

      Section {
        TextEditor(text: $chatInstructions)
          .frame(minHeight: 120)
      } footer: {
        Text("Added to the recipe chat system prompt before each conversation.")
      }
    }
    .navigationTitle("AI")
    .task { model.onAppear() }
  }

  private var modelTierSection: some View {
    Section {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("On-device")
          Text("Private and offline. Always available.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "iphone")
          .foregroundStyle(.green)
      }

      ForEach(model.providers) { provider in
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Frontier (\(provider.displayName))")
            Text(
              model.hasStoredKey(provider)
                ? "Enabled with your key. Sends recipe context off device."
                : "Add your key below to enable. Off until then."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "network")
            .foregroundStyle(model.hasStoredKey(provider) ? .blue : .secondary)
        }
      }
    } header: {
      Text("Model tiers")
    } footer: {
      Text(
        "Each frontier provider uses your own API key, stored in iCloud Keychain. "
          + "Configure more than one to switch providers per conversation."
      )
    }
  }

  private func keySection(for provider: FrontierProvider) -> some View {
    Section {
      SecureField(Self.placeholder(for: provider), text: keyBinding(for: provider))
        .textContentType(.password)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .privacySensitive()

      if let preview = model.keyPreview(for: provider) {
        LabeledContent("Stored") {
          Text(preview)
            .monospaced()
            .foregroundStyle(.secondary)
        }
      }

      Button {
        model.save(provider)
      } label: {
        Label("Save Key", systemImage: "key")
      }
      .disabled(!model.canSave(provider))

      if model.hasStoredKey(provider) {
        Button(role: .destructive) {
          model.clear(provider)
        } label: {
          Label("Clear Key", systemImage: "trash")
        }
      }
    } header: {
      Text("\(provider.displayName) API key")
    } footer: {
      Text(
        model.hasStoredKey(provider)
          ? "A key is stored on this device. Saving a new one replaces it."
          : "Stored in iCloud Keychain and used only for direct frontier model calls from this device."
      )
    }
  }

  private func keyBinding(for provider: FrontierProvider) -> Binding<String> {
    Binding(
      get: { model.keyInput(for: provider) },
      set: { model.setKeyInput($0, for: provider) }
    )
  }

  private static func placeholder(for provider: FrontierProvider) -> String {
    switch provider {
    case .anthropic: "sk-ant-..."
    case .openai: "sk-..."
    }
  }
}

@MainActor
@Observable
private final class AISettingsModel {
  var keyInputs: [FrontierProvider: String] = [:]
  private(set) var storedProviders: Set<FrontierProvider> = []
  private(set) var keyPreviews: [FrontierProvider: String] = [:]

  @ObservationIgnored @Dependency(\.apiKeyStore) private var apiKeyStore

  let providers = FrontierProvider.allCases

  func onAppear() {
    refresh()
  }

  func hasStoredKey(_ provider: FrontierProvider) -> Bool {
    storedProviders.contains(provider)
  }

  func keyPreview(for provider: FrontierProvider) -> String? {
    keyPreviews[provider]
  }

  func keyInput(for provider: FrontierProvider) -> String {
    keyInputs[provider] ?? ""
  }

  func setKeyInput(_ value: String, for provider: FrontierProvider) {
    keyInputs[provider] = value
  }

  func canSave(_ provider: FrontierProvider) -> Bool {
    !keyInput(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func save(_ provider: FrontierProvider) {
    apiKeyStore.setKey(keyInputs[provider], for: provider)
    keyInputs[provider] = ""
    refresh()
  }

  func clear(_ provider: FrontierProvider) {
    apiKeyStore.setKey(nil, for: provider)
    keyInputs[provider] = ""
    refresh()
  }

  private func refresh() {
    storedProviders = Set(providers.filter { apiKeyStore.key($0) != nil })
    keyPreviews = Dictionary(
      uniqueKeysWithValues: providers.compactMap { provider in
        apiKeyStore.maskedKey(provider).map { (provider, $0) }
      })
  }
}
