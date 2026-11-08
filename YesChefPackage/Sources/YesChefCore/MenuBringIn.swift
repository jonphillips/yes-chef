import Foundation
import SQLiteData

private struct MenuPlacementItemKey: Hashable {
  var placementID: MenuPlacement.ID
  var itemID: MenuItem.ID
}

extension MenuRepository {
  public static func bringInOffer(menuID: Menu.ID, in db: Database) throws -> MenuBringInOffer? {
    guard let targetMenu = try Menu.find(menuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(menuID)
    }
    let placements = try MenuPlacement.where { $0.menuID.eq(menuID) }.fetchAll(db)
    guard placements.count == 1, let targetPlacement = placements.first else { return nil }
    guard let rangeEnd = MenuPlacementDay.date(for: targetMenu.dayCount - 1, from: targetPlacement) else {
      return nil
    }
    let calendar = Calendar(identifier: .gregorian)
    let rangeStartDay = calendar.startOfDay(for: targetPlacement.startDate)
    let rangeEndDay = calendar.startOfDay(for: rangeEnd)
    let looseItems = try MealPlanItem.fetchAll(db).filter { item in
      let day = calendar.startOfDay(for: item.scheduledDate)
      return day >= rangeStartDay && day <= rangeEndDay
    }
    let menusByID = Dictionary(uniqueKeysWithValues: try Menu.fetchAll(db).map { ($0.id, $0) })
    let itemsByMenuID = Dictionary(grouping: try MenuItem.fetchAll(db), by: \.menuID)
    let stepsByMenuID = Dictionary(grouping: try PrepPlanStepRecord.fetchAll(db), by: \.menuID)
    var contained: [MenuBringInContainedPlacement] = []
    var partial: [String] = []
    for placement in try MenuPlacement.fetchAll(db) where placement.menuID != menuID {
      guard let menu = menusByID[placement.menuID],
        let otherEnd = MenuPlacementDay.date(for: menu.dayCount - 1, from: placement)
      else { continue }
      let otherStartDay = calendar.startOfDay(for: placement.startDate)
      let otherEndDay = calendar.startOfDay(for: otherEnd)
      guard otherStartDay <= rangeEndDay && otherEndDay >= rangeStartDay else { continue }
      if otherStartDay >= rangeStartDay && otherEndDay <= rangeEndDay {
        let dishes = itemsByMenuID[menu.id] ?? []
        let steps = stepsByMenuID[menu.id] ?? []
        if !dishes.isEmpty || !steps.isEmpty {
          contained.append(MenuBringInContainedPlacement(
            menuID: menu.id,
            title: menu.title,
            dishCount: dishes.count,
            prepStepCount: steps.count
          ))
        }
      } else {
        partial.append(menu.title)
      }
    }
    guard !looseItems.isEmpty || !contained.isEmpty else { return nil }
    return MenuBringInOffer(
      looseCalendarItemCount: looseItems.count,
      containedPlacements: contained.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
      partiallyOverlappingMenuTitles: partial.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    )
  }

