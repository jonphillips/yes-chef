import Dependencies
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import YesChefCore

final class ShareViewController: UIViewController {
  private var model: ShareCaptureModel?

  override func viewDidLoad() {
    super.viewDidLoad()

    do {
      try prepareDependencies {
        try $0.bootstrapDatabaseForShareExtension()
      }
      let model = ShareCaptureModel(extensionContext: extensionContext)
      self.model = model
      embed(
        ShareCaptureView(model: model) { [weak self] isModalInPresentation in
          self?.isModalInPresentation = isModalInPresentation
        }
      )
      Task { await model.loadSharedPage() }
    } catch {
      embed(ShareSetupRequiredView(message: error.localizedDescription) { [weak self] in
        self?.completeRequest()
      })
    }
  }

  private func embed<Content: View>(_ rootView: Content) {
    let hostingController = UIHostingController(rootView: rootView)
    addChild(hostingController)
    guard let hostView = hostingController.view, let containerView = view else { return }
    hostView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(hostView)
    NSLayoutConstraint.activate([
      hostView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      hostView.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])
    hostingController.didMove(toParent: self)
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: nil)
  }
}

@Observable
@MainActor
final class ShareCaptureModel {
  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Dependency(\.webRecipeCaptureClient) private var captureClient

  private let extensionContext: NSExtensionContext?

  var draft: WebRecipeCaptureDraft?
  var errorMessage: String?
  var isLoading = false
  var isCommitting = false
  var isShowingDiscardConfirmation = false
  var didSave = false

  init(extensionContext: NSExtensionContext?) {
    self.extensionContext = extensionContext
  }

  var canSave: Bool {
    draft != nil && !isLoading && !isCommitting && !didSave
  }

  var hasUnsavedReviewChanges: Bool {
    draft != nil && !didSave
  }

  var editorialBlocks: [ParsedRecipeEditorialBlock] {
    get { draft?.page.editorialBlocks ?? [] }
    set { draft?.page.editorialBlocks = newValue }
  }

