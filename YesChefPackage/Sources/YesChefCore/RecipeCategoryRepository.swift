import Foundation
import SQLiteData

public struct CategoryListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [Category] {
    CategoryRepository.sortedCategories(try Category.fetchAll(db))
  }
}

public enum CategoryRepositoryError: Error, Equatable {
  case emptyName
  case duplicateSibling(name: String)
  case categoryNotFound
  case parentNotFound
  case cannotParentCategoryUnderItself
  case cannotParentCategoryUnderDescendant
  case cannotDeleteCategoryWithChildren
  case cannotDeleteCategoryUsedByRecipes
}

extension CategoryRepositoryError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .emptyName:
      "Category name cannot be empty."
    case let .duplicateSibling(name):
      "A category named \(name) already exists at that level."
    case .categoryNotFound:
      "Category not found."
    case .parentNotFound:
      "Parent category not found."
    case .cannotParentCategoryUnderItself:
      "A category cannot be its own parent."
    case .cannotParentCategoryUnderDescendant:
      "A category cannot be moved under one of its own children."
    case .cannotDeleteCategoryWithChildren:
      "Delete or move this category's children before deleting it."
    case .cannotDeleteCategoryUsedByRecipes:
      "Remove this category from recipes before deleting it."
    }
  }
}

public enum CategoryRepository {
  public static func sortedCategories(_ categories: [Category]) -> [Category] {
    CategoryHierarchy.displayRows(from: categories).map(\.category)
  }

  public static func createCategory(
    name: String,
    parentCategoryID: Category.ID?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    let categories = try Category.fetchAll(db)
    let name = try normalizedName(name)
    try validateParent(parentCategoryID, categories: categories)
    try validateUniqueSiblingName(
      name,
      parentCategoryID: parentCategoryID,
      excluding: nil,
      categories: categories
    )

    let category = Category(
      id: uuid(),
      name: name,
      parentCategoryID: parentCategoryID,
      sortOrder: nextSortOrder(parentCategoryID: parentCategoryID, categories: categories),
      dateCreated: now
    )
    try Category.insert { category }.execute(db)
    return category
  }

  public static func updateCategory(
    categoryID: Category.ID,
    name: String,
    parentCategoryID: Category.ID?,
    in db: Database
  ) throws {
    let categories = try Category.fetchAll(db)
    let category = try category(categoryID, in: categories)
    let name = try normalizedName(name)
    try validateMove(categoryID: categoryID, parentCategoryID: parentCategoryID, categories: categories)
    try validateUniqueSiblingName(
      name,
      parentCategoryID: parentCategoryID,
      excluding: categoryID,
      categories: categories
    )

    try Category.find(category.id).update {
      $0.name = name
      $0.parentCategoryID = parentCategoryID
    }
    .execute(db)
  }

  public static func deleteCategory(categoryID: Category.ID, in db: Database) throws {
    let categories = try Category.fetchAll(db)
    _ = try category(categoryID, in: categories)
    guard !categories.contains(where: { $0.parentCategoryID == categoryID }) else {
      throw CategoryRepositoryError.cannotDeleteCategoryWithChildren
    }
    let recipeCategoryCount = try RecipeCategory
      .where { $0.categoryID.eq(categoryID) }
      .fetchAll(db)
      .count
    guard recipeCategoryCount == 0 else {
      throw CategoryRepositoryError.cannotDeleteCategoryUsedByRecipes
    }

    try #sql("DELETE FROM \"categories\" WHERE \"id\" = \(bind: categoryID)").execute(db)
  }

  private static func category(_ categoryID: Category.ID, in categories: [Category]) throws -> Category {
    guard let category = categories.first(where: { $0.id == categoryID }) else {
      throw CategoryRepositoryError.categoryNotFound
    }
    return category
  }

