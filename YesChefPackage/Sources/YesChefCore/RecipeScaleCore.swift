import Foundation
import SQLiteData

public enum ScaleContext: Hashable, Identifiable, Sendable {
  case recipe(Recipe.ID)
  case menuItem(MenuItem.ID)
  case mealPlanItem(MealPlanItem.ID)

  public var id: String {
    switch self {
    case let .recipe(recipeID):
      "recipe:\(recipeID.uuidString)"
    case let .menuItem(itemID):
      "menuItem:\(itemID.uuidString)"
    case let .mealPlanItem(itemID):
      "mealPlanItem:\(itemID.uuidString)"
    }
  }
}

public struct RecipeScaleRequest: FetchKeyRequest {
  public var context: ScaleContext

  public init(context: ScaleContext) {
    self.context = context
  }

  public func fetch(_ db: Database) throws -> Double? {
    try RecipeScaleRepository.scale(for: context, in: db)
  }
}

public enum RecipeScaleRepository {
  public static func scale(for context: ScaleContext, in db: Database) throws -> Double? {
    switch context {
    case let .recipe(recipeID):
      return try Recipe.find(recipeID).fetchOne(db)?.viewScale
    case let .menuItem(itemID):
      return try MenuItem.find(itemID).fetchOne(db)?.scale
    case let .mealPlanItem(itemID):
      return try MealPlanItem.find(itemID).fetchOne(db)?.scale
    }
  }

  public static func setScale(_ scale: Double, for context: ScaleContext, in db: Database) throws {
    switch context {
    case let .recipe(recipeID):
      try Recipe.find(recipeID)
        .update { $0.viewScale = scale }
        .execute(db)
    case let .menuItem(itemID):
      try MenuItem.find(itemID)
        .update { $0.scale = scale }
        .execute(db)
    case let .mealPlanItem(itemID):
      try MealPlanItem.find(itemID)
        .update { $0.scale = scale }
        .execute(db)
    }
  }
}
