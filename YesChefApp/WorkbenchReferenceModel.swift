import Foundation
import WebExtractorKit
import YesChefCore

extension WorkbenchDetailModel {
  func addReferenceButtonTapped() {
    destination = .referenceEditor(WorkbenchReferenceEditorState())
  }

  func editReferenceButtonTapped(_ reference: WorkbenchReferenceListRow) {
    destination = .referenceEditor(WorkbenchReferenceEditorState(reference: reference))
  }

  @discardableResult
  func saveReferenceLabelButtonTapped(_ editor: WorkbenchReferenceEditorState) -> Bool {
    guard let referenceID = editor.referenceID else { return false }
    do {
      try database.write { db in
        try WorkbenchReferenceRepository.updateLabel(
          referenceID: referenceID,
          label: editor.label,
          in: db,
          now: now
        )
      }
      toastCenter?.postSuccess("Reference updated.")
      return true
    } catch {
      showReferenceError(error)
      return false
    }
  }

  func deleteReferenceButtonTapped(referenceID: WorkbenchReference.ID) {
    do {
      try database.write { db in
        try WorkbenchReferenceRepository.delete(referenceID: referenceID, in: db, now: now)
      }
    } catch {
      showReferenceError(error)
    }
  }

  func refreshReferenceButtonTapped(_ reference: WorkbenchReferenceListRow) {
    destination = .referenceEditor(WorkbenchReferenceEditorState(reference: reference))
  }

  func confirmReferenceRefreshButtonTapped(_ context: WorkbenchReferenceReplacementContext) {
    referenceRefreshConfirmation = nil
    guard let url = context.editor.url else {
      errorMessage = "This captured reference has no source URL to refresh."
      isShowingError = true
      return
    }
    if context.captureKind == .browserCapture {
      browserReferenceCapture = WorkbenchReferenceBrowserCaptureContext(
        referenceID: context.editor.referenceID,
        label: context.editor.label,
        startURL: url
      )
      return
    }
    Task { await fetchReference(context.editor) }
  }

  func fetchReferenceButtonTapped(_ editor: WorkbenchReferenceEditorState) async {
    if let referenceID = editor.referenceID,
       let reference = referenceRows.first(where: { $0.id == referenceID }) {
      referenceRefreshConfirmation = WorkbenchReferenceReplacementContext(
        editor: editor,
        captureKind: reference.captureKind
      )
      return
    }
    await fetchReference(editor)
  }

  private func fetchReference(_ editor: WorkbenchReferenceEditorState) async {
    guard let url = editor.url else {
      errorMessage = "Enter a valid reference URL."
      isShowingError = true
      return
    }

    do {
      let content = try await WorkbenchReferenceCapture.reduce(.url(url), using: referenceCaptureClient)
      guard !content.isThin else {
        thinReferenceCapture = WorkbenchThinReferenceCaptureContext(editor: editor, content: content)
        return
      }
      _ = storeReference(content, using: editor)
    } catch is CancellationError {
    } catch {
      showReferenceError(error)
    }
  }

  func useThinReferenceButtonTapped(_ context: WorkbenchThinReferenceCaptureContext) {
    thinReferenceCapture = nil
    _ = storeReference(context.content, using: context.editor)
  }

  func openBrowserForThinReferenceButtonTapped(_ context: WorkbenchThinReferenceCaptureContext) {
    thinReferenceCapture = nil
    guard let startURL = context.editor.url else { return }
    browserReferenceCapture = WorkbenchReferenceBrowserCaptureContext(
      referenceID: context.editor.referenceID,
      label: context.editor.label,
      startURL: startURL
    )
  }

  func pasteReferenceButtonTapped(_ editor: WorkbenchReferenceEditorState, text: String) async {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty else {
      errorMessage = "Paste readable page text before saving a reference."
      isShowingError = true
      return
    }

    do {
      let content = try await WorkbenchReferenceCapture.reduce(
        .pastedText(text: trimmedText, sourceURL: editor.url),
        using: referenceCaptureClient
      )
      _ = storeReference(content, using: editor)
    } catch is CancellationError {
    } catch {
      showReferenceError(error)
    }
  }

