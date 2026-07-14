import Foundation
import SQLiteData

public struct MenuRowData: Identifiable, Equatable, Sendable {
  public var menu: Menu
  public var itemCount: Int
  public var placementCount: Int

  public init(menu: Menu, itemCount: Int = 0, placementCount: Int = 0) {
    self.menu = menu
    self.itemCount = itemCount
    self.placementCount = placementCount
  }

  public var id: Menu.ID { menu.id }
}

public struct MenuDetailData: Equatable, Sendable {
  public var menu: Menu
  public var itemRows: [MenuItemRowData]
  public var placements: [MenuPlacement]

  public init(
    menu: Menu,
    itemRows: [MenuItemRowData] = [],
    placements: [MenuPlacement] = []
  ) {
    self.menu = menu
    self.itemRows = itemRows
    self.placements = placements
  }
}

public struct MenuItemRowData: Identifiable, Equatable, Sendable {
  public var item: MenuItem
  public var recipe: Recipe?
  public var recipeIngredientLines: [String]
  public var recipeMethodLines: [String]
  public var thumbnailData: Data?

  public init(
    item: MenuItem,
    recipe: Recipe? = nil,
    recipeIngredientLines: [String] = [],
    recipeMethodLines: [String] = [],
    thumbnailData: Data? = nil
  ) {
    self.item = item
    self.recipe = recipe
    self.recipeIngredientLines = recipeIngredientLines
    self.recipeMethodLines = recipeMethodLines
    self.thumbnailData = thumbnailData
  }

  public var id: MenuItem.ID { item.id }

  public var displayTitle: String {
    recipe?.title ?? item.title
  }

  public var displayNotes: String? {
    item.notes
  }
}

public struct MenuListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [MenuRowData] {
    let activeRecipeIDs = Set(try Recipe.fetchAll(db).filter { !$0.archived }.map(\.id))
    let itemsByMenuID = Dictionary(
      grouping: try MenuItem.fetchAll(db).filter { item in
        guard item.kind == .recipe, let recipeID = item.recipeID else { return true }
        return activeRecipeIDs.contains(recipeID)
      },
      by: \.menuID
    )
    let placementsByMenuID = Dictionary(grouping: try MenuPlacement.fetchAll(db), by: \.menuID)

    return try Menu.fetchAll(db)
      .map { menu in
        MenuRowData(
          menu: menu,
          itemCount: itemsByMenuID[menu.id]?.count ?? 0,
          placementCount: placementsByMenuID[menu.id]?.count ?? 0
        )
      }
      .sorted {
        $0.menu.title.localizedStandardCompare($1.menu.title) == .orderedAscending
      }
  }
}

public struct MenuDetailRequest: FetchKeyRequest {
  public var menuID: Menu.ID

  public init(menuID: Menu.ID) {
    self.menuID = menuID
  }

  public func fetch(_ db: Database) throws -> MenuDetailData? {
    guard let menu = try Menu.find(menuID).fetchOne(db) else { return nil }

    let recipesByID = Dictionary(
      uniqueKeysWithValues: try Recipe.fetchAll(db)
        .filter { !$0.archived }
        .map { ($0.id, $0) }
    )
    let recipeIDs = Set(recipesByID.keys)
    let photoRows = try RecipePhoto
      .select {
        MenuItemPhotoRow.Columns(
          recipeID: $0.recipeID,
          thumbnailData: $0.thumbnailData,
          kind: $0.kind,
          sortOrder: $0.sortOrder
        )
      }
      .fetchAll(db)
    var thumbnailsByRecipeID: [Recipe.ID: MenuItemPhotoRow] = [:]
    for photo in photoRows where photo.kind != .referenceDocument && photo.thumbnailData != nil {
      guard let existing = thumbnailsByRecipeID[photo.recipeID] else {
        thumbnailsByRecipeID[photo.recipeID] = photo
        continue
      }
      if photo.isPreferred(over: existing) {
        thumbnailsByRecipeID[photo.recipeID] = photo
      }
    }
    let ingredientLinesByRecipeID = Dictionary(
      grouping: try IngredientLine.fetchAll(db)
        .filter { recipeIDs.contains($0.recipeID) },
      by: \.recipeID
    )
    let recipeMethodLinesByRecipeID = try recipeMethodLinesByRecipeID(recipeIDs, in: db)
    let itemRows = try MenuItem
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
      .compactMap { item in
        let recipe = item.recipeID.flatMap { recipesByID[$0] }
        if item.kind == .recipe && item.recipeID != nil && recipe == nil {
          return nil
        }

        let recipeIngredientLines: [String]
        let recipeMethodLines: [String]
        let thumbnailData: Data?
        if let recipe {
          recipeIngredientLines = (ingredientLinesByRecipeID[recipe.id] ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.originalText)
          recipeMethodLines = recipeMethodLinesByRecipeID[recipe.id] ?? []
          thumbnailData = thumbnailsByRecipeID[recipe.id]?.thumbnailData
        } else {
          recipeIngredientLines = []
          recipeMethodLines = []
          thumbnailData = nil
        }

        return MenuItemRowData(
          item: item,
          recipe: recipe,
          recipeIngredientLines: recipeIngredientLines,
          recipeMethodLines: recipeMethodLines,
          thumbnailData: thumbnailData
        )
      }
      .sorted(by: areMenuItemRowsInIncreasingOrder)
    let placements = try MenuPlacement
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
      .sorted {
        if $0.startDate != $1.startDate {
          return $0.startDate < $1.startDate
        }
        return $0.dateCreated < $1.dateCreated
      }

    return MenuDetailData(menu: menu, itemRows: itemRows, placements: placements)
  }
}

