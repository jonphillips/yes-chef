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
