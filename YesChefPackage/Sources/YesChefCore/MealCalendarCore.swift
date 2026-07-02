import Foundation
import SQLiteData

public struct MealPlanItemRowID: Hashable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static func manual(_ itemID: MealPlanItem.ID) -> Self {
    Self(rawValue: "meal:\(itemID.uuidString)")
  }

  public static func menu(placementID: MenuPlacement.ID, itemID: MenuItem.ID) -> Self {
    Self(rawValue: "menu:\(placementID.uuidString):\(itemID.uuidString)")
  }

  public var description: String { rawValue }
}

public struct MealPlanItemRowData: Identifiable, Equatable, Sendable {
  public var item: MealPlanItem
  public var recipe: Recipe?
  public var source: RecipeSource?
  public var thumbnailData: Data?
  public var menu: Menu?
  public var menuPlacement: MenuPlacement?
  public var menuItem: MenuItem?

  public init(
    item: MealPlanItem,
    recipe: Recipe? = nil,
    source: RecipeSource? = nil,
    thumbnailData: Data? = nil,
    menu: Menu? = nil,
    menuPlacement: MenuPlacement? = nil,
    menuItem: MenuItem? = nil
  ) {
    self.item = item
    self.recipe = recipe
    self.source = source
    self.thumbnailData = thumbnailData
    self.menu = menu
    self.menuPlacement = menuPlacement
    self.menuItem = menuItem
  }

  public var id: MealPlanItemRowID {
    if let menuPlacement, let menuItem {
      return .menu(placementID: menuPlacement.id, itemID: menuItem.id)
    }
    return .manual(item.id)
  }

  public var isFromMenu: Bool {
    menuPlacement != nil
  }

  public var displayTitle: String {
    recipe?.title ?? item.title
  }

  public var displayNotes: String? {
    item.notes
  }
}

public struct MealCalendarRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [MealPlanItemRowData] {
    let recipesByID = Dictionary(
      uniqueKeysWithValues: try Recipe.fetchAll(db)
        .filter { !$0.archived }
        .map { ($0.id, $0) }
    )
    let sourcesByRecipeID = Dictionary(grouping: try RecipeSource.fetchAll(db), by: \.recipeID)
    let photoRows = try RecipePhoto
      .select {
        MealCalendarPhotoRow.Columns(
          recipeID: $0.recipeID,
          displayData: $0.displayData,
          thumbnailData: $0.thumbnailData,
          pixelWidth: $0.pixelWidth,
          pixelHeight: $0.pixelHeight,
          kind: $0.kind,
          sortOrder: $0.sortOrder
        )
      }
      .fetchAll(db)

    var thumbnailsByRecipeID: [Recipe.ID: MealCalendarPhotoRow] = [:]
    for row in photoRows where row.kind != .referenceDocument && row.listImageData != nil {
      guard let existingRow = thumbnailsByRecipeID[row.recipeID] else {
        thumbnailsByRecipeID[row.recipeID] = row
        continue
      }
      if row.listSortKey < existingRow.listSortKey {
        thumbnailsByRecipeID[row.recipeID] = row
      }
    }

    let manualRows: [MealPlanItemRowData] = try MealPlanItem.fetchAll(db)
      .compactMap { item -> MealPlanItemRowData? in
        let recipe = item.recipeID.flatMap { recipesByID[$0] }
        if item.kind == .recipe && item.recipeID != nil && recipe == nil {
          return nil
        }
        return MealPlanItemRowData(
          item: item,
          recipe: recipe,
          source: recipe.map { sourcesByRecipeID[$0.id]?.first } ?? nil,
          thumbnailData: recipe.flatMap { thumbnailsByRecipeID[$0.id]?.listImageData }
        )
      }

    let menuRows = try projectedMenuRows(
      db,
      recipesByID: recipesByID,
      sourcesByRecipeID: sourcesByRecipeID,
      thumbnailsByRecipeID: thumbnailsByRecipeID
    )

