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

/// A whole-day replacement proposal, including the day the helper last read for drift review.
public struct ChatAccessStagedMenuDay: Codable, Equatable, Sendable {
  public struct LiveItem: Codable, Equatable, Sendable {
    public var kind: MealPlanItemKind
    public var title: String
    public var recipeID: UUID?
    public var slot: MealPlanItemSlot
    public var note: String?
    public var scale: Double

    public init(kind: MealPlanItemKind, title: String, recipeID: UUID?, slot: MealPlanItemSlot, note: String?, scale: Double) {
      self.kind = kind
      self.title = title
      self.recipeID = recipeID
      self.slot = slot
      self.note = note
      self.scale = scale
    }
  }

  public var format: String
  public var version: Int
  public var menuID: UUID
  public var menuTitle: String
  public var dayOffset: Int
  public var items: [ChatAccessStagedMenu.Item]
  public var dayAtStage: [LiveItem]

  public init(menuID: UUID, menuTitle: String, dayOffset: Int, items: [ChatAccessStagedMenu.Item], dayAtStage: [LiveItem]) {
    self.format = "yc-menu-day"
    self.version = 1
    self.menuID = menuID
    self.menuTitle = menuTitle
    self.dayOffset = dayOffset
    self.items = items
    self.dayAtStage = dayAtStage
  }

  private enum CodingKeys: String, CodingKey { case format, version, menuID, menuTitle, dayOffset, items, dayAtStage }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let format = try c.decode(String.self, forKey: .format)
    let version = try c.decode(Int.self, forKey: .version)
    guard format == "yc-menu-day" else { throw ChatAccessStagedEnvelopeError.unsupportedFormat(format) }
    guard version == 1 else { throw ChatAccessStagedEnvelopeError.unsupportedVersion(found: version, supported: 1) }
    self.format = format
    self.version = version
    self.menuID = try c.decode(UUID.self, forKey: .menuID)
    self.menuTitle = try c.decode(String.self, forKey: .menuTitle)
    self.dayOffset = try c.decode(Int.self, forKey: .dayOffset)
    self.items = try c.decode([ChatAccessStagedMenu.Item].self, forKey: .items)
    self.dayAtStage = try c.decode([LiveItem].self, forKey: .dayAtStage)
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

public enum ChatMenuDayImport {
  public enum Error: LocalizedError, Equatable, Sendable {
    case menuUnavailable
    case dayOutOfRange

    public var errorDescription: String? {
      switch self {
      case .menuUnavailable: "That menu isn't available on this device."
      case .dayOutOfRange: "That day is no longer in this menu."
      }
    }
  }

  public enum Resolution: Equatable, Sendable {
    case libraryRecipe(Recipe.ID)
    case newDish
    case recipeMissing
  }

  public enum Change: Equatable, Sendable {
    case slot(from: MealPlanItemSlot, to: MealPlanItemSlot)
    case note(String?)
    case scale(from: Double, to: Double)
  }

  public enum Entry: Equatable, Sendable {
    case kept(row: MenuItem, resolution: Resolution)
    case changed(row: MenuItem, changes: [Change], resolution: Resolution)
    case new(item: ChatAccessStagedMenu.Item, resolution: Resolution)
  }

  public struct Plan: Equatable, Sendable {
    public var menuID: Menu.ID
    public var menuTitle: String
    public var dayOffset: Int
    public var entries: [Entry]
    public var removed: [MenuItem]
    public var dayChangedSinceStage: Bool

    public init(menuID: Menu.ID, menuTitle: String, dayOffset: Int, entries: [Entry], removed: [MenuItem], dayChangedSinceStage: Bool) {
      self.menuID = menuID
      self.menuTitle = menuTitle
      self.dayOffset = dayOffset
      self.entries = entries
      self.removed = removed
      self.dayChangedSinceStage = dayChangedSinceStage
    }

    public func removedRows(keeping: Set<Int>) -> [MenuItem] {
      removed + entries.enumerated().compactMap { index, entry -> MenuItem? in
        guard !keeping.contains(index) else { return nil }
        switch entry {
        case let .kept(row, _), let .changed(row, _, _): return row
        case .new: return nil
        }
      }
    }
  }

