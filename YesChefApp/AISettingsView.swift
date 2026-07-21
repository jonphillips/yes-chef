import LLMClientKit
import SwiftUI
import YesChefCore

struct AISettingsView: View {
  @State private var model = AISettingsModel()
  @State private var isTaskPreferencesExpanded = false

  var body: some View {
    @Bindable var model = model

    Form {
      modelTierSection
      activeModelsSection

      ForEach(model.providers) { provider in
        keySection(for: provider)
      }

      Section {
        StackedTextEditor(
          title: "Taste Profile",
          text: $model.tasteProfile,
          minHeight: 140
        )
      } footer: {
        Text("Shapes every AI reply unless it conflicts with the task rules.")
      }

      Section {
        DisclosureGroup(isExpanded: $isTaskPreferencesExpanded) {
          StackedTextEditor(
            title: "Chef It Up",
            text: $model.chefItUpPreference,
            minHeight: 90
          )
          StackedTextEditor(
            title: "Serve With",
            text: $model.serveWithPreference,
            minHeight: 90
          )
          StackedTextEditor(
            title: "Make-ahead & Prep Plans",
            text: $model.makeAheadPrepPlanPreference,
            minHeight: 90
          )
          StackedTextEditor(
            title: "Complements",
            text: $model.complementsPreference,
            minHeight: 90
          )
          StackedTextEditor(
            title: "Capture to Note",
            text: $model.captureToNotePreference,
            minHeight: 110
          )
          StackedTextEditor(
            title: "Reader Feedback",
            text: $model.readerFeedbackPreference,
            minHeight: 90
          )
        } label: {
          Label("Per-task Preferences", systemImage: "slider.horizontal.3")
        }
      } footer: {
        Text("Optional preferences for judgment tasks. The app's task prompts stay fixed.")
      }

      Section {
        Button {
          model.savePreferencesButtonTapped()
        } label: {
          Label("Save Preferences", systemImage: "square.and.arrow.down")
        }
        .disabled(!model.hasUnsavedPreferenceChanges)
      }

      Section {
        Button {
          model.copyProjectInstructionsButtonTapped()
        } label: {
          Label("Copy Yes Chef Instructions", systemImage: "doc.on.doc")
        }
      } header: {
        Text("ChatGPT Project")
      } footer: {
        Text("Paste these into the shared Yes Chef project's custom instructions. Yes Chef rejects returned handoffs from stale instructions.")
      }
    }
    .navigationTitle("AI")
    .task { model.onAppear() }
    .alert(
      "AI Settings Error",
      isPresented: $model.isShowingError,
      actions: {
        Button("OK", role: .cancel) {}
      },
      message: {
        if let errorMessage = model.errorMessage {
          Text(errorMessage)
        }
      }
    )
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

  private var activeModelsSection: some View {
    Section("Active models") {
      ForEach(model.providers) { provider in
        LabeledContent(provider.displayName, value: provider.defaultModel)
      }
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
