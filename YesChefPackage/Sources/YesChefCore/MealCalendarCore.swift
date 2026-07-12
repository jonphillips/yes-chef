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
  public var recipeIngredientLines: [String]
  public var source: RecipeSource?
  public var thumbnailData: Data?
  public var menu: Menu?
  public var menuPlacement: MenuPlacement?
  public var menuItem: MenuItem?

  public init(
    item: MealPlanItem,
    recipe: Recipe? = nil,
    recipeIngredientLines: [String] = [],
    source: RecipeSource? = nil,
    thumbnailData: Data? = nil,
    menu: Menu? = nil,
    menuPlacement: MenuPlacement? = nil,
    menuItem: MenuItem? = nil
  ) {
    self.item = item
    self.recipe = recipe
    self.recipeIngredientLines = recipeIngredientLines
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

/// Per-(day, meal slot) explicit ordering overlay for the day agenda.
///
/// Rows in a slot come from two sources — manual `MealPlanItem`s and menu-projected
/// rows synthesized from `MenuItem`/`MenuPlacement`. Menu rows are fixed anchors whose
/// order lives on the underlying menu, so we cannot renumber them to interleave a manual
/// item between them. Instead the day view stores its own order over *all* of a slot's
/// rows here (identified by `MealPlanItemRowID.rawValue`), overlaying projection without
/// ever mutating the menu. Rows absent from `orderedKeys` fall back to the natural
/// comparator order, so newly added or stale rows degrade gracefully.
@Table("mealPlanDayOrders")
public struct MealPlanDayOrder: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var scheduledDate: Date
  public var mealSlot: MealPlanItemSlot
  /// JSON-encoded `[String]` of `MealPlanItemRowID.rawValue`, in display order.
  public var orderedKeys: Data
  public var dateModified: Date

  public init(
    id: UUID,
    scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    orderedKeys: Data,
    dateModified: Date
  ) {
    self.id = id
    self.scheduledDate = scheduledDate
    self.mealSlot = mealSlot
    self.orderedKeys = orderedKeys
    self.dateModified = dateModified
  }
}

extension MealPlanDayOrder {
  public var rowKeys: [String] {
    (try? JSONDecoder().decode([String].self, from: orderedKeys)) ?? []
  }

  public static func encodeKeys(_ keys: [String]) -> Data {
    (try? JSONEncoder().encode(keys)) ?? Data("[]".utf8)
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
    let recipeIDs = Set(recipesByID.keys)
    let ingredientLinesByRecipeID = Dictionary(
      grouping: try IngredientLine.fetchAll(db)
        .filter { recipeIDs.contains($0.recipeID) },
      by: \.recipeID
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
          recipeIngredientLines: recipe.map { recipe in
            (ingredientLinesByRecipeID[recipe.id] ?? [])
              .sorted { $0.sortOrder < $1.sortOrder }
              .map(\.originalText)
          } ?? [],
          source: recipe.map { sourcesByRecipeID[$0.id]?.first } ?? nil,
          thumbnailData: recipe.flatMap { thumbnailsByRecipeID[$0.id]?.listImageData }
        )
      }

    let menuRows = try projectedMenuRows(
      db,
      recipesByID: recipesByID,
      ingredientLinesByRecipeID: ingredientLinesByRecipeID,
      sourcesByRecipeID: sourcesByRecipeID,
      thumbnailsByRecipeID: thumbnailsByRecipeID
    )

