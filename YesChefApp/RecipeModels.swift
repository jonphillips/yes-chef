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
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @FetchAll var recipes: [Recipe]

  var destination: Destination?
  var errorMessage: String?
  var isShowingError = false
  var searchText = ""
  var selectedRecipeID: Recipe.ID?

  var visibleRecipes: [Recipe] {
    recipes
      .filter { !$0.archived }
      .filter { recipe in
        guard !searchText.isEmpty else { return true }
        return recipe.title.localizedCaseInsensitiveContains(searchText)
          || (recipe.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
          || (recipe.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
          || (recipe.cuisine?.localizedCaseInsensitiveContains(searchText) ?? false)
          || (recipe.course?.localizedCaseInsensitiveContains(searchText) ?? false)
      }
      .sorted { lhs, rhs in
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }

  var selectedRecipe: Recipe? {
    recipes.first { $0.id == selectedRecipeID }
  }

  func addRecipeButtonTapped() {
    destination = .addRecipe
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
    recipes.first { $0.id == recipeID }?.title ?? "this recipe"
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

  func detailChanged(_ detail: RecipeDetailData?) {
    guard !hasLoadedDraft, let detail else { return }
    draft = RecipeEditorDraft(detail: detail)
    hasLoadedDraft = true
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
