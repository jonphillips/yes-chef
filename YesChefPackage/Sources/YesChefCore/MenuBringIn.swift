import Foundation
import SQLiteData

struct MenuBringInContainedCandidate {
  var placement: MenuPlacement
  var menu: Menu
  var items: [MenuItem]
  var prepSteps: [PrepPlanStepRecord]
}

struct MenuBringInCandidates {
  var targetMenu: Menu
  var targetPlacement: MenuPlacement
  var rangeStartDay: Date
  var rangeEndExclusive: Date
  var looseItems: [MealPlanItem]
  var containedPlacements: [MenuBringInContainedCandidate]
  var partiallyOverlappingMenuTitles: [String]
}

private struct MenuPlacementItemKey: Hashable {
  var placementID: MenuPlacement.ID
  var itemID: MenuItem.ID
}

extension MenuRepository {
  static func bringInCandidates(menuID: Menu.ID, in db: Database) throws -> MenuBringInCandidates? {
    guard let targetMenu = try Menu.find(menuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(menuID)
    }
    let targetPlacements = try MenuPlacement.where { $0.menuID.eq(menuID) }.fetchAll(db)
    guard targetPlacements.count == 1, let targetPlacement = targetPlacements.first else { return nil }
    guard
      let rangeEndExclusive = MenuPlacementDay.date(for: targetMenu.dayCount, from: targetPlacement)
    else { return nil }

    let calendar = Calendar(identifier: .gregorian)
    let rangeStartDay = calendar.startOfDay(for: targetPlacement.startDate)
    let looseItems = try MealPlanItem
      .where { $0.scheduledDate.gte(rangeStartDay) && $0.scheduledDate.lt(rangeEndExclusive) }
      .fetchAll(db)
      .sorted(by: areMealPlanItemsInBringInOrder)

    let otherPlacements = try MenuPlacement
      .where { $0.menuID.neq(menuID) }
      .fetchAll(db)
    let otherMenuIDs = Set(otherPlacements.map(\.menuID))
    let menusByID: [Menu.ID: Menu]
    if otherMenuIDs.isEmpty {
      menusByID = [:]
    } else {
      menusByID = Dictionary(
        uniqueKeysWithValues: try Menu.where { $0.id.in(otherMenuIDs) }.fetchAll(db).map { ($0.id, $0) }
      )
    }

    var containedPlacements: [(MenuPlacement, Menu)] = []
    var partialTitles: [String] = []
    for placement in otherPlacements {
      guard let menu = menusByID[placement.menuID],
        let menuEndExclusive = MenuPlacementDay.date(for: menu.dayCount, from: placement)
      else { continue }
      let placementStartDay = calendar.startOfDay(for: placement.startDate)
      let placementEndExclusive = calendar.startOfDay(for: menuEndExclusive)
      guard placementStartDay < rangeEndExclusive && placementEndExclusive > rangeStartDay else { continue }
      if placementStartDay >= rangeStartDay && placementEndExclusive <= rangeEndExclusive {
        containedPlacements.append((placement, menu))
      } else {
        partialTitles.append(menu.title)
      }
    }

    let containedMenuIDs = Set(containedPlacements.map { $0.1.id })
    let itemsByMenuID: [Menu.ID: [MenuItem]]
    let stepsByMenuID: [Menu.ID: [PrepPlanStepRecord]]
    if containedMenuIDs.isEmpty {
      itemsByMenuID = [:]
      stepsByMenuID = [:]
    } else {
      itemsByMenuID = Dictionary(
        grouping: try MenuItem.where { $0.menuID.in(containedMenuIDs) }.fetchAll(db),
        by: \.menuID
      )
      stepsByMenuID = Dictionary(
        grouping: try PrepPlanStepRecord.where { $0.menuID.in(containedMenuIDs) }.fetchAll(db),
        by: \.menuID
      )
    }
    let copyablePlacements = containedPlacements.compactMap { placement, menu -> MenuBringInContainedCandidate? in
      let items = (itemsByMenuID[menu.id] ?? []).sorted(by: areMenuItemsInBringInOrder)
      let prepSteps = (stepsByMenuID[menu.id] ?? []).sorted(by: arePrepPlanStepsInBringInOrder)
      guard !items.isEmpty || !prepSteps.isEmpty else { return nil }
      return MenuBringInContainedCandidate(
        placement: placement,
        menu: menu,
        items: items,
        prepSteps: prepSteps
      )
    }

    let orderedCopyablePlacements = copyablePlacements.sorted { lhs, rhs in
      let titleOrder = lhs.menu.title.localizedStandardCompare(rhs.menu.title)
      if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
      if lhs.placement.startDate != rhs.placement.startDate {
        return lhs.placement.startDate < rhs.placement.startDate
      }
      return lhs.placement.id.uuidString < rhs.placement.id.uuidString
    }

    return MenuBringInCandidates(
      targetMenu: targetMenu,
      targetPlacement: targetPlacement,
      rangeStartDay: rangeStartDay,
      rangeEndExclusive: rangeEndExclusive,
      looseItems: looseItems,
      containedPlacements: orderedCopyablePlacements,
      partiallyOverlappingMenuTitles: partialTitles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    )
  }

