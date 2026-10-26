import Foundation
import SQLiteData

/// Text-only snapshot shared with the macOS MCP helper. The format is deliberately
/// separate from the database schema and carries no sync or image payloads.
public struct ChatAccessExport: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var generatedAt: Date
  public var device: String
  public var recipes: [RecipeBundleCoding.RecipeBundle]
  public var menus: [MenuRecord]
  public var mealPlan: [MealPlanRecord]

  public init(
    generatedAt: Date,
    device: String,
    recipes: [RecipeBundleCoding.RecipeBundle],
    menus: [MenuRecord],
    mealPlan: [MealPlanRecord]
  ) {
    self.format = "yc-library-export"
    self.version = 1
    self.generatedAt = generatedAt
    self.device = device
    self.recipes = recipes.map { bundle in
      var bundle = bundle
      bundle.photos = []
      bundle.recipe.originalSnapshot = nil
      return bundle
    }
    self.menus = menus
    self.mealPlan = mealPlan
  }

  public struct MenuRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var dayCount: Int
    public var modified: Date
    public var items: [MenuItemRecord]

    public init(id: UUID, title: String, notes: String?, dayCount: Int, modified: Date, items: [MenuItemRecord]) {
      self.id = id
      self.title = title
      self.notes = notes
      self.dayCount = dayCount
      self.modified = modified
      self.items = items
    }
  }

  public struct MenuItemRecord: Codable, Equatable, Sendable {
    public var kind: MealPlanItemKind
    public var title: String
    public var recipeID: UUID?
    public var dayOffset: Int
    public var slot: MealPlanItemSlot
    public var note: String?
    public var scale: Double

    public init(kind: MealPlanItemKind, title: String, recipeID: UUID?, dayOffset: Int, slot: MealPlanItemSlot, note: String?, scale: Double) {
      self.kind = kind
      self.title = title
      self.recipeID = recipeID
      self.dayOffset = dayOffset
      self.slot = slot
      self.note = note
      self.scale = scale
    }
  }

  public struct MealPlanRecord: Codable, Equatable, Sendable {
    public var kind: MealPlanItemKind
    public var title: String
    public var recipeID: UUID?
    public var scheduledDate: Date
    public var slot: MealPlanItemSlot
    public var note: String?
    public var scale: Double

    public init(kind: MealPlanItemKind, title: String, recipeID: UUID?, scheduledDate: Date, slot: MealPlanItemSlot, note: String?, scale: Double) {
      self.kind = kind
      self.title = title
      self.recipeID = recipeID
      self.scheduledDate = scheduledDate
      self.slot = slot
      self.note = note
      self.scale = scale
    }
  }
}

public enum ChatAccessExportError: LocalizedError, Equatable {
  case unsupportedFormat(found: String)
  case unsupportedVersion(found: Int, supported: Int)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedFormat(found):
      "This file uses the export format `\(found)`; this helper expects `yc-library-export`."
    case let .unsupportedVersion(found, supported):
      "This Yes Chef export uses version \(found); this helper supports version \(supported). Update the helper before reading it."
    }
  }
}

public enum ChatAccessExportCoding {
  private struct Header: Decodable {
    var format: String
    var version: Int
  }

  public static func encode(_ export: ChatAccessExport) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(export)
  }

  public static func decode(_ data: Data) throws -> ChatAccessExport {
    let header = try JSONDecoder().decode(Header.self, from: data)
    guard header.format == "yc-library-export" else {
      throw ChatAccessExportError.unsupportedFormat(found: header.format)
    }
    guard header.version == 1 else {
      throw ChatAccessExportError.unsupportedVersion(found: header.version, supported: 1)
    }
    return try JSONDecoder().decode(ChatAccessExport.self, from: data)
  }
}

