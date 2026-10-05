import CasePaths
import Observation
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class CategoryManagementModel {
  @CasePathable
  enum Destination {
    case deleteCategory(YesChefCore.Category.ID)
    case deleteCategoryGroup(Facet.ID)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(CategoryManagementListRequest(), animation: .default) var categories: [YesChefCore.Category] = []
  @ObservationIgnored
  @Fetch(FacetManagementListRequest(), animation: .default) var facets: [Facet] = []

  var destination: Destination?
  var categoryEditor: CategoryEditorModel?
  var facetEditor: FacetEditorModel?
  var recipeMove: CategoryRecipeMoveModel?
  var recipeMoveResultMessage: String?
  var errorMessage: String?
  var isShowingError = false

  var looseCategories: [YesChefCore.Category] {
    categories.filter { $0.facetID == nil }
  }

  var visibleFacets: [Facet] {
    facets.filter { !$0.hidden }
  }

  func addCategoryGroupButtonTapped() {
    facetEditor = FacetEditorModel()
  }

  func addLooseCategoryButtonTapped() {
    categoryEditor = CategoryEditorModel()
  }

  func addCategoryButtonTapped(facetID: Facet.ID) {
    let editor = CategoryEditorModel()
    editor.facetID = facetID
    categoryEditor = editor
  }

  func editCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    guard let category = categories.first(where: { $0.id == categoryID }) else { return }
    let editor = CategoryEditorModel()
    editor.categoryID = category.id
    editor.name = category.name
    editor.facetID = category.facetID
    editor.parentCategoryID = category.parentCategoryID
    categoryEditor = editor
  }

  func editCategoryGroupButtonTapped(facetID: Facet.ID) {
    guard let facet = facets.first(where: { $0.id == facetID }) else { return }
    let editor = FacetEditorModel()
    editor.facetID = facet.id
    editor.name = facet.name
    facetEditor = editor
  }

  func moveRecipesButtonTapped(categoryID: YesChefCore.Category.ID) {
    do {
      let recipeCount = try database.read { db in
        try CategoryRepository.recipeCount(categoryID: categoryID, in: db)
      }
      let move = CategoryRecipeMoveModel(
        sourceID: categoryID,
        sourceTitle: fullTitle(for: categoryID),
        recipeCount: recipeCount,
        canDeleteSource: canDelete(categoryID: categoryID) && childCount(for: categoryID) == 0
      )
      move.deletesSource = move.canDeleteSource
      recipeMove = move
    } catch {
      showError(error)
    }
  }

  func confirmRecipeMoveButtonTapped() -> Bool {
    guard let move = recipeMove, let targetID = move.targetID else { return false }
    do {
      let report = try database.write { db in
        try CategoryRepository.moveRecipes(
          fromCategoryID: move.sourceID,
          toCategoryID: targetID,
          deletingSource: move.deletesSource,
          in: db
        )
      }
      var message = "\(report.recipeCount) \(report.recipeCount == 1 ? "recipe" : "recipes") now tagged \(fullTitle(for: targetID))."
      if report.alreadyTaggedCount > 0 {
        message += " \(report.alreadyTaggedCount) already had it."
      }
      if report.deletedSource {
        message += " Deleted \(move.sourceTitle)."
      }
      recipeMoveResultMessage = message
      recipeMove = nil
      return true
    } catch {
      showError(error)
      return false
    }
  }

  func cancelRecipeMoveButtonTapped() {
    recipeMove = nil
  }

  /// Every category except the source, grouped the way the Categories list groups them.
  func recipeMoveTargetSections(excluding sourceID: YesChefCore.Category.ID) -> [CategoryMoveTargetSection] {
    var sections = facets.map { facet in
      CategoryMoveTargetSection(
        id: facet.id.uuidString,
        title: facet.name,
        options: CategoryHierarchy.displayRows(from: categories(in: facet.id))
          .filter { $0.category.id != sourceID }
          .map { CategoryParentOption(categoryID: $0.category.id, title: fullTitle(for: $0.category.id)) }
      )
    }
    sections.append(
      CategoryMoveTargetSection(
        id: "loose",
        title: "Other Categories",
        options: looseCategories
          .filter { $0.id != sourceID }
          .map { CategoryParentOption(categoryID: $0.id, title: $0.name) }
      )
    )
    return sections.filter { !$0.options.isEmpty }
  }

  /// "Dish Type > Salad" for grouped categories, so same-named tags in different groups stay distinguishable.
  func fullTitle(for categoryID: YesChefCore.Category.ID) -> String {
    guard let category = categories.first(where: { $0.id == categoryID }) else { return "Category" }
    let path = CategoryHierarchy.displayName(
      for: category,
      categoriesByID: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    )
    guard let facetID = category.facetID else { return path }
    return "\(categoryGroupTitle(for: facetID)) > \(path)"
  }

  func deleteCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    destination = .deleteCategory(categoryID)
  }

  func deleteCategoryGroupButtonTapped(facetID: Facet.ID) {
    destination = .deleteCategoryGroup(facetID)
  }

  func toggleCategoryVisibilityButtonTapped(categoryID: YesChefCore.Category.ID) {
    guard let category = categories.first(where: { $0.id == categoryID }) else { return }
    do {
      try database.write { db in
        try CategoryRepository.setCategoryHidden(categoryID: categoryID, hidden: !category.hidden, in: db)
      }
    } catch {
      showError(error)
    }
  }

  func toggleCategoryGroupVisibilityButtonTapped(facetID: Facet.ID) {
    guard let facet = facets.first(where: { $0.id == facetID }) else { return }
    do {
      try database.write { db in
        try CategoryRepository.setFacetHidden(facetID: facetID, hidden: !facet.hidden, in: db)
      }
    } catch {
      showError(error)
    }
  }

  var isCategorySaveDisabled: Bool {
    categoryEditor?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  var isCategoryGroupSaveDisabled: Bool {
    facetEditor?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  func saveCategoryButtonTapped() -> Bool {
    guard let editor = categoryEditor else { return false }

    do {
      if let categoryID = editor.categoryID {
        try database.write { db in
          try CategoryRepository.updateCategory(
            categoryID: categoryID,
            name: editor.name,
            facetID: editor.facetID,
            parentCategoryID: editor.parentCategoryID,
            in: db
          )
        }
      } else {
        _ = try database.write { db in
          try CategoryRepository.createCategory(
            name: editor.name,
            facetID: editor.facetID,
            parentCategoryID: editor.parentCategoryID,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      categoryEditor = nil
      return true
    } catch {
      showError(error)
      return false
    }
  }

  func saveCategoryGroupButtonTapped() -> Bool {
    guard let editor = facetEditor else { return false }

    do {
      if let facetID = editor.facetID {
        try database.write { db in
          try CategoryRepository.renameFacet(facetID: facetID, name: editor.name, in: db)
        }
      } else {
        _ = try database.write { db in
          try CategoryRepository.createFacet(name: editor.name, in: db, now: now, uuid: { uuid() })
        }
      }
      facetEditor = nil
      return true
    } catch {
      showError(error)
      return false
    }
  }

  func confirmDeleteCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    do {
      try database.write { db in
        try CategoryRepository.deleteCategory(categoryID: categoryID, in: db)
      }
      if categoryEditor?.categoryID == categoryID {
        categoryEditor = nil
      }
      destination = nil
    } catch {
      showError(error)
    }
  }

  func confirmDeleteCategoryGroupButtonTapped(facetID: Facet.ID) {
    do {
      try database.write { db in
        try CategoryRepository.deleteFacet(facetID: facetID, in: db)
      }
      if facetEditor?.facetID == facetID {
        facetEditor = nil
      }
      destination = nil
    } catch {
      showError(error)
    }
  }

  func title(for categoryID: YesChefCore.Category.ID) -> String {
    categories.first { $0.id == categoryID }?.name ?? "this category"
  }

  func categoryGroupTitle(for facetID: Facet.ID) -> String {
    facets.first { $0.id == facetID }?.name ?? "this category group"
  }

  func cancelCategoryEditingButtonTapped() {
    categoryEditor = nil
  }

  func cancelCategoryGroupEditingButtonTapped() {
    facetEditor = nil
  }

  func categories(in facetID: Facet.ID) -> [YesChefCore.Category] {
    CategoryHierarchy.children(of: nil, in: categories.filter { $0.facetID == facetID })
  }

  func children(of parentCategoryID: YesChefCore.Category.ID?, in facetID: Facet.ID) -> [YesChefCore.Category] {
    CategoryHierarchy.children(of: parentCategoryID, in: categories.filter { $0.facetID == facetID })
  }

  func childCount(for categoryID: YesChefCore.Category.ID) -> Int {
    categories.count { $0.parentCategoryID == categoryID }
  }

  func parentTitle(for categoryID: YesChefCore.Category.ID?) -> String {
    categoryID.map { title(for: $0) } ?? "None"
  }

  func canDelete(categoryID: YesChefCore.Category.ID) -> Bool {
    !CategoryRepository.isStarterCategory(categoryID)
  }

  func canDeleteCategoryGroup(facetID: Facet.ID) -> Bool {
    !CategoryRepository.isStarterFacet(facetID)
  }

  func parentOptions(
    in facetID: Facet.ID?,
    excluding categoryID: YesChefCore.Category.ID?
  ) -> [CategoryParentOption] {
    guard let facetID else { return [] }
    let facetCategories = categories.filter { $0.facetID == facetID }
    let excludedIDs = categoryID
      .map { CategoryHierarchy.descendantIDs(of: $0, in: facetCategories).union([$0]) }
      ?? Set<YesChefCore.Category.ID>()
    return CategoryHierarchy.displayRows(from: facetCategories)
      .filter { !excludedIDs.contains($0.category.id) }
      .map { CategoryParentOption(categoryID: $0.category.id, title: $0.displayName) }
  }

  private func showError(_ error: any Error) {
    errorMessage = error.localizedDescription
    isShowingError = true
  }
}

@Observable
@MainActor
final class CategoryEditorModel: Identifiable {
  var categoryID: YesChefCore.Category.ID?
  var name = ""
  var facetID: Facet.ID?
  var parentCategoryID: YesChefCore.Category.ID?
}

@Observable
@MainActor
final class CategoryRecipeMoveModel: Identifiable {
  let sourceID: YesChefCore.Category.ID
  let sourceTitle: String
  let recipeCount: Int
  let canDeleteSource: Bool
  var targetID: YesChefCore.Category.ID?
  var deletesSource = false

  init(sourceID: YesChefCore.Category.ID, sourceTitle: String, recipeCount: Int, canDeleteSource: Bool) {
    self.sourceID = sourceID
    self.sourceTitle = sourceTitle
    self.recipeCount = recipeCount
    self.canDeleteSource = canDeleteSource
  }
}

struct CategoryMoveTargetSection: Identifiable, Equatable {
  var id: String
  var title: String
  var options: [CategoryParentOption]
}

@Observable
@MainActor
final class FacetEditorModel: Identifiable {
  var facetID: Facet.ID?
  var name = ""
}

struct CategoryParentOption: Identifiable, Equatable {
  var categoryID: YesChefCore.Category.ID
  var title: String

  var id: YesChefCore.Category.ID { categoryID }
}
