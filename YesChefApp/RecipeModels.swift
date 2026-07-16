import CasePaths
import Dependencies
import Observation
import SwiftUI
import WebExtractorKit
import WebKit
import YesChefCore

@Observable
@MainActor
final class RecipeLibraryModel {
  @CasePathable
  enum Destination {
    case addRecipe
    case captureRecipe
    case editRecipe(Recipe.ID)
    case originalSnapshot(Recipe.ID)
    case deleteRecipe(Recipe.ID)
    case deleteArchivedRecipe(Recipe.ID)
    case filterRecipes
    case importReview
    case captureSummary(WebRecipeCaptureSummary)
    case importSummary(RecipeImportSummary)
    case backupSupplementSummary(RecipeBackupSupplementSummary)
    case workbench(WorkbenchPresentation)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(RecipeListRequest(), animation: .default) var recipeRows: [RecipeListRowData] = []

  var destination: Destination?
  var errorMessage: String?
  var isShowingError = false
  var isImporting = false
  var importActivityTitle = "Importing"
  var isPresentingPaprikaImporter = false
  var isPresentingPaprikaBackupSupplementer = false
  var captureModel = RecipeCaptureModel()
  var importModel = RecipeImportModel()
  var searchText = ""
  var selectedRecipeID: Recipe.ID?
  var sortOrder = RecipeListSort.title
  var libraryScope = RecipeLibraryScope.main
  var showsFavoritesOnly = false
  var showsPhotosOnly = false
  var selectedCategoryNames: Set<String> = []
  var selectedTagNames: Set<String> = []
  var selectedCuisine: String?
  var selectedCourse: String?
  var selectedSourceNames: Set<String> = []
  var selectedAuthorNames: Set<String> = []
  var isSelectingWorkbenchRecipes = false
  var selectedWorkbenchRecipeIDs: Set<Recipe.ID> = []

  func reloadAfterExternalChange() async {
    try? await $recipeRows.load()
  }

  func addRecipeButtonTapped() {
    destination = .addRecipe
  }

  func workbenchSelectionButtonTapped() {
    selectedWorkbenchRecipeIDs = []
    isSelectingWorkbenchRecipes = true
  }

  func cancelWorkbenchSelectionButtonTapped() {
    selectedWorkbenchRecipeIDs = []
    isSelectingWorkbenchRecipes = false
  }

