import Foundation
import SQLiteData

public struct GroceryItemRowData: Identifiable, Equatable, Sendable {
  public var item: GroceryItem
  public var sources: [GroceryItemSource]

  public init(item: GroceryItem, sources: [GroceryItemSource] = []) {
    self.item = item
    self.sources = sources
  }

  public var id: GroceryItem.ID { item.id }
}

public struct GroceryListRowData: Identifiable, Equatable, Sendable {
  public var list: GroceryList
  public var itemCount: Int
  public var remainingItemCount: Int

  public init(list: GroceryList, itemCount: Int = 0, remainingItemCount: Int = 0) {
    self.list = list
    self.itemCount = itemCount
    self.remainingItemCount = remainingItemCount
  }

  public var id: GroceryList.ID { list.id }
}

public struct GroceryListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [GroceryListRowData] {
    let itemsByListID = Dictionary(grouping: try GroceryItem.fetchAll(db), by: \.groceryListID)

    return try GroceryList.fetchAll(db)
      .map { list in
        let items = itemsByListID[list.id] ?? []
        return GroceryListRowData(
          list: list,
          itemCount: items.count,
          remainingItemCount: items.filter { !$0.isPurchased }.count
        )
      }
      .sorted(by: areGroceryListRowsInIncreasingOrder)
  }
}

public struct GroceryItemListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [GroceryItemRowData] {
    let sourcesByItemID = Dictionary(grouping: try GroceryItemSource.fetchAll(db), by: \.groceryItemID)

    return try GroceryItem.fetchAll(db)
      .map { item in
        GroceryItemRowData(
          item: item,
          sources: (sourcesByItemID[item.id] ?? [])
            .sorted(by: areGroceryItemSourcesInIncreasingOrder)
        )
      }
      .sorted(by: areGroceryItemRowsInIncreasingOrder)
  }
}

public enum GroceryRepository {
  public static let defaultListTitle = "My Grocery List"

  @discardableResult
  public static func ensureDefaultList(
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> GroceryList.ID {
    let lists = try GroceryList.fetchAll(db).sorted(by: areGroceryListsInIncreasingOrder)
    if let defaultList = lists.first(where: \.isDefault) {
      return defaultList.id
    }
    if let firstList = lists.first {
      return firstList.id
    }

    let list = GroceryList(
      id: uuid(),
      title: defaultListTitle,
      sortOrder: 0,
      isDefault: true,
      dateCreated: now,
      dateModified: now
    )
    try GroceryList.insert { list }.execute(db)
    return list.id
  }

  @discardableResult
  public static func addList(
    title: String,
    remindersListName: String? = nil,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> GroceryList.ID {
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyListTitle
    }

    let list = GroceryList(
      id: uuid(),
      title: title,
      sortOrder: try nextListSortOrder(in: db),
      remindersListName: remindersListName?.nonEmptyGroceryText,
      dateCreated: now,
      dateModified: now
    )
    try GroceryList.insert { list }.execute(db)
    return list.id
  }

  @discardableResult
  public static func addCustomItem(
    title: String,
    quantityText: String? = nil,
    unit: String? = nil,
    aisle: String? = nil,
    notes: String? = nil,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> GroceryItem.ID {
    _ = try requireList(groceryListID, in: db)
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyItemTitle
    }

    let item = GroceryItem(
      id: uuid(),
      groceryListID: groceryListID,
      title: title,
      quantityText: quantityText?.nonEmptyGroceryText,
      unit: unit?.nonEmptyGroceryText,
      aisle: aisle?.nonEmptyGroceryText,
      notes: notes?.nonEmptyGroceryText,
      sortOrder: try nextItemSortOrder(groceryListID: groceryListID, in: db),
      dateCreated: now,
      dateModified: now
    )
    try GroceryItem.insert { item }.execute(db)
    try GroceryItemSource.insert {
      GroceryItemSource(
        id: uuid(),
        groceryItemID: item.id,
        origin: .custom,
        sourceTitle: "Custom",
        ingredientText: title,
        dateCreated: now
      )
    }
    .execute(db)
    return item.id
  }

  public static func updatePurchasedState(
    itemID: GroceryItem.ID,
    isPurchased: Bool,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try GroceryItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.itemNotFound(itemID)
    }

    item.isPurchased = isPurchased
    item.purchasedAt = isPurchased ? now : nil
    item.dateModified = now
    try GroceryItem.upsert { item }.execute(db)
  }