  private static func normalizedName(_ name: String) throws -> String {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw CategoryRepositoryError.emptyName }
    return name
  }

  private static func validateParent(_ parentCategoryID: Category.ID?, categories: [Category]) throws {
    guard let parentCategoryID else { return }
    guard categories.contains(where: { $0.id == parentCategoryID }) else {
      throw CategoryRepositoryError.parentNotFound
    }
  }

  private static func validateMove(
    categoryID: Category.ID,
    parentCategoryID: Category.ID?,
    categories: [Category]
  ) throws {
    try validateParent(parentCategoryID, categories: categories)
    guard parentCategoryID != categoryID else {
      throw CategoryRepositoryError.cannotParentCategoryUnderItself
    }
    let descendantIDs = CategoryHierarchy.descendantIDs(of: categoryID, in: categories)
    guard parentCategoryID.map({ !descendantIDs.contains($0) }) ?? true else {
      throw CategoryRepositoryError.cannotParentCategoryUnderDescendant
    }
  }

  private static func validateUniqueSiblingName(
    _ name: String,
    parentCategoryID: Category.ID?,
    excluding categoryID: Category.ID?,
    categories: [Category]
  ) throws {
    let duplicate = categories.contains {
      $0.id != categoryID
        && $0.parentCategoryID == parentCategoryID
        && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
    guard !duplicate else {
      throw CategoryRepositoryError.duplicateSibling(name: name)
    }
  }

  private static func nextSortOrder(parentCategoryID: Category.ID?, categories: [Category]) -> Int {
    (categories
      .filter { $0.parentCategoryID == parentCategoryID }
      .map(\.sortOrder)
      .max() ?? -1) + 1
  }
}

extension RecipeRepository {
  static func reconcileCategoryIDs(
    _ categoryIDs: [Category.ID],
    recipeID: Recipe.ID,
    in db: Database,
    uuid: () -> UUID
  ) throws {
    let existingRecipeCategories = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    let validCategoryIDs = Set(try Category.fetchAll(db).map(\.id))
    var keptRecipeCategoryIDs: Set<RecipeCategory.ID> = []
    var seenCategoryIDs: Set<Category.ID> = []

    for categoryID in categoryIDs where validCategoryIDs.contains(categoryID) && !seenCategoryIDs.contains(categoryID) {
      seenCategoryIDs.insert(categoryID)
      let recipeCategory = RecipeCategory(
        id: existingRecipeCategories.first { $0.categoryID == categoryID }?.id ?? uuid(),
        recipeID: recipeID,
        categoryID: categoryID
      )
      keptRecipeCategoryIDs.insert(recipeCategory.id)
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }

    try deleteMissingRecipeCategories(existingRecipeCategories, keeping: keptRecipeCategoryIDs, in: db)
  }

  static func reconcileCategories(
    _ names: [String],
    recipeID: Recipe.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    var existingCategories = try Category.fetchAll(db)
    let existingRecipeCategories = try RecipeCategory.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
    var keptRecipeCategoryIDs: Set<RecipeCategory.ID> = []

    for path in CategoryHierarchy.paths(from: names) {
      let category = try findOrCreateCategory(
        path: path,
        existingCategories: &existingCategories,
        in: db,
        now: now,
        uuid: uuid
      )
      let recipeCategory = RecipeCategory(
        id: existingRecipeCategories.first { $0.categoryID == category.id }?.id ?? uuid(),
        recipeID: recipeID,
        categoryID: category.id
      )
      keptRecipeCategoryIDs.insert(recipeCategory.id)
      try RecipeCategory.upsert { recipeCategory }.execute(db)
    }

    try deleteMissingRecipeCategories(existingRecipeCategories, keeping: keptRecipeCategoryIDs, in: db)
  }

  private static func findOrCreateCategory(
    path: CategoryHierarchy.Path,
    existingCategories: inout [Category],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Category {
    var parentCategoryID: Category.ID?
    var currentCategory: Category?

    for component in path.components {
      let category = existingCategories.first {
        $0.parentCategoryID == parentCategoryID
          && $0.name.caseInsensitiveCompare(component) == .orderedSame
      }
      ?? Category(
        id: uuid(),
        name: component,
        parentCategoryID: parentCategoryID,
        sortOrder: existingCategories.count,
        dateCreated: now
      )

      if !existingCategories.contains(where: { $0.id == category.id }) {
        try Category.insert { category }.execute(db)
        existingCategories.append(category)
      }

      currentCategory = category
      parentCategoryID = category.id
    }

    guard let currentCategory else { throw CategoryHierarchyError.emptyPath }
    return currentCategory
  }

  private static func deleteMissingRecipeCategories(
    _ rows: [RecipeCategory],
    keeping keptIDs: Set<RecipeCategory.ID>,
    in db: Database
  ) throws {
    for row in rows where !keptIDs.contains(row.id) {
      try #sql("DELETE FROM \"recipeCategories\" WHERE \"id\" = \(bind: row.id)").execute(db)
    }
  }
}
