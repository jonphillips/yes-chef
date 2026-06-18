import Foundation
import SQLiteData

extension RecipeRepository {
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
