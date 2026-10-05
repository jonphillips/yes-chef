import Foundation
import SQLiteData

/// Result of re-tagging every recipe from one category onto another.
public struct CategoryRecipeMoveReport: Equatable, Sendable {
  /// Recipes that gained the target tag.
  public var movedCount: Int
  /// Recipes that already carried the target tag; they just lose the source tag.
  public var alreadyTaggedCount: Int
  public var deletedSource: Bool

  public init(movedCount: Int = 0, alreadyTaggedCount: Int = 0, deletedSource: Bool = false) {
    self.movedCount = movedCount
    self.alreadyTaggedCount = alreadyTaggedCount
    self.deletedSource = deletedSource
  }

  public var recipeCount: Int { movedCount + alreadyTaggedCount }
}

public enum CategoryRecipeMoveError: Error, Equatable, LocalizedError {
  case sameCategory

  public var errorDescription: String? {
    switch self {
    case .sameCategory: "Choose a different category to move these recipes to."
    }
  }
}

extension CategoryRepository {
  public static func recipeCount(categoryID: Category.ID, in db: Database) throws -> Int {
    try RecipeCategory.where { $0.categoryID.eq(categoryID) }.fetchCount(db)
  }

  /// Re-tags every recipe carrying `sourceID` with `targetID` and removes the source tag, then optionally deletes
  /// the emptied source (subject to the usual delete rules). Target assignments use the deterministic identity so
  /// two devices doing the same move converge on one row.
  public static func moveRecipes(
    fromCategoryID sourceID: Category.ID,
    toCategoryID targetID: Category.ID,
    deletingSource: Bool,
    in db: Database
  ) throws -> CategoryRecipeMoveReport {
    let categories = try Category.fetchAll(db)
    _ = try category(sourceID, in: categories)
    _ = try category(targetID, in: categories)
    guard sourceID != targetID else { throw CategoryRecipeMoveError.sameCategory }

    let targetRecipeIDs = Set(
      try RecipeCategory.where { $0.categoryID.eq(targetID) }.fetchAll(db).map(\.recipeID)
    )
    var report = CategoryRecipeMoveReport()
    for assignment in try RecipeCategory.where({ $0.categoryID.eq(sourceID) }).fetchAll(db) {
      if targetRecipeIDs.contains(assignment.recipeID) {
        report.alreadyTaggedCount += 1
      } else {
        let target = RecipeCategory(
          id: DeterministicID.recipeCategory(recipeID: assignment.recipeID, categoryID: targetID),
          recipeID: assignment.recipeID,
          categoryID: targetID
        )
        try RecipeCategory.upsert { target }.execute(db)
        report.movedCount += 1
      }
      try RecipeCategory.find(assignment.id).delete().execute(db)
    }

    if deletingSource {
      try deleteCategory(categoryID: sourceID, in: db)
      report.deletedSource = true
    }
    return report
  }
}