  public static func plan(_ envelope: ChatAccessStagedMenuDay, in db: Database) throws -> Plan {
    guard let menu = try Menu.find(envelope.menuID).fetchOne(db) else { throw Error.menuUnavailable }
    guard (0..<menu.dayCount).contains(envelope.dayOffset) else { throw Error.dayOutOfRange }
    let live = try MenuItem.where { $0.menuID.eq(menu.id) && $0.dayOffset.eq(envelope.dayOffset) }.fetchAll(db)
      .sorted { ($0.mealSlot.sortOrder, $0.sortOrder) < ($1.mealSlot.sortOrder, $1.sortOrder) }
    let recipes = try Dictionary(uniqueKeysWithValues: Recipe.fetchAll(db).map { ($0.id, $0) })
    var used = Set<MenuItem.ID>()
    let entries = envelope.items.map { item -> Entry in
      let resolution: Resolution
      if let recipeID = item.recipeID, let recipe = recipes[recipeID], !recipe.archived {
        resolution = .libraryRecipe(recipeID)
      } else if item.recipeID != nil {
        resolution = .recipeMissing
      } else { resolution = .newDish }
      let match: MenuItem?
      switch resolution {
      case let .libraryRecipe(recipeID):
        let candidates = live.filter { $0.kind == .recipe && $0.recipeID == recipeID && !used.contains($0.id) }
        match = candidates.first(where: { $0.mealSlot == item.slot }) ?? candidates.first
      case .newDish:
        let normalized = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = live.filter { ($0.kind == .note || $0.kind == .reservation) && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(normalized) == .orderedSame && !used.contains($0.id) }
        match = candidates.first(where: { $0.mealSlot == item.slot }) ?? candidates.first
      case .recipeMissing: match = nil
      }
      guard let row = match else { return .new(item: item, resolution: resolution) }
      used.insert(row.id)
      var changes: [Change] = []
      if row.mealSlot != item.slot { changes.append(.slot(from: row.mealSlot, to: item.slot)) }
      let note = item.note.flatMap { value -> String? in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
      if row.notes != note { changes.append(.note(note)) }
      let scale = item.scale ?? 1
      if row.scale != scale { changes.append(.scale(from: row.scale, to: scale)) }
      return changes.isEmpty ? .kept(row: row, resolution: resolution) : .changed(row: row, changes: changes, resolution: resolution)
    }
    let staged = envelope.dayAtStage.map(Self.normalized).sorted(by: Self.precedes)
    let current = live.map(Self.liveValue).map(Self.normalized).sorted(by: Self.precedes)
    return Plan(menuID: menu.id, menuTitle: menu.title, dayOffset: envelope.dayOffset, entries: entries,
      removed: live.filter { !used.contains($0.id) }, dayChangedSinceStage: staged != current)
  }

  public static func apply(_ plan: Plan, keeping: Set<Int>, in db: Database, now: Date, uuid: @Sendable () -> UUID) throws {
    guard let menu = try Menu.find(plan.menuID).fetchOne(db) else { throw Error.menuUnavailable }
    guard (0..<menu.dayCount).contains(plan.dayOffset) else { throw Error.dayOutOfRange }
    var rowsByIndex: [(Int, MenuItem)] = []
    for row in plan.removedRows(keeping: keeping) {
      try MenuRepository.deleteItem(itemID: row.id, in: db)
    }
    for (index, entry) in plan.entries.enumerated() where keeping.contains(index) {
      switch entry {
      case let .kept(row, _): rowsByIndex.append((index, row))
      case let .changed(row, _, _):
        var updated = row
        switch entry {
        case let .changed(_, changes, _):
          for change in changes {
            switch change {
            case let .slot(_, to): updated.mealSlot = to
            case let .note(note): updated.notes = note
            case let .scale(_, to): updated.scale = to
            }
          }
        default: break
        }
        updated.dateModified = now
        try MenuItem.upsert { updated }.execute(db)
        rowsByIndex.append((index, updated))
      case let .new(item, resolution):
        let rowID: MenuItem.ID
        switch resolution {
        case let .libraryRecipe(recipeID):
          rowID = try MenuRepository.addRecipeItem(menuID: plan.menuID, recipeID: recipeID, dayOffset: plan.dayOffset, mealSlot: item.slot, notes: item.note, in: db, now: now, uuid: uuid)
        case .newDish, .recipeMissing:
          rowID = try MenuRepository.addNoteItem(menuID: plan.menuID, title: item.title, notes: item.note, dayOffset: plan.dayOffset, mealSlot: item.slot, in: db, now: now, uuid: uuid)
        }
        if let scale = item.scale { try RecipeScaleRepository.setScale(scale, for: .menuItem(rowID), in: db) }
        guard let row = try MenuItem.find(rowID).fetchOne(db) else { continue }
        rowsByIndex.append((index, row))
      }
    }
    for slot in MealPlanItemSlot.allCases {
      let group = rowsByIndex.filter { $0.1.mealSlot == slot }.sorted { $0.0 < $1.0 }
      for (order, pair) in group.enumerated() where pair.1.sortOrder != order {
        var updated = pair.1
        updated.sortOrder = order
        updated.dateModified = now
        try MenuItem.upsert { updated }.execute(db)
      }
    }
    try Menu.find(plan.menuID).update { $0.dateModified = #bind(now) }.execute(db)
  }

  private static func liveValue(_ row: MenuItem) -> ChatAccessStagedMenuDay.LiveItem {
    .init(kind: row.kind, title: row.title, recipeID: row.recipeID, slot: row.mealSlot, note: row.notes, scale: row.scale)
  }

  private static func normalized(_ item: ChatAccessStagedMenuDay.LiveItem) -> ChatAccessStagedMenuDay.LiveItem {
    var item = item
    item.note = item.note.flatMap { value -> String? in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    return item
  }

  private static func precedes(_ lhs: ChatAccessStagedMenuDay.LiveItem, _ rhs: ChatAccessStagedMenuDay.LiveItem) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
    if lhs.title != rhs.title { return lhs.title < rhs.title }
    if lhs.recipeID != rhs.recipeID { return (lhs.recipeID?.uuidString ?? "") < (rhs.recipeID?.uuidString ?? "") }
    if lhs.slot != rhs.slot { return lhs.slot.sortOrder < rhs.slot.sortOrder }
    if lhs.note != rhs.note { return (lhs.note ?? "") < (rhs.note ?? "") }
    return lhs.scale < rhs.scale
  }
}
