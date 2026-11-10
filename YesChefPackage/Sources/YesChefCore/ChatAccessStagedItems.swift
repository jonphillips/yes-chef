import Foundation
import SQLiteData

/// A lossless-or-loud transport for recipe-targeted prose from the chat helper.
public struct ChatAccessStagedRecipeReturn: Codable, Equatable, Sendable {
  public var format: String
  public var version: Int
  public var recipeID: UUID
  public var recipeTitle: String
  public var text: String

  public init(recipeID: UUID, recipeTitle: String, text: String) {
    self.format = "yc-recipe-return"
    self.version = 1
    self.recipeID = recipeID
    self.recipeTitle = recipeTitle
    self.text = text
  }

  private enum CodingKeys: String, CodingKey { case format, version, recipeID, recipeTitle, text }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = try c.decode(String.self, forKey: .format)
    let version = try c.decode(Int.self, forKey: .version)
    guard format == "yc-recipe-return" else { throw ChatAccessStagedEnvelopeError.unsupportedFormat(format) }
    guard version == 1 else { throw ChatAccessStagedEnvelopeError.unsupportedVersion(found: version, supported: 1) }
    self.format = format
    self.version = version
    self.recipeID = try c.decode(UUID.self, forKey: .recipeID)
    self.recipeTitle = try c.decode(String.self, forKey: .recipeTitle)
    self.text = try c.decode(String.self, forKey: .text)
  }
}

/// A lossless-or-loud transport for a reviewed menu proposal.
public struct ChatAccessStagedMenu: Codable, Equatable, Sendable {
  public struct Item: Codable, Equatable, Sendable {
    public var recipeID: UUID?
    public var title: String
    public var dayOffset: Int
    public var slot: MealPlanItemSlot
    public var note: String?
    public var scale: Double?

    public init(recipeID: UUID?, title: String, dayOffset: Int, slot: MealPlanItemSlot, note: String?, scale: Double?) {
      self.recipeID = recipeID
      self.title = title
      self.dayOffset = dayOffset
      self.slot = slot
      self.note = note
      self.scale = scale
    }
  }

  public var format: String
  public var version: Int
  public var title: String
  public var dayCount: Int
  public var items: [Item]

  public init(title: String, dayCount: Int, items: [Item]) {
    self.format = "yc-menu"
    self.version = 1
    self.title = title
    self.dayCount = dayCount
    self.items = items
  }

  private enum CodingKeys: String, CodingKey { case format, version, title, dayCount, items }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = try c.decode(String.self, forKey: .format)
    let version = try c.decode(Int.self, forKey: .version)
    guard format == "yc-menu" else { throw ChatAccessStagedEnvelopeError.unsupportedFormat(format) }
    guard version == 1 else { throw ChatAccessStagedEnvelopeError.unsupportedVersion(found: version, supported: 1) }
    self.format = format
    self.version = version
    self.title = try c.decode(String.self, forKey: .title)
    self.dayCount = try c.decode(Int.self, forKey: .dayCount)
    self.items = try c.decode([Item].self, forKey: .items)
  }
}

public enum ChatAccessStagedEnvelopeError: LocalizedError, Equatable {
  case unsupportedFormat(String)
  case unsupportedVersion(found: Int, supported: Int)

  public var errorDescription: String? {
    switch self {
    case let .unsupportedFormat(found): "This file uses the unsupported format `\(found)`."
    case let .unsupportedVersion(found, supported): "This staged item uses version \(found); this app supports version \(supported). Update Yes Chef first."
    }
  }
}

public enum ChatRecipeReturnImportError: Error, Equatable, Sendable {
  case recipeUnavailable
}

public enum ChatRecipeReturnImport {
  /// Stages a recipe return against the live recipe row; any parse failure rolls back the local hand-off row.
  /// A model that also knows the hand-off contract may echo its `YC-CONTRACT:` marker; strip it so the labeled
  /// parser doesn't file it as an unfiled deliverable. No marker is expected here, so its absence isn't a warning.
  public static func stageReview(
    _ envelope: ChatAccessStagedRecipeReturn,
    in db: Database,
    now: Date,
    uuid: @Sendable () -> UUID
  ) throws -> AIHandoffReview {
    guard let recipe = try Recipe.find(envelope.recipeID).fetchOne(db), !recipe.archived else {
      throw ChatRecipeReturnImportError.recipeUnavailable
    }
    let text = try AIHandoffReturnContract.strippingMarker(from: envelope.text).text
    let handoff = AIHandoff(
      id: uuid(), sourceType: .recipe, sourceID: recipe.id, taskType: .recipe,
      dayOffset: nil, variationID: nil, createdAt: now, status: .awaitingReturn,
      schemaVersion: AIHandoff.initialSchemaVersion, regenerates: false, exportedPrompt: ""
    )
    try AIHandoffRepository.create(handoff, in: db)
    return try AIHandoffIntentImport.stageReview(handoffID: handoff.id, result: text, in: db, now: now)
  }
}

public enum ChatMenuImport {
  public enum Resolution: Equatable, Sendable {
    case libraryRecipe(Recipe.ID)
    case newDish
    case recipeMissing
  }

  public struct ResolvedItem: Equatable, Sendable {
    public var item: ChatAccessStagedMenu.Item
    public var resolution: Resolution
    public var isKept: Bool

    public init(item: ChatAccessStagedMenu.Item, resolution: Resolution, isKept: Bool = true) {
      self.item = item
      self.resolution = resolution
      self.isKept = isKept
    }
  }

  public static func resolve(_ envelope: ChatAccessStagedMenu, in db: Database) throws -> [ResolvedItem] {
    try envelope.items.map { item in
      guard let recipeID = item.recipeID else { return ResolvedItem(item: item, resolution: .newDish) }
      guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
        return ResolvedItem(item: item, resolution: .recipeMissing)
      }
      return ResolvedItem(item: item, resolution: .libraryRecipe(recipeID))
    }
  }

  @discardableResult
  public static func create(
    title: String,
    dayCount: Int,
    items: [ResolvedItem],
    in db: Database,
    now: Date,
    uuid: @Sendable () -> UUID
  ) throws -> Menu.ID {
    let menuID = try MenuRepository.addMenu(title: title, notes: nil, dayCount: dayCount, in: db, now: now, uuid: uuid)
    for resolved in items where resolved.isKept {
      let item = resolved.item
      switch resolved.resolution {
      case let .libraryRecipe(recipeID):
        let itemID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: item.dayOffset, mealSlot: item.slot, notes: item.note, in: db, now: now, uuid: uuid)
        if let scale = item.scale { try RecipeScaleRepository.setScale(scale, for: .menuItem(itemID), in: db) }
      case .newDish, .recipeMissing:
        _ = try MenuRepository.addNoteItem(menuID: menuID, title: item.title, notes: item.note, dayOffset: item.dayOffset, mealSlot: item.slot, in: db, now: now, uuid: uuid)
      }
    }
    return menuID
  }
}
