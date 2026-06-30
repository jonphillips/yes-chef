import CasePaths
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
    let bundles = try parseResult.recipes.map { recipe in
      try recipe.makeRecipeBundle(now: importDate, uuid: { makeUUID() })
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

  func noticeDismissButtonTapped() {
    notice = nil
  }

  func reloadAfterExternalChange() async {
  }
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
  var isPresentingBrowser = false
  var isFetching = false
  var isCommitting = false

  var canFetch: Bool {
    normalizedURL != nil && !isFetching && !isCommitting
  }

  var canCommit: Bool {
    draft != nil && !isFetching && !isCommitting
  }

  func reset() {
    urlText = ""
    draft = nil
    errorMessage = nil
    isShowingError = false
    isPresentingBrowser = false
    isFetching = false
    isCommitting = false
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
      draft = try await captureClient.capture(url: url, capturedAt: now)
    } catch is CancellationError {
    } catch {
      showError(String(describing: error))
    }
  }

  func ingestBrowserCapture(html: String, sourceURL: URL?) -> WebExtractionOutcome {
    let capturedDraft = captureClient.browserCapture(
      html: html,
      sourceURL: sourceURL,
      capturedAt: now
    )
    guard capturedDraft.isUsable else {
      return .notFound(message: "No recipe found on this page - sign in or open the recipe, then try again.")
    }
    draft = capturedDraft
    return .extracted
  }

  func commitButtonTapped() async -> RecipeImportBundleResult? {
    guard let draft else { return nil }
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

  var browserStartURL: URL {
    if let normalizedURL {
      return normalizedURL
    }
    return WebAddress.duckDuckGo("recipe") ?? URL(string: "https://duckduckgo.com")!
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
  }

  let recipeID: Recipe.ID

  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?

  var destination: Destination?
  var scaleFactor = 1.0
  var scaleWholePart = 1
  var scaleFraction = ScaleFraction.none

  init(recipeID: Recipe.ID) {
    self.recipeID = recipeID
    _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
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
        photo.kind != .referenceDocument
          && (photo.displayData != nil || photo.thumbnailData != nil)
      } ?? []
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

  func scaleButtonTapped() {
    syncScalePickerFromCurrentScale()
    destination = .scaling
  }

  func resetScaleButtonTapped() {
    scaleFactor = 1
    syncScalePickerFromCurrentScale()
  }

  func setScaledServings(_ servings: Double) {
    guard let baseServings, baseServings > 0 else { return }
    scaleFactor = servings / baseServings
  }

  func scalePickerChanged() {
    let value = Double(scaleWholePart) + scaleFraction.value
    if baseServings == nil {
      scaleFactor = value
    } else {
      setScaledServings(value)
    }
  }

  private func syncScalePickerFromCurrentScale() {
    let value = scaledServings ?? scaleFactor
    let selection = ScaleFraction.nearestSelection(to: value)
    scaleWholePart = selection.whole
    scaleFraction = selection.fraction
  }
}

enum ScaleFraction: String, CaseIterable, Identifiable {
  case none
  case oneHalf
  case oneThird
  case oneFourth
  case oneFifth
  case oneEighth
  case twoThirds
  case threeFourths

  var id: Self { self }

  var label: String {
    switch self {
    case .none: "-"
    case .oneHalf: "1/2"
    case .oneThird: "1/3"
    case .oneFourth: "1/4"
    case .oneFifth: "1/5"
    case .oneEighth: "1/8"
    case .twoThirds: "2/3"
    case .threeFourths: "3/4"
    }
  }

  var value: Double {
    switch self {
    case .none: 0
    case .oneHalf: 1.0 / 2.0
    case .oneThird: 1.0 / 3.0
    case .oneFourth: 1.0 / 4.0
    case .oneFifth: 1.0 / 5.0
    case .oneEighth: 1.0 / 8.0
    case .twoThirds: 2.0 / 3.0
    case .threeFourths: 3.0 / 4.0
    }
  }

  static func nearestSelection(to value: Double) -> (whole: Int, fraction: ScaleFraction) {
    var bestWhole = 1
    var bestFraction = ScaleFraction.none
    var bestDistance = Double.greatestFiniteMagnitude

    for whole in 1...10 {
      for fraction in ScaleFraction.allCases {
        let candidate = Double(whole) + fraction.value
        let distance = abs(candidate - value)
        if distance < bestDistance {
          bestWhole = whole
          bestFraction = fraction
          bestDistance = distance
        }
      }
    }

    return (bestWhole, bestFraction)
  }
}

enum ScaleText {
  static func factor(_ factor: Double) -> String {
    if factor == 1 { return "1x" }
    return "\(number(factor))x"
  }

  static func number(_ value: Double) -> String {
    if value.rounded() == value {
      return "\(Int(value))"
    }
    return value.formatted(.number.precision(.fractionLength(0...2)))
  }

  static func mixedNumber(_ value: Double) -> String {
    let whole = Int(value.rounded(.down))
    let fractionValue = value - Double(whole)
    let fraction = ScaleFraction.allCases
      .filter { $0 != .none }
      .min { lhs, rhs in
        abs(lhs.value - fractionValue) < abs(rhs.value - fractionValue)
      }

    guard let fraction, abs(fraction.value - fractionValue) < 0.01 else {
      return number(value)
    }
    if whole == 0 {
      return fraction.label
    }
    return "\(whole) \(fraction.label)"
  }

  static func servingUnit(_ value: Double) -> String {
    value == 1 ? "serving" : "servings"
  }
}

@Observable
@MainActor
final class RecipeEditorModel {
  let recipeID: Recipe.ID?

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?
  @ObservationIgnored
  @Fetch(CategoryListRequest(), animation: .default) var categories: [YesChefCore.Category] = []

  var draft = RecipeEditorDraft()
  var errorMessage: String?
  var isShowingError = false
  private var hasLoadedDraft = false

  init(recipeID: Recipe.ID?) {
    self.recipeID = recipeID
    if let recipeID {
      _detail = Fetch(wrappedValue: nil, RecipeDetailRequest(recipeID: recipeID), animation: .default)
    } else {
      _detail = Fetch(wrappedValue: nil)
    }
  }

  var isSavingDisabled: Bool {
    draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var categoryRows: [CategoryHierarchy.DisplayRow] {
    CategoryHierarchy.displayRows(from: categories)
  }

  var selectedCategoryIDs: Set<YesChefCore.Category.ID> {
    draft.selectedCategoryIDs ?? []
  }

  var selectedCategorySummary: String {
    let selectedRows = categoryRows.filter { selectedCategoryIDs.contains($0.category.id) }
    guard !selectedRows.isEmpty else { return "No categories" }
    return selectedRows.map(\.displayName).joined(separator: ", ")
  }

  func detailChanged(_ detail: RecipeDetailData?) {
    guard !hasLoadedDraft, let detail else { return }
    draft = RecipeEditorDraft(detail: detail)
    hasLoadedDraft = true
  }

  func categorySelectionButtonTapped(_ categoryID: YesChefCore.Category.ID) {
    var categoryIDs = selectedCategoryIDs
    if categoryIDs.contains(categoryID) {
      categoryIDs.remove(categoryID)
    } else {
      categoryIDs.insert(categoryID)
    }
    draft.selectedCategoryIDs = categoryIDs
    draft.categoryNames = categoryRows
      .filter { categoryIDs.contains($0.category.id) }
      .map(\.displayName)
      .joined(separator: ", ")
  }

  func saveButtonTapped() -> Bool {
    do {
      _ = try database.write { db in
        try RecipeRepository.save(
          draft: draft,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
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