  public static func deleteItem(
    itemID: GroceryItem.ID,
    in db: Database
  ) throws {
    guard try GroceryItem.find(itemID).fetchOne(db) != nil else {
      throw GroceryRepositoryError.itemNotFound(itemID)
    }
    try GroceryItem.find(itemID).delete().execute(db)
  }

  @discardableResult
  public static func addRecipe(
    recipeID: Recipe.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let recipe = try requireRecipe(recipeID, in: db)

    return try addRecipeIngredients(
      recipe: recipe,
      groceryListID: groceryListID,
      source: GroceryItemSourceDraft(
        origin: .recipe,
        sourceTitle: recipe.title
      ),
      in: db,
      now: now,
      uuid: uuid
    )
  }

  @discardableResult
  public static func addMealPlanItem(
    itemID: MealPlanItem.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let item = try requireMealPlanItem(itemID, in: db)
    guard item.kind == .recipe, let recipeID = item.recipeID else {
      throw GroceryRepositoryError.mealPlanItemHasNoRecipe(itemID)
    }
    let recipe = try requireRecipe(recipeID, in: db)

    return try addRecipeIngredients(
      recipe: recipe,
      groceryListID: groceryListID,
      source: GroceryItemSourceDraft(
        origin: .calendarItem,
        mealPlanItemID: item.id,
        scheduledDate: item.scheduledDate,
        mealSlot: item.mealSlot,
        sourceTitle: recipe.title,
        sourceSubtitle: item.mealSlot.title
      ),
      in: db,
      now: now,
      uuid: uuid
    )
  }

  @discardableResult
  public static func addMealPlanRows(
    _ rows: [MealPlanItemRowData],
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)

    var itemIDs: [GroceryItem.ID] = []
    for row in rows {
      guard row.item.kind == .recipe, let recipeID = row.item.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      let source: GroceryItemSourceDraft

      if let menu = row.menu,
         let menuPlacement = row.menuPlacement,
         let menuItem = row.menuItem {
        source = GroceryItemSourceDraft(
          origin: .menuPlacement,
          mealPlanItemID: nil,
          menuID: menu.id,
          menuItemID: menuItem.id,
          menuPlacementID: menuPlacement.id,
          scheduledDate: row.item.scheduledDate,
          mealSlot: row.item.mealSlot,
          sourceTitle: menu.title,
          sourceSubtitle: recipe.title
        )
      } else {
        source = GroceryItemSourceDraft(
          origin: .calendarItem,
          mealPlanItemID: row.item.id,
          scheduledDate: row.item.scheduledDate,
          mealSlot: row.item.mealSlot,
          sourceTitle: recipe.title,
          sourceSubtitle: row.item.mealSlot.title
        )
      }

      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: source,
          in: db,
          now: now,
          uuid: uuid
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }

  @discardableResult
  public static func addMenu(
    menuID: Menu.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let menu = try requireMenu(menuID, in: db)
    let items = try MenuItem
      .where { $0.menuID.eq(menuID) }
      .fetchAll(db)
      .filter { $0.kind == .recipe && $0.recipeID != nil }
      .sorted(by: areMenuItemsInIncreasingOrder)

    var itemIDs: [GroceryItem.ID] = []
    for menuItem in items {
      guard let recipeID = menuItem.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: GroceryItemSourceDraft(
            origin: .menu,
            menuID: menu.id,
            menuItemID: menuItem.id,
            mealSlot: menuItem.mealSlot,
            sourceTitle: menu.title,
            sourceSubtitle: recipe.title
          ),
          in: db,
          now: now,
          uuid: uuid
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }

  @discardableResult
  public static func addMenuPlacement(
    placementID: MenuPlacement.ID,
    groceryListID: GroceryList.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    _ = try requireList(groceryListID, in: db)
    let placement = try requireMenuPlacement(placementID, in: db)
    let menu = try requireMenu(placement.menuID, in: db)
    let items = try MenuItem
      .where { $0.menuID.eq(menu.id) }
      .fetchAll(db)
      .filter { $0.kind == .recipe && $0.recipeID != nil }
      .sorted(by: areMenuItemsInIncreasingOrder)
    let calendar = Calendar(identifier: .gregorian)

    var itemIDs: [GroceryItem.ID] = []
    for menuItem in items {
      guard let recipeID = menuItem.recipeID else { continue }
      let recipe = try requireRecipe(recipeID, in: db)
      let scheduledDate = calendar.date(
        byAdding: .day,
        value: menuItem.dayOffset,
        to: placement.startDate
      )
      do {
        itemIDs += try addRecipeIngredients(
          recipe: recipe,
          groceryListID: groceryListID,
          source: GroceryItemSourceDraft(
            origin: .menuPlacement,
            menuID: menu.id,
            menuItemID: menuItem.id,
            menuPlacementID: placement.id,
            scheduledDate: scheduledDate,
            mealSlot: menuItem.mealSlot,
            sourceTitle: menu.title,
            sourceSubtitle: recipe.title
          ),
          in: db,
          now: now,
          uuid: uuid
        )
      } catch GroceryRepositoryError.noShoppableIngredients {
        continue
      }
    }

    guard !itemIDs.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }
    return itemIDs
  }