  func browserReferenceCaptured(
    _ context: WorkbenchReferenceBrowserCaptureContext,
    html: String,
    sourceURL: URL?
  ) async -> WebExtractionOutcome {
    do {
      let content = try await WorkbenchReferenceCapture.reduce(
        .capturedHTML(html: html, sourceURL: sourceURL),
        using: referenceCaptureClient
      )
      guard storeReference(content, using: context.editor, dismissEditor: false) else {
        return .notFound(
          message: "This URL is already reference material. Close the browser to choose whether to refresh it."
        )
      }
      browserReferenceCaptureStored = true
      return .extracted
    } catch is CancellationError {
      return .notFound(message: "Capture cancelled.")
    } catch {
      return .notFound(message: (error as? LocalizedError)?.errorDescription ?? "This page could not be captured.")
    }
  }

  func browserReferenceCaptureDismissed() -> Bool {
    browserReferenceCapture = nil
    defer { browserReferenceCaptureStored = false }
    return browserReferenceCaptureStored
  }

  func confirmDuplicateReferenceButtonTapped(_ context: WorkbenchDuplicateReferenceContext) {
    duplicateReference = nil
    do {
      try database.write { db in
        try WorkbenchReferenceRepository.refresh(
          referenceID: context.existingReferenceID,
          content: context.content,
          in: db,
          now: now
        )
      }
      destination = nil
      toastCenter?.postSuccess("Reference refreshed.")
    } catch {
      showReferenceError(error)
    }
  }

  private func storeReference(
    _ content: WorkbenchReferenceReducedContent,
    using editor: WorkbenchReferenceEditorState,
    dismissEditor: Bool = true
  ) -> Bool {
    do {
      try database.write { db in
        if let referenceID = editor.referenceID {
          try WorkbenchReferenceRepository.updateLabel(
            referenceID: referenceID,
            label: editor.label,
            in: db,
            now: now
          )
          try WorkbenchReferenceRepository.refresh(
            referenceID: referenceID,
            content: content,
            in: db,
            now: now
          )
        } else {
          _ = try WorkbenchReferenceRepository.store(
            workbenchID: workbenchID,
            label: editor.label,
            content: content,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      if dismissEditor {
        destination = nil
      }
      toastCenter?.postSuccess(editor.referenceID == nil ? "Reference added." : "Reference updated.")
      return true
    } catch let WorkbenchReferenceRepositoryError.duplicateSourceURL(existingReferenceID) {
      duplicateReference = WorkbenchDuplicateReferenceContext(
        existingReferenceID: existingReferenceID,
        label: editor.label,
        content: content
      )
      return false
    } catch {
      showReferenceError(error)
      return false
    }
  }

  private func showReferenceError(_ error: Error) {
    errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    isShowingError = true
  }
}

struct WorkbenchReferenceEditorState: Identifiable {
  let transientID: UUID
  var referenceID: WorkbenchReference.ID?
  var label = ""
  var sourceURL = ""

  init(reference: WorkbenchReferenceListRow? = nil) {
    transientID = UUID()
    referenceID = reference?.id
    label = reference?.label ?? ""
    sourceURL = reference?.sourceURL ?? ""
  }

  var id: UUID { transientID }

  var url: URL? {
    URL(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines))
  }
}

struct WorkbenchReferenceBrowserCaptureContext: Identifiable {
  let id = UUID()
  var referenceID: WorkbenchReference.ID?
  var label: String
  var startURL: URL

  var editor: WorkbenchReferenceEditorState {
    WorkbenchReferenceEditorState(
      referenceID: referenceID,
      label: label,
      sourceURL: startURL.absoluteString
    )
  }
}

struct WorkbenchThinReferenceCaptureContext: Identifiable {
  let id = UUID()
  var editor: WorkbenchReferenceEditorState
  var content: WorkbenchReferenceReducedContent
}

struct WorkbenchReferenceReplacementContext: Identifiable {
  let id = UUID()
  var editor: WorkbenchReferenceEditorState
  var captureKind: WorkbenchReferenceCaptureKind

  init(reference: WorkbenchReferenceListRow) {
    self.init(
      editor: WorkbenchReferenceEditorState(reference: reference),
      captureKind: reference.captureKind
    )
  }

  init(editor: WorkbenchReferenceEditorState, captureKind: WorkbenchReferenceCaptureKind) {
    self.editor = editor
    self.captureKind = captureKind
  }
}

struct WorkbenchDuplicateReferenceContext: Identifiable {
  let id = UUID()
  var existingReferenceID: WorkbenchReference.ID
  var label: String
  var content: WorkbenchReferenceReducedContent
}

private extension WorkbenchReferenceEditorState {
  init(referenceID: WorkbenchReference.ID?, label: String, sourceURL: String) {
    transientID = UUID()
    self.referenceID = referenceID
    self.label = label
    self.sourceURL = sourceURL
  }
}