private func recipeMethodLinesByRecipeID(
  _ recipeIDs: Set<Recipe.ID>,
  in db: Database
) throws -> [Recipe.ID: [String]] {
  var sectionsByRecipeID: [Recipe.ID: [InstructionSection]] = [:]
  for section in try InstructionSection.fetchAll(db) where recipeIDs.contains(section.recipeID) {
    sectionsByRecipeID[section.recipeID, default: []].append(section)
  }

  var stepsByRecipeID: [Recipe.ID: [InstructionStep]] = [:]
  for step in try InstructionStep.fetchAll(db) where recipeIDs.contains(step.recipeID) {
    stepsByRecipeID[step.recipeID, default: []].append(step)
  }

  var linesByRecipeID: [Recipe.ID: [String]] = [:]
  for recipeID in recipeIDs {
    linesByRecipeID[recipeID] = recipeMethodLines(
      sections: sectionsByRecipeID[recipeID] ?? [],
      steps: stepsByRecipeID[recipeID] ?? []
    )
  }
  return linesByRecipeID
}

private func recipeMethodLines(
  sections: [InstructionSection],
  steps: [InstructionStep]
) -> [String] {
  var sortedSections = sections
  sortedSections.sort(by: isInstructionSectionInIncreasingOrder)
  let includesSectionSubheaders = sortedSections.count > 1

  var stepsBySectionID: [InstructionSection.ID: [InstructionStep]] = [:]
  for step in steps {
    stepsBySectionID[step.sectionID, default: []].append(step)
  }

  var lines: [String] = []
  for section in sortedSections {
    var sectionSteps = stepsBySectionID[section.id] ?? []
    sectionSteps.sort(by: isInstructionStepInIncreasingOrder)
    guard !sectionSteps.isEmpty else { continue }

    if includesSectionSubheaders, let name = section.name, !name.isEmpty {
      lines.append("\(name):")
    }
    for (offset, step) in sectionSteps.enumerated() {
      lines.append("\(offset + 1). \(step.text)")
    }
  }
  return lines
}