  public static func bringIn(
    menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuBringInResult {
    guard let targetMenu = try Menu.find(menuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(menuID)
    }
    let targetPlacements = try MenuPlacement.where { $0.menuID.eq(menuID) }.fetchAll(db)
    guard targetPlacements.count == 1, let targetPlacement = targetPlacements.first else {
      throw MenuRepositoryError.menuMustHaveOnePlacement
    }
    guard let rangeEnd = MenuPlacementDay.date(for: targetMenu.dayCount - 1, from: targetPlacement) else {
      return MenuBringInResult(movedCalendarItemCount: 0, copiedPlacementCount: 0)
    }
    let calendar = Calendar(identifier: .gregorian)
    let startDay = calendar.startOfDay(for: targetPlacement.startDate)
    let endDay = calendar.startOfDay(for: rangeEnd)
    let sourceCalendarItems = try MealPlanItem.fetchAll(db)
      .filter { item in
        let day = calendar.startOfDay(for: item.scheduledDate)
        return day >= startDay && day <= endDay
      }
      .sorted {
        if $0.scheduledDate != $1.scheduledDate { return $0.scheduledDate < $1.scheduledDate }
        if $0.mealSlot.sortOrder != $1.mealSlot.sortOrder { return $0.mealSlot.sortOrder < $1.mealSlot.sortOrder }
        if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
        return $0.id.uuidString < $1.id.uuidString
      }

    var newItemIDsByCalendarItemID: [MealPlanItem.ID: MenuItem.ID] = [:]
    var newItemIDsByPlacementItem: [MenuPlacementItemKey: MenuItem.ID] = [:]
    var deletedPlacementIDs: Set<MenuPlacement.ID> = []
    for source in sourceCalendarItems {
      guard let dayOffset = MenuPlacementDay.offset(of: source.scheduledDate, from: targetPlacement) else { continue }
      let kind: MealPlanItemKind = source.kind == .recipe && source.recipeID == nil ? .note : source.kind
      let item = MenuItem(
        id: uuid(), menuID: menuID, kind: kind, recipeID: kind == .recipe ? source.recipeID : nil,
        title: source.title, dayOffset: dayOffset, mealSlot: source.mealSlot, notes: source.notes,
        sortOrder: try nextSortOrder(menuID: menuID, dayOffset: dayOffset, mealSlot: source.mealSlot, in: db),
        dateCreated: source.dateCreated, dateModified: now, scale: source.scale
      )
      try MenuItem.insert { item }.execute(db)
      newItemIDsByCalendarItemID[source.id] = item.id
    }

    let menusByID = Dictionary(uniqueKeysWithValues: try Menu.fetchAll(db).map { ($0.id, $0) })
    let allItems = try MenuItem.fetchAll(db)
    let allSteps = try PrepPlanStepRecord.fetchAll(db)
    let containedPlacements = try MenuPlacement.fetchAll(db).filter { placement in
      guard placement.menuID != menuID, let menu = menusByID[placement.menuID],
        let otherEnd = MenuPlacementDay.date(for: menu.dayCount - 1, from: placement)
      else { return false }
      let otherStartDay = calendar.startOfDay(for: placement.startDate)
      let otherEndDay = calendar.startOfDay(for: otherEnd)
      return otherStartDay >= startDay && otherEndDay <= endDay
        && (allItems.contains { $0.menuID == menu.id } || allSteps.contains { $0.menuID == menu.id })
    }
    for sourcePlacement in containedPlacements {
      let sourceMenuID = sourcePlacement.menuID
      var copiedItemIDs: [MenuItem.ID: MenuItem.ID] = [:]
      let shift = MenuPlacementDay.offset(of: sourcePlacement.startDate, from: targetPlacement) ?? 0
      let sourceItems = allItems.filter { $0.menuID == sourceMenuID }
        .sorted { lhs, rhs in
          if lhs.dayOffset != rhs.dayOffset { return lhs.dayOffset < rhs.dayOffset }
          if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder { return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder }
          if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
          return lhs.id.uuidString < rhs.id.uuidString
        }
      for source in sourceItems {
        let item = MenuItem(
          id: uuid(), menuID: menuID, kind: source.kind, recipeID: source.recipeID, title: source.title,
          dayOffset: source.dayOffset + shift, mealSlot: source.mealSlot, notes: source.notes,
          sortOrder: try nextSortOrder(menuID: menuID, dayOffset: source.dayOffset + shift, mealSlot: source.mealSlot, in: db),
          dateCreated: source.dateCreated, dateModified: now, scale: source.scale
        )
        try MenuItem.insert { item }.execute(db)
        copiedItemIDs[source.id] = item.id
        newItemIDsByPlacementItem[MenuPlacementItemKey(placementID: sourcePlacement.id, itemID: source.id)] = item.id
      }
      let sourceSteps = allSteps.filter { $0.menuID == sourceMenuID }.sorted { $0.sortOrder < $1.sortOrder }
      var nextStepOrder = (try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.sortOrder).max() ?? -1) + 1
      for source in sourceSteps {
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: uuid(), menuID: menuID, sortOrder: nextStepOrder, session: source.session,
            task: source.task, serves: source.serves,
            sourceDish: source.sourceDish.flatMap { copiedItemIDs[$0] }
          )
        }.execute(db)
        nextStepOrder += 1
      }
      deletedPlacementIDs.insert(sourcePlacement.id)
    }

    for source in try GroceryItemSource.fetchAll(db) {
      let movedMenuItemID = source.mealPlanItemID.flatMap { newItemIDsByCalendarItemID[$0] }
      let copiedMenuItemID = source.menuPlacementID.flatMap { placementID in
        source.menuItemID.flatMap { itemID in
          newItemIDsByPlacementItem[MenuPlacementItemKey(placementID: placementID, itemID: itemID)]
        }
      }
      guard let newMenuItemID = movedMenuItemID ?? copiedMenuItemID,
        (movedMenuItemID != nil || source.menuPlacementID.map(deletedPlacementIDs.contains) == true)
      else { continue }
      var updated = source
      updated.origin = .menuPlacement
      updated.menuID = menuID
      updated.menuItemID = newMenuItemID
      updated.menuPlacementID = targetPlacement.id
      updated.mealPlanItemID = nil
      try GroceryItemSource.upsert { updated }.execute(db)
    }
    for item in sourceCalendarItems {
      try MealPlanItem.find(item.id).delete().execute(db)
    }
    for placementID in deletedPlacementIDs {
      try MenuPlacement.find(placementID).delete().execute(db)
    }
    return MenuBringInResult(
      movedCalendarItemCount: sourceCalendarItems.count,
      copiedPlacementCount: deletedPlacementIDs.count
    )
  }

}
