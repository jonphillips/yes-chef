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
  var errorMessage: String?
  var isShowingError = false

  var looseCategories: [YesChefCore.Category] {
    categories.filter { $0.facetID == nil }
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

  func deleteCategoryButtonTapped(categoryID: YesChefCore.Category.ID) {
    destination = .deleteCategory(categoryID)
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
final class FacetEditorModel: Identifiable {
  var facetID: Facet.ID?
  var name = ""
}

struct CategoryParentOption: Identifiable, Equatable {
  var categoryID: YesChefCore.Category.ID
  var title: String

  var id: YesChefCore.Category.ID { categoryID }
}