  var reviewTitle: String {
    get { draft?.page.title ?? "" }
    set { draft?.page.title = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
  }

  var reviewSummary: String {
    get { draft?.page.summary ?? "" }
    set { draft?.page.summary = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
  }

  var reviewServingsText: String {
    get { draft?.page.servingsText ?? "" }
    set { draft?.page.servingsText = newValue.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
  }

  var reviewTotalTimeText: String {
    get { draft?.page.totalTimeMinutes.map(String.init) ?? "" }
    set {
      let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
      draft?.page.totalTimeMinutes = trimmed.isEmpty ? nil : Int(trimmed)
    }
  }

  func loadSharedPage() async {
    isLoading = true
    defer { isLoading = false }

    do {
      let payload = try await ShareCaptureExtraction.payload(from: extensionContext)
      let capturedDraft = try await captureClient.capture(sharePayload: payload, capturedAt: now)
      draft = await captureClient.hydrateHeroImage(in: capturedDraft)
    } catch is CancellationError {
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func saveButtonTapped() async {
    guard let draft = curatedDraftForSave() else { return }
    isCommitting = true
    defer { isCommitting = false }

    do {
      let importDate = now
      let makeUUID = uuid
      let pendingChangeCountBeforeSave = try? await YesChefCloudSync
        .pendingRecordZoneChangeCount(in: database)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: importDate,
          uuid: { makeUUID() }
        )
      }
      if result.outcome == .imported, let pendingChangeCountBeforeSave {
        _ = try? await YesChefCloudSync.waitForPendingRecordZoneChanges(
          in: database,
          exceeding: pendingChangeCountBeforeSave
        )
      }
      DatabaseChangeBeacon.post()
      didSave = true
      extensionContext?.completeRequest(returningItems: nil)
    } catch is CancellationError {
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func cancelButtonTapped() {
    guard hasUnsavedReviewChanges else {
      discardCaptureButtonTapped()
      return
    }
    isShowingDiscardConfirmation = true
  }

  func discardCaptureButtonTapped() {
    extensionContext?.completeRequest(returningItems: nil)
  }

  func updateEditorialBlockText(_ text: String, at index: Int) {
    guard editorialBlocks.indices.contains(index) else { return }
    var blocks = editorialBlocks
    blocks[index].text = text
    editorialBlocks = blocks
  }

  func removeEditorialBlocks(atOffsets offsets: IndexSet) {
    var blocks = editorialBlocks
    blocks.remove(atOffsets: offsets)
    editorialBlocks = blocks
  }

  private func curatedDraftForSave() -> WebRecipeCaptureDraft? {
    guard var draft else { return nil }
    draft.page.editorialBlocks = draft.page.editorialBlocks
      .map { ParsedRecipeEditorialBlock(label: $0.label, text: $0.text) }
      .filter { !$0.text.isEmpty }
    self.draft = draft
    return draft
  }
}

private struct ShareCaptureView: View {
  @Bindable var model: ShareCaptureModel
  var setModalInPresentation: (Bool) -> Void

  var body: some View {
    NavigationStack {
      Form {
        if model.isLoading {
          Section {
            ProgressView("Reading shared page")
          }
        } else if let draft = model.draft {
          ShareCaptureReviewSections(model: model, draft: draft)
        } else {
          Section {
            Text(model.errorMessage ?? "Could not read that recipe page.")
              .foregroundStyle(.secondary)
          }
        }
      }
      .navigationTitle("Save to Yes Chef")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            model.cancelButtonTapped()
          }
          .disabled(model.isCommitting)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            Task { await model.saveButtonTapped() }
          } label: {
            if model.isCommitting {
              ProgressView()
            } else {
              Text("Save")
            }
          }
          .disabled(!model.canSave)
        }
      }
    }
    .confirmationDialog(
      "Discard this captured recipe?",
      isPresented: $model.isShowingDiscardConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard Capture", role: .destructive) {
        model.discardCaptureButtonTapped()
      }
      Button("Keep Editing", role: .cancel) {}
    } message: {
      Text("Your review edits have not been saved.")
    }
    .interactiveDismissDisabled(model.hasUnsavedReviewChanges)
    .onAppear {
      setModalInPresentation(model.hasUnsavedReviewChanges)
    }
    .onChange(of: model.hasUnsavedReviewChanges) { _, hasUnsavedReviewChanges in
      setModalInPresentation(hasUnsavedReviewChanges)
    }
  }
}

private struct ShareCaptureReviewSections: View {
  @Bindable var model: ShareCaptureModel
  let draft: WebRecipeCaptureDraft

  private var page: ParsedRecipePage {
    draft.page
  }

  var body: some View {
    Section("Review") {
      ShareStackedTextField(title: "Title", text: $model.reviewTitle)
      ShareStackedTextField(title: "Summary", text: $model.reviewSummary, axis: .vertical)
      ShareStackedTextField(title: "Servings", text: $model.reviewServingsText)
      ShareStackedTextField(title: "Total Time", text: $model.reviewTotalTimeText)
        .keyboardType(.numberPad)
    }

    Section("Source") {
      if let sourceURL = page.sourceURL {
        LabeledContent("URL") {
          Text(sourceURL.absoluteString)
            .textSelection(.enabled)
        }
      }
      if let publisherName = page.publisherName {
        LabeledContent("Source") {
          Text(publisherName)
        }
      }
      if let author = page.author {
        LabeledContent("Author") {
          Text(author)
        }
      }
    }

    if let heroImage {
      Section("Photo") {
        Image(uiImage: heroImage)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 220)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
    }

    if !page.warnings.isEmpty {
      Section("Warnings") {
        Text(page.warnings.map(\.shareReviewTitle).joined(separator: "\n"))
          .foregroundStyle(.secondary)
      }
    }

    if !model.editorialBlocks.isEmpty {
      Section("Notes") {
        ForEach(model.editorialBlocks.indices, id: \.self) { index in
          VStack(alignment: .leading, spacing: 8) {
            Text(model.editorialBlocks[index].label)
              .font(.headline)
              .foregroundStyle(.secondary)
            TextField("Note", text: editorialBlockTextBinding(at: index), axis: .vertical)
              .lineLimit(3...8)
          }
          .padding(.vertical, 4)
        }
        .onDelete { offsets in
          model.removeEditorialBlocks(atOffsets: offsets)
        }
      }
    }

    Section("Ingredients") {
      if ingredientText.isEmpty {
        Text("No ingredients found")
          .foregroundStyle(.secondary)
      } else {
        Text(ingredientText)
          .textSelection(.enabled)
      }
    }

    Section("Instructions") {
      if instructionText.isEmpty {
        Text("No instructions found")
          .foregroundStyle(.secondary)
      } else {
        Text(instructionText)
          .textSelection(.enabled)
      }
    }
  }

