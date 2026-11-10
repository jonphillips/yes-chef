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

public struct RecipeRowNote: Equatable, Sendable {
  public enum Origin: Equatable, Sendable {
    case menu(title: String)
    case day(date: Date, slot: MealPlanItemSlot)
  }

  public var text: String
  public var origin: Origin

  public init(text: String, origin: Origin) {
    self.text = text
    self.origin = origin
  }
}

public struct RecipeRowNoteRequest: FetchKeyRequest {
  public var context: ScaleContext
  public var recipeID: Recipe.ID

  public init(context: ScaleContext, recipeID: Recipe.ID) {
    self.context = context
    self.recipeID = recipeID
  }

  public func fetch(_ db: Database) throws -> RecipeRowNote? {
    try RecipeRowNoteRepository.note(for: context, recipeID: recipeID, in: db)
  }
}

public enum RecipeRowNoteRepository {
  public static func note(
    for context: ScaleContext,
    recipeID: Recipe.ID,
    in db: Database
  ) throws -> RecipeRowNote? {
    let text: String?
    let origin: RecipeRowNote.Origin

    switch context {
    case .recipe:
      return nil
    case let .menuItem(itemID):
      guard
        let item = try MenuItem.find(itemID).fetchOne(db),
        item.recipeID == recipeID,
        let menu = try Menu.find(item.menuID).fetchOne(db)
      else {
        return nil
      }
      text = item.notes
      origin = .menu(title: menu.title)
    case let .mealPlanItem(itemID):
      guard
        let item = try MealPlanItem.find(itemID).fetchOne(db),
        item.recipeID == recipeID
      else {
        return nil
      }
      text = item.notes
      origin = .day(date: item.scheduledDate, slot: item.mealSlot)
    }

    guard let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedText.isEmpty else {
      return nil
    }
    return RecipeRowNote(text: trimmedText, origin: origin)
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
