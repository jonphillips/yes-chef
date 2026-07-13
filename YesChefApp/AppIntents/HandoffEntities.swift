import AppIntents
import Dependencies
import Foundation
import SQLiteData
import YesChefCore

struct RecipeHandoffEntity: AppEntity, SyncableEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
  static let defaultQuery = RecipeHandoffEntityQuery()

  let id: Recipe.ID
  let title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), image: .init(systemName: "book.closed"))
  }
}

struct RecipeHandoffEntityQuery: EntityQuery {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  init() {}

  func entities(for identifiers: [RecipeHandoffEntity.ID]) async throws -> [RecipeHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try Recipe
        .where { $0.id.in(identifiers) && !$0.archived }
        .fetchAll(db)
        .map(RecipeHandoffEntity.init)
    }
  }

  func suggestedEntities() async throws -> [RecipeHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try Recipe
        .where { !$0.archived }
        .fetchAll(db)
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(RecipeHandoffEntity.init)
    }
  }
}

private extension RecipeHandoffEntity {
  init(recipe: Recipe) {
    self.init(id: recipe.id, title: recipe.title)
  }
}

struct MenuHandoffEntity: AppEntity, SyncableEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Menu"
  static let defaultQuery = MenuHandoffEntityQuery()

  let id: Menu.ID
  let title: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: LocalizedStringResource(stringLiteral: title), image: .init(systemName: "menucard"))
  }
}

struct MenuHandoffEntityQuery: EntityQuery {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  init() {}

  func entities(for identifiers: [MenuHandoffEntity.ID]) async throws -> [MenuHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try Menu
        .where { $0.id.in(identifiers) }
        .fetchAll(db)
        .map(MenuHandoffEntity.init)
    }
  }

  func suggestedEntities() async throws -> [MenuHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try Menu.fetchAll(db)
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(MenuHandoffEntity.init)
    }
  }
}

private extension MenuHandoffEntity {
  init(menu: Menu) {
    self.init(id: menu.id, title: menu.title)
  }
}

struct MealPlanHandoffEntity: AppEntity, SyncableEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Meal Plan"
  static let defaultQuery = MealPlanHandoffEntityQuery()

  let id: MealPlanItem.ID
  let title: String
  let scheduledDate: Date

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: LocalizedStringResource(stringLiteral: title),
      subtitle: LocalizedStringResource(stringLiteral: scheduledDate.formatted(date: .abbreviated, time: .omitted)),
      image: .init(systemName: "calendar")
    )
  }
}

struct MealPlanHandoffEntityQuery: EntityQuery {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  init() {}

  func entities(for identifiers: [MealPlanHandoffEntity.ID]) async throws -> [MealPlanHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try MealPlanItem
        .where { $0.id.in(identifiers) }
        .fetchAll(db)
        .map(MealPlanHandoffEntity.init)
    }
  }

  func suggestedEntities() async throws -> [MealPlanHandoffEntity] {
    @Dependency(\.defaultDatabase) var database
    return try await database.read { db in
      try MealPlanItem.fetchAll(db)
        .sorted { $0.scheduledDate < $1.scheduledDate }
        .map(MealPlanHandoffEntity.init)
    }
  }
}

private extension MealPlanHandoffEntity {
  init(item: MealPlanItem) {
    self.init(id: item.id, title: item.title, scheduledDate: item.scheduledDate)
  }
}

@UnionValue
enum HandoffSource: Sendable {
  case recipe(RecipeHandoffEntity)
  case menu(MenuHandoffEntity)
  case mealPlan(MealPlanHandoffEntity)

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Handoff Source"
  static let caseDisplayRepresentations: [Cases: DisplayRepresentation] = [
    .recipe: "Recipe",
    .menu: "Menu",
    .mealPlan: "Meal Plan",
  ]
}

struct HandoffExport: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Handoff Context"
  static let defaultQuery = HandoffExportQuery()

  let id: AIHandoff.ID
  @ComputedProperty(title: "Prompt") var prompt: String
  @ComputedProperty(title: "ChatGPT Project") var externalProjectName: String?

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "Yes Chef Handoff")
  }
}

struct HandoffExportQuery: EntityQuery {
  init() {}

  func entities(for identifiers: [HandoffExport.ID]) async throws -> [HandoffExport] {
    []
  }
}