    return (manualRows + menuRows)
      .sorted(by: areMealPlanRowsInIncreasingOrder)
  }

  private func projectedMenuRows(
    _ db: Database,
    recipesByID: [Recipe.ID: Recipe],
    sourcesByRecipeID: [Recipe.ID: [RecipeSource]],
    thumbnailsByRecipeID: [Recipe.ID: MealCalendarPhotoRow]
  ) throws -> [MealPlanItemRowData] {
    let calendar = Calendar(identifier: .gregorian)
    let menusByID = Dictionary(uniqueKeysWithValues: try Menu.fetchAll(db).map { ($0.id, $0) })
    let itemsByMenuID = Dictionary(grouping: try MenuItem.fetchAll(db), by: \.menuID)

    return try MenuPlacement.fetchAll(db).flatMap { placement -> [MealPlanItemRowData] in
      guard let menu = menusByID[placement.menuID] else { return [] }
      return (itemsByMenuID[placement.menuID] ?? []).compactMap { menuItem in
        guard
          let scheduledDate = calendar.date(
            byAdding: .day,
            value: menuItem.dayOffset,
            to: placement.startDate
          )
        else { return nil }

        let item = MealPlanItem(
          id: menuItem.id,
          kind: menuItem.kind,
          recipeID: menuItem.recipeID,
          title: menuItem.title,
          scheduledDate: scheduledDate,
          mealSlot: menuItem.mealSlot,
          notes: menuItem.notes,
          sortOrder: menuItem.sortOrder,
          dateCreated: menuItem.dateCreated,
          dateModified: menuItem.dateModified
        )
        let recipe = menuItem.recipeID.flatMap { recipesByID[$0] }
        if menuItem.kind == .recipe && menuItem.recipeID != nil && recipe == nil {
          return nil
        }
        return MealPlanItemRowData(
          item: item,
          recipe: recipe,
          source: recipe.map { sourcesByRecipeID[$0.id]?.first } ?? nil,
          thumbnailData: recipe.flatMap { thumbnailsByRecipeID[$0.id]?.listImageData },
          menu: menu,
          menuPlacement: placement,
          menuItem: menuItem
        )
      }
    }
  }
}

public enum MealCalendarRepository {
  @discardableResult
  public static func addRecipeItem(
    recipeID: Recipe.ID,
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    notes: String?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MealPlanItem.ID {
    guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
      throw MealCalendarRepositoryError.recipeNotFound(recipeID)
    }

    let item = MealPlanItem(
      id: uuid(),
      kind: .recipe,
      recipeID: recipeID,
      title: recipe.title,
      scheduledDate: scheduledDate,
      mealSlot: mealSlot,
      notes: notes?.nonEmptyMealCalendarText,
      sortOrder: try nextSortOrder(on: scheduledDate, mealSlot: mealSlot, in: db),
      dateCreated: now,
      dateModified: now
    )
    try MealPlanItem.insert { item }.execute(db)
    return item.id
  }