public enum ChatAccessExportBuilder {
  public static func build(in db: Database, generatedAt: Date, device: String, calendar: Calendar = .current) throws -> ChatAccessExport {
    let recipes = try Recipe.fetchAll(db)
    let sources = try RecipeSource.fetchAll(db)
    let ingredientSections = try IngredientSection.fetchAll(db)
    let ingredientLines = try IngredientLine.fetchAll(db)
    let instructionSections = try InstructionSection.fetchAll(db)
    let instructionSteps = try InstructionStep.fetchAll(db)
    let recipeNotes = try RecipeNote.fetchAll(db)
    let recipeCategories = try RecipeCategory.fetchAll(db)
    let categoriesByID = try Dictionary(uniqueKeysWithValues: Category.fetchAll(db).map { ($0.id, $0.name) })
    let photos = try RecipePhoto.fetchAll(db)
    let sourcesByRecipeID = Dictionary(uniqueKeysWithValues: sources.map { ($0.recipeID, $0) })
    let ingredientSectionsByRecipeID = Dictionary(grouping: ingredientSections, by: \.recipeID)
    let ingredientLinesByRecipeID = Dictionary(grouping: ingredientLines, by: \.recipeID)
    let instructionSectionsByRecipeID = Dictionary(grouping: instructionSections, by: \.recipeID)
    let instructionStepsByRecipeID = Dictionary(grouping: instructionSteps, by: \.recipeID)
    let notesByRecipeID = Dictionary(grouping: recipeNotes, by: \.recipeID)
    let categoriesByRecipeID = Dictionary(grouping: recipeCategories, by: \.recipeID)
    let photosByRecipeID = Dictionary(grouping: photos, by: \.recipeID)

    let bundles = recipes.map { recipe in
      let id = recipe.id
      let sections = ingredientSectionsByRecipeID[id, default: []].sorted { $0.sortOrder < $1.sortOrder }
      let lines = ingredientLinesByRecipeID[id, default: []].sorted { $0.sortOrder < $1.sortOrder }
      let methodSections = instructionSectionsByRecipeID[id, default: []].sorted { $0.sortOrder < $1.sortOrder }
      let steps = instructionStepsByRecipeID[id, default: []].sorted { $0.sortOrder < $1.sortOrder }
      let notes = notesByRecipeID[id, default: []].sorted { $0.dateCreated < $1.dateCreated }
      let categoryNames = categoriesByRecipeID[id, default: []].compactMap { categoriesByID[$0.categoryID] }.sorted()
      return RecipeBundleCoding.RecipeBundle(recipe: recipe, source: sourcesByRecipeID[id], ingredientSections: sections, ingredientLines: lines, instructionSections: methodSections, instructionSteps: steps, recipeNotes: notes, photos: photosByRecipeID[id, default: []], categoryNames: categoryNames)
    }

    let menuItems = try MenuItem.fetchAll(db)
    let menuItemsByMenuID = Dictionary(grouping: menuItems, by: \.menuID)
    let menus = try Menu.fetchAll(db).map { menu in
      ChatAccessExport.MenuRecord(
        id: menu.id,
        title: menu.title,
        notes: menu.notes,
        dayCount: menu.dayCount,
        modified: menu.dateModified,
        items: menuItemsByMenuID[menu.id, default: []].sorted { ($0.dayOffset, $0.mealSlot.sortOrder, $0.sortOrder) < ($1.dayOffset, $1.mealSlot.sortOrder, $1.sortOrder) }.map {
          ChatAccessExport.MenuItemRecord(kind: $0.kind, title: $0.title, recipeID: $0.recipeID, dayOffset: $0.dayOffset, slot: $0.mealSlot, note: $0.notes, scale: $0.scale)
        }
      )
    }

    let generatedDay = calendar.startOfDay(for: generatedAt)
    let lower = calendar.date(byAdding: .day, value: -30, to: generatedDay) ?? generatedDay
    let upperExclusive = calendar.date(byAdding: .day, value: 61, to: generatedDay) ?? generatedDay
    let mealPlan = try MealPlanItem.fetchAll(db)
      .filter { $0.scheduledDate >= lower && $0.scheduledDate < upperExclusive }
      .sorted { ($0.scheduledDate, $0.mealSlot.sortOrder, $0.sortOrder) < ($1.scheduledDate, $1.mealSlot.sortOrder, $1.sortOrder) }
      .map { ChatAccessExport.MealPlanRecord(kind: $0.kind, title: $0.title, recipeID: $0.recipeID, scheduledDate: $0.scheduledDate, slot: $0.mealSlot, note: $0.notes, scale: $0.scale) }
    return ChatAccessExport(generatedAt: generatedAt, device: device, recipes: bundles, menus: menus, mealPlan: mealPlan)
  }
}