  private var ingredientText: String {
    page.ingredientSections
      .flatMap { section -> [String] in
        if let name = section.name {
          return [name] + section.lines
        }
        return section.lines
      }
      .joined(separator: "\n")
  }

  private var heroImage: UIImage? {
    guard let heroURL = page.imageURLs.first,
      let photo = page.processedImages[heroURL]
    else { return nil }
    return UIImage(data: photo.thumbnailData ?? photo.displayData)
  }

  private func editorialBlockTextBinding(at index: Int) -> Binding<String> {
    Binding {
      guard model.editorialBlocks.indices.contains(index) else { return "" }
      return model.editorialBlocks[index].text
    } set: { text in
      model.updateEditorialBlockText(text, at: index)
    }
  }

  private var instructionText: String {
    page.instructionSections
      .flatMap { section -> [String] in
        if let name = section.name {
          return [name] + section.steps
        }
        return section.steps
      }
      .joined(separator: "\n")
  }
}

private struct ShareSetupRequiredView: View {
  var message: String
  var done: () -> Void

  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Open Yes Chef Once",
        systemImage: "fork.knife",
        description: Text(message)
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: done)
        }
      }
    }
  }
}

@MainActor
private enum ShareCaptureExtraction {
  static func payload(from extensionContext: NSExtensionContext?) async throws -> WebRecipeSharePayload {
    let attachments = extensionContext?.inputItems
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] } ?? []

    var fallbackURL: URL?

    for attachment in attachments {
      if attachment.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
         let payload = try await loadPreprocessedPayload(from: attachment)
      {
        return payload
      }

      if fallbackURL == nil,
         attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier)
      {
        fallbackURL = try await loadURL(from: attachment)
      }
    }

    return WebRecipeSharePayload(sourceURL: fallbackURL, renderedHTML: nil)
  }

  private static func loadPreprocessedPayload(from provider: NSItemProvider) async throws -> WebRecipeSharePayload? {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard
          let dictionary = item as? [String: Any],
          let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
        else {
          continuation.resume(returning: nil)
          return
        }

        let html = (results["html"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = (results["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlString.flatMap(URL.init(string:))
        continuation.resume(
          returning: WebRecipeSharePayload(
            sourceURL: url,
            renderedHTML: html?.isEmpty == false ? html : nil
          )
        )
      }
    }
  }

  private static func loadURL(from provider: NSItemProvider) async throws -> URL? {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        if let url = item as? URL {
          continuation.resume(returning: url)
        } else if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
          continuation.resume(returning: URL(string: string))
        } else if let string = item as? String {
          continuation.resume(returning: URL(string: string))
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }
}

private struct ShareStackedTextField: View {
  let title: LocalizedStringKey
  @Binding var text: String
  var axis: Axis = .horizontal

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      TextField(title, text: $text, axis: axis)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private extension WebRecipeCaptureWarning {
  var shareReviewTitle: String {
    switch self {
    case .noStructuredRecipeData:
      "No structured recipe data found."
    case .truncatedStructuredData:
      "Structured recipe data appears truncated."
    case .untitledRecipe:
      "No title found."
    case .noIngredients:
      "No ingredients found."
    case .noInstructions:
      "No instructions found."
    }
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
