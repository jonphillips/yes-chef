import CasePaths
import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class RecipeLibraryModel {
  @CasePathable
  enum Destination {
    case addRecipe
    case editRecipe(Recipe.ID)
    case cookingMode(Recipe.ID)
    case originalSnapshot(Recipe.ID)
    case deleteRecipe(Recipe.ID)
    case filterRecipes
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

  func addRecipeButtonTapped() {
    destination = .addRecipe
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
      importActivityTitle = "Importing"
      isImporting = true
      defer { isImporting = false }

      let importDate = now
      let makeUUID = uuid
      let importResult = try await PaprikaImportWorkspace.parseExport(from: sourceURL)
      let bundles = try importResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: importDate, uuid: { makeUUID() })
      }
      let importSummary = try await database.write { db in
        try RecipeRepository.importBundles(
          bundles,
          in: db,
          now: importDate,
          uuid: { makeUUID() }
        )
      }
      selectedRecipeID = importSummary.importedIDs.first ?? importSummary.results.first?.recipeID ?? selectedRecipeID
      destination = .importSummary(
        RecipeImportSummary(
          importedCount: importSummary.importedCount,
          alreadyImportedCount: importSummary.alreadyImportedCount,
          warningCount: importResult.warnings.count + importSummary.warnings.count,
          identityWarningCount: importSummary.warnings.count,
          missingRecipePageCount: importResult.warnings
            .filter { $0.kind == .missingRecipePages }
            .compactMap(\.affectedCount)
            .reduce(0, +),
          missingPhotoCount: importResult.warnings.filter { $0.kind == .missingPhoto }.count,
          unreadableRecipeCount: importResult.warnings.filter { $0.kind == .unreadableRecipe }.count
        )
      )
    } catch CocoaError.userCancelled {
      isImporting = false
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      isImporting = false
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

struct RecipeImportSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var importedCount: Int
  var alreadyImportedCount: Int
  var warningCount: Int
  var identityWarningCount: Int
  var missingRecipePageCount: Int
  var missingPhotoCount: Int
  var unreadableRecipeCount: Int

  var message: String {
    var lines = ["Imported \(importedCount) \(importedCount == 1 ? "recipe" : "recipes")."]
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
