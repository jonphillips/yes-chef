import SwiftUI
import WebExtractorKit
import YesChefCore

struct WorkbenchReferenceRow: View {
  let model: WorkbenchDetailModel
  let reference: WorkbenchReferenceListRow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        model.editReferenceButtonTapped(reference)
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reference.label)
              .font(.headline)
              .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Label(reference.captureKind.displayName, systemImage: reference.captureKind.systemImage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let sourceURL = reference.sourceURL {
            Text(sourceURL)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          Label(reference.reductionStatus.referenceDisplayName, systemImage: reference.reductionStatus.systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Edits this reference material")

      HStack {
        if reference.sourceURL != nil {
          Button {
            model.refreshReferenceButtonTapped(reference)
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        Spacer()
        Button(role: .destructive) {
          model.deleteReferenceButtonTapped(referenceID: reference.id)
        } label: {
          Label("Delete", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.vertical, 4)
  }
}

struct WorkbenchReferenceEditorView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchDetailModel
  @State private var editorState: WorkbenchReferenceEditorState
  @State private var pastedText = ""
  @State private var isCapturing = false

  init(model: WorkbenchDetailModel, editorState: WorkbenchReferenceEditorState) {
    self.model = model
    _editorState = State(wrappedValue: editorState)
  }

  var body: some View {
    @Bindable var model = model

    Form {
      Section {
        StackedTextField(title: "Label", text: $editorState.label)
        StackedTextField(title: "URL", text: $editorState.sourceURL, axis: .vertical)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      } footer: {
        Text("A URL fetch is fastest for public pages. Short extracts offer the browser capture path for signed-in or gated pages.")
      }

      Section {
        TextEditor(text: $pastedText)
          .frame(minHeight: 160)
        Button {
          Task {
            isCapturing = true
            await model.pasteReferenceButtonTapped(editorState, text: pastedText)
            isCapturing = false
          }
        } label: {
          Label("Save Pasted Text", systemImage: "doc.on.clipboard")
        }
        .disabled(!canSavePastedText || isCapturing)
      } header: {
        Text("Last Resort")
      } footer: {
        Text("Use this only if the page will not render in Yes Chef’s browser. Pasted text is reduced and stored as captured source material.")
      }
    }
    .navigationTitle(editorState.referenceID == nil ? "Add Reference" : "Edit Reference")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
        .disabled(isCapturing)
      }
      ToolbarItem(placement: .confirmationAction) {
        if editorState.referenceID != nil {
          Button("Save Label") {
            if model.saveReferenceLabelButtonTapped(editorState) {
              dismiss()
            }
          }
          .disabled(!hasLabel || isCapturing)
        } else {
          Button {
            Task {
              isCapturing = true
              await model.fetchReferenceButtonTapped(editorState)
              isCapturing = false
            }
          } label: {
            if isCapturing {
              ProgressView()
            } else {
              Text("Fetch")
            }
          }
          .disabled(!canFetch || isCapturing)
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if editorState.referenceID != nil {
        Button {
          Task {
            isCapturing = true
            await model.fetchReferenceButtonTapped(editorState)
            isCapturing = false
          }
        } label: {
          if isCapturing {
            ProgressView()
          } else {
            Label("Fetch and Replace Extract", systemImage: "arrow.clockwise")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canFetch || isCapturing)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
      }
    }
    .confirmationDialog(
      "This extract is short",
      item: $model.thinReferenceCapture,
      titleVisibility: .visible
    ) { context in
      Button("Open in Browser to Capture") {
        model.openBrowserForThinReferenceButtonTapped(context)
      }
      Button("Use This Extract") {
        model.useThinReferenceButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("A short extract can be a login wall or teaser. Open the page in Yes Chef’s browser, sign in if needed, then capture the rendered page.")
    }
    .confirmationDialog(
      "Refresh Reference?",
      item: $model.referenceRefreshConfirmation,
      titleVisibility: .visible
    ) { context in
      Button("Replace Extract") {
        model.confirmReferenceRefreshButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { context in
      Text(context.captureKind.replacementConfirmationMessage)
    }
    .confirmationDialog(
      "This URL is already reference material",
      item: $model.duplicateReference,
      titleVisibility: .visible
    ) { context in
      Button("Refresh Existing Reference") {
        model.confirmDuplicateReferenceButtonTapped(context)
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Refresh the existing reference with this newly fetched extract? This replaces its durable captured text.")
    }
    .fullScreenCover(item: $model.browserReferenceCapture, onDismiss: {
      if model.browserReferenceCaptureDismissed() {
        dismiss()
      }
    }) { context in
      WebExtractorBrowser(
        startURL: context.startURL,
        title: "Capture Reference",
        confirmLabel: "Capture to Workbench",
        onExtract: { html, sourceURL in
          await model.browserReferenceCaptured(context, html: html, sourceURL: sourceURL)
        }
      )
    }
  }

  private var hasLabel: Bool {
    !editorState.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canFetch: Bool {
    hasLabel && editorState.url != nil
  }

  private var canSavePastedText: Bool {
    hasLabel && !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

extension WorkbenchReferenceCaptureKind {
  var systemImage: String {
    switch self {
    case .urlFetch: "link"
    case .browserCapture: "safari"
    case .pastedText: "doc.on.clipboard"
    }
  }
}

private extension WorkbenchReferenceReductionStatus {
  var referenceDisplayName: String {
    switch self {
    case .complete: "Complete extract"
    case .truncated: "Extract truncated"
    }
  }

  var systemImage: String {
    switch self {
    case .complete: "checkmark.circle"
    case .truncated: "text.badge.minus"
    }
  }
}