  private static func addRecipeIngredients(
    recipe: Recipe,
    groceryListID: GroceryList.ID,
    source: GroceryItemSourceDraft,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [GroceryItem.ID] {
    let sectionsByID = Dictionary(uniqueKeysWithValues: try IngredientSection
      .where { $0.recipeID.eq(recipe.id) }
      .fetchAll(db)
      .map { ($0.id, $0) })
    let lines = try IngredientLine
      .where { $0.recipeID.eq(recipe.id) }
      .fetchAll(db)
      .filter(\.isShoppable)
      .sorted { lhs, rhs in
        let lhsSectionSort = sectionsByID[lhs.sectionID]?.sortOrder ?? 0
        let rhsSectionSort = sectionsByID[rhs.sectionID]?.sortOrder ?? 0
        if lhsSectionSort != rhsSectionSort {
          return lhsSectionSort < rhsSectionSort
        }
        return lhs.sortOrder < rhs.sortOrder
      }

    guard !lines.isEmpty else {
      throw GroceryRepositoryError.noShoppableIngredients
    }

    var itemIDs: [GroceryItem.ID] = []
    var sortOrder = try nextItemSortOrder(groceryListID: groceryListID, in: db)
    for line in lines {
      let itemID = try addOrConsolidateGeneratedItem(
        GroceryGeneratedItemDraft(line: line),
        groceryListID: groceryListID,
        source: PendingGroceryItemSource(
          id: uuid(),
          origin: source.origin,
          recipeID: recipe.id,
          ingredientLineID: line.id,
          mealPlanItemID: source.mealPlanItemID,
          menuID: source.menuID,
          menuItemID: source.menuItemID,
          menuPlacementID: source.menuPlacementID,
          scheduledDate: source.scheduledDate,
          mealSlot: source.mealSlot,
          sourceTitle: source.sourceTitle ?? recipe.title,
          sourceSubtitle: source.sourceSubtitle,
          ingredientText: line.originalText,
          dateCreated: now
        ),
        sortOrder: &sortOrder,
        in: db,
        now: now,
        uuid: uuid
      )
      itemIDs.append(itemID)
    }

    return itemIDs
  }

  private static func addOrConsolidateGeneratedItem(
    _ draft: GroceryGeneratedItemDraft,
    groceryListID: GroceryList.ID,
    source: PendingGroceryItemSource,
    sortOrder: inout Int,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> GroceryItem.ID {
    if var item = try existingItemCompatibleWithGeneratedDraft(
      draft,
      groceryListID: groceryListID,
      in: db
    ) {
      item.quantity = combinedQuantity(item.quantity, draft.quantity)
      item.quantityText = item.quantity.map(formatGroceryQuantity)
      item.dateModified = now
      try GroceryItem.upsert { item }.execute(db)
      try insertSource(source, groceryItemID: item.id, in: db)
      return item.id
    }

    let item = GroceryItem(
      id: uuid(),
      groceryListID: groceryListID,
      title: draft.title,
      quantity: draft.quantity,
      quantityText: draft.quantityText,
      unit: draft.unit,
      aisle: draft.aisle,
      notes: draft.notes,
      sortOrder: sortOrder,
      dateCreated: now,
      dateModified: now
    )
    try GroceryItem.insert { item }.execute(db)
    try insertSource(source, groceryItemID: item.id, in: db)
    sortOrder += 1
    return item.id
  }

  private static func insertSource(
    _ source: PendingGroceryItemSource,
    groceryItemID: GroceryItem.ID,
    in db: Database
  ) throws {
    try GroceryItemSource.insert {
      GroceryItemSource(
        id: source.id,
        groceryItemID: groceryItemID,
        origin: source.origin,
        recipeID: source.recipeID,
        ingredientLineID: source.ingredientLineID,
        mealPlanItemID: source.mealPlanItemID,
        menuID: source.menuID,
        menuItemID: source.menuItemID,
        menuPlacementID: source.menuPlacementID,
        scheduledDate: source.scheduledDate,
        mealSlot: source.mealSlot,
        sourceTitle: source.sourceTitle,
        sourceSubtitle: source.sourceSubtitle,
        ingredientText: source.ingredientText,
        dateCreated: source.dateCreated
      )
    }
    .execute(db)
  }

  private static func existingItemCompatibleWithGeneratedDraft(
    _ draft: GroceryGeneratedItemDraft,
    groceryListID: GroceryList.ID,
    in db: Database
  ) throws -> GroceryItem? {
    try GroceryItem
      .where { $0.groceryListID.eq(groceryListID) }
      .fetchAll(db)
      .filter { !$0.isPurchased }
      .sorted {
        if $0.sortOrder != $1.sortOrder {
          return $0.sortOrder < $1.sortOrder
        }
        return $0.id.uuidString < $1.id.uuidString
      }
      .first { item in
        item.canConsolidate(with: draft)
      }
  }

  private static func requireList(_ listID: GroceryList.ID, in db: Database) throws -> GroceryList {
    guard let list = try GroceryList.find(listID).fetchOne(db) else {
      throw GroceryRepositoryError.listNotFound(listID)
    }
    return list
  }

  private static func requireRecipe(_ recipeID: Recipe.ID, in db: Database) throws -> Recipe {
    guard let recipe = try Recipe.find(recipeID).fetchOne(db) else {
      throw GroceryRepositoryError.recipeNotFound(recipeID)
    }
    return recipe
  }

  private static func requireMenu(_ menuID: Menu.ID, in db: Database) throws -> Menu {
    guard let menu = try Menu.find(menuID).fetchOne(db) else {
      throw GroceryRepositoryError.menuNotFound(menuID)
    }
    return menu
  }

  private static func requireMenuPlacement(
    _ placementID: MenuPlacement.ID,
    in db: Database
  ) throws -> MenuPlacement {
    guard let placement = try MenuPlacement.find(placementID).fetchOne(db) else {
      throw GroceryRepositoryError.menuPlacementNotFound(placementID)
    }
    return placement
  }

  private static func requireMealPlanItem(
    _ itemID: MealPlanItem.ID,
    in db: Database
  ) throws -> MealPlanItem {
    guard let item = try MealPlanItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.mealPlanItemNotFound(itemID)
    }
    return item
  }

  private static func nextListSortOrder(in db: Database) throws -> Int {
    (try GroceryList.fetchAll(db).map(\.sortOrder).max() ?? -1) + 1
  }

  private static func nextItemSortOrder(
    groceryListID: GroceryList.ID,
    in db: Database
  ) throws -> Int {
    let items = try GroceryItem
      .where { $0.groceryListID.eq(groceryListID) }
      .fetchAll(db)
    return (items.map(\.sortOrder).max() ?? -1) + 1
  }
}

public enum GroceryRepositoryError: Error, Equatable, Sendable {
  case emptyItemTitle
  case emptyListTitle
  case itemNotFound(GroceryItem.ID)
  case listNotFound(GroceryList.ID)
  case mealPlanItemHasNoRecipe(MealPlanItem.ID)
  case mealPlanItemNotFound(MealPlanItem.ID)
  case menuNotFound(Menu.ID)
  case menuPlacementNotFound(MenuPlacement.ID)
  case noShoppableIngredients
  case recipeNotFound(Recipe.ID)
}

private struct GroceryItemSourceDraft {
  var origin: GroceryItemOrigin
  var mealPlanItemID: MealPlanItem.ID? = nil
  var menuID: Menu.ID? = nil
  var menuItemID: MenuItem.ID? = nil
  var menuPlacementID: MenuPlacement.ID? = nil
  var scheduledDate: Date? = nil
  var mealSlot: MealPlanItemSlot? = nil
  var sourceTitle: String? = nil
  var sourceSubtitle: String? = nil
}

private struct GroceryGeneratedItemDraft {
  var title: String
  var quantity: Double?
  var quantityText: String?
  var unit: String?
  var aisle: String?
  var notes: String?

