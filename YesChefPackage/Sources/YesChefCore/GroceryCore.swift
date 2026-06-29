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

public struct GroceryIngredientChoice: Identifiable, Equatable, Sendable {
  public var recipe: Recipe
  public var section: IngredientSection
  public var line: IngredientLine

  public init(recipe: Recipe, section: IngredientSection, line: IngredientLine) {
    self.recipe = recipe
    self.section = section
    self.line = line
  }

  public var id: IngredientLine.ID { line.id }

  public var isAssumedPantryStaple: Bool {
    GroceryPantryAssumptions.isPantryStaple(line)
  }

  public func isAssumedPantryStaple(pantryStaples: [String]) -> Bool {
    GroceryPantryAssumptions.isPantryStaple(line, pantryStaples: pantryStaples)
  }
}

public struct GroceryMenuRecipeItem: Identifiable, Equatable, Sendable {
  public var item: MenuItem
  public var recipe: Recipe

  public init(item: MenuItem, recipe: Recipe) {
    self.item = item
    self.recipe = recipe
  }

  public var id: MenuItem.ID { item.id }
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

public struct PantryItemListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [PantryItem] {
    try PantryItem.fetchAll(db)
      .sorted(by: arePantryItemsInIncreasingOrder)
  }
}

public struct GroceryIngredientChoiceRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [GroceryIngredientChoice] {
    let recipesByID = Dictionary(uniqueKeysWithValues: try Recipe.fetchAll(db).map { ($0.id, $0) })
    let sectionsByID = Dictionary(uniqueKeysWithValues: try IngredientSection.fetchAll(db).map { ($0.id, $0) })

    return try IngredientLine.fetchAll(db)
      .filter(\.isShoppableForGroceries)
      .compactMap { line in
        guard let recipe = recipesByID[line.recipeID],
              let section = sectionsByID[line.sectionID]
        else { return nil }
        return GroceryIngredientChoice(recipe: recipe, section: section, line: line)
      }
      .sorted(by: areGroceryIngredientChoicesInIncreasingOrder)
  }
}

public struct GroceryMenuRecipeItemRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [GroceryMenuRecipeItem] {
    let recipesByID = Dictionary(uniqueKeysWithValues: try Recipe.fetchAll(db).map { ($0.id, $0) })

    return try MenuItem.fetchAll(db)
      .compactMap { item in
        guard item.kind == .recipe,
              let recipeID = item.recipeID,
              let recipe = recipesByID[recipeID]
        else { return nil }
        return GroceryMenuRecipeItem(item: item, recipe: recipe)
      }
      .sorted(by: areGroceryMenuRecipeItemsInIncreasingOrder)
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
      var list = firstList
      list.isDefault = true
      list.dateModified = now
      try GroceryList.upsert { list }.execute(db)
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
    let isFirstList = try GroceryList.fetchCount(db) == 0