private func isInstructionSectionInIncreasingOrder(
  _ lhs: InstructionSection,
  _ rhs: InstructionSection
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func isInstructionStepInIncreasingOrder(
  _ lhs: InstructionStep,
  _ rhs: InstructionStep
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return lhs.id.uuidString < rhs.id.uuidString
}

@Selection
private struct MenuItemPhotoRow: Equatable, Sendable {
  let recipeID: Recipe.ID
  let thumbnailData: Data?
  let kind: RecipePhotoKind
  let sortOrder: Int

  func isPreferred(over other: Self) -> Bool {
    if kind != other.kind {
      return kind == .hero
    }
    return sortOrder < other.sortOrder
  }
}

public enum MenuRepository {
  @discardableResult
  public static func addMenu(
    title: String,
    notes: String?,
    dayCount: Int,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Menu.ID {
    guard let title = title.nonEmptyMenuText else {
      throw MenuRepositoryError.emptyTitle
    }
    guard dayCount > 0 else {
      throw MenuRepositoryError.invalidDayCount
    }

    let menu = Menu(
      id: uuid(),
      title: title,
      notes: notes?.nonEmptyMenuText,
      dayCount: dayCount,
      dateCreated: now,
      dateModified: now
    )
    try Menu.insert { menu }.execute(db)
    return menu.id
  }

  @discardableResult
  public static func addRecipeItem(
    menuID: Menu.ID,
    recipeID: Recipe.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    notes: String?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuItem.ID {
    let menu = try requireMenu(menuID, in: db)
    try validateDayOffset(dayOffset, for: menu)
    guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
      throw MenuRepositoryError.recipeNotFound(recipeID)
    }

    let item = MenuItem(
      id: uuid(),
      menuID: menuID,
      kind: .recipe,
      recipeID: recipeID,
      title: recipe.title,
      dayOffset: dayOffset,
      mealSlot: mealSlot,
      notes: notes?.nonEmptyMenuText,
      sortOrder: try nextSortOrder(menuID: menuID, dayOffset: dayOffset, mealSlot: mealSlot, in: db),
      dateCreated: now,
      dateModified: now
    )
    try MenuItem.insert { item }.execute(db)
    return item.id
  }

  @discardableResult
  public static func addNoteItem(
    menuID: Menu.ID,
    title: String,
    notes: String?,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuItem.ID {
    let menu = try requireMenu(menuID, in: db)
    try validateDayOffset(dayOffset, for: menu)
    guard let title = title.nonEmptyMenuText else {
      throw MenuRepositoryError.emptyTitle
    }

    let item = MenuItem(
      id: uuid(),
      menuID: menuID,
      kind: .note,
      title: title,
      dayOffset: dayOffset,
      mealSlot: mealSlot,
      notes: notes?.nonEmptyMenuText,
      sortOrder: try nextSortOrder(menuID: menuID, dayOffset: dayOffset, mealSlot: mealSlot, in: db),
      dateCreated: now,
      dateModified: now
    )
    try MenuItem.insert { item }.execute(db)
    return item.id
  }

  @discardableResult
  public static func addComplementItem(
    _ suggestion: MenuComplementSuggestion,
    to menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuItem.ID {
    let menu = try requireMenu(menuID, in: db)
    try validateDayOffset(suggestion.dayOffset, for: menu)
    guard let title = suggestion.title.nonEmptyMenuText else {
      throw MenuRepositoryError.emptyTitle
    }

    let item = MenuItem(
      id: uuid(),
      menuID: menuID,
      kind: suggestion.kind == .reservation ? .note : suggestion.kind,
      title: title,
      dayOffset: suggestion.dayOffset,
      mealSlot: suggestion.mealSlot,
      notes: suggestion.body?.nonEmptyMenuText,
      sortOrder: try nextSortOrder(
        menuID: menuID,
        dayOffset: suggestion.dayOffset,
        mealSlot: suggestion.mealSlot,
        in: db
      ),
      dateCreated: now,
      dateModified: now
    )
    try MenuItem.insert { item }.execute(db)
    return item.id
  }

  public static func updateRecipeItem(
    itemID: MenuItem.ID,
    recipeID: Recipe.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    notes: String?,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }
    let menu = try requireMenu(item.menuID, in: db)
    try validateDayOffset(dayOffset, for: menu)
    guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
      throw MenuRepositoryError.recipeNotFound(recipeID)
    }

    let isMoving = item.dayOffset != dayOffset || item.mealSlot != mealSlot
    item.kind = .recipe
    item.recipeID = recipeID
    item.title = recipe.title
    item.dayOffset = dayOffset
    item.mealSlot = mealSlot
    item.notes = notes?.nonEmptyMenuText
    item.sortOrder = isMoving
      ? try nextSortOrder(menuID: item.menuID, dayOffset: dayOffset, mealSlot: mealSlot, in: db)
      : item.sortOrder
    item.dateModified = now
    try MenuItem.upsert { item }.execute(db)
  }

  public static func updateNoteItem(
    itemID: MenuItem.ID,
    title: String,
    notes: String?,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }
    let menu = try requireMenu(item.menuID, in: db)
    try validateDayOffset(dayOffset, for: menu)
    guard let title = title.nonEmptyMenuText else {
      throw MenuRepositoryError.emptyTitle
    }

    let isMoving = item.dayOffset != dayOffset || item.mealSlot != mealSlot
    item.kind = .note
    item.recipeID = nil
    item.title = title
    item.dayOffset = dayOffset
    item.mealSlot = mealSlot
    item.notes = notes?.nonEmptyMenuText
    item.sortOrder = isMoving
      ? try nextSortOrder(menuID: item.menuID, dayOffset: dayOffset, mealSlot: mealSlot, in: db)
      : item.sortOrder
    item.dateModified = now
    try MenuItem.upsert { item }.execute(db)
  }

  /// Turns an existing note-kind menu item into a recipe-kind item without moving it. Promotion is an
  /// explicit second step after the new recipe has been reviewed and saved, so declining this operation
  /// leaves the note untouched.
  public static func replaceNoteItemWithRecipe(
    itemID: MenuItem.ID,
    recipeID: Recipe.ID,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }
    guard item.kind == .note else {
      throw MenuRepositoryError.menuItemIsNotNote(itemID)
    }
    guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
      throw MenuRepositoryError.recipeNotFound(recipeID)
    }

    item.kind = .recipe
    item.recipeID = recipeID
    item.title = recipe.title
    item.notes = nil
    item.dateModified = now
    try MenuItem.upsert { item }.execute(db)
  }

  @discardableResult
  public static func placeMenu(
    menuID: Menu.ID,
    startDate: Date,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuPlacement.ID {
    _ = try requireMenu(menuID, in: db)
    let placement = MenuPlacement(
      id: uuid(),
      menuID: menuID,
      startDate: startDate,
      dateCreated: now,
      dateModified: now
    )
    try MenuPlacement.insert { placement }.execute(db)
    return placement.id
  }

  public static func updateMenuPlacement(
    placementID: MenuPlacement.ID,
    startDate: Date,
    in db: Database,
    now: Date
  ) throws {
    var placement = try requirePlacement(placementID, in: db)
    placement.startDate = startDate
    placement.dateModified = now
    try MenuPlacement.upsert { placement }.execute(db)
  }

  public static func updateMenuDayCount(
    menuID: Menu.ID,
    dayCount: Int,
    in db: Database,
    now: Date
  ) throws {
    guard dayCount > 0 else {
      throw MenuRepositoryError.invalidDayCount
    }
    var menu = try requireMenu(menuID, in: db)
    let highestOccupiedDayOffset = try MenuItem
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
      .map(\.dayOffset)
      .max()
    if let highestOccupiedDayOffset, highestOccupiedDayOffset >= dayCount {
      throw MenuRepositoryError.invalidDayCount
    }
    menu.dayCount = dayCount
    menu.dateModified = now
    try Menu.upsert { menu }.execute(db)
  }

  public static func moveItem(
    itemID: MenuItem.ID,
    toDayOffset dayOffset: Int,
    mealSlot: MealPlanItemSlot? = nil,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }
    let menu = try requireMenu(item.menuID, in: db)
    try validateDayOffset(dayOffset, for: menu)

    let mealSlot = mealSlot ?? item.mealSlot
    let isMoving = item.dayOffset != dayOffset || item.mealSlot != mealSlot
    item.dayOffset = dayOffset
    item.mealSlot = mealSlot
    item.sortOrder = isMoving
      ? try nextSortOrder(menuID: item.menuID, dayOffset: dayOffset, mealSlot: mealSlot, in: db)
      : item.sortOrder
    item.dateModified = now
    try MenuItem.upsert { item }.execute(db)
  }

  /// Interim within-a-day reorder (parked drag-and-drop stand-in). Swaps an item's position with its
  /// adjacent same-day, same-meal-slot sibling by renumbering the slot's `sortOrder` sequentially, so
  /// the move is stable even if stored `sortOrder`s had gaps or ties. No-op (returns `false`) when the
  /// item is already at the slot's edge in the requested direction.
  @discardableResult
  public static func reorderItemWithinDay(
    itemID: MenuItem.ID,
    direction: MenuItemMoveDirection,
    in db: Database,
    now: Date
  ) throws -> Bool {
    guard let item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }

    var siblings = try MenuItem
      .where {
        $0.menuID.eq(item.menuID)
          && $0.dayOffset.eq(item.dayOffset)
          && $0.mealSlot.eq(item.mealSlot)
      }
      .fetchAll(db)
      .sorted { $0.sortOrder < $1.sortOrder }

    guard let index = siblings.firstIndex(where: { $0.id == itemID }) else { return false }
    let neighborIndex = direction == .earlier ? index - 1 : index + 1
    guard siblings.indices.contains(neighborIndex) else { return false }

    siblings.swapAt(index, neighborIndex)

    for (position, sibling) in siblings.enumerated() where sibling.sortOrder != position {
      var updated = sibling
      updated.sortOrder = position
      updated.dateModified = now
      try MenuItem.upsert { updated }.execute(db)
    }
    return true
  }

  public static func deleteItem(
    itemID: MenuItem.ID,
    in db: Database
  ) throws {
    _ = try requireMenuItem(itemID, in: db)
    try MenuItem.find(itemID).delete().execute(db)
  }

  public static func deleteMenu(
    menuID: Menu.ID,
    in db: Database
  ) throws {
    _ = try requireMenu(menuID, in: db)
    try LearningRepository.deleteAll(sourceType: .menu, sourceID: menuID, in: db)
    try Menu.find(menuID).delete().execute(db)
  }

  public static func deleteMenuPlacement(
    placementID: MenuPlacement.ID,
    in db: Database
  ) throws {
    _ = try requirePlacement(placementID, in: db)
    try MenuPlacement.find(placementID).delete().execute(db)
  }

  public static func updateExternalProjectName(
    menuID: Menu.ID,
    externalProjectName: String?,
    in db: Database,
    now: Date
  ) throws {
    _ = try requireMenu(menuID, in: db)
    try Menu.find(menuID).update {
      $0.externalProjectName = #bind(externalProjectName?.nonEmptyMenuText)
      $0.dateModified = #bind(now)
    }
    .execute(db)
  }

  private static func requireMenu(_ menuID: Menu.ID, in db: Database) throws -> Menu {
    guard let menu = try Menu.find(menuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(menuID)
    }
    return menu
  }

  private static func requireMenuItem(_ itemID: MenuItem.ID, in db: Database) throws -> MenuItem {
    guard let item = try MenuItem.find(itemID).fetchOne(db) else {
      throw MenuRepositoryError.menuItemNotFound(itemID)
    }
    return item
  }

  private static func requirePlacement(
    _ placementID: MenuPlacement.ID,
    in db: Database
  ) throws -> MenuPlacement {
    guard let placement = try MenuPlacement.find(placementID).fetchOne(db) else {
      throw MenuRepositoryError.placementNotFound(placementID)
    }
    return placement
  }

  private static func validateDayOffset(_ dayOffset: Int, for menu: Menu) throws {
    guard (0..<menu.dayCount).contains(dayOffset) else {
      throw MenuRepositoryError.invalidDayOffset(dayOffset)
    }
  }

  private static func nextSortOrder(
    menuID: Menu.ID,
    dayOffset: Int,
    mealSlot: MealPlanItemSlot,
    in db: Database
  ) throws -> Int {
    let items = try MenuItem
      .where {
        $0.menuID.eq(menuID)
          && $0.dayOffset.eq(dayOffset)
          && $0.mealSlot.eq(mealSlot)
      }
      .fetchAll(db)
    return (items.map(\.sortOrder).max() ?? -1) + 1
  }
}

/// Direction for `MenuRepository.reorderItemWithinDay` — `.earlier` moves a dish up (toward the top of
/// its meal-slot group), `.later` moves it down.
public enum MenuItemMoveDirection: Sendable {
  case earlier
  case later
}

public enum MenuRepositoryError: Error, Equatable, Sendable {
  case emptyTitle
  case invalidDayCount
  case invalidDayOffset(Int)
  case menuNotFound(Menu.ID)
  case menuItemNotFound(MenuItem.ID)
  case menuItemIsNotNote(MenuItem.ID)
  case placementNotFound(MenuPlacement.ID)
  case recipeNotFound(Recipe.ID)
}

private func areMenuItemRowsInIncreasingOrder(
  _ lhs: MenuItemRowData,
  _ rhs: MenuItemRowData
) -> Bool {
  if lhs.item.dayOffset != rhs.item.dayOffset {
    return lhs.item.dayOffset < rhs.item.dayOffset
  }
  if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
    return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
}

private extension String {
  var nonEmptyMenuText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
