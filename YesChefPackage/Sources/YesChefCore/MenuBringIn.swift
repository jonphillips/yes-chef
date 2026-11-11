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
  static func copyMenuContents(
    sourceMenu: Menu,
    into targetMenuID: Menu.ID,
    dayShift: Int,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> [MenuItem.ID: MenuItem.ID] {
    let sourceItems = try MenuItem.where { $0.menuID.eq(sourceMenu.id) }.fetchAll(db)
      .sorted(by: areMenuItemsInBringInOrder)
    let sourceSteps = try PrepPlanStepRepository.steps(for: sourceMenu.id, in: db)
    var copiedItemIDs: [MenuItem.ID: MenuItem.ID] = [:]
    for source in sourceItems {
      let dayOffset = source.dayOffset + dayShift
      let item = MenuItem(
        id: uuid(), menuID: targetMenuID, kind: source.kind, recipeID: source.recipeID, title: source.title,
        dayOffset: dayOffset, mealSlot: source.mealSlot, notes: source.notes,
        sortOrder: try nextSortOrder(menuID: targetMenuID, dayOffset: dayOffset, mealSlot: source.mealSlot, in: db),
        dateCreated: source.dateCreated, dateModified: now, scale: source.scale
      )
      try MenuItem.insert { item }.execute(db)
      copiedItemIDs[source.id] = item.id
    }
    let nextStepOrder = (try PrepPlanStepRepository.steps(for: targetMenuID, in: db).map(\.sortOrder).max() ?? -1) + 1
    for (stepIndex, source) in sourceSteps.enumerated() {
      let workDayOffset: Int?
      if let sourceOffset = source.workDayOffset {
        workDayOffset = sourceOffset + dayShift
      } else if sourceMenu.dayCount == 1 {
        switch PrepPlanSessionBand(matching: source.session) {
        case .dayOf, .atService: workDayOffset = dayShift
        case .dayBefore: workDayOffset = dayShift - 1
        default: workDayOffset = nil
        }
      } else {
        workDayOffset = nil
      }
      try PrepPlanStepRecord.insert {
        PrepPlanStepRecord(
          id: uuid(), menuID: targetMenuID, sortOrder: nextStepOrder + stepIndex, session: source.session,
          task: source.task, serves: source.serves, makeAheadWindow: source.makeAheadWindow, timeOfDay: source.timeOfDay,
          sourceDish: source.sourceDish.flatMap { copiedItemIDs[$0] }, workDayOffset: workDayOffset
        )
      }.execute(db)
    }
    return copiedItemIDs
  }

  public static func addMenuOffer(targetMenuID: Menu.ID, in db: Database) throws -> MenuAddMenuOffer {
    guard let targetMenu = try Menu.find(targetMenuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(targetMenuID)
    }
    let sourceMenus = try Menu.where { $0.id.neq(targetMenuID) }.fetchAll(db)
    let itemsByMenuID = Dictionary(grouping: try MenuItem.fetchAll(db), by: \.menuID)
    let stepsByMenuID = Dictionary(grouping: try PrepPlanStepRecord.fetchAll(db), by: \.menuID)
    let targetPlacements = try MenuPlacement.where { $0.menuID.eq(targetMenuID) }.fetchAll(db)
    let targetPlacement = targetPlacements.count == 1 ? targetPlacements.first : nil
    let targetRangeEnd = targetPlacement.flatMap { MenuPlacementDay.date(for: targetMenu.dayCount, from: $0) }
    let calendar = Calendar(identifier: .gregorian)

    let sources = try sourceMenus.compactMap { source -> MenuAddMenuSourceOffer? in
      let dishCount = itemsByMenuID[source.id]?.count ?? 0
      let stepCount = stepsByMenuID[source.id]?.count ?? 0
      guard dishCount > 0 || stepCount > 0 else { return nil }
      var overlapStartDate: Date?
      if let targetPlacement, let targetRangeEnd {
        let targetStart = calendar.startOfDay(for: targetPlacement.startDate)
        let targetEnd = calendar.startOfDay(for: targetRangeEnd)
        overlapStartDate = try MenuPlacement.where { $0.menuID.eq(source.id) }
          .fetchAll(db)
          .first { placement in
            guard let sourceEnd = MenuPlacementDay.date(for: source.dayCount, from: placement) else { return false }
            return calendar.startOfDay(for: placement.startDate) >= targetStart
              && calendar.startOfDay(for: sourceEnd) <= targetEnd
          }?.startDate
      }
      return MenuAddMenuSourceOffer(
        menuID: source.id, title: source.title, dayCount: source.dayCount, dishCount: dishCount,
        fits: source.dayCount <= targetMenu.dayCount, overlappingPlacementStartDate: overlapStartDate
      )
    }
    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    return MenuAddMenuOffer(
      targetMenuID: targetMenuID, targetDayCount: targetMenu.dayCount,
      targetPlacementStartDate: targetPlacement?.startDate, sources: sources
    )
  }

  public static func addMenu(
    sourceMenuID: Menu.ID,
    into targetMenuID: Menu.ID,
    startDayOffset: Int,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard sourceMenuID != targetMenuID else { throw MenuRepositoryError.cannotAddMenuToItself }
    guard let targetMenu = try Menu.find(targetMenuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(targetMenuID)
    }
    guard let sourceMenu = try Menu.find(sourceMenuID).fetchOne(db) else {
      throw MenuRepositoryError.menuNotFound(sourceMenuID)
    }
    let sourceItems = try MenuItem.where { $0.menuID.eq(sourceMenuID) }.fetchAll(db)
    let sourceSteps = try PrepPlanStepRepository.steps(for: sourceMenuID, in: db)
    guard !sourceItems.isEmpty || !sourceSteps.isEmpty else {
      throw MenuRepositoryError.emptySourceMenu(sourceMenuID)
    }
    guard startDayOffset >= 0, sourceMenu.dayCount <= targetMenu.dayCount,
      startDayOffset <= targetMenu.dayCount - sourceMenu.dayCount
    else {
      throw MenuRepositoryError.sourceMenuDoesNotFit(sourceMenuID)
    }
    _ = try copyMenuContents(
      sourceMenu: sourceMenu, into: targetMenuID, dayShift: startDayOffset, in: db, now: now, uuid: uuid
    )
  }

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
      let shift = MenuPlacementDay.offset(of: sourcePlacement.startDate, from: targetPlacement) ?? 0
      let copiedItemIDs = try copyMenuContents(
        sourceMenu: candidate.menu, into: menuID, dayShift: shift, in: db, now: now, uuid: uuid
      )
      for (sourceID, copiedID) in copiedItemIDs {
        newItemIDsByPlacementItem[MenuPlacementItemKey(placementID: sourcePlacement.id, itemID: sourceID)] = copiedID
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
