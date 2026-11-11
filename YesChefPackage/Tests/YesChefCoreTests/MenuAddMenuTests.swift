import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuAddMenuTests {
    @Test
    func addMenuCopiesAtChosenDayAndLeavesSourceAndTargetPrepInPlace() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_000_000)
      let targetID = SampleUUIDSequence.uuid(90_001)
      let sourceID = SampleUUIDSequence.uuid(90_002)
      let emptyID = SampleUUIDSequence.uuid(90_003)
      let tooLongID = SampleUUIDSequence.uuid(90_004)
      let targetItemID = SampleUUIDSequence.uuid(90_005)
      let sourceItemID = SampleUUIDSequence.uuid(90_006)
      let targetStepID = SampleUUIDSequence.uuid(90_007)
      let sourceStepIDs = [SampleUUIDSequence.uuid(90_008), SampleUUIDSequence.uuid(90_009), SampleUUIDSequence.uuid(90_010)]
      let targetPlacementID = SampleUUIDSequence.uuid(90_011)
      let sourcePlacementID = SampleUUIDSequence.uuid(90_012)
      let tooLongItemID = SampleUUIDSequence.uuid(90_013)
      var uuids = SampleUUIDSequence(start: 90_100)

      try database.write { db in
        for menu in [
          Menu(id: targetID, title: "Target", dayCount: 7, dateCreated: now, dateModified: now),
          Menu(id: sourceID, title: "Thanksgiving", dayCount: 1, dateCreated: now, dateModified: now),
          Menu(id: emptyID, title: "Empty", dayCount: 2, dateCreated: now, dateModified: now),
          Menu(id: tooLongID, title: "Too Long", dayCount: 8, dateCreated: now, dateModified: now),
        ] {
          try Menu.insert { menu }.execute(db)
        }
        try MenuPlacement.insert {
          MenuPlacement(id: targetPlacementID, menuID: targetID, startDate: now, dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuPlacement.insert {
          MenuPlacement(id: sourcePlacementID, menuID: sourceID, startDate: now.addingTimeInterval(86_400), dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: targetItemID, menuID: targetID, kind: .note, title: "Target dish", dayOffset: 0,
            mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: sourceItemID, menuID: sourceID, kind: .note, title: "Roast turkey", dayOffset: 0,
            mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now, scale: 1.5)
        }.execute(db)
        try MenuItem.insert {
          MenuItem(id: tooLongItemID, menuID: tooLongID, kind: .note, title: "Long feast", dayOffset: 7,
            mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(id: targetStepID, menuID: targetID, sortOrder: 0, session: "Flexible", task: "Target prep")
        }.execute(db)
        for (index, session, task) in [
          (0, "The day before", "Make gravy"),
          (1, "The day of", "Roast turkey"),
          (2, "Flexible", "Set the table"),
        ] {
          try PrepPlanStepRecord.insert {
            PrepPlanStepRecord(
              id: sourceStepIDs[index], menuID: sourceID, sortOrder: index, session: session, task: task,
              sourceDish: index == 1 ? sourceItemID : nil
            )
          }.execute(db)
        }

        let offer = try MenuRepository.addMenuOffer(targetMenuID: targetID, in: db)
        #expect(offer.sources.map(\.title) == ["Thanksgiving", "Too Long"])
        #expect(offer.sources.map(\.fits) == [true, false])
        #expect(offer.sources.first?.dishCount == 1)
        #expect(offer.sources.first?.overlappingPlacementStartDate == now.addingTimeInterval(86_400))

        try MenuRepository.addMenu(
          sourceMenuID: sourceID, into: targetID, startDayOffset: 3, in: db, now: now.addingTimeInterval(30),
          uuid: { uuids.next() }
        )

        let targetItems = try MenuItem.where { $0.menuID.eq(targetID) }.fetchAll(db)
        #expect(targetItems.count == 2)
        let copiedItem = try #require(targetItems.first { $0.title == "Roast turkey" })
        #expect(copiedItem.id != sourceItemID)
        #expect(copiedItem.dayOffset == 3)
        #expect(copiedItem.scale == 1.5)
        let steps = try PrepPlanStepRepository.steps(for: targetID, in: db)
        #expect(steps.map(\.task) == ["Target prep", "Make gravy", "Roast turkey", "Set the table"])
        #expect(steps.map(\.workDayOffset) == [nil, 2, 3, nil])
        #expect(steps[2].sourceDish == copiedItem.id)

        #expect(try MenuItem.where { $0.menuID.eq(sourceID) }.fetchAll(db).map(\.id) == [sourceItemID])
        #expect(try PrepPlanStepRepository.steps(for: sourceID, in: db).map(\.id) == sourceStepIDs)
        #expect(try MenuPlacement.find(sourcePlacementID).fetchOne(db) != nil)
      }
    }

    @Test
    func addMenuShiftsDatedStepsForMultiDaySourcesAndRejectsInvalidSources() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 910_100_000)
      let targetID = SampleUUIDSequence.uuid(91_001)
      let sourceID = SampleUUIDSequence.uuid(91_002)
      let emptyID = SampleUUIDSequence.uuid(91_003)
      let missingID = SampleUUIDSequence.uuid(91_006)
      let itemID = SampleUUIDSequence.uuid(91_004)
      let stepID = SampleUUIDSequence.uuid(91_005)
      var uuids = SampleUUIDSequence(start: 91_100)

      try database.write { db in
        for menu in [
          Menu(id: targetID, title: "Week", dayCount: 7, dateCreated: now, dateModified: now),
          Menu(id: sourceID, title: "Two days", dayCount: 2, dateCreated: now, dateModified: now),
          Menu(id: emptyID, title: "No dishes", dayCount: 1, dateCreated: now, dateModified: now),
        ] { try Menu.insert { menu }.execute(db) }
        try MenuItem.insert {
          MenuItem(id: itemID, menuID: sourceID, kind: .note, title: "Soup", dayOffset: 1,
            mealSlot: .dinner, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(id: stepID, menuID: sourceID, sortOrder: 0, session: "Morning", task: "Chill soup", workDayOffset: 1)
        }.execute(db)

        try MenuRepository.addMenu(
          sourceMenuID: sourceID, into: targetID, startDayOffset: 2, in: db, now: now, uuid: { uuids.next() }
        )
        #expect(try MenuItem.where { $0.menuID.eq(targetID) }.fetchAll(db).first?.dayOffset == 3)
        #expect(try PrepPlanStepRepository.steps(for: targetID, in: db).first?.workDayOffset == 3)

        #expect(throws: MenuRepositoryError.cannotAddMenuToItself) {
          try MenuRepository.addMenu(sourceMenuID: targetID, into: targetID, startDayOffset: 0, in: db, now: now, uuid: { uuids.next() })
        }
        #expect(throws: MenuRepositoryError.emptySourceMenu(emptyID)) {
          try MenuRepository.addMenu(sourceMenuID: emptyID, into: targetID, startDayOffset: 0, in: db, now: now, uuid: { uuids.next() })
        }
        #expect(throws: MenuRepositoryError.menuNotFound(missingID)) {
          try MenuRepository.addMenu(sourceMenuID: missingID, into: targetID, startDayOffset: 0, in: db, now: now, uuid: { uuids.next() })
        }
        #expect(throws: MenuRepositoryError.sourceMenuDoesNotFit(sourceID)) {
          try MenuRepository.addMenu(sourceMenuID: sourceID, into: targetID, startDayOffset: 6, in: db, now: now, uuid: { uuids.next() })
        }
      }
    }

    @Test
    func offerOnlyAddsCalendarOverlapNoteForOneWhollyContainedTargetPlacement() throws {
      @Dependency(\.defaultDatabase) var database
      let calendar = Calendar(identifier: .gregorian)
      let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25)))
      let secondTargetDate = try #require(calendar.date(byAdding: .day, value: 12, to: start))
      let partialStart = try #require(calendar.date(byAdding: .day, value: 1, to: start))
      let now = start
      let multiplePlacementTargetID = SampleUUIDSequence.uuid(92_001)
      let partialSourceID = SampleUUIDSequence.uuid(92_002)
      let itemID = SampleUUIDSequence.uuid(92_003)

      try database.write { db in
        try Menu.insert {
          Menu(id: multiplePlacementTargetID, title: "Two dinners", dayCount: 2, dateCreated: now, dateModified: now)
        }.execute(db)
        try Menu.insert {
          Menu(id: partialSourceID, title: "Three day event", dayCount: 3, dateCreated: now, dateModified: now)
        }.execute(db)
        for placement in [
          MenuPlacement(id: SampleUUIDSequence.uuid(92_004), menuID: multiplePlacementTargetID, startDate: start, dateCreated: now, dateModified: now),
          MenuPlacement(id: SampleUUIDSequence.uuid(92_005), menuID: multiplePlacementTargetID, startDate: secondTargetDate, dateCreated: now, dateModified: now),
          MenuPlacement(id: SampleUUIDSequence.uuid(92_006), menuID: partialSourceID, startDate: partialStart, dateCreated: now, dateModified: now),
        ] { try MenuPlacement.insert { placement }.execute(db) }
        try MenuItem.insert {
          MenuItem(id: itemID, menuID: partialSourceID, kind: .note, title: "Brunch", dayOffset: 0,
            mealSlot: .breakfast, sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)

        let offer = try MenuRepository.addMenuOffer(targetMenuID: multiplePlacementTargetID, in: db)
        #expect(offer.sources.map(\.title) == ["Three day event"])
        #expect(offer.sources.first?.overlappingPlacementStartDate == nil)
      }
    }

    @Test
    func helpPageIsCompactAndMenuChatContextCarriesIt() {
      #expect(AppHelpPage.menus.plainText.count <= 1_800)
      #expect(AppHelpPage.menus.plainText.contains("Add Menu…"))
      #expect(RecipeChatContext.menu(MenuChatContext(title: "Dinner", dayCount: 1)).helpPage == .menus)
      #expect(RecipeChatContext.recipe(RecipeChatRecipeContext(title: "Tart")).helpPage == nil)
    }

    @Test @MainActor
    func menuChatPromptAndModelCallIncludeHelpWhileRecipeChatDoesNot() async {
      let callRecords = ModelCallRecordCollector()
      await withDependencies {
        $0.uuid = .incrementing
        $0.modelClient = StubModelClient { _ in ModelResponse(text: "Use Add Menu…") }
        $0.modelCallRecordSink = .inMemory(callRecords)
      } operation: {
        let menuChat = RecipeChatModel(context: .menu(MenuChatContext(title: "Dinner", dayCount: 1)))
        let menuPrompt = menuChat.systemPrompt()
        #expect(menuPrompt.contains("How this screen works. Answer questions about using the app from this."))
        #expect(menuPrompt.contains(AppHelpPage.menus.plainText))
        #expect(await menuChat.send("How do I put one menu into another?"))

        let recipeChat = RecipeChatModel(context: .recipe(RecipeChatRecipeContext(title: "Tart")))
        #expect(!recipeChat.systemPrompt().contains(AppHelpPage.menus.plainText))
      }
      let calls = await callRecords.records()
      #expect(calls.first?.contextLayers.included == [.menu, .conversation, .help])
    }
  }
}
