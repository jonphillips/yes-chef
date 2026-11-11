import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct MenuBringInModelTests {
  @Test
  func savingMenuEditsWritesFieldsAndPlacementsTogetherAndOffersBringIn() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_100_000)
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
      let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
      let placementID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Three Day Menu", notes: "Old", dayCount: 2, dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: itemID, menuID: menuID, kind: .note, title: "Dish", dayOffset: 1, mealSlot: .dinner, notes: nil, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuPlacement.insert {
          MenuPlacement(id: placementID, menuID: menuID, startDate: now, dateCreated: now, dateModified: now)
        }.execute(db)
        try MealPlanItem.insert {
          MealPlanItem(id: UUID(), kind: .note, title: "Calendar note", scheduledDate: now.addingTimeInterval(86_400),
            mealSlot: .dinner, notes: "Keep", sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
      }

      var moved = MenuEditPlacementDraft(placementID: placementID, startDate: now)
      moved.startDate = now.addingTimeInterval(86_400)
      let context = MenuEditDraftContext(
        menuID: menuID,
        title: "Updated Menu",
        notes: "New notes",
        dayCount: 3,
        minimumDayCount: 2,
        placements: [moved, MenuEditPlacementDraft(startDate: now.addingTimeInterval(2 * 86_400))],
        bringInOffer: nil
      )
      let model = MenuLibraryModel()
      #expect(model.saveMenuEditsButtonTapped(context: context))

      let savedMenu = try database.read { db in try Menu.find(menuID).fetchOne(db) }
      #expect(savedMenu?.title == "Updated Menu")
      #expect(savedMenu?.notes == "New notes")
      #expect(savedMenu?.dayCount == 3)
      let savedPlacements = try database.read { db in try MenuPlacement.where { $0.menuID.eq(menuID) }.fetchAll(db) }
      #expect(savedPlacements.count == 2)
      #expect(savedPlacements.first(where: { $0.id == placementID })?.startDate == Calendar.autoupdatingCurrent.startOfDay(for: moved.startDate))
      #expect(model.destination == nil)
    }
  }

  @Test
  func addingOnePlacementWithCalendarItemsPresentsBringIn() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_150_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_150_000)
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000000151")!
      let calendarItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000152")!
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Menu", dayCount: 2, dateCreated: now, dateModified: now) }.execute(db)
        try MealPlanItem.insert {
          MealPlanItem(id: calendarItemID, kind: .note, title: "Calendar note", scheduledDate: now,
            mealSlot: .dinner, notes: nil, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
      }
      let model = MenuLibraryModel()
      let context = MenuEditDraftContext(menuID: menuID, title: "Menu", notes: "", dayCount: 2,
        minimumDayCount: 1, placements: [MenuEditPlacementDraft(startDate: now)], bringInOffer: nil)
      #expect(model.saveMenuEditsButtonTapped(context: context))
      guard case let .bringIn(presentation) = model.destination else {
        Issue.record("Expected a single new placement to present the Bring In offer")
        return
      }

      // Not Now dismisses without writing: the calendar item stays put.
      model.destination = nil
      #expect(try database.read { db in try MealPlanItem.find(calendarItemID).fetchOne(db) } != nil)
      #expect(try database.read { db in try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db) }.isEmpty)

      // Bring In moves the calendar item into the menu.
      model.confirmBringIn(presentation)
      #expect(model.destination == nil)
      let menuItems = try database.read { db in try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db) }
      #expect(menuItems.map(\.title) == ["Calendar note"])
      #expect(try database.read { db in try MealPlanItem.find(calendarItemID).fetchOne(db) } == nil)
    }
  }

  @Test
  func renamingWithoutPlacementChangesDoesNotOfferBringIn() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_200_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_200_000)
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Menu", dayCount: 1, dateCreated: now, dateModified: now) }.execute(db)
      }
      let model = MenuLibraryModel()
      let context = MenuEditDraftContext(menuID: menuID, title: "Renamed", notes: "", dayCount: 1,
        minimumDayCount: 1, placements: [], bringInOffer: nil)
      #expect(model.saveMenuEditsButtonTapped(context: context))
      #expect(model.destination == nil)
    }
  }

  @Test
  func shrinkingBelowOccupiedDayFloorFails() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_300_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_300_000)
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Menu", dayCount: 2, dateCreated: now, dateModified: now) }.execute(db)
        try MenuItem.insert {
          MenuItem(id: UUID(), menuID: menuID, kind: .note, title: "Day 2", dayOffset: 1, mealSlot: .dinner, notes: nil, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
      }
      let model = MenuLibraryModel()
      let context = MenuEditDraftContext(menuID: menuID, title: "Menu", notes: "", dayCount: 1,
        minimumDayCount: 1, placements: [], bringInOffer: nil)
      #expect(!model.saveMenuEditsButtonTapped(context: context))
      #expect(model.isShowingError)
      #expect(try database.read { db in try Menu.find(menuID).fetchOne(db)?.dayCount } == 2)
    }
  }

  @Test
  func addMenuThroughModelCopiesIntoTargetAndClearsDestination() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_400_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_400_000)
      let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
      let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
      let sourceItemID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
      try database.write { db in
        try Menu.insert { Menu(id: targetID, title: "Week", dayCount: 5, dateCreated: now, dateModified: now) }.execute(db)
        try Menu.insert { Menu(id: sourceID, title: "Dinner", dayCount: 1, dateCreated: now, dateModified: now) }.execute(db)
        try MenuItem.insert {
          MenuItem(id: sourceItemID, menuID: sourceID, kind: .note, title: "Roast chicken", dayOffset: 0,
            mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
      }

      let model = MenuLibraryModel()
      model.addMenuToMenuButtonTapped(targetMenuID: targetID)
      guard case let .addMenuToMenu(presentation) = model.destination else {
        Issue.record("Expected Add Menu presentation")
        return
      }
      model.confirmAddMenuToMenu(presentation, sourceMenuID: sourceID, startDayOffset: 2)

      #expect(model.destination == nil)
      let copied = try database.read { db in try MenuItem.where { $0.menuID.eq(targetID) }.fetchAll(db).first }
      #expect(copied?.title == "Roast chicken")
      #expect(copied?.dayOffset == 2)
      #expect(copied?.id != sourceItemID)
      #expect(try database.read { db in try MenuItem.where { $0.menuID.eq(sourceID) }.fetchAll(db).map(\.id) } == [sourceItemID])
    }
  }
}