  init(line: IngredientLine) {
    self.title = line.groceryItemTitle
    self.quantity = line.quantity
    self.quantityText = line.groceryQuantityText
    self.unit = line.unit?.nonEmptyGroceryText
    self.aisle = line.shoppingCategory?.nonEmptyGroceryText
    self.notes = line.groceryNotes
  }
}

private struct PendingGroceryItemSource {
  var id: UUID
  var origin: GroceryItemOrigin
  var recipeID: Recipe.ID? = nil
  var ingredientLineID: IngredientLine.ID? = nil
  var mealPlanItemID: MealPlanItem.ID? = nil
  var menuID: Menu.ID? = nil
  var menuItemID: MenuItem.ID? = nil
  var menuPlacementID: MenuPlacement.ID? = nil
  var scheduledDate: Date? = nil
  var mealSlot: MealPlanItemSlot? = nil
  var sourceTitle: String? = nil
  var sourceSubtitle: String? = nil
  var ingredientText: String? = nil
  var dateCreated: Date
}

private func areGroceryListRowsInIncreasingOrder(
  _ lhs: GroceryListRowData,
  _ rhs: GroceryListRowData
) -> Bool {
  areGroceryListsInIncreasingOrder(lhs.list, rhs.list)
}

private func areGroceryListsInIncreasingOrder(_ lhs: GroceryList, _ rhs: GroceryList) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}

