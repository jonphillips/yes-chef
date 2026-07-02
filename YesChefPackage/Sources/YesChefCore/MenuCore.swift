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

  public init(item: MenuItem, recipe: Recipe? = nil) {
    self.item = item
    self.recipe = recipe
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
    let itemRows = try MenuItem
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
      .compactMap { item in
        let recipe = item.recipeID.flatMap { recipesByID[$0] }
        if item.kind == .recipe && item.recipeID != nil && recipe == nil {
          return nil
        }
        return MenuItemRowData(
          item: item,
          recipe: recipe
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

  public static func deleteMenuPlacement(
    placementID: MenuPlacement.ID,
    in db: Database
  ) throws {
    _ = try requirePlacement(placementID, in: db)
    try MenuPlacement.find(placementID).delete().execute(db)
  }

  private static func requireMenu(_ menuID: Menu.ID, in db: Database) throws -> Menu {
    guard let menu = try Menu.find(menuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(menuID)
    }
    return menu
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

public enum MenuRepositoryError: Error, Equatable, Sendable {
  case emptyTitle
  case invalidDayCount
  case invalidDayOffset(Int)
  case menuNotFound(Menu.ID)
  case menuItemNotFound(MenuItem.ID)
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