    let sorted = (manualRows + menuRows)
      .sorted(by: areMealPlanRowsInIncreasingOrder)
    let dayOrders = try MealPlanDayOrder.fetchAll(db)
    return MealPlanDayOrderApplier.apply(dayOrders, to: sorted)
  }

  private func projectedMenuRows(
    _ db: Database,
    recipesByID: [Recipe.ID: Recipe],
    ingredientLinesByRecipeID: [Recipe.ID: [IngredientLine]],
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
          dateModified: menuItem.dateModified,
          scale: menuItem.scale
        )
        let recipe = menuItem.recipeID.flatMap { recipesByID[$0] }
        if menuItem.kind == .recipe && menuItem.recipeID != nil && recipe == nil {
          return nil
        }
        return MealPlanItemRowData(
          item: item,
          recipe: recipe,
          recipeIngredientLines: recipe.map { recipe in
            (ingredientLinesByRecipeID[recipe.id] ?? [])
              .sorted { $0.sortOrder < $1.sortOrder }
              .map(\.originalText)
          } ?? [],
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

/// Applies `MealPlanDayOrder` overlays to a comparator-sorted row list.
///
/// Input rows must already be sorted by the natural comparator. An overlay both orders
/// rows within its meal slot and, when a row originated in another slot, projects it into
/// the destination slot for this placed day without mutating the underlying menu.
enum MealPlanDayOrderApplier {
  struct Key: Hashable {
    var date: Date
    var slot: MealPlanItemSlot
  }

  static func apply(
    _ orders: [MealPlanDayOrder],
    to rows: [MealPlanItemRowData]
  ) -> [MealPlanItemRowData] {
    guard !orders.isEmpty else { return rows }

    // On the rare duplicate overlay for one slot (concurrent devices), the most recently
    // modified record wins.
    let latestByKey = Dictionary(
      orders.map { (Key(date: $0.scheduledDate, slot: $0.mealSlot), $0) },
      uniquingKeysWith: { $0.dateModified >= $1.dateModified ? $0 : $1 }
    )
    let positionsByKey: [Key: [String: Int]] = latestByKey.mapValues { order in
      Dictionary(uniqueKeysWithValues: order.rowKeys.enumerated().map { ($0.element, $0.offset) })
    }
    guard !positionsByKey.isEmpty else { return rows }

    var assignedSlotByDayAndRowKey: [Date: [String: MealPlanItemSlot]] = [:]
    for (key, order) in latestByKey {
      for rowKey in order.rowKeys {
        assignedSlotByDayAndRowKey[key.date, default: [:]][rowKey] = key.slot
      }
    }

    let projected = rows.enumerated().map { offset, originalRow in
      var row = originalRow
      if let assignedSlot = assignedSlotByDayAndRowKey[row.item.scheduledDate]?[row.id.rawValue] {
        row.item.mealSlot = assignedSlot
      }
      return (offset: offset, row: row)
    }

    return projected.sorted { lhs, rhs in
      if lhs.row.item.scheduledDate != rhs.row.item.scheduledDate {
        return lhs.row.item.scheduledDate < rhs.row.item.scheduledDate
      }
      if lhs.row.item.mealSlot.sortOrder != rhs.row.item.mealSlot.sortOrder {
        return lhs.row.item.mealSlot.sortOrder < rhs.row.item.mealSlot.sortOrder
      }

      let key = Key(date: lhs.row.item.scheduledDate, slot: lhs.row.item.mealSlot)
      let positions = positionsByKey[key] ?? [:]
      switch (positions[lhs.row.id.rawValue], positions[rhs.row.id.rawValue]) {
      case let (left?, right?):
        return left < right
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return lhs.offset < rhs.offset
      }
    }
    .map(\.row)
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

  @discardableResult
  public static func addComplementItem(
    _ suggestion: MealPlanComplementSuggestion,
    on scheduledDate: Date,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MealPlanItem.ID {
    guard let title = suggestion.title.nonEmptyMealCalendarText else {
      throw MealCalendarRepositoryError.emptyTitle
    }

    let item = MealPlanItem(
      id: uuid(),
      kind: .note,
      title: title,
      scheduledDate: scheduledDate,
      mealSlot: suggestion.mealSlot,
      notes: nil,
      sortOrder: try nextSortOrder(on: scheduledDate, mealSlot: suggestion.mealSlot, in: db),
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

  /// Persists the explicit display order for one (day, meal slot) as a `MealPlanDayOrder`
  /// overlay. `orderedRowKeys` are `MealPlanItemRowID.rawValue` strings in display order,
  /// covering both manual and menu-projected rows. The underlying menu is never touched.
  public static func setDayOrder(
    orderedRowKeys: [String],
    on scheduledDate: Date,
    mealSlot: MealPlanItemSlot,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    let existing = try MealPlanDayOrder
      .where { $0.scheduledDate.eq(scheduledDate) && $0.mealSlot.eq(mealSlot) }
      .order { $0.dateModified.desc() }
      .fetchAll(db)

    let record = MealPlanDayOrder(
      id: existing.first?.id ?? uuid(),
      scheduledDate: scheduledDate,
      mealSlot: mealSlot,
      orderedKeys: MealPlanDayOrder.encodeKeys(orderedRowKeys),
      dateModified: now
    )
    try MealPlanDayOrder.upsert { record }.execute(db)

    // Collapse any duplicate overlays a prior concurrent write may have left behind.
    for stale in existing.dropFirst() where stale.id != record.id {
      try MealPlanDayOrder.find(stale.id).delete().execute(db)
    }
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
  case emptyMakeAheadStrategy
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