  func workbenchTheseButtonTapped() {
    let recipeIDs = selectedWorkbenchRecipeIDs
    guard !recipeIDs.isEmpty else { return }
    let selectedRows = recipeRows.filter { recipeIDs.contains($0.recipe.id) && !$0.recipe.archived }
    let title = selectedRows.count == 1
      ? selectedRows[0].recipe.title
      : "Recipe Workbench"

    do {
      let workbenchID = try database.write { db in
        try WorkbenchRepository.addWorkbench(
          title: title,
          candidateRecipeIDs: selectedRows.map(\.recipe.id),
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      selectedWorkbenchRecipeIDs = []
      isSelectingWorkbenchRecipes = false
      destination = .workbench(WorkbenchPresentation(workbenchID: workbenchID))
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func captureRecipeButtonTapped() {
    captureModel.reset()
    destination = .captureRecipe
  }

  func webCaptureCompleted(_ result: RecipeImportBundleResult) {
    selectedRecipeID = result.recipeID
    destination = .captureSummary(WebRecipeCaptureSummary(result: result))
  }

  func importPaprikaExportButtonTapped() {
    isPresentingPaprikaImporter = true
  }

  func supplementPaprikaBackupButtonTapped() {
    isPresentingPaprikaBackupSupplementer = true
  }

  func paprikaExportSelected(_ result: Result<URL, any Error>) async {
    do {
      let sourceURL = try result.get()
      importActivityTitle = "Preparing Import"
      isImporting = true
      defer { isImporting = false }

      try await importModel.prepareImport(from: sourceURL)
      destination = .importReview
    } catch CocoaError.userCancelled {
      isImporting = false
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      isImporting = false
    }
  }

  func paprikaImportCommitted(_ commit: RecipeImportCommitResult) {
    selectedRecipeID = commit.selectedRecipeID ?? selectedRecipeID
    destination = .importSummary(commit.summary)
  }

  func undoPaprikaImportButtonTapped(_ summary: RecipeImportSummary) async {
    guard !summary.importedIDs.isEmpty else { return }
    importActivityTitle = "Undoing Import"
    isImporting = true
    defer { isImporting = false }

    do {
      let rollback = try await importModel.rollbackImportedRecipes(summary.importedIDs)
      if rollback.recipes > 0, let selectedRecipeID, summary.importedIDs.contains(selectedRecipeID) {
        self.selectedRecipeID = nil
      }
      destination = .importSummary(summary.rolledBack(rollback))
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func paprikaBackupSelected(_ result: Result<URL, any Error>) async {
    do {
      let sourceURL = try result.get()
      importActivityTitle = "Supplementing"
      isImporting = true
      defer { isImporting = false }

      let parseResult = try await PaprikaImportWorkspace.parseRecipeBackup(from: sourceURL)
      var summary = try await database.write { db in
        try RecipeRepository.supplementCreatedDates(from: parseResult.records, in: db)
      }
      summary.backupRecipeCount += parseResult.skippedEntryCount
      summary.skippedRecordCount += parseResult.skippedEntryCount
      destination = .backupSupplementSummary(RecipeBackupSupplementSummary(summary: summary))
    } catch CocoaError.userCancelled {
      isImporting = false
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      isImporting = false
    }
  }

  func editButtonTapped(recipeID: Recipe.ID) {
    destination = .editRecipe(recipeID)
  }

  func originalSnapshotButtonTapped(recipeID: Recipe.ID) {
    destination = .originalSnapshot(recipeID)
  }

  func deleteButtonTapped(recipeID: Recipe.ID) {
    destination = .deleteRecipe(recipeID)
  }

  func confirmDeleteRecipeButtonTapped(recipeID: Recipe.ID) {
    destination = nil
    if selectedRecipeID == recipeID {
      selectedRecipeID = nil
    }

    Task {
      let now = now
      do {
        try await database.write { db in
          try RecipeRepository.archive(recipeID: recipeID, in: db, now: now)
        }
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  var archivedRecipeRows: [RecipeListRowData] {
    recipeRows
      .filter { $0.recipe.archived }
      .sorted {
        if $0.recipe.dateModified != $1.recipe.dateModified {
          return $0.recipe.dateModified > $1.recipe.dateModified
        }
        return $0.recipe.title.localizedStandardCompare($1.recipe.title) == .orderedAscending
      }
  }

  func restoreArchivedRecipeButtonTapped(recipeID: Recipe.ID) {
    Task {
      let now = now
      do {
        try await database.write { db in
          try RecipeRepository.restore(recipeID: recipeID, in: db, now: now)
        }
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  func deleteArchivedRecipeButtonTapped(recipeID: Recipe.ID) {
    destination = .deleteArchivedRecipe(recipeID)
  }

  func confirmDeleteArchivedRecipeButtonTapped(recipeID: Recipe.ID) {
    destination = nil
    if selectedRecipeID == recipeID {
      selectedRecipeID = nil
    }

    Task {
      do {
        try await database.write { db in
          try RecipeRepository.permanentlyDelete(recipeID: recipeID, in: db)
        }
      } catch {
        errorMessage = String(describing: error)
        isShowingError = true
      }
    }
  }

  func title(for recipeID: Recipe.ID) -> String {
    recipeRows.first { $0.recipe.id == recipeID }?.recipe.title ?? "this recipe"
  }
}

@Observable
@MainActor
final class RecipeImportModel {
  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid

  var draft: PaprikaRecipeImportDraft?
  var errorMessage: String?
  var isShowingError = false
  var isCommitting = false

  var canCommit: Bool {
    draft != nil && !isCommitting
  }

  func reset() {
    draft = nil
    errorMessage = nil
    isShowingError = false
    isCommitting = false
  }

  func prepareImport(from sourceURL: URL) async throws {
    reset()
    let importDate = now
    let makeUUID = uuid
    let parseResult = try await PaprikaImportWorkspace.parseExport(from: sourceURL)
#if DEBUG
    let preserveRawImportHTML = true
#else
    let preserveRawImportHTML = false
#endif
    let bundles = try parseResult.recipes.map { recipe in
      try recipe.makeRecipeBundle(
        now: importDate,
        uuid: { makeUUID() },
        preserveRawImportHTML: preserveRawImportHTML
      )
    }
    let preview = try await database.read { db in
      RecipeRepository.previewImportBundles(
        bundles,
        against: try RecipeImportRef.fetchAll(db)
      )
    }
    draft = PaprikaRecipeImportDraft(
      parseResult: parseResult,
      bundles: bundles,
      preview: preview,
      importDate: importDate
    )
  }

  func commitButtonTapped() async -> RecipeImportCommitResult? {
    guard let draft else { return nil }
    isCommitting = true
    defer { isCommitting = false }

    do {
      let makeUUID = uuid
      let importResult = try await database.write { db in
        try RecipeRepository.importBundles(
          draft.bundles,
          in: db,
          now: draft.importDate,
          uuid: { makeUUID() }
        )
      }
      let summary = RecipeImportSummary(parseResult: draft.parseResult, importResult: importResult)
      return RecipeImportCommitResult(
        summary: summary,
        selectedRecipeID: importResult.importedIDs.first ?? importResult.results.first?.recipeID
      )
    } catch is CancellationError {
      return nil
    } catch {
      showError(String(describing: error))
      return nil
    }
  }

  func rollbackImportedRecipes(_ recipeIDs: [Recipe.ID]) async throws -> RecipeImportRollbackResult {
    try await database.write { db in
      try RecipeRepository.rollbackImportedRecipes(recipeIDs: recipeIDs, in: db)
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    isShowingError = true
  }
}

struct PaprikaRecipeImportDraft: Identifiable {
  let id = UUID()
  var parseResult: PaprikaHTMLImportResult
  var bundles: [RecipeBundleCoding.RecipeBundle]
  var preview: RecipeImportBatchPreview
  var importDate: Date
}

struct RecipeImportCommitResult {
  var summary: RecipeImportSummary
  var selectedRecipeID: Recipe.ID?
}

@Observable
@MainActor
final class RecipeCaptureModel {
  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Dependency(\.webRecipeCaptureClient) private var captureClient

  var urlText = ""
  var draft: WebRecipeCaptureDraft?
  var errorMessage: String?
  var isShowingError = false
  var isShowingDiscardConfirmation = false
  var isPresentingBrowser = false
  var isFetching = false
  var isCommitting = false
  var readerFeedbackProposals: [ReaderFeedbackTip] = []
  var readerFeedbackComments: [RawComment] = []

  var canFetch: Bool {
    normalizedURL != nil && !isFetching && !isCommitting
  }

  var canCommit: Bool {
    draft != nil && !isFetching && !isCommitting
  }

  var hasUnsavedReviewChanges: Bool {
    draft != nil
  }

  var editorialBlocks: [ParsedRecipeEditorialBlock] {
    get { draft?.page.editorialBlocks ?? [] }
    set { draft?.page.editorialBlocks = newValue }
  }

  var readerFeedbackBlocks: [ParsedRecipeReaderFeedbackBlock] {
    get { draft?.page.readerFeedbackBlocks ?? [] }
    set { draft?.page.readerFeedbackBlocks = newValue }
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

  func reset() {
    urlText = ""
    draft = nil
    errorMessage = nil
    isShowingError = false
    isShowingDiscardConfirmation = false
    isPresentingBrowser = false
    isFetching = false
    isCommitting = false
    readerFeedbackProposals = []
    readerFeedbackComments = []
  }

  func cancelButtonTapped() -> Bool {
    guard hasUnsavedReviewChanges else { return true }
    isShowingDiscardConfirmation = true
    return false
  }

  func pastedText(_ text: String?) {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      showError("No recipe URL was pasted.")
      return
    }
    urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func fetchButtonTapped() async {
    guard let url = normalizedURL else {
      showError("Enter a valid recipe URL.")
      return
    }

    isFetching = true
    defer { isFetching = false }

    do {
      let capturedDraft = try await captureClient.capture(url: url, capturedAt: now)
      draft = await captureClient.hydrateHeroImage(in: capturedDraft)
    } catch is CancellationError {
    } catch {
      showError(String(describing: error))
    }
  }

  func ingestBrowserCapture(html: String, sourceURL: URL?) async -> WebExtractionOutcome {
    let capturedDraft = captureClient.browserCapture(
      html: html,
      sourceURL: sourceURL,
      capturedAt: now
    )
    guard capturedDraft.isUsable else {
      return .notFound(message: "No recipe found on this page - sign in or open the recipe, then try again.")
    }
    draft = await captureClient.hydrateHeroImage(in: capturedDraft)
    return .extracted
  }

  func stageReaderFeedback(tips: [ReaderFeedbackTip], comments: [RawComment]) {
    readerFeedbackComments = comments
    guard !tips.isEmpty else { return }
    let acceptedKeys = Set(readerFeedbackBlocks.map { $0.text.lowercased() })
    var seen = Set(readerFeedbackProposals.map { $0.text.lowercased() })
    readerFeedbackProposals.append(
      contentsOf: tips.filter { tip in
        let key = tip.text.lowercased()
        return !acceptedKeys.contains(key) && seen.insert(key).inserted
      }
    )
  }

  func promoteReaderFeedbackComment(_ comment: RawComment, commentNumber: Int) -> ReaderFeedbackTip {
    let tip = ReaderFeedbackTip(
      text: comment.text,
      provenanceKind: .singularPreserved,
      supportCount: 1,
      backingComments: [
        ReaderFeedbackBackingComment(
          commentNumber: commentNumber,
          text: comment.text,
          helpfulCount: comment.helpfulCount
        )
      ]
    )
    stageReaderFeedback(tips: [tip], comments: readerFeedbackComments)
    return tip
  }

  func acceptReaderFeedbackTip(_ tip: ReaderFeedbackTip, approvedText: String) {
    let trimmed = approvedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var blocks = readerFeedbackBlocks
    blocks.append(ParsedRecipeReaderFeedbackBlock(text: trimmed))
    readerFeedbackBlocks = blocks
    discardReaderFeedbackTip(tip)
  }

  func discardReaderFeedbackTip(_ tip: ReaderFeedbackTip) {
    readerFeedbackProposals.removeAll { $0.id == tip.id }
  }

  func commitButtonTapped() async -> RecipeImportBundleResult? {
    guard let draft = curatedDraftForCommit() else { return nil }
    isCommitting = true
    defer { isCommitting = false }

    do {
      let importDate = now
      let makeUUID = uuid
      return try await database.write { db in
        try RecipeRepository.importCapturedRecipe(
          draft,
          in: db,
          now: importDate,
          uuid: { makeUUID() }
        )
      }
    } catch is CancellationError {
      return nil
    } catch {
      showError(String(describing: error))
      return nil
    }
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

  func updateReaderFeedbackBlockText(_ text: String, at index: Int) {
    guard readerFeedbackBlocks.indices.contains(index) else { return }
    var blocks = readerFeedbackBlocks
    blocks[index].text = text
    readerFeedbackBlocks = blocks
  }

  func removeReaderFeedbackBlocks(atOffsets offsets: IndexSet) {
    var blocks = readerFeedbackBlocks
    blocks.remove(atOffsets: offsets)
    readerFeedbackBlocks = blocks
  }

  var browserStartURL: URL {
    if let normalizedURL {
      return normalizedURL
    }
    return WebAddress.duckDuckGo("recipe") ?? URL(string: "https://duckduckgo.com")!
  }

  private func curatedDraftForCommit() -> WebRecipeCaptureDraft? {
    guard var draft else { return nil }
    draft.page.editorialBlocks = draft.page.editorialBlocks
      .map { ParsedRecipeEditorialBlock(label: $0.label, text: $0.text) }
      .filter { !$0.text.isEmpty }
    draft.page.readerFeedbackBlocks = draft.page.readerFeedbackBlocks
      .map { ParsedRecipeReaderFeedbackBlock(text: $0.text) }
      .filter { !$0.text.isEmpty }
    self.draft = draft
    return draft
  }

  private var normalizedURL: URL? {
    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let url = URL(string: candidate), url.host()?.isEmpty == false else { return nil }
    return url
  }

  private func showError(_ message: String) {
    errorMessage = message
    isShowingError = true
  }
}

struct WebRecipeCaptureSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var title: String
  var outcome: RecipeImportOutcome
  var warningCount: Int

  init(result: RecipeImportBundleResult) {
    self.title = result.title
    self.outcome = result.outcome
    self.warningCount = result.warnings.count
  }

  var message: String {
    var lines: [String]
    switch outcome {
    case .imported:
      lines = ["Saved \(title)."]
    case .alreadyImported:
      lines = ["Skipped \(title) because it is already in your library."]
    }
    if warningCount > 0 {
      lines.append("\(warningCount) identity \(warningCount == 1 ? "warning" : "warnings").")
    }
    return lines.joined(separator: "\n")
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

struct RecipeImportSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var importedCount: Int
  var alreadyImportedCount: Int
  var warningCount: Int
  var identityWarningCount: Int
  var missingRecipePageCount: Int
  var missingPhotoCount: Int
  var unreadableRecipeCount: Int
  var importedIDs: [Recipe.ID]
  var rollbackDeletedRecipeCount: Int

  init(
    importedCount: Int,
    alreadyImportedCount: Int,
    warningCount: Int,
    identityWarningCount: Int,
    missingRecipePageCount: Int,
    missingPhotoCount: Int,
    unreadableRecipeCount: Int,
    importedIDs: [Recipe.ID] = [],
    rollbackDeletedRecipeCount: Int = 0
  ) {
    self.importedCount = importedCount
    self.alreadyImportedCount = alreadyImportedCount
    self.warningCount = warningCount
    self.identityWarningCount = identityWarningCount
    self.missingRecipePageCount = missingRecipePageCount
    self.missingPhotoCount = missingPhotoCount
    self.unreadableRecipeCount = unreadableRecipeCount
    self.importedIDs = importedIDs
    self.rollbackDeletedRecipeCount = rollbackDeletedRecipeCount
  }

  init(parseResult: PaprikaHTMLImportResult, importResult: RecipeImportBatchResult) {
    self.init(
      importedCount: importResult.importedCount,
      alreadyImportedCount: importResult.alreadyImportedCount,
      warningCount: parseResult.warnings.count + importResult.warnings.count,
      identityWarningCount: importResult.warnings.count,
      missingRecipePageCount: parseResult.warnings
        .filter { $0.kind == .missingRecipePages }
        .compactMap(\.affectedCount)
        .reduce(0, +),
      missingPhotoCount: parseResult.warnings.filter { $0.kind == .missingPhoto }.count,
      unreadableRecipeCount: parseResult.warnings.filter { $0.kind == .unreadableRecipe }.count,
      importedIDs: importResult.importedIDs
    )
  }

  var message: String {
    var lines = ["Imported \(importedCount) \(importedCount == 1 ? "recipe" : "recipes")."]
    if rollbackDeletedRecipeCount > 0 {
      lines = ["Undo removed \(rollbackDeletedRecipeCount) imported \(rollbackDeletedRecipeCount == 1 ? "recipe" : "recipes")."]
    }
    if alreadyImportedCount > 0 {
      lines.append("Skipped \(alreadyImportedCount) already-imported \(alreadyImportedCount == 1 ? "recipe" : "recipes").")
    }
    if missingRecipePageCount > 0 {
      lines.append("\(missingRecipePageCount) index \(missingRecipePageCount == 1 ? "entry was" : "entries were") missing from the ZIP.")
    }
    if missingPhotoCount > 0 {
      lines.append("\(missingPhotoCount) image \(missingPhotoCount == 1 ? "file was" : "files were") missing.")
    }
    if unreadableRecipeCount > 0 {
      lines.append("\(unreadableRecipeCount) recipe \(unreadableRecipeCount == 1 ? "page could" : "pages could") not be read.")
    }
    if identityWarningCount > 0 {
      lines.append("\(identityWarningCount) import identity \(identityWarningCount == 1 ? "warning" : "warnings").")
    }
    if warningCount == 0 {
      lines.append("No warnings.")
    }
    return lines.joined(separator: "\n")
  }

  var canUndo: Bool {
    rollbackDeletedRecipeCount == 0 && !importedIDs.isEmpty
  }

  func rolledBack(_ rollback: RecipeImportRollbackResult) -> Self {
    RecipeImportSummary(
      importedCount: importedCount,
      alreadyImportedCount: alreadyImportedCount,
      warningCount: warningCount,
      identityWarningCount: identityWarningCount,
      missingRecipePageCount: missingRecipePageCount,
      missingPhotoCount: missingPhotoCount,
      unreadableRecipeCount: unreadableRecipeCount,
      importedIDs: rollback.recipes > 0 ? [] : importedIDs,
      rollbackDeletedRecipeCount: rollback.recipes
    )
  }
}

struct RecipeBackupSupplementSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var summary: PaprikaRecipeBackupSupplementSummary

  var message: String {
    [
      "Read \(summary.backupRecipeCount) \(summary.backupRecipeCount == 1 ? "backup recipe" : "backup recipes").",
      "Updated \(summary.updatedRecipeCount) \(summary.updatedRecipeCount == 1 ? "recipe" : "recipes").",
      "Left \(summary.unchangedRecipeCount) already-correct \(summary.unchangedRecipeCount == 1 ? "recipe" : "recipes") unchanged.",
      "\(summary.unmatchedRecipeCount) did not match an existing recipe.",
      "\(summary.ambiguousRecipeCount) had ambiguous title matches.",
      "\(summary.skippedRecordCount) \(summary.skippedRecordCount == 1 ? "record was" : "records were") skipped."
    ]
    .joined(separator: "\n")
  }
}

@Observable
@MainActor
final class RecipeDetailModel {
  @CasePathable
  enum Destination {
    case scaling
    case chat(RecipeChatModel)
    case workbench(WorkbenchPresentation)
    case adjustmentReview(RecipeAdjustmentReviewState)
  }

  let recipeID: Recipe.ID
  let scaleContext: ScaleContext

  @ObservationIgnored
  @Dependency(\.date.now) var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) var database
  @ObservationIgnored
  @Dependency(\.defaultSyncEngine) var syncEngine
  @ObservationIgnored
  @Dependency(\.uuid) var uuid
  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?
  @ObservationIgnored
  @Fetch var workbenchCandidateLinks: [WorkbenchCandidateLink] = []
  @ObservationIgnored
  @Fetch var persistedScale: Double?

  var destination: Destination?
  var errorMessage: String?
  var isShowingError = false
  var scaleFactor = 1.0
  var scaleWholePart = 1
  var scaleFraction = ScaleFraction.none
  var adjustmentRestorePoint: RecipeAdjustmentRestorePoint?
  @ObservationIgnored let detailFetchAnimationDescription: String
  private var lastAppliedPersistedScale: Double?

  init(recipeID: Recipe.ID, scaleContext: ScaleContext? = nil) {
    self.recipeID = recipeID
    self.scaleContext = scaleContext ?? .recipe(recipeID)
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-YesChefDisableDetailFetchAnimation") {
      detailFetchAnimationDescription = "nil"
      _detail = Fetch(
        wrappedValue: nil,
        RecipeDetailRequest(recipeID: recipeID)
      )
    } else {
      detailFetchAnimationDescription = "default"
      _detail = Fetch(
        wrappedValue: nil,
        RecipeDetailRequest(recipeID: recipeID),
        animation: .default
      )
    }
    #else
    detailFetchAnimationDescription = "default"
    _detail = Fetch(
      wrappedValue: nil,
      RecipeDetailRequest(recipeID: recipeID),
      animation: .default
    )
    #endif
    _workbenchCandidateLinks = Fetch(
      wrappedValue: [],
      RecipeWorkbenchLinksRequest(recipeID: recipeID),
      animation: .default
    )
    _persistedScale = Fetch(
      wrappedValue: nil,
      RecipeScaleRequest(context: self.scaleContext),
      animation: .default
    )
  }

  var displayablePhotos: [RecipeDetailPhoto] {
    detail?.photos.filter(\.isDisplayable) ?? []
  }

  var primaryDisplayPhoto: RecipeDetailPhoto? {
    RecipePhotoCover.coverPhoto(
      coverPhotoID: recipe?.coverPhotoID,
      from: displayablePhotos
    )
  }

  var makeAhead: String? {
    recipe?.makeAhead?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? recipe?.makeAhead
      : nil
  }

  var chefItUp: String? {
    recipe?.chefItUp?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
      ? recipe?.chefItUp
      : nil
  }

  var serveWithItems: [ServeWithItem] {
    ServeWithCoding.decode(recipe?.serveWith)
  }

  var baseServings: Double? {
    recipe?.servings
  }

  var scaledServings: Double? {
    baseServings.map { $0 * scaleFactor }
  }

  var scaleSummary: String {
    let factor = ScaleText.factor(scaleFactor)
    guard let scaledServings else { return factor }
    return "\(ScaleText.mixedNumber(scaledServings)) \(ScaleText.servingUnit(scaledServings)) · \(factor)"
  }

  var scaledServingsSummary: String? {
    RecipeYieldScaler.scaledText(recipe?.servingsText ?? recipe?.yieldText, factor: scaleFactor)
  }

  func scaleButtonTapped() {
    syncScalePickerFromCurrentScale()
    destination = .scaling
  }

  func chatButtonTapped() {
    guard let detail else { return }
    // Toggle: Ask is a non-modal companion on wide iPad, so its trigger stays live
    // beside the open panel. Re-tapping closes it (rather than rebuilding the model and
    // discarding the scratch transcript). See the Menu recipe-browser toggle for the pattern.
    if destination.chat != nil {
      destination = nil
      return
    }
    destination = .chat(RecipeChatModel(context: .recipe(RecipeChatRecipeContext(detail: detail))))
  }

  func openWorkbenchButtonTapped() {
    guard let recipe = detail?.recipe else { return }
    do {
      let workbenchID = try database.write { db in
        try WorkbenchRepository.addWorkbench(
          title: recipe.title,
          candidateRecipeIDs: [recipe.id],
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = .workbench(WorkbenchPresentation(workbenchID: workbenchID))
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  

  func clearMakeAheadButtonTapped() {
    do {
      try database.write { db in
        try RecipeRepository.clearMakeAhead(recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func updateReaderFeedbackNote(_ note: RecipeNote, text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != note.text else { return }
    guard !trimmed.isEmpty else {
      deleteReaderFeedbackNote(note)
      return
    }
    do {
      try database.write { db in
        try RecipeRepository.updateReaderFeedbackNote(id: note.id, text: trimmed, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteReaderFeedbackNote(_ note: RecipeNote) {
    do {
      try database.write { db in
        try RecipeRepository.deleteReaderFeedbackNote(id: note.id, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func coverPhotoButtonTapped(_ coverPhotoID: RecipePhoto.ID?) {
    do {
      try database.write { db in
        try RecipeRepository.setCoverPhotoID(
          coverPhotoID,
          recipeID: recipeID,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func resetScaleButtonTapped() {
    setScaleFactor(1, persist: true)
    syncScalePickerFromCurrentScale()
  }

  func scalePickerChanged() {
    var value = Double(scaleWholePart) + scaleFraction.value
    if value < ScaleFraction.minimumScale {
      scaleWholePart = 0
      scaleFraction = .oneThird
      value = ScaleFraction.minimumScale
    }
    setScaleFactor(value, persist: true)
  }

  func persistedScaleChanged(_ persistedScale: Double?) {
    guard let persistedScale else { return }
    guard lastAppliedPersistedScale != persistedScale else { return }
    lastAppliedPersistedScale = persistedScale
    setScaleFactor(persistedScale, persist: false)
    syncScalePickerFromCurrentScale()
  }

  private func syncScalePickerFromCurrentScale() {
    let selection = ScaleFraction.nearestSelection(to: scaleFactor)
    scaleWholePart = selection.whole
    scaleFraction = selection.fraction
  }

  private func setScaleFactor(_ scaleFactor: Double, persist: Bool) {
    guard self.scaleFactor != scaleFactor else { return }
    self.scaleFactor = scaleFactor
    guard persist else { return }
    persistScaleFactor()
  }

  private func persistScaleFactor() {
    do {
      try database.write { db in
        try RecipeScaleRepository.setScale(scaleFactor, for: scaleContext, in: db)
      }
      lastAppliedPersistedScale = scaleFactor
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

}
