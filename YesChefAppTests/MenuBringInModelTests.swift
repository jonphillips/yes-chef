import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct MenuBringInModelTests {
  @Test
  func savingPlacementOffersBringInAndConfirmationMovesCalendarItems() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_100_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_100_000)
      let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
      let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Three Day Menu", dayCount: 2, dateCreated: now, dateModified: now)
        }.execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: itemID, kind: .note, title: "Calendar note", scheduledDate: now,
            mealSlot: .dinner, notes: "Keep", sortOrder: 0, dateCreated: now, dateModified: now
          )
        }.execute(db)
      }

      let model = MenuLibraryModel()
      let context = MenuPlacementDraftContext(
        menuID: menuID, menuTitle: "Three Day Menu", placementID: nil,
        startDate: now, dayCount: 2, minimumDayCount: 1
      )
      #expect(model.savePlacementButtonTapped(context: context, startDate: now))
      guard case let .bringIn(presentation) = model.destination else {
        Issue.record("Expected the placement save to present the bring-in offer")
        return
      }

      model.confirmBringIn(presentation)
      #expect(model.destination == nil)
      let savedItems = try database.read { db in try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db) }
      #expect(savedItems.count == 1)
      #expect(savedItems.first?.title == "Calendar note")
      let remainsOnCalendar = try database.read { db in try MealPlanItem.find(itemID).fetchOne(db) == nil }
      #expect(remainsOnCalendar)
    }
  }

  @Test
  func placementSaveWithoutCandidatesOrWithMultiplePlacementsDoesNotOffer() throws {
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSinceReferenceDate: 900_200_000)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_200_000)
      let emptyMenuID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
      let twicePlacedMenuID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
      try database.write { db in
        for menuID in [emptyMenuID, twicePlacedMenuID] {
          try Menu.insert {
            Menu(id: menuID, title: "Menu", dayCount: 1, dateCreated: now, dateModified: now)
          }.execute(db)
        }
        try MenuRepository.placeMenu(menuID: twicePlacedMenuID, startDate: now, in: db, now: now, uuid: UUID.init)
        try MenuRepository.placeMenu(
          menuID: twicePlacedMenuID,
          startDate: now.addingTimeInterval(86_400),
          in: db,
          now: now,
          uuid: UUID.init
        )
      }

      let model = MenuLibraryModel()
      for menuID in [emptyMenuID, twicePlacedMenuID] {
        let context = MenuPlacementDraftContext(
          menuID: menuID, menuTitle: "Menu", placementID: nil,
          startDate: now, dayCount: 1, minimumDayCount: 1
        )
        #expect(model.savePlacementButtonTapped(context: context, startDate: now))
        #expect(model.destination == nil)
      }
    }
  }
}
