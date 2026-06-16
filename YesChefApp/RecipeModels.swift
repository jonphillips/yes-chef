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
    case markCooked(Recipe.ID)
    case originalSnapshot(Recipe.ID)
  }

  @ObservationIgnored
  @FetchAll(animation: .default) var recipes: [Recipe]

  var destination: Destination?
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

  func markCookedButtonTapped(recipeID: Recipe.ID) {
    destination = .markCooked(recipeID)
  }

  func originalSnapshotButtonTapped(recipeID: Recipe.ID) {
    destination = .originalSnapshot(recipeID)
  }
}

@Observable
@MainActor
final class RecipeDetailModel {
  let recipeID: Recipe.ID

  @ObservationIgnored
  @Fetch var detail: RecipeDetailData?

  var scaleFactor = 1.0

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

@Observable
@MainActor
final class MarkCookedModel {
  let recipeID: Recipe.ID

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid

  var noteText = ""
  var errorMessage: String?
  var isShowingError = false

  init(recipeID: Recipe.ID) {
    self.recipeID = recipeID
  }

  func saveButtonTapped() -> Bool {
    do {
      try database.write { db in
        try RecipeRepository.markCooked(
          recipeID: recipeID,
          noteText: noteText,
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