  public static func bringInOffer(menuID: Menu.ID, in db: Database) throws -> MenuBringInOffer? {
    guard let candidates = try bringInCandidates(menuID: menuID, in: db),
      !candidates.looseItems.isEmpty || !candidates.containedPlacements.isEmpty
    else { return nil }
    return MenuBringInOffer(
      looseCalendarItemCount: candidates.looseItems.count,
      containedPlacements: candidates.containedPlacements.map { candidate in
        MenuBringInContainedPlacement(
          menuID: candidate.menu.id,
          title: candidate.menu.title,
          dishCount: candidate.items.count,
          prepStepCount: candidate.prepSteps.count
        )
      },
      partiallyOverlappingMenuTitles: candidates.partiallyOverlappingMenuTitles
    )
  }

  public static func bringIn(
    menuID: Menu.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> MenuBringInResult {
    guard let candidates = try bringInCandidates(menuID: menuID, in: db) else {
      throw MenuRepositoryError.menuMustHaveOnePlacement
    }
    let targetPlacement = candidates.targetPlacement
    var newItemIDsByCalendarItemID: [MealPlanItem.ID: MenuItem.ID] = [:]
    var newItemIDsByPlacementItem: [MenuPlacementItemKey: MenuItem.ID] = [:]
    var deletedPlacementIDs: Set<MenuPlacement.ID> = []

    for source in candidates.looseItems {
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

    for candidate in candidates.containedPlacements {
      let sourcePlacement = candidate.placement
      var copiedItemIDs: [MenuItem.ID: MenuItem.ID] = [:]
      let shift = MenuPlacementDay.offset(of: sourcePlacement.startDate, from: targetPlacement) ?? 0
      for source in candidate.items {
        let dayOffset = source.dayOffset + shift
        let item = MenuItem(
          id: uuid(), menuID: menuID, kind: source.kind, recipeID: source.recipeID, title: source.title,
          dayOffset: dayOffset, mealSlot: source.mealSlot, notes: source.notes,
          sortOrder: try nextSortOrder(menuID: menuID, dayOffset: dayOffset, mealSlot: source.mealSlot, in: db),
          dateCreated: source.dateCreated, dateModified: now, scale: source.scale
        )
        try MenuItem.insert { item }.execute(db)
        copiedItemIDs[source.id] = item.id
        newItemIDsByPlacementItem[MenuPlacementItemKey(placementID: sourcePlacement.id, itemID: source.id)] = item.id
      }
      let nextStepOrder = (try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.sortOrder).max() ?? -1) + 1
      for (stepIndex, source) in candidate.prepSteps.enumerated() {
        let workDayOffset: Int?
        if let sourceOffset = source.workDayOffset {
          workDayOffset = sourceOffset + shift
        } else if candidate.menu.dayCount == 1 {
          switch PrepPlanSessionBand(matching: source.session) {
          case .dayOf, .atService: workDayOffset = shift
          case .dayBefore: workDayOffset = shift - 1
          default: workDayOffset = nil
          }
        } else {
          workDayOffset = nil
        }
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: uuid(), menuID: menuID, sortOrder: nextStepOrder + stepIndex, session: source.session,
            task: source.task, serves: source.serves,
            makeAheadWindow: source.makeAheadWindow,
            sourceDish: source.sourceDish.flatMap { copiedItemIDs[$0] },
            workDayOffset: workDayOffset
          )
        }.execute(db)
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
    for item in candidates.looseItems {
      try MealPlanItem.find(item.id).delete().execute(db)
    }
    for placementID in deletedPlacementIDs {
      try MenuPlacement.find(placementID).delete().execute(db)
    }
    return MenuBringInResult(
      movedCalendarItemCount: candidates.looseItems.count,
      copiedPlacementCount: deletedPlacementIDs.count
    )
  }
}

private func areMealPlanItemsInBringInOrder(_ lhs: MealPlanItem, _ rhs: MealPlanItem) -> Bool {
  if lhs.scheduledDate != rhs.scheduledDate { return lhs.scheduledDate < rhs.scheduledDate }
  if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder { return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder }
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func areMenuItemsInBringInOrder(_ lhs: MenuItem, _ rhs: MenuItem) -> Bool {
  if lhs.dayOffset != rhs.dayOffset { return lhs.dayOffset < rhs.dayOffset }
  if lhs.mealSlot.sortOrder != rhs.mealSlot.sortOrder { return lhs.mealSlot.sortOrder < rhs.mealSlot.sortOrder }
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func arePrepPlanStepsInBringInOrder(_ lhs: PrepPlanStepRecord, _ rhs: PrepPlanStepRecord) -> Bool {
  if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
  return lhs.id.uuidString < rhs.id.uuidString
}