  @discardableResult
  public static func addRecipeItems(
    recipeIDs: [Recipe.ID],
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    notes: String?,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [MealPlanItem.ID] {
    var itemIDs: [MealPlanItem.ID] = []
    for recipeID in recipeIDs {
      let itemID = try addRecipeItem(
        recipeID: recipeID,
        on: scheduledDate,
        mealSlot: mealSlot,
        notes: notes,
        in: db,
        now: now,
        uuid: uuid
      )
      itemIDs.append(itemID)
    }
    return itemIDs
  }

  @discardableResult
  public static func addNoteItem(
    title: String,
    notes: String?,
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MealPlanItem.ID {
    guard let title = title.nonEmptyMealCalendarText else {
      throw MealCalendarRepositoryError.emptyTitle
    }

    let item = MealPlanItem(
      id: uuid(),
      kind: .note,
      title: title,
      scheduledDate: scheduledDate,
      mealSlot: mealSlot,
      notes: notes?.nonEmptyMealCalendarText,
      sortOrder: try nextSortOrder(on: scheduledDate, mealSlot: mealSlot, in: db),
      dateCreated: now,
      dateModified: now
    )
    try MealPlanItem.insert { item }.execute(db)
    return item.id
  }

  public static func updateRecipeItem(
    itemID: MealPlanItem.ID,
    recipeID: Recipe.ID,
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    notes: String?,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MealPlanItem.find(itemID).fetchOne(db) else {
      throw MealCalendarRepositoryError.itemNotFound(itemID)
    }
    guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
      throw MealCalendarRepositoryError.recipeNotFound(recipeID)
    }

    let isMoving = item.scheduledDate != scheduledDate || item.mealSlot != mealSlot
    item.kind = .recipe
    item.recipeID = recipeID
    item.title = recipe.title
    item.scheduledDate = scheduledDate
    item.mealSlot = mealSlot
    item.notes = notes?.nonEmptyMealCalendarText
    item.sortOrder = isMoving ? try nextSortOrder(on: scheduledDate, mealSlot: mealSlot, in: db) : item.sortOrder
    item.dateModified = now
    try MealPlanItem.upsert { item }.execute(db)
  }

  public static func updateNoteItem(
    itemID: MealPlanItem.ID,
    title: String,
    notes: String?,
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    in db: Database,
    now: Date
  ) throws {
    guard var item = try MealPlanItem.find(itemID).fetchOne(db) else {
      throw MealCalendarRepositoryError.itemNotFound(itemID)
    }
    guard let title = title.nonEmptyMealCalendarText else {
      throw MealCalendarRepositoryError.emptyTitle
    }

    let isMoving = item.scheduledDate != scheduledDate || item.mealSlot != mealSlot
    item.kind = .note
    item.recipeID = nil
    item.title = title
    item.scheduledDate = scheduledDate
    item.mealSlot = mealSlot
    item.notes = notes?.nonEmptyMealCalendarText
    item.sortOrder = isMoving ? try nextSortOrder(on: scheduledDate, mealSlot: mealSlot, in: db) : item.sortOrder
    item.dateModified = now
    try MealPlanItem.upsert { item }.execute(db)
  }

  public static func deleteItem(
    itemID: MealPlanItem.ID,
    in db: Database
  ) throws {
    try MealPlanItem.find(itemID).delete().execute(db)
  }

  private static func nextSortOrder(
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    in db: Database
  ) throws -> Int {
    let items = try MealPlanItem
      .where {
        $0.scheduledDate.eq(scheduledDate)
          && $0.mealSlot.eq(mealSlot)
      }
      .fetchAll(db)
    return (items.map(\.sortOrder).max() ?? -1) + 1
  }
}

public enum MealCalendarRepositoryError: Error, Equatable, Sendable {
  case emptyTitle
  case itemNotFound(MealPlanItem.ID)
  case recipeNotFound(Recipe.ID)
}

@Selection
private struct MealCalendarPhotoRow: Equatable, Sendable {
  let recipeID: Recipe.ID
  let displayData: Data?
  let thumbnailData: Data?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let kind: RecipePhotoKind
  let sortOrder: Int

  var listImageData: Data? {
    thumbnailData ?? displayData
  }

  var listSortKey: MealCalendarPhotoSortKey {
    MealCalendarPhotoSortKey(
      isLowResolution: Swift.max(pixelWidth ?? 0, pixelHeight ?? 0) < 700,
      kindRank: kind == .hero ? 0 : 1,
      sortOrder: sortOrder
    )
  }
}

private struct MealCalendarPhotoSortKey: Comparable {
  var isLowResolution: Bool
  var kindRank: Int
  var sortOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.isLowResolution != rhs.isLowResolution {
      return !lhs.isLowResolution
    }
    if lhs.kindRank != rhs.kindRank {
      return lhs.kindRank < rhs.kindRank
    }
    return lhs.sortOrder < rhs.sortOrder
  }
}

private func areMealPlanRowsInIncreasingOrder(
  _ lhs: MealPlanItemRowData,
  _ rhs: MealPlanItemRowData
) -> Bool {
  if lhs.item.scheduledDate != rhs.item.scheduledDate {
    return lhs.item.scheduledDate < rhs.item.scheduledDate
  }
  if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
    return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  if lhs.isFromMenu != rhs.isFromMenu {
    return !lhs.isFromMenu
  }
  let titleComparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.id.rawValue < rhs.id.rawValue
}

private extension String {
  var nonEmptyMealCalendarText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
