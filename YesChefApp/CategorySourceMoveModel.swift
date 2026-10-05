import Observation
import YesChefCore

@Observable
@MainActor
final class CategorySourceMoveModel {
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid

  /// What a run would do right now, or — after Apply — what it did.
  var report: CategorySourceMoveReport?
  /// Cookbook values routed to Publication rather than Book title. Seeded from the known-publication list on
  /// the first plan, then the user's to adjust.
  var publicationNames: Set<String>?
  var hasApplied = false
  var isConfirmingApply = false
  var isConfirmingCleanup = false
  var cleanupReport: CategorySourceGroupCleanupReport?
  var editingRecipeID: Recipe.ID?
  var errorMessage: String?

  func task() {
    refresh()
  }

  func applyButtonTapped() {
    isConfirmingApply = true
  }

  func confirmApplyButtonTapped() {
    do {
      report = try database.write { db in
        try RecipeRepository.applyCategorySourceMove(
          publicationNames: publicationNames ?? [], in: db, uuid: { uuid() }
        )
      }
      hasApplied = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func cleanupButtonTapped() {
    isConfirmingCleanup = true
  }

  func confirmCleanupButtonTapped() {
    do {
      cleanupReport = try database.write { db in
        try RecipeRepository.deleteUnusedCategorySourceGroups(in: db)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func isPublication(_ cookbookValue: String) -> Bool {
    publicationNames?.contains(cookbookValue) ?? false
  }

  func publicationToggled(_ cookbookValue: String, isPublication: Bool) {
    var names = publicationNames ?? []
    if isPublication {
      names.insert(cookbookValue)
    } else {
      names.remove(cookbookValue)
    }
    publicationNames = names
    refresh()
  }

  func problemTapped(_ entry: CategorySourceMoveReport.Entry) {
    editingRecipeID = entry.recipeID
  }

  /// After fixing a recipe by hand, re-check it so the list reflects what is left.
  func editorDismissed() {
    refresh()
  }

  private func refresh() {
    do {
      let names = publicationNames ?? Set(CategorySourceMoveReport.knownPublications)
      let report = try database.read { db in
        try RecipeRepository.planCategorySourceMove(publicationNames: names, in: db)
      }
      if publicationNames == nil {
        publicationNames = Set(report.cookbookValues.filter(CategorySourceMoveReport.isKnownPublication))
      }
      self.report = report
      hasApplied = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