private func areGroceryItemRowsInIncreasingOrder(
  _ lhs: GroceryItemRowData,
  _ rhs: GroceryItemRowData
) -> Bool {
  if lhs.item.groceryListID != rhs.item.groceryListID {
    return lhs.item.groceryListID.uuidString < rhs.item.groceryListID.uuidString
  }
  if lhs.item.isPurchased != rhs.item.isPurchased {
    return !lhs.item.isPurchased
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  let titleComparison = lhs.item.title.localizedStandardCompare(rhs.item.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.item.id.uuidString < rhs.item.id.uuidString
}

private func areGroceryItemSourcesInIncreasingOrder(
  _ lhs: GroceryItemSource,
  _ rhs: GroceryItemSource
) -> Bool {
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func areMenuItemsInIncreasingOrder(_ lhs: MenuItem, _ rhs: MenuItem) -> Bool {
  if lhs.dayOffset != rhs.dayOffset {
    return lhs.dayOffset < rhs.dayOffset
  }
  if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder {
    return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder
  }
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
}

private extension GroceryItem {
  func canConsolidate(with draft: GroceryGeneratedItemDraft) -> Bool {
    title.groceryConsolidationKey == draft.title.groceryConsolidationKey
      && unit.groceryConsolidationKey == draft.unit.groceryConsolidationKey
      && aisle.groceryConsolidationKey == draft.aisle.groceryConsolidationKey
      && notes.groceryConsolidationKey == draft.notes.groceryConsolidationKey
      && canCombineQuantity(
        quantity,
        quantityText: quantityText,
        with: draft.quantity,
        quantityText: draft.quantityText
      )
  }
}

private extension IngredientLine {
  var isShoppable: Bool {
    !doNotShop && !isHeader && !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var groceryItemTitle: String {
    item?.nonEmptyGroceryText ?? originalText
  }

  var groceryQuantityText: String? {
    quantityText?.nonEmptyGroceryText ?? quantity.map(formatGroceryQuantity)
  }

  var groceryNotes: String? {
    [preparation, comment]
      .compactMap { $0?.nonEmptyGroceryText }
      .joined(separator: "; ")
      .nonEmptyGroceryText
  }
}

private func canCombineQuantity(
  _ lhs: Double?,
  quantityText lhsQuantityText: String?,
  with rhs: Double?,
  quantityText rhsQuantityText: String?
) -> Bool {
  if lhs != nil, rhs != nil {
    return true
  }
  return lhs == nil
    && rhs == nil
    && lhsQuantityText == nil
    && rhsQuantityText == nil
}

private func combinedQuantity(_ lhs: Double?, _ rhs: Double?) -> Double? {
  guard let lhs, let rhs else { return nil }
  return lhs + rhs
}

private func formatGroceryQuantity(_ quantity: Double) -> String {
  if quantity.rounded() == quantity {
    return String(Int(quantity))
  }
  return String(format: "%g", quantity)
}

private extension String {
  var nonEmptyGroceryText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  var groceryConsolidationKey: String? {
    let collapsedWhitespace = split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let trimmed = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed.folding(
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
  }
}

private extension Optional where Wrapped == String {
  var groceryConsolidationKey: String? {
    flatMap(\.groceryConsolidationKey)
  }
}