    let list = GroceryList(
      id: uuid(),
      title: title,
      sortOrder: try nextListSortOrder(in: db),
      isDefault: isFirstList,
      remindersListName: remindersListName?.nonEmptyGroceryText,
      dateCreated: now,
      dateModified: now
    )
    try GroceryList.insert { list }.execute(db)
    return list.id
  }

  public static func updateList(
    listID: GroceryList.ID,
    title: String,
    remindersListName: String? = nil,
    in db: Database,
    now: Date
  ) throws {
    guard var list = try GroceryList.find(listID).fetchOne(db) else {
      throw GroceryRepositoryError.listNotFound(listID)
    }
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyListTitle
    }

    list.title = title
    list.remindersListName = remindersListName?.nonEmptyGroceryText
    list.dateModified = now
    try GroceryList.upsert { list }.execute(db)
  }

  public static func setDefaultList(
    listID: GroceryList.ID,
    in db: Database,
    now: Date
  ) throws {
    _ = try requireList(listID, in: db)

    for var list in try GroceryList.fetchAll(db) {
      let shouldBeDefault = list.id == listID
      guard list.isDefault != shouldBeDefault else { continue }
      list.isDefault = shouldBeDefault
      list.dateModified = now
      try GroceryList.upsert { list }.execute(db)
    }
  }

  @discardableResult
  public static func deleteList(
    listID: GroceryList.ID,
    in db: Database,
    now: Date
  ) throws -> GroceryList.ID {
    let list = try requireList(listID, in: db)
    let lists = try GroceryList.fetchAll(db).sorted(by: areGroceryListsInIncreasingOrder)
    guard lists.count > 1 else {
      throw GroceryRepositoryError.cannotDeleteOnlyList
    }

    try GroceryList.find(list.id).delete().execute(db)

    let remainingLists = try GroceryList.fetchAll(db).sorted(by: areGroceryListsInIncreasingOrder)
    if let defaultList = remainingLists.first(where: \.isDefault) {
      return defaultList.id
    }

    guard var promotedList = remainingLists.first else {
      throw GroceryRepositoryError.cannotDeleteOnlyList
    }
    promotedList.isDefault = true
    promotedList.dateModified = now
    try GroceryList.upsert { promotedList }.execute(db)
    return promotedList.id
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
  public static func clearPurchasedItems(
    groceryListID: GroceryList.ID,
    in db: Database
  ) throws -> Int {
    _ = try requireList(groceryListID, in: db)
    let items = try GroceryItem
      .where { $0.groceryListID.eq(groceryListID) }
      .fetchAll(db)
      .filter(\.isPurchased)

    for item in items {
      try GroceryItem.find(item.id).delete().execute(db)
    }
    return items.count
  }

  @discardableResult
  public static func clearAllItems(
    groceryListID: GroceryList.ID,
    in db: Database
  ) throws -> Int {
    _ = try requireList(groceryListID, in: db)
    let items = try GroceryItem
      .where { $0.groceryListID.eq(groceryListID) }
      .fetchAll(db)

    for item in items {
      try GroceryItem.find(item.id).delete().execute(db)
    }
    return items.count
  }

  public static func deleteSource(
    sourceID: GroceryItemSource.ID,
    in db: Database,
    now: Date
  ) throws {
    guard let source = try GroceryItemSource.find(sourceID).fetchOne(db) else {
      throw GroceryRepositoryError.sourceNotFound(sourceID)
    }
    guard try GroceryItem.find(source.groceryItemID).fetchOne(db) != nil else {
      throw GroceryRepositoryError.itemNotFound(source.groceryItemID)
    }

    try deleteGroceryItemSources([source], in: db, now: now)
  }

  public static func deleteContribution(
    containingSourceID sourceID: GroceryItemSource.ID,
    in db: Database,
    now: Date
  ) throws {
    guard let source = try GroceryItemSource.find(sourceID).fetchOne(db) else {
      throw GroceryRepositoryError.sourceNotFound(sourceID)
    }
    guard let item = try GroceryItem.find(source.groceryItemID).fetchOne(db) else {
      throw GroceryRepositoryError.itemNotFound(source.groceryItemID)
    }

    let contributionID = source.contributionID
    let itemsByID = Dictionary(uniqueKeysWithValues: try GroceryItem.fetchAll(db).map { ($0.id, $0) })
    let sourcesToDelete = try GroceryItemSource.fetchAll(db)
      .filter { candidate in
        candidate.contributionID == contributionID
          && itemsByID[candidate.groceryItemID]?.groceryListID == item.groceryListID
      }

    try deleteGroceryItemSources(sourcesToDelete, in: db, now: now)
  }

  static func addRecipeIngredients(
    recipe: Recipe,
    groceryListID: GroceryList.ID,
    source: GroceryItemSourceDraft,
    in db: Database,
    now: Date,
    uuid: () -> UUID,
    includedIngredientLineIDs: Set<IngredientLine.ID>? = nil
  ) throws -> [GroceryItem.ID] {
    let sectionsByID = Dictionary(uniqueKeysWithValues: try IngredientSection
      .where { $0.recipeID.eq(recipe.id) }
      .fetchAll(db)
      .map { ($0.id, $0) })
    let lines = try IngredientLine
      .where { $0.recipeID.eq(recipe.id) }
      .fetchAll(db)
      .filter(\.isShoppableForGroceries)
      .filter { line in
        includedIngredientLineIDs?.contains(line.id) ?? true
      }
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

  static func requireList(_ listID: GroceryList.ID, in db: Database) throws -> GroceryList {
    guard let list = try GroceryList.find(listID).fetchOne(db) else {
      throw GroceryRepositoryError.listNotFound(listID)
    }
    return list
  }

  static func requireRecipe(_ recipeID: Recipe.ID, in db: Database) throws -> Recipe {
    guard let recipe = try Recipe.find(recipeID).fetchOne(db) else {
      throw GroceryRepositoryError.recipeNotFound(recipeID)
    }
    return recipe
  }

  static func requireMenu(_ menuID: Menu.ID, in db: Database) throws -> Menu {
    guard let menu = try Menu.find(menuID).fetchOne(db) else {
      throw GroceryRepositoryError.menuNotFound(menuID)
    }
    return menu
  }

  static func requireMenuPlacement(
    _ placementID: MenuPlacement.ID,
    in db: Database
  ) throws -> MenuPlacement {
    guard let placement = try MenuPlacement.find(placementID).fetchOne(db) else {
      throw GroceryRepositoryError.menuPlacementNotFound(placementID)
    }
    return placement
  }

  static func requireMealPlanItem(
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

public enum PantryRepository {
  @discardableResult
  public static func ensureDefaultItems(
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [PantryItem.ID] {
    guard try PantryItem.fetchCount(db) == 0 else { return [] }
    return try addItems(
      GroceryPantryAssumptions.defaultStaples,
      in: db,
      now: now,
      uuid: uuid
    )
  }

  @discardableResult
  public static func replaceItems(
    titles: [String],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [PantryItem.ID] {
    try PantryItem.delete().execute(db)
    return try addItems(titles, in: db, now: now, uuid: uuid)
  }

  @discardableResult
  public static func resetToDefaults(
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [PantryItem.ID] {
    try replaceItems(
      titles: GroceryPantryAssumptions.defaultStaples,
      in: db,
      now: now,
      uuid: uuid
    )
  }

  @discardableResult
  public static func addItem(
    title: String,
    notes: String? = nil,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> PantryItem.ID {
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyPantryItemTitle
    }

    if var existingItem = try pantryItem(matching: title, in: db) {
      let notes = notes?.nonEmptyGroceryText
      if let notes, existingItem.notes != notes {
        existingItem.notes = notes
        existingItem.dateModified = now
        try PantryItem.upsert { existingItem }.execute(db)
      }
      return existingItem.id
    }

    let item = PantryItem(
      id: uuid(),
      title: title,
      notes: notes?.nonEmptyGroceryText,
      sortOrder: try nextPantrySortOrder(in: db),
      dateCreated: now,
      dateModified: now
    )
    try PantryItem.insert { item }.execute(db)
    return item.id
  }

  public static func updateItem(
    itemID: PantryItem.ID,
    title: String,
    notes: String? = nil,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try PantryItem.find(itemID).fetchOne(db) else {
      throw GroceryRepositoryError.pantryItemNotFound(itemID)
    }
    guard let title = title.nonEmptyGroceryText else {
      throw GroceryRepositoryError.emptyPantryItemTitle
    }

    if let existingItem = try pantryItem(matching: title, in: db),
       existingItem.id != itemID {
      try PantryItem.find(itemID).delete().execute(db)
      return
    }

    item.title = title
    item.notes = notes?.nonEmptyGroceryText
    item.dateModified = now
    try PantryItem.upsert { item }.execute(db)
  }

  public static func deleteItem(
    itemID: PantryItem.ID,
    in db: Database
  ) throws {
    guard try PantryItem.find(itemID).fetchOne(db) != nil else {
      throw GroceryRepositoryError.pantryItemNotFound(itemID)
    }
    try PantryItem.find(itemID).delete().execute(db)
  }

  @discardableResult
  private static func addItems(
    _ titles: [String],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [PantryItem.ID] {
    var itemIDs: [PantryItem.ID] = []
    for title in uniquePantryTitles(titles) {
      itemIDs.append(
        try addItem(
          title: title,
          in: db,
          now: now,
          uuid: uuid
        )
      )
    }
    return itemIDs
  }

  private static func pantryItem(
    matching title: String,
    in db: Database
  ) throws -> PantryItem? {
    let key = title.groceryConsolidationKey
    return try PantryItem.fetchAll(db)
      .first { $0.title.groceryConsolidationKey == key }
  }

  private static func nextPantrySortOrder(in db: Database) throws -> Int {
    (try PantryItem.fetchAll(db).map(\.sortOrder).max() ?? -1) + 1
  }

  private static func uniquePantryTitles(_ titles: [String]) -> [String] {
    var seen: Set<String> = []
    var uniqueTitles: [String] = []
    for title in titles {
      guard let title = title.nonEmptyGroceryText,
            let key = title.groceryConsolidationKey,
            !seen.contains(key)
      else { continue }
      seen.insert(key)
      uniqueTitles.append(title)
    }
    return uniqueTitles
  }
}

public enum GroceryRepositoryError: Error, Equatable, Sendable {
  case cannotDeleteOnlyList
  case emptyItemTitle
  case emptyListTitle
  case emptyPantryItemTitle
  case itemNotFound(GroceryItem.ID)
  case listNotFound(GroceryList.ID)
  case mealPlanItemHasNoRecipe(MealPlanItem.ID)
  case mealPlanItemNotFound(MealPlanItem.ID)
  case menuNotFound(Menu.ID)
  case menuPlacementNotFound(MenuPlacement.ID)
  case noShoppableIngredients
  case pantryItemNotFound(PantryItem.ID)
  case recipeNotFound(Recipe.ID)
  case sourceNotFound(GroceryItemSource.ID)
}

private func deleteGroceryItemSources(
  _ sources: [GroceryItemSource],
  in db: Database,
  now: Date
) throws {
  for source in sources {
    try GroceryItemSource.find(source.id).delete().execute(db)
  }

  for itemID in Set(sources.map(\.groceryItemID)) {
    guard var item = try GroceryItem.find(itemID).fetchOne(db) else { continue }
    let remainingSources = try GroceryItemSource
      .where { $0.groceryItemID.eq(item.id) }
      .fetchAll(db)
      .sorted(by: areGroceryItemSourcesInIncreasingOrder)

    guard !remainingSources.isEmpty else {
      try GroceryItem.find(item.id).delete().execute(db)
      continue
    }

    if let recalculatedQuantity = try generatedQuantity(for: remainingSources, in: db) {
      item.quantity = recalculatedQuantity
      item.quantityText = formatGroceryQuantity(recalculatedQuantity)
    }
    item.dateModified = now
    try GroceryItem.upsert { item }.execute(db)
  }
}

struct GroceryItemSourceDraft {
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

private func arePantryItemsInIncreasingOrder(_ lhs: PantryItem, _ rhs: PantryItem) -> Bool {
  let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func areGroceryIngredientChoicesInIncreasingOrder(
  _ lhs: GroceryIngredientChoice,
  _ rhs: GroceryIngredientChoice
) -> Bool {
  let recipeComparison = lhs.recipe.title.localizedStandardCompare(rhs.recipe.title)
  if recipeComparison != .orderedSame {
    return recipeComparison == .orderedAscending
  }
  if lhs.section.sortOrder != rhs.section.sortOrder {
    return lhs.section.sortOrder < rhs.section.sortOrder
  }
  if lhs.line.sortOrder != rhs.line.sortOrder {
    return lhs.line.sortOrder < rhs.line.sortOrder
  }
  return lhs.line.id.uuidString < rhs.line.id.uuidString
}

private func areGroceryMenuRecipeItemsInIncreasingOrder(
  _ lhs: GroceryMenuRecipeItem,
  _ rhs: GroceryMenuRecipeItem
) -> Bool {
  if lhs.item.menuID != rhs.item.menuID {
    return lhs.item.menuID.uuidString < rhs.item.menuID.uuidString
  }
  if lhs.item.dayOffset != rhs.item.dayOffset {
    return lhs.item.dayOffset < rhs.item.dayOffset
  }
  if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
    return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  return lhs.recipe.title.localizedStandardCompare(rhs.recipe.title) == .orderedAscending
}

func areMenuItemsInIncreasingOrder(_ lhs: MenuItem, _ rhs: MenuItem) -> Bool {
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

public extension IngredientLine {
  var isShoppableForGroceries: Bool {
    !doNotShop && !isHeader && !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private extension IngredientLine {
  var groceryItemTitle: String {
    canonicalGroceryItemTitle(item?.nonEmptyGroceryText ?? originalText)
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

private func canonicalGroceryItemTitle(_ title: String) -> String {
  switch title.groceryConsolidationKey {
  case "anchovy fillet", "anchovy fillets", "anchovy filet", "anchovy filets":
    return "anchovies"
  default:
    return title
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

private func generatedQuantity(
  for sources: [GroceryItemSource],
  in db: Database
) throws -> Double? {
  var quantity: Double?
  for source in sources {
    guard let lineID = source.ingredientLineID,
          let line = try IngredientLine.find(lineID).fetchOne(db),
          let lineQuantity = line.quantity
    else {
      return nil
    }
    quantity = (quantity ?? 0) + lineQuantity
  }
  return quantity
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
