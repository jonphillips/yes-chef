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
    case cookingMode(Recipe.ID)
    case originalSnapshot(Recipe.ID)
    case deleteRecipe(Recipe.ID)
    case deleteArchivedRecipe(Recipe.ID)
    case filterRecipes
    case importReview
    case captureSummary(WebRecipeCaptureSummary)
    case importSummary(RecipeImportSummary)
    case backupSupplementSummary(RecipeBackupSupplementSummary)
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

  func reloadAfterExternalChange() async {
    try? await $recipeRows.load()
  }

  func addRecipeButtonTapped() {
    destination = .addRecipe
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

  func cookButtonTapped(recipeID: Recipe.ID) {
    destination = .cookingMode(recipeID)
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

    do {
      try database.write { db in
        try RecipeRepository.archive(recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
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
    do {
      try database.write { db in
        try RecipeRepository.restore(recipeID: recipeID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
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

    do {
      try database.write { db in
        try RecipeRepository.permanentlyDelete(recipeID: recipeID, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
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
final class BrowserModel {
  let page = WebPage.browser()
  var recents: [URL] = []
  var notice: String?
  var isCapturing = false
  var isLoadingComments = false

  func recordRecent(_ url: URL) {
    recents.removeAll { $0.absoluteString == url.absoluteString }
    recents.insert(url, at: 0)
    if recents.count > 12 {
      recents.removeSubrange(12...)
    }
  }

  func captureButtonTapped(
    page: WebPage,
    ingest: (String, URL?) async -> WebExtractionOutcome
  ) async -> WebExtractionOutcome {
    isCapturing = true
    notice = nil
    defer { isCapturing = false }

    guard let html = await page.currentDOM(), !html.isEmpty else {
      let message = "Couldn't read this page - try again once it's loaded."
      notice = message
      return .notFound(message: message)
    }

    let outcome = await ingest(html, page.url)
    switch outcome {
    case .extracted:
      notice = nil
    case .notFound(let message):
      notice = message
    }
    return outcome
  }

  func loadCommentsButtonTapped(page: WebPage) async {
    guard let playbook = BrowserCommentLoadingPlaybook.playbook(for: page.url) else {
      notice = "Comment loading is only available for NYT Cooking."
      return
    }

    isLoadingComments = true
    notice = nil
    defer { isLoadingComments = false }

    do {
      let result = try await playbook.load(on: page)
      switch result.status {
      case .loaded:
        notice = "Loaded \(result.commentCount) comments."
      case .notFound:
        notice = "Couldn't find NYT comments on this page."
      }
    } catch {
      notice = "Couldn't load comments - try again once the page settles."
    }
  }

  func noticeDismissButtonTapped() {
    notice = nil
  }

  func reloadAfterExternalChange() async {
  }
}

enum BrowserCommentLoadingPlaybook: Equatable {
  case nytCooking

  static func playbook(for url: URL?) -> Self? {
    guard let host = url?.host()?.lowercased() else { return nil }
    if host == "cooking.nytimes.com" {
      return .nytCooking
    }
    return nil
  }

  func load(on page: WebPage) async throws -> BrowserCommentLoadingResult {
    switch self {
    case .nytCooking:
      return try await loadNYTCookingComments(on: page)
    }
  }

  private func loadNYTCookingComments(on page: WebPage) async throws -> BrowserCommentLoadingResult {
    let value = try await page.callJavaScript(Self.nytCookingScript)
    guard let json = value as? String else {
      throw BrowserCommentLoadingError.invalidResult
    }
    return try JSONDecoder().decode(BrowserCommentLoadingResult.self, from: Data(json.utf8))
  }

  private static let nytCookingScript = #"""
  const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
  const classStartsWith = (element, prefix) =>
    Array.from(element.classList || []).some((className) => className.startsWith(prefix));
  const section = document.querySelector("#notes_section");

  if (!section) {
    return JSON.stringify({ status: "notFound", commentCount: 0, loadMoreClicks: 0 });
  }

  const noteCount = () =>
    Array.from(section.querySelectorAll("[class]"))
      .filter((element) => classStartsWith(element, "note_note__"))
      .length;
  const visibleButton = (button) =>
    !button.disabled && button.offsetParent !== null && getComputedStyle(button).visibility !== "hidden";
  const buttonText = (button) => (button.innerText || button.textContent || "").replace(/\s+/g, " ").trim();
  const buttons = () => Array.from(section.querySelectorAll("button, [role='tab']"));

  const helpfulTab = buttons().find((button) => buttonText(button).includes("Most Helpful"));
  if (helpfulTab && helpfulTab.getAttribute("aria-selected") !== "true") {
    helpfulTab.click();
    await sleep(1200);
  }

  let loadMoreClicks = 0;
  for (let index = 0; index < 4; index += 1) {
    const loadMore = buttons().find((button) =>
      visibleButton(button) &&
      (buttonText(button).includes("Show more comments") ||
        classStartsWith(button, "showmorebutton_showMoreButton__"))
    );
    if (!loadMore) { break; }

    const before = noteCount();
    loadMore.click();
    loadMoreClicks += 1;
    await sleep(1400);
    if (noteCount() <= before) {
      await sleep(900);
    }
  }

  return JSON.stringify({
    status: "loaded",
    commentCount: noteCount(),
    loadMoreClicks
  });
  """#
}

struct BrowserCommentLoadingResult: Decodable, Equatable {
  enum Status: String, Decodable {
    case loaded
    case notFound
  }

  var status: Status
  var commentCount: Int
  var loadMoreClicks: Int
}

enum BrowserCommentLoadingError: Error {
  case invalidResult
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

  func reset() {
    urlText = ""
    draft = nil
    errorMessage = nil
    isShowingError = false
    isShowingDiscardConfirmation = false
    isPresentingBrowser = false
    isFetching = false
    isCommitting = false
  }

  func cancelButtonTapped() -> Bool {
    guard hasUnsavedReviewChanges else { return true }
    isShowingDiscardConfirmation = true
    return false
  }

  func pastedText(_ text: String) {
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

/// A run of ingredient lines under an optional section heading, for grouped detail display.
struct IngredientLineGroup: Identifiable {
  let id: IngredientSection.ID
  var name: String?
  var lines: [IngredientLine]
}

@Observable
@MainActor
final class RecipeDetailModel {
  @CasePathable
  enum Destination {
    case scaling
    case chat(RecipeChatModel)
  }

  let recipeID: Recipe.ID
  let scaleContext: ScaleContext

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?
  @ObservationIgnored
  @Fetch var persistedScale: Double?

  var destination: Destination?
  var errorMessage: String?
  var isShowingError = false
  var scaleFactor = 1.0
  var scaleWholePart = 1
  var scaleFraction = ScaleFraction.none
  var pendingSubstitution: PendingIngredientSubstitution?
  var isFindingSubstitution = false
  private var lastAppliedPersistedScale: Double?

  init(recipeID: Recipe.ID, scaleContext: ScaleContext? = nil) {
    self.recipeID = recipeID
    self.scaleContext = scaleContext ?? .recipe(recipeID)
    _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
    _persistedScale = Fetch(
      wrappedValue: nil,
      RecipeScaleRequest(context: self.scaleContext),
      animation: .default
    )
  }

  var recipe: Recipe? {
    detail?.recipe
  }

  var ingredientLines: [IngredientLine] {
    detail?.ingredientLines.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  /// Ingredient lines grouped under their (optional) section heading, ordered by the
  /// section sort order, so recovered Paprika sections (e.g. CHICKEN / SAUCE) render as
  /// headings instead of a flat list.
  var ingredientGroups: [IngredientLineGroup] {
    guard let detail else { return [] }
    let linesBySection = Dictionary(grouping: detail.ingredientLines) { $0.sectionID }
    return detail.ingredientSections
      .sorted { $0.sortOrder < $1.sortOrder }
      .compactMap { section in
        let lines = (linesBySection[section.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
        guard !lines.isEmpty else { return nil }
        return IngredientLineGroup(id: section.id, name: section.name, lines: lines)
      }
  }

  var instructionSteps: [InstructionStep] {
    detail?.instructionSteps.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var visibleNotes: [RecipeNote] {
    detail?.notes.filter { $0.noteType != .retrospective } ?? []
  }

  var displayablePhotos: [RecipePhoto] {
    detail?.photos
      .filter { photo in
        photo.displayData != nil || photo.thumbnailData != nil
      } ?? []
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
    guard let scaledServings else { return nil }
    return "\(ScaleText.mixedNumber(scaledServings)) \(ScaleText.servingUnit(scaledServings))"
  }

  func scaleButtonTapped() {
    syncScalePickerFromCurrentScale()
    destination = .scaling
  }

  func chatButtonTapped() {
    guard let detail else { return }
    destination = .chat(RecipeChatModel(context: .recipe(RecipeChatRecipeContext(detail: detail))))
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

@Observable
@MainActor
final class CookingModeModel {
  let recipeID: Recipe.ID

  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?

  var checkedIngredientIDs: Set<IngredientLine.ID> = []
  var checkedStepIDs: Set<InstructionStep.ID> = []
  var focusedStepIndex = 0

  init(recipeID: Recipe.ID) {
    self.recipeID = recipeID
    _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
  }

  var ingredientLines: [IngredientLine] {
    detail?.ingredientLines.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var instructionSteps: [InstructionStep] {
    detail?.instructionSteps.sorted { $0.sortOrder < $1.sortOrder } ?? []
  }

  var currentStep: InstructionStep? {
    guard instructionSteps.indices.contains(focusedStepIndex) else { return nil }
    return instructionSteps[focusedStepIndex]
  }

  var visibleNotes: [RecipeNote] {
    detail?.notes.filter { $0.noteType != .retrospective } ?? []
  }

  func detailChanged(_ detail: RecipeDetailData?) {
    guard detail != nil else { return }
    focusedStepIndex = min(focusedStepIndex, max(instructionSteps.count - 1, 0))
  }

  func ingredientToggleButtonTapped(_ id: IngredientLine.ID) {
    toggle(id, in: &checkedIngredientIDs)
  }

  func stepToggleButtonTapped(_ id: InstructionStep.ID) {
    toggle(id, in: &checkedStepIDs)
  }

  private func toggle<ID>(_ id: ID, in ids: inout Set<ID>) {
    if ids.contains(id) {
      ids.remove(id)
    } else {
      ids.insert(id)
    }
  }
}
