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
  var selectedSourceName: String?
  var selectedAuthorName: String?

  var visibleRecipeRows: [RecipeListRowData] {
    unarchivedRecipeRows
      .filter { row in
        matchesSearch(row)
          && matchesFilters(row)
      }
      .sorted(by: areInIncreasingOrder)
  }

  var hasActiveFilters: Bool {
    showsFavoritesOnly
      || showsPhotosOnly
      || libraryScope != .main
      || !selectedCategoryNames.isEmpty
      || !selectedTagNames.isEmpty
      || selectedCuisine != nil
      || selectedCourse != nil
      || selectedSourceName != nil
      || selectedAuthorName != nil
  }

  var categoryFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.flatMap(\.categoryFilterNames))
  }

  var tagFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.flatMap(\.tagNames))
  }

  var cuisineFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.recipe.cuisine))
  }

  var courseFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.recipe.course))
  }

  var sourceFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap(\.filterSourceName))
  }

  var authorFilterOptions: [String] {
    distinctOptions(unarchivedRecipeRows.compactMap { $0.source?.author.nonEmpty })
  }

  var selectedCategoryFilterSummary: String {
    guard !selectedCategoryNames.isEmpty else { return "All categories" }
    return selectedCategoryNames
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      .joined(separator: ", ")
  }

  var selectedRecipe: Recipe? {
    recipeRows.first { $0.recipe.id == selectedRecipeID }?.recipe
  }

  private var unarchivedRecipeRows: [RecipeListRowData] {
    recipeRows.filter { !$0.recipe.archived }
  }

  func addRecipeButtonTapped() {
    destination = .addRecipe
  }

  func importPaprikaExportButtonTapped() {
    isPresentingPaprikaImporter = true
  }

  func supplementPaprikaBackupButtonTapped() {
    isPresentingPaprikaBackupSupplementer = true
  }

  func filterButtonTapped() {
    destination = .filterRecipes
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
      let importedIDs = try await database.write { db in
        var recipeIDs: [Recipe.ID] = []
        for bundle in bundles {
          let recipeID = try RecipeRepository.importBundle(
            bundle,
            in: db,
            now: importDate,
            uuid: { makeUUID() }
          )
          recipeIDs.append(recipeID)
        }
        return recipeIDs
      }
      selectedRecipeID = importedIDs.first ?? selectedRecipeID
      destination = .importSummary(
        RecipeImportSummary(
          importedCount: importedIDs.count,
          warningCount: importResult.warnings.count,
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

  func clearFiltersButtonTapped() {
    showsFavoritesOnly = false
    showsPhotosOnly = false
    libraryScope = .main
    selectedCategoryNames = []
    selectedTagNames = []
    selectedCuisine = nil
    selectedCourse = nil
    selectedSourceName = nil
    selectedAuthorName = nil
  }

  func doneFilteringButtonTapped() {
    destination = nil
  }

  func tagFilterButtonTapped(_ tagName: String) {
    if selectedTagNames.contains(tagName) {
      selectedTagNames.remove(tagName)
    } else {
      selectedTagNames.insert(tagName)
    }
  }

  func categoryFilterButtonTapped(_ categoryName: String) {
    if selectedCategoryNames.contains(categoryName) {
      selectedCategoryNames.remove(categoryName)
    } else {
      selectedCategoryNames.insert(categoryName)
    }
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

  private func matchesSearch(_ row: RecipeListRowData) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    let recipe = row.recipe
    return recipe.title.localizedCaseInsensitiveContains(query)
      || (recipe.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.summary?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.cuisine?.localizedCaseInsensitiveContains(query) ?? false)
      || (recipe.course?.localizedCaseInsensitiveContains(query) ?? false)
      || row.sourceSearchValues.contains { $0.localizedCaseInsensitiveContains(query) }
      || row.categoryNames.contains { $0.localizedCaseInsensitiveContains(query) }
      || row.tagNames.contains { $0.localizedCaseInsensitiveContains(query) }
  }

  private func matchesFilters(_ row: RecipeListRowData) -> Bool {
    let recipe = row.recipe
    switch libraryScope {
    case .main where recipe.libraryPlacement != .main:
      return false
    case .reference where recipe.libraryPlacement != .reference:
      return false
    case .all, .main, .reference:
      break
    }
    if showsFavoritesOnly && !recipe.favorite { return false }
    if showsPhotosOnly && !row.hasPhoto { return false }
    if !selectedCategoryNames.isEmpty,
       !selectedCategoryNames.isSubset(of: Set(row.categoryFilterNames)) {
      return false
    }
    if !selectedTagNames.isEmpty, !selectedTagNames.isSubset(of: Set(row.tagNames)) {
      return false
    }
    if let selectedCuisine, recipe.cuisine != selectedCuisine {
      return false
    }
    if let selectedCourse, recipe.course != selectedCourse {
      return false
    }
    if let selectedSourceName, row.filterSourceName != selectedSourceName {
      return false
    }
    if let selectedAuthorName, row.source?.author.nonEmpty != selectedAuthorName {
      return false
    }
    return true
  }

  private func areInIncreasingOrder(_ lhs: RecipeListRowData, _ rhs: RecipeListRowData) -> Bool {
    switch sortOrder {
    case .title:
      titleSort(lhs.recipe, rhs.recipe)
    case .newest:
      descendingDateSort(lhs.recipe.dateCreated, rhs.recipe.dateCreated, lhs.recipe, rhs.recipe)
    case .recentlyModified:
      descendingDateSort(lhs.recipe.dateModified, rhs.recipe.dateModified, lhs.recipe, rhs.recipe)
    case .cookTime:
      optionalIntSort(lhs.recipe.listCookTimeMinutes, rhs.recipe.listCookTimeMinutes, lhs.recipe, rhs.recipe)
    case .recentlyCooked:
      optionalDateSort(lhs.recipe.lastCookedAt, rhs.recipe.lastCookedAt, lhs.recipe, rhs.recipe)
    }
  }

  private func titleSort(_ lhs: Recipe, _ rhs: Recipe) -> Bool {
    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  private func descendingDateSort(_ lhsDate: Date, _ rhsDate: Date, _ lhs: Recipe, _ rhs: Recipe) -> Bool {
    if lhsDate != rhsDate {
      return lhsDate > rhsDate
    }
    return titleSort(lhs, rhs)
  }

  private func optionalDateSort(
    _ lhsDate: Date?,
    _ rhsDate: Date?,
    _ lhs: Recipe,
    _ rhs: Recipe
  ) -> Bool {
    switch (lhsDate, rhsDate) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
      lhsDate > rhsDate
    case (nil, nil), (_?, _?):
      titleSort(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
  }

  private func optionalIntSort(
    _ lhsValue: Int?,
    _ rhsValue: Int?,
    _ lhs: Recipe,
    _ rhs: Recipe
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case let (lhsValue?, rhsValue?) where lhsValue != rhsValue:
      lhsValue < rhsValue
    case (nil, nil), (_?, _?):
      titleSort(lhs, rhs)
    case (_?, nil):
      true
    case (nil, _?):
      false
    }
  }

  private func distinctOptions(_ values: [String]) -> [String] {
    Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}

enum RecipeListSort: String, CaseIterable, Identifiable, Sendable {
  case title
  case newest
  case recentlyModified
  case cookTime
  case recentlyCooked

  var id: Self { self }

  var title: String {
    switch self {
    case .title: "Title"
    case .newest: "Newest"
    case .recentlyModified: "Recently Modified"
    case .cookTime: "Cook Time"
    case .recentlyCooked: "Last Cooked"
    }
  }
}

enum RecipeLibraryScope: String, CaseIterable, Identifiable, Sendable {
  case main
  case reference
  case all

  var id: Self { self }

  var title: String {
    switch self {
    case .main: "Main"
    case .reference: "Reference"
    case .all: "All"
    }
  }
}

extension RecipeLibraryPlacement {
  var title: String {
    switch self {
    case .main: "Main Library"
    case .reference: "Reference"
    }
  }

  var badgeTitle: String {
    switch self {
    case .main: "Main"
    case .reference: "Reference"
    }
  }
}

private extension Recipe {
  var listCookTimeMinutes: Int? {
    if let totalTimeMinutes {
      return totalTimeMinutes
    }
    let parts = [prepTimeMinutes, cookTimeMinutes, activeTimeMinutes].compactMap { $0 }
    guard !parts.isEmpty else { return nil }
    return parts.reduce(0, +)
  }
}

private extension RecipeListRowData {
  var filterSourceName: String? {
    source?.name.nonEmpty
      ?? source?.publicationName.nonEmpty
      ?? source?.bookTitle.nonEmpty
  }

  var sourceSearchValues: [String] {
    [
      source?.name,
      source?.url,
      source?.author,
      source?.publicationName,
      source?.bookTitle,
      source?.pageNumber,
      source?.sourceNotes,
    ]
    .compactMap { $0?.nonEmpty }
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    flatMap(\.nonEmpty)
  }
}

struct RecipeImportSummary: Identifiable, Equatable, Sendable {
  let id = UUID()
  var importedCount: Int
  var warningCount: Int
  var missingRecipePageCount: Int
  var missingPhotoCount: Int
  var unreadableRecipeCount: Int

  var message: String {
    var lines = ["Imported \(importedCount) \(importedCount == 1 ? "recipe" : "recipes")."]
    if missingRecipePageCount > 0 {
      lines.append("\(missingRecipePageCount) index \(missingRecipePageCount == 1 ? "entry was" : "entries were") missing from the ZIP.")
    }
    if missingPhotoCount > 0 {
      lines.append("\(missingPhotoCount) image \(missingPhotoCount == 1 ? "file was" : "files were") missing.")
    }
    if unreadableRecipeCount > 0 {
      lines.append("\(unreadableRecipeCount) recipe \(unreadableRecipeCount == 1 ? "page could" : "pages could") not be read.")
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
final class CategoryManagementModel {
  @CasePathable
  enum Destination {
    case deleteCategory(YesChefCore.Category.ID)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(CategoryListRequest(), animation: .default) var categories: [YesChefCore.Category] = []

  var destination: Destination?
  var editor: CategoryEditorModel?
  var errorMessage: String?
  var isShowingError = false

  var categoryRows: [CategoryHierarchy.DisplayRow] {
    CategoryHierarchy.displayRows(from: categories)
  }

  func addRootCategoryButtonTapped() {
    let editor = CategoryEditorModel()
    editor.parentCategoryID = nil
    self.editor = editor
  }

  func addChildCategoryButtonTapped(parentCategoryID: YesChefCore.Category.ID) {
    let editor = CategoryEditorModel()
    editor.parentCategoryID = parentCategoryID
    self.editor = editor
  }

  func editCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    guard let category = categories.first(where: { $0.id == categoryID }) else { return }
    let editor = CategoryEditorModel()
    editor.categoryID = category.id
    editor.name = category.name
    editor.parentCategoryID = category.parentCategoryID
    self.editor = editor
  }

  func deleteCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    destination = .deleteCategory(categoryID)
  }

  var isSaveDisabled: Bool {
    editor?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  func saveCategoryButtonTapped() -> Bool {
    guard let editor else { return false }

    do {
      if let categoryID = editor.categoryID {
        try database.write { db in
          try CategoryRepository.updateCategory(
            categoryID: categoryID,
            name: editor.name,
            parentCategoryID: editor.parentCategoryID,
            in: db
          )
        }
      } else {
        _ = try database.write { db in
          try CategoryRepository.createCategory(
            name: editor.name,
            parentCategoryID: editor.parentCategoryID,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      self.editor = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func confirmDeleteCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    do {
      try database.write { db in
        try CategoryRepository.deleteCategory(categoryID: categoryID, in: db)
      }
      if editor?.categoryID == categoryID {
        editor = nil
      }
      destination = nil
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
    }
  }

  func title(for categoryID: YesChefCore.Category.ID) -> String {
    categories.first { $0.id == categoryID }?.name ?? "this category"
  }

  func cancelEditingButtonTapped() {
    editor = nil
  }

  func children(of parentCategoryID: YesChefCore.Category.ID?) -> [YesChefCore.Category] {
    CategoryHierarchy.children(of: parentCategoryID, in: categories)
  }

  func childCount(for categoryID: YesChefCore.Category.ID) -> Int {
    children(of: categoryID).count
  }

  func parentTitle(for categoryID: YesChefCore.Category.ID?) -> String {
    categoryID.map { title(for: $0) } ?? "None"
  }

  @discardableResult
  func categoryItemsDropped(
    _ categoryIDs: [YesChefCore.Category.ID],
    onParentCategoryID parentCategoryID: YesChefCore.Category.ID?
  ) -> Bool {
    var didMoveCategory = false
    for categoryID in categoryIDs {
      didMoveCategory = moveCategory(categoryID: categoryID, parentCategoryID: parentCategoryID) || didMoveCategory
    }
    return didMoveCategory
  }

  @discardableResult
  private func moveCategory(
    categoryID: YesChefCore.Category.ID,
    parentCategoryID: YesChefCore.Category.ID?
  ) -> Bool {
    guard categoryID != parentCategoryID,
          let category = categories.first(where: { $0.id == categoryID }),
          category.parentCategoryID != parentCategoryID else { return false }

    do {
      try database.write { db in
        try CategoryRepository.updateCategory(
          categoryID: categoryID,
          name: category.name,
          parentCategoryID: parentCategoryID,
          in: db
        )
      }
      if editor?.categoryID == categoryID {
        editor?.parentCategoryID = parentCategoryID
      }
      return true
    } catch {
      errorMessage = error.localizedDescription
      isShowingError = true
      return false
    }
  }

  func parentOptions(excluding categoryID: YesChefCore.Category.ID?) -> [CategoryParentOption] {
    let excludedIDs = categoryID
      .map { CategoryHierarchy.descendantIDs(of: $0, in: categories).union([$0]) }
      ?? Set<YesChefCore.Category.ID>()
    return categoryRows
      .filter { !excludedIDs.contains($0.category.id) }
      .map { CategoryParentOption(categoryID: $0.category.id, title: $0.displayName) }
  }
}

@Observable
@MainActor
final class CategoryEditorModel: Identifiable {
  var categoryID: YesChefCore.Category.ID?
  var name = ""
  var parentCategoryID: YesChefCore.Category.ID?
}

struct CategoryParentOption: Identifiable, Equatable {
  var categoryID: YesChefCore.Category.ID
  var title: String

  var id: YesChefCore.Category.ID { categoryID }
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
