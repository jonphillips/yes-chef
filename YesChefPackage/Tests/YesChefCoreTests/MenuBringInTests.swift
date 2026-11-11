import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuBringInTests {
    @Test
    func offerAndBringInMoveLooseItemsCopyContainedMenusAndLeavePartialOverlaps() throws {
      @Dependency(\.defaultDatabase) var database
      let calendar = Calendar(identifier: .gregorian)
      let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
      let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
      let partialStart = try #require(calendar.date(byAdding: .day, value: 2, to: start))
      let now = start
      let targetID = SampleUUIDSequence.uuid(61_001)
      let containedID = SampleUUIDSequence.uuid(61_002)
      let partialID = SampleUUIDSequence.uuid(61_003)
      let targetPlacementID = SampleUUIDSequence.uuid(61_004)
      let containedPlacementID = SampleUUIDSequence.uuid(61_005)
      let partialPlacementID = SampleUUIDSequence.uuid(61_006)
      let looseItemID = SampleUUIDSequence.uuid(61_007)
      let containedItemID = SampleUUIDSequence.uuid(61_008)
      let containedStepID = SampleUUIDSequence.uuid(61_009)
      let invalidRecipeItemID = SampleUUIDSequence.uuid(61_015)
      let lateItemID = SampleUUIDSequence.uuid(61_016)
      let listID = SampleUUIDSequence.uuid(61_010)
      let looseGroceryID = SampleUUIDSequence.uuid(61_011)
      let containedGroceryID = SampleUUIDSequence.uuid(61_012)
      var ids = SampleUUIDSequence(start: 61_100)

      try database.write { db in
        for menu in [
          Menu(id: targetID, title: "Week", dayCount: 3, dateCreated: now, dateModified: now),
          Menu(id: containedID, title: "Thanksgiving", dayCount: 1, dateCreated: now, dateModified: now),
          Menu(id: partialID, title: "Beach Brunch", dayCount: 3, dateCreated: now, dateModified: now),
        ] {
          try Menu.insert { menu }.execute(db)
        }
        for placement in [
          MenuPlacement(id: targetPlacementID, menuID: targetID, startDate: start, dateCreated: now, dateModified: now),
          MenuPlacement(id: containedPlacementID, menuID: containedID, startDate: nextDay, dateCreated: now, dateModified: now),
          MenuPlacement(id: partialPlacementID, menuID: partialID, startDate: partialStart, dateCreated: now, dateModified: now),
        ] {
          try MenuPlacement.insert { placement }.execute(db)
        }
        let containedItem = MenuItem(
          id: containedItemID, menuID: containedID, kind: .note, title: "Roast turkey",
          dayOffset: 0, mealSlot: .dinner, notes: "Dry brined", sortOrder: 0,
          dateCreated: now, dateModified: now, scale: 1.5
        )
        try MenuItem.insert { containedItem }.execute(db)
        for (index, session, task) in [
          (0, "The day before", "Make gravy base"),
          (1, "The day of", "Roast turkey"),
          (2, "At service", "Carve turkey"),
          (3, "Flexible", "Set out platters"),
        ] {
          try PrepPlanStepRecord.insert {
            PrepPlanStepRecord(
              id: index == 0 ? containedStepID : SampleUUIDSequence.uuid(61_020 + index),
              menuID: containedID, sortOrder: index, session: session, task: task,
              serves: index == 0 ? "Gravy" : nil,
              makeAheadWindow: index == 0 ? "Up to 3 days ahead" : nil,
              timeOfDay: index == 0 ? 13 * 60 + 30 : nil,
              sourceDish: index == 0 ? containedItemID : nil,
              completedAt: index == 0 ? now : nil
            )
          }.execute(db)
        }
        let looseItem = MealPlanItem(
          id: looseItemID, kind: .reservation, title: "Farmers market",
          scheduledDate: nextDay, mealSlot: .breakfast, notes: "Bring bags", sortOrder: 0,
          dateCreated: now, dateModified: now, scale: 2
        )
        try MealPlanItem.insert { looseItem }.execute(db)
        try MealPlanItem.insert {
          MealPlanItem(
            id: invalidRecipeItemID, kind: .recipe, title: "Unmatched recipe", scheduledDate: start,
            mealSlot: .lunch, sortOrder: 0, dateCreated: now, dateModified: now
          )
        }.execute(db)
        try GroceryList.insert {
          GroceryList(id: listID, title: "Shopping", sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        for (groceryID, title) in [(looseGroceryID, "Bags"), (containedGroceryID, "Turkey") ] {
          try GroceryItem.insert {
            GroceryItem(id: groceryID, groceryListID: listID, title: title, sortOrder: 0, dateCreated: now, dateModified: now)
          }.execute(db)
        }
        try GroceryItemSource.insert {
          GroceryItemSource(
            id: SampleUUIDSequence.uuid(61_013), groceryItemID: looseGroceryID, origin: .calendarItem,
            mealPlanItemID: looseItemID, scheduledDate: nextDay, mealSlot: .breakfast,
            sourceTitle: "Farmers market", ingredientText: "Bring bags", dateCreated: now
          )
        }.execute(db)
        try GroceryItemSource.insert {
          GroceryItemSource(
            id: SampleUUIDSequence.uuid(61_014), groceryItemID: containedGroceryID, origin: .menuPlacement,
            menuID: containedID, menuItemID: containedItemID, menuPlacementID: containedPlacementID,
            scheduledDate: nextDay, mealSlot: .dinner, sourceTitle: "Thanksgiving",
            ingredientText: "Turkey", dateCreated: now
          )
        }.execute(db)

        let possibleOffer = try MenuRepository.bringInOffer(menuID: targetID, in: db)
        let offer = try #require(possibleOffer)
        #expect(offer.looseCalendarItemCount == 2)
        #expect(offer.containedPlacements.map(\.title) == ["Thanksgiving"])
        #expect(offer.containedPlacements.first?.dishCount == 1)
        #expect(offer.containedPlacements.first?.prepStepCount == 4)
        #expect(offer.partiallyOverlappingMenuTitles == ["Beach Brunch"])

        // The write deliberately sees a row added after the offer was computed.
        try MealPlanItem.insert {
          MealPlanItem(
            id: lateItemID, kind: .note, title: "Late addition", scheduledDate: partialStart,
            mealSlot: .snack, sortOrder: 0, dateCreated: now, dateModified: now
          )
        }.execute(db)

        let result = try MenuRepository.bringIn(menuID: targetID, in: db, now: now, uuid: { ids.next() })
        #expect(result.movedCalendarItemCount == 3)
        #expect(result.copiedPlacementCount == 1)

        let targetItems = try MenuItem.where { $0.menuID.eq(targetID) }.fetchAll(db)
        #expect(targetItems.count == 4)
        let moved = try #require(targetItems.first { $0.kind == .reservation })
        #expect(moved.dayOffset == 1)
        #expect(moved.mealSlot == .breakfast)
        #expect(moved.notes == "Bring bags")
        #expect(moved.scale == 2)
        let convertedRecipe = try #require(targetItems.first { $0.title == "Unmatched recipe" })
        #expect(convertedRecipe.kind == .note)
        #expect(convertedRecipe.recipeID == nil)
        #expect(convertedRecipe.dayOffset == 0)
        let lateAddition = try #require(targetItems.first { $0.title == "Late addition" })
        #expect(lateAddition.dayOffset == 2)
        let copied = try #require(targetItems.first { $0.title == "Roast turkey" })
        #expect(copied.id != containedItemID)
        #expect(copied.dayOffset == 1)
        #expect(copied.scale == 1.5)
        let maybeTargetPlacement = try MenuPlacement.find(targetPlacementID).fetchOne(db)
        let targetPlacement = try #require(maybeTargetPlacement)
        #expect(MenuPlacementDay.date(for: moved.dayOffset, from: targetPlacement) == nextDay)
        #expect(MenuPlacementDay.date(for: copied.dayOffset, from: targetPlacement) == nextDay)
        #expect(try MenuItem.find(containedItemID).fetchOne(db) != nil)
        #expect(try MenuPlacement.find(containedPlacementID).fetchOne(db) == nil)
        #expect(try MenuPlacement.find(partialPlacementID).fetchOne(db) != nil)
        #expect(try MealPlanItem.find(looseItemID).fetchOne(db) == nil)
        let copiedStep = try #require(PrepPlanStepRepository.steps(for: targetID, in: db).first)
        #expect(copiedStep.id != containedStepID)
        #expect(copiedStep.sourceDish == copied.id)
        #expect(copiedStep.session == "The day before")
        #expect(copiedStep.serves == "Gravy")
        #expect(copiedStep.makeAheadWindow == "Up to 3 days ahead")
        #expect(copiedStep.timeOfDay == 13 * 60 + 30)
        #expect(copiedStep.workDayOffset == 0)
        #expect(copiedStep.completedAt == nil)
        #expect(try PrepPlanStepRecord.find(containedStepID).fetchOne(db)?.completedAt == now)
        let copiedSteps = try PrepPlanStepRepository.steps(for: targetID, in: db)
        #expect(copiedSteps.first { $0.task == "Roast turkey" }?.workDayOffset == 1)
        #expect(copiedSteps.first { $0.task == "Carve turkey" }?.workDayOffset == 1)
        #expect(copiedSteps.first { $0.task == "Set out platters" }?.workDayOffset == nil)

        let sources = try GroceryItemSource.fetchAll(db)
        let looseSource = try #require(sources.first { $0.groceryItemID == looseGroceryID })
        #expect(looseSource.origin == .menuPlacement)
        #expect(looseSource.menuID == targetID)
        #expect(looseSource.menuItemID == moved.id)
        #expect(looseSource.menuPlacementID == targetPlacementID)
        #expect(looseSource.mealPlanItemID == nil)
        let containedSource = try #require(sources.first { $0.groceryItemID == containedGroceryID })
        #expect(containedSource.menuID == targetID)
        #expect(containedSource.menuItemID == copied.id)
        #expect(containedSource.menuPlacementID == targetPlacementID)
        #expect(containedSource.scheduledDate == nextDay)
      }
    }

    @Test
    func offerRequiresExactlyOnePlacementAndSomethingInRange() throws {
      @Dependency(\.defaultDatabase) var database
      let date = Date(timeIntervalSinceReferenceDate: 803_400_000)
      let zeroPlacementsID = SampleUUIDSequence.uuid(62_000)
      let onePlacementID = SampleUUIDSequence.uuid(62_001)
      let twoPlacementsID = SampleUUIDSequence.uuid(62_002)
      try database.write { db in
        for menu in [
          Menu(id: zeroPlacementsID, title: "Unplaced", dayCount: 1, dateCreated: date, dateModified: date),
          Menu(id: onePlacementID, title: "Empty", dayCount: 1, dateCreated: date, dateModified: date),
          Menu(id: twoPlacementsID, title: "Twice", dayCount: 1, dateCreated: date, dateModified: date),
        ] { try Menu.insert { menu }.execute(db) }
        for (index, menuID) in [onePlacementID, twoPlacementsID, twoPlacementsID].enumerated() {
          try MenuPlacement.insert {
            MenuPlacement(
              id: SampleUUIDSequence.uuid(62_010 + index), menuID: menuID, startDate: date,
              dateCreated: date, dateModified: date
            )
          }.execute(db)
        }
        #expect(try MenuRepository.bringInOffer(menuID: zeroPlacementsID, in: db) == nil)
        #expect(try MenuRepository.bringInOffer(menuID: onePlacementID, in: db) == nil)
        #expect(try MenuRepository.bringInOffer(menuID: twoPlacementsID, in: db) == nil)
      }
    }

    @Test
    func bringingInDatedStepFromMultiDayMenuShiftsItsWorkDay() throws {
      @Dependency(\.defaultDatabase) var database
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0)!
      let start = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 805_800_000))
      let sourceStart = try #require(calendar.date(byAdding: .day, value: 3, to: start))
      let targetID = SampleUUIDSequence.uuid(63_000)
      let sourceID = SampleUUIDSequence.uuid(63_001)
      let targetPlacementID = SampleUUIDSequence.uuid(63_002)
      let sourcePlacementID = SampleUUIDSequence.uuid(63_003)
      let sourceStepID = SampleUUIDSequence.uuid(63_004)
      var ids = SampleUUIDSequence(start: 63_100)

      try database.write { db in
        for menu in [
          Menu(id: targetID, title: "Week", dayCount: 7, dateCreated: start, dateModified: start),
          Menu(id: sourceID, title: "Prep weekend", dayCount: 2, dateCreated: start, dateModified: start),
        ] {
          try Menu.insert { menu }.execute(db)
        }
        for placement in [
          MenuPlacement(id: targetPlacementID, menuID: targetID, startDate: start, dateCreated: start, dateModified: start),
          MenuPlacement(id: sourcePlacementID, menuID: sourceID, startDate: sourceStart, dateCreated: start, dateModified: start),
        ] {
          try MenuPlacement.insert { placement }.execute(db)
        }
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: sourceStepID,
            menuID: sourceID,
            sortOrder: 0,
            session: "Morning",
            task: "Make the dough",
            workDayOffset: 1
          )
        }.execute(db)

        let result = try MenuRepository.bringIn(menuID: targetID, in: db, now: start, uuid: { ids.next() })
        #expect(result.copiedPlacementCount == 1)

        let copiedStep = try #require(try PrepPlanStepRepository.steps(for: targetID, in: db).first)
        #expect(copiedStep.task == "Make the dough")
        #expect(copiedStep.session == "Morning")
        #expect(copiedStep.workDayOffset == 4)
      }
    }
  }
}
