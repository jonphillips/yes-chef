import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized, .dependencies { try $0.bootstrapDatabase() })
struct ChatAccessStagedItemsTests {
  @Test func envelopesRoundTripAndRejectNewerVersions() throws {
    let recipe = ChatAccessStagedRecipeReturn(recipeID: UUID(), recipeTitle: "Soup", text: "YC-REVISION:\nBrown it")
    let recipeData = try JSONEncoder().encode(recipe)
    #expect(try JSONDecoder().decode(ChatAccessStagedRecipeReturn.self, from: recipeData) == recipe)
    let menu = ChatAccessStagedMenu(title: "Supper", dayCount: 2, items: [
      .init(recipeID: nil, title: "Salad", dayOffset: 1, slot: .lunch, note: "Dress late", scale: nil),
    ])
    let menuData = try JSONEncoder().encode(menu)
    #expect(try JSONDecoder().decode(ChatAccessStagedMenu.self, from: menuData) == menu)
    let menuDay = ChatAccessStagedMenuDay(menuID: UUID(), menuTitle: "Supper", dayOffset: 1,
      items: [.init(recipeID: nil, title: "Salad", dayOffset: 1, slot: .lunch, note: nil, scale: nil)],
      dayAtStage: [.init(kind: .reservation, title: "Market", recipeID: nil, slot: .breakfast, note: "Get herbs", scale: 1)])
    let menuDayData = try JSONEncoder().encode(menuDay)
    #expect(try JSONDecoder().decode(ChatAccessStagedMenuDay.self, from: menuDayData) == menuDay)
    let newer = Data("{\"format\":\"yc-menu\",\"version\":2,\"title\":\"Supper\",\"dayCount\":1,\"items\":[]}".utf8)
    #expect(throws: ChatAccessStagedEnvelopeError.unsupportedVersion(found: 2, supported: 1)) {
      try JSONDecoder().decode(ChatAccessStagedMenu.self, from: newer)
    }
    let newerDay = Data("{\"format\":\"yc-menu-day\",\"version\":2}".utf8)
    #expect(throws: ChatAccessStagedEnvelopeError.unsupportedVersion(found: 2, supported: 1)) {
      try JSONDecoder().decode(ChatAccessStagedMenuDay.self, from: newerDay)
    }
  }

  @Test func prepPlanReplacementKeepsMatchedIdentityAndLinksNewSteps() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_100), menuID = UUID(), recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let actualMenuID = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
      let dishID = try MenuRepository.addRecipeItem(menuID: actualMenuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day before", task: "Toast spices", serves: "Beans", sourceDish: dishID, workDayOffset: -1), for: actualMenuID, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day before", task: "Old step", serves: "Beans", sourceDish: dishID, workDayOffset: -1), for: actualMenuID, in: db, now: now, uuid: { UUID() })
      let original = try PrepPlanStepRepository.steps(for: actualMenuID, in: db)
      let envelope = ChatAccessStagedPrepPlan(menuID: actualMenuID, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: recipeID, title: "Beans", steps: [
          .init(workDayOffset: -1, session: "Day before", task: "Toast spices"),
          .init(workDayOffset: -1, session: "Day before", task: "Chop herbs"),
        ]),
      ], planAtStage: original.map { .init(workDayOffset: $0.workDayOffset, session: $0.session, task: $0.task, serves: $0.serves, dishIndex: nil) })
      let plan = try ChatPrepPlanImport.plan(envelope, in: db)
      #expect(plan.planChangedSinceStage == false)
      #expect(plan.newCount == 1)
      try ChatPrepPlanImport.apply(plan, keeping: [1], in: db, now: now.addingTimeInterval(1), uuid: { UUID() })
      let updated = try PrepPlanStepRepository.steps(for: actualMenuID, in: db)
      #expect(updated.count == 2)
      #expect(updated.first?.id == original.first?.id)
      #expect(updated.map(\.task) == ["Toast spices", "Chop herbs"])
      #expect(updated.last?.sourceDish == dishID)
      #expect(updated.last?.serves == "Beans")
      let droppedNew = try ChatPrepPlanImport.plan(.init(menuID: actualMenuID, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: recipeID, title: "Beans", steps: [
          .init(workDayOffset: -1, session: "Day before", task: "Toast spices"),
          .init(workDayOffset: -1, session: "Day before", task: "Do not add"),
        ]),
      ], planAtStage: nil), in: db)
      try ChatPrepPlanImport.apply(droppedNew, keeping: [], in: db, now: now.addingTimeInterval(2), uuid: { UUID() })
      #expect(try PrepPlanStepRepository.steps(for: actualMenuID, in: db).map(\.task) == ["Toast spices"])
    }
  }

  @Test func prepPlanLinksKeptByNameWithoutChangingOtherRowsOrOrder() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_200), menuID = UUID(), beansID = UUID(), pieID = UUID()
    try database.write { db in
      try Recipe.insert { [
        Recipe(id: beansID, title: "Beans", dateCreated: now, dateModified: now),
        Recipe(id: pieID, title: "Pie", dateCreated: now, dateModified: now),
      ] }.execute(db)
      let menu = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
      let beansDish = try MenuRepository.addRecipeItem(menuID: menu, recipeID: beansID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let pieDish = try MenuRepository.addRecipeItem(menuID: menu, recipeID: pieID, dayOffset: 0, mealSlot: .snack, notes: nil, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day before", task: "Soak beans", serves: "Beans", workDayOffset: -1), for: menu, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day of", task: "Make crust", serves: "Pie", sourceDish: pieDish, workDayOffset: 0), for: menu, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Anytime", task: "Set the table"), for: menu, in: db, now: now, uuid: { UUID() })
      let before = try PrepPlanStepRepository.steps(for: menu, in: db)
      let plan = try ChatPrepPlanImport.plan(.init(menuID: menu, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: beansID, title: "Beans", steps: [.init(workDayOffset: -1, session: "Day before", task: "Soak beans")]),
      ], planAtStage: nil), in: db)
      guard case .kept(_, let matched, let matchedByName) = try #require(plan.dishes.first?.1.first) else { Issue.record("Expected the name-matched step to be Kept"); return }
      #expect(matched.id == before[0].id)
      #expect(matchedByName)
      #expect(matched.sourceDish == nil)
      try ChatPrepPlanImport.apply(plan, keeping: [], in: db, now: now.addingTimeInterval(1), uuid: { UUID() })
      let after = try PrepPlanStepRepository.steps(for: menu, in: db)
      #expect(after.map(\.id) == before.map(\.id))
      #expect(after.map(\.sortOrder) == before.map(\.sortOrder))
      #expect(after.map(\.task) == before.map(\.task))
      #expect(after[0].sourceDish == beansDish)
      #expect(after[1].sourceDish == pieDish)
      #expect(after[2].sourceDish == nil)
    }
  }

  @Test func prepPlanClearsAnEmptyDishAndLeavesAmbiguousAndOtherLinkedStepsAlone() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_300), menuID = UUID(), beansID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: beansID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let menu = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      let recipeDish = try MenuRepository.addRecipeItem(menuID: menu, recipeID: beansID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let noteDish = try MenuRepository.addNoteItem(menuID: menu, title: "Beans", notes: nil, dayOffset: 0, mealSlot: .lunch, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day of", task: "Cook beans", serves: "Beans", sourceDish: recipeDish), for: menu, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day of", task: "Ambiguous beans", serves: "Beans"), for: menu, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day of", task: "Dress salad", serves: "Beans", sourceDish: noteDish), for: menu, in: db, now: now, uuid: { UUID() })
      let before = try PrepPlanStepRepository.steps(for: menu, in: db)
      let plan = try ChatPrepPlanImport.plan(.init(menuID: menu, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: beansID, title: "Beans", steps: []),
      ], planAtStage: nil), in: db)
      #expect(plan.dishes.first?.1 == [.removed(dish: plan.dishes[0].0, step: before[0], matchedByName: false)])
      try ChatPrepPlanImport.apply(plan, keeping: [], in: db, now: now, uuid: { UUID() })
      let after = try PrepPlanStepRepository.steps(for: menu, in: db)
      #expect(after.map(\.id) == [before[1].id, before[2].id])
      #expect(after.map(\.sortOrder) == [0, 1])
      #expect(after.map(\.task) == ["Ambiguous beans", "Dress salad"])
    }
  }

  @Test func prepPlanOrdersNewStepsByBandThenDayThenPlanEnd() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_400), menuID = UUID(), beansID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: beansID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let menu = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 3, in: db, now: now, uuid: { menuID })
      _ = try MenuRepository.addRecipeItem(menuID: menu, recipeID: beansID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let pieDish = try MenuRepository.addNoteItem(menuID: menu, title: "Pie", notes: nil, dayOffset: 1, mealSlot: .snack, in: db, now: now, uuid: { UUID() })
      for (session, task, workDay) in [("Same", "same-1", -1), ("Same", "same-2", -1), ("Other", "other-day", -1), ("Day zero", "day-zero", 0), ("Tail", "tail", 2)] {
        try PrepPlanStepRepository.create(.init(session: session, task: task, sourceDish: pieDish, workDayOffset: workDay), for: menu, in: db, now: now, uuid: { UUID() })
      }
      let plan = try ChatPrepPlanImport.plan(.init(menuID: menu, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: beansID, title: "Beans", steps: [
          .init(workDayOffset: -1, session: "Same", task: "new-band"),
          .init(workDayOffset: 0, session: "No band", task: "new-day"),
          .init(workDayOffset: 1, session: "No day", task: "new-end"),
        ]),
      ], planAtStage: nil), in: db)
      try ChatPrepPlanImport.apply(plan, keeping: [0, 1, 2], in: db, now: now, uuid: { UUID() })
      let tasks = try PrepPlanStepRepository.steps(for: menu, in: db).map(\.task)
      #expect(tasks == ["same-1", "same-2", "new-band", "other-day", "day-zero", "new-day", "tail", "new-end"])
    }
  }

  @Test func prepPlanReportsDriftAndRejectsDeletedMenuOrDishWithoutPartialApply() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_500), menuID = UUID(), recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let menu = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
      let dishID = try MenuRepository.addRecipeItem(menuID: menu, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      try PrepPlanStepRepository.create(.init(session: "Day before", task: "Soak beans", sourceDish: dishID, workDayOffset: -1), for: menu, in: db, now: now, uuid: { UUID() })
      let current = try PrepPlanStepRepository.steps(for: menu, in: db)
      let envelope = ChatAccessStagedPrepPlan(menuID: menu, menuTitle: "Week", dishes: [
        .init(dayOffset: 0, recipeID: recipeID, title: "Beans", steps: [.init(workDayOffset: -1, session: "Day before", task: "Soak beans")]),
      ], planAtStage: current.map { .init(workDayOffset: $0.workDayOffset, session: $0.session, task: $0.task, serves: $0.serves, dishIndex: nil) })
      #expect(try ChatPrepPlanImport.plan(envelope, in: db).planChangedSinceStage == false)
      try PrepPlanStepRecord.find(current[0].id).update { $0.task = #bind("Changed") }.execute(db)
      #expect(try ChatPrepPlanImport.plan(envelope, in: db).planChangedSinceStage == true)
      var withoutBaseline = envelope; withoutBaseline.planAtStage = nil
      #expect(try ChatPrepPlanImport.plan(withoutBaseline, in: db).planChangedSinceStage == nil)
      let plan = try ChatPrepPlanImport.plan(envelope, in: db)
      let beforeFailedApply = try PrepPlanStepRepository.steps(for: menu, in: db)
      try MenuItem.find(dishID).delete().execute(db)
      #expect(throws: ChatPrepPlanImport.Error.dishUnavailable("Beans")) { try ChatPrepPlanImport.plan(envelope, in: db) }
      #expect(throws: ChatPrepPlanImport.Error.dishUnavailable("Beans")) { try ChatPrepPlanImport.apply(plan, keeping: [], in: db, now: now, uuid: { UUID() }) }
      #expect(try PrepPlanStepRepository.steps(for: menu, in: db) == beforeFailedApply)

      let secondMenu = try MenuRepository.addMenu(title: "Other", notes: nil, dayCount: 1, in: db, now: now, uuid: { UUID() })
      _ = try MenuRepository.addRecipeItem(menuID: secondMenu, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let missingMenuEnvelope = ChatAccessStagedPrepPlan(menuID: secondMenu, menuTitle: "Other", dishes: [
        .init(dayOffset: 0, recipeID: recipeID, title: "Beans", steps: []),
      ], planAtStage: [])
      let missingMenuPlan = try ChatPrepPlanImport.plan(missingMenuEnvelope, in: db)
      try Menu.find(secondMenu).delete().execute(db)
      #expect(throws: ChatPrepPlanImport.Error.menuUnavailable) { try ChatPrepPlanImport.plan(missingMenuEnvelope, in: db) }
      #expect(throws: ChatPrepPlanImport.Error.menuUnavailable) { try ChatPrepPlanImport.apply(missingMenuPlan, keeping: [], in: db, now: now, uuid: { UUID() }) }
    }
  }

  @Test func recipeReturnCreatesReviewAndRollsBackOnEmptyBody() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_100_000)
    let recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let envelope = ChatAccessStagedRecipeReturn(recipeID: recipeID, recipeTitle: "Beans", text: "YC-REVISION:\nToast the spices")
      let review = try ChatRecipeReturnImport.stageReview(envelope, in: db, now: now, uuid: { UUID() })
      guard case .recipeItems = review else { Issue.record("Expected a recipe review"); return }
      #expect(try AIHandoff.fetchAll(db).count == 1)
    }
    #expect(throws: AIHandoffIntentImportError.emptyPlan) {
      try database.write { db in
        try ChatRecipeReturnImport.stageReview(
          .init(recipeID: recipeID, recipeTitle: "Beans", text: "YC-MAKE-AHEAD:"),
          in: db, now: now, uuid: { UUID() }
        )
      }
    }
    try database.write { db in
      #expect(try AIHandoff.fetchAll(db).count == 1)
      try Recipe.find(recipeID).update { $0.archived = true }.execute(db)
    }
    #expect(throws: ChatRecipeReturnImportError.recipeUnavailable) {
      try database.write { db in
        try ChatRecipeReturnImport.stageReview(
          .init(recipeID: recipeID, recipeTitle: "Beans", text: "YC-REVISION:\nToast it"),
          in: db, now: now, uuid: { UUID() }
        )
      }
    }
    #expect(try database.read { db in try AIHandoff.fetchAll(db).count } == 1)
  }

  @Test func recipeReturnDropsAnEchoedContractMarker() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_150_000)
    let recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let envelope = ChatAccessStagedRecipeReturn(
        recipeID: recipeID, recipeTitle: "Beans", text: "\(AIHandoffReturnContract.marker)\nYC-REVISION:\nToast the spices"
      )
      let review = try ChatRecipeReturnImport.stageReview(envelope, in: db, now: now, uuid: { UUID() })
      guard case let .recipeItems(_, items) = review else { Issue.record("Expected a recipe review"); return }
      #expect(items.count == 1)
      guard case .recipeAdjustmentBrief = items.first else { Issue.record("Expected only the revision brief"); return }
    }
  }

  @Test func menuImportPreservesOrderKindsAndScales() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_200_000)
    let recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
      let envelope = ChatAccessStagedMenu(title: "Supper", dayCount: 2, items: [
        .init(recipeID: recipeID, title: "Beans", dayOffset: 0, slot: .dinner, note: "Warm", scale: 2),
        .init(recipeID: nil, title: "Green salad", dayOffset: 1, slot: .lunch, note: "Dress at table", scale: nil),
        .init(recipeID: UUID(), title: "Missing roast", dayOffset: 1, slot: .dinner, note: nil, scale: nil),
      ])
      let resolved = try ChatMenuImport.resolve(envelope, in: db)
      #expect(resolved.map(\.resolution) == [.libraryRecipe(recipeID), .newDish, .recipeMissing])
      let menuID = try ChatMenuImport.create(title: envelope.title, dayCount: envelope.dayCount, items: resolved, in: db, now: now, uuid: { UUID() })
      let rows = try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db)
      #expect(rows.map(\.title) == ["Beans", "Green salad", "Missing roast"])
      #expect(rows.map(\.kind) == [.recipe, .note, .note])
      #expect(rows.map(\.recipeID) == [recipeID, nil, nil])
      #expect(try RecipeScaleRepository.scale(for: .menuItem(rows[0].id), in: db) == 2)
    }
  }

  @Test func menuDayReplacementKeepsMatchedIdentityAndUntouchedDays() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_250_000)
    let menuID = UUID()
    let recipeID = UUID()
    let otherRecipeID = UUID()
    try database.write { db in
      try Recipe.insert {
        Recipe(id: recipeID, title: "Souvlaki", dateCreated: now, dateModified: now)
      }.execute(db)
      try Recipe.insert {
        Recipe(id: otherRecipeID, title: "Pie", dateCreated: now, dateModified: now)
      }.execute(db)
      _ = try MenuRepository.addMenu(title: "Thanksgiving Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
      let keptID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: "Sauce aside", in: db, now: now, uuid: { UUID() })
      try RecipeScaleRepository.setScale(2, for: .menuItem(keptID), in: db)
      let groceryListID = UUID()
      let groceryItemID = UUID()
      let grocerySourceID = UUID()
      let prepStepID = UUID()
      try GroceryList.insert { GroceryList(id: groceryListID, title: "Shopping", sortOrder: 0, dateCreated: now, dateModified: now) }.execute(db)
      try GroceryItem.insert { GroceryItem(id: groceryItemID, groceryListID: groceryListID, title: "Pita", sortOrder: 0, dateCreated: now, dateModified: now) }.execute(db)
      try GroceryItemSource.insert {
        GroceryItemSource(id: grocerySourceID, groceryItemID: groceryItemID, origin: .menuPlacement, menuID: menuID, menuItemID: keptID, dateCreated: now)
      }.execute(db)
      try PrepPlanStepRecord.insert {
        PrepPlanStepRecord(id: prepStepID, menuID: menuID, sortOrder: 0, session: "Dinner", task: "Warm pita", sourceDish: keptID)
      }.execute(db)
      let reservationID = try MenuRepository.addNoteItem(menuID: menuID, title: "Bakery pickup", notes: nil, dayOffset: 0, mealSlot: .lunch, in: db, now: now, uuid: { UUID() })
      let foundReservation = try MenuItem.find(reservationID).fetchOne(db)
      var reservation = try #require(foundReservation)
      reservation.kind = .reservation
      try MenuItem.upsert { reservation }.execute(db)
      let removedID = try MenuRepository.addNoteItem(menuID: menuID, title: "Remove me", notes: nil, dayOffset: 0, mealSlot: .breakfast, in: db, now: now, uuid: { UUID() })
      let otherDayID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: otherRecipeID, dayOffset: 1, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let before = try MenuItem.where { $0.menuID.eq(menuID) && $0.dayOffset.eq(0) }.fetchAll(db)
      let staged = before.map { ChatAccessStagedMenuDay.LiveItem(kind: $0.kind, title: $0.title, recipeID: $0.recipeID, slot: $0.mealSlot, note: $0.notes, scale: $0.scale) }
      let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Thanksgiving Week", dayOffset: 0, items: [
        .init(recipeID: recipeID, title: "Souvlaki", dayOffset: 0, slot: .lunch, note: "Serve sauce separately", scale: nil),
        .init(recipeID: nil, title: " bakery pickup ", dayOffset: 0, slot: .lunch, note: nil, scale: nil),
      ], dayAtStage: staged)
      let plan = try ChatMenuDayImport.plan(envelope, in: db)
      #expect(!plan.dayChangedSinceStage)
      #expect(plan.entries.count == 2)
      guard case let .changed(row, changes, .libraryRecipe(id)) = plan.entries[0] else { Issue.record("Expected a changed recipe row"); return }
      #expect(id == recipeID)
      #expect(row.id == keptID)
      #expect(changes.contains(.scale(from: 2, to: 1)))
      guard case let .kept(reservationRow, .newDish) = plan.entries[1] else { Issue.record("Expected the matching reservation to stay"); return }
      #expect(reservationRow.id == reservationID)
      #expect(reservationRow.kind == .reservation)
      #expect(plan.removed.map(\.id) == [removedID])
      try ChatMenuDayImport.apply(plan, keeping: Set(plan.entries.indices), in: db, now: now.addingTimeInterval(1), uuid: { UUID() })
      let after = try MenuItem.where { $0.menuID.eq(menuID) && $0.dayOffset.eq(0) }.fetchAll(db)
      let matched = try #require(after.first { $0.id == keptID })
      #expect(matched.mealSlot == .lunch)
      #expect(matched.notes == "Serve sauce separately")
      #expect(matched.scale == 1)
      #expect(try GroceryItemSource.find(grocerySourceID).fetchOne(db)?.menuItemID == keptID)
      #expect(try PrepPlanStepRecord.find(prepStepID).fetchOne(db)?.sourceDish == keptID)
      #expect(after.contains { $0.id == reservationID && $0.kind == .reservation })
      #expect(!after.contains { $0.id == removedID })
      #expect(try MenuItem.find(otherDayID).fetchOne(db) != nil)
      #expect(try Menu.find(menuID).fetchOne(db)?.dateModified == now.addingTimeInterval(1))
    }
  }

  @Test func menuDayDriftAndDroppedMatchedRowAreVisibleAndApplied() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_260_000)
    let menuID = UUID()
    let recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      let itemID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let staged = ChatAccessStagedMenuDay.LiveItem(kind: .recipe, title: "Soup", recipeID: recipeID, slot: .dinner, note: nil, scale: 1)
      try MenuRepository.updateRecipeItem(itemID: itemID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: "Changed after chat", in: db, now: now)
      let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 0,
        items: [.init(recipeID: recipeID, title: "Soup", dayOffset: 0, slot: .dinner, note: nil, scale: nil)], dayAtStage: [staged])
      let plan = try ChatMenuDayImport.plan(envelope, in: db)
      #expect(plan.dayChangedSinceStage)
      let changedRow = try MenuItem.find(itemID).fetchOne(db)
      #expect(plan.entries == [.changed(row: try #require(changedRow), changes: [.note(nil)], resolution: .libraryRecipe(recipeID))])
      try ChatMenuDayImport.apply(plan, keeping: [], in: db, now: now, uuid: { UUID() })
      #expect(try MenuItem.find(itemID).fetchOne(db) == nil)
    }
  }

  @Test func menuDayApplyRollsBackIfAnAddedRecipeBecomesUnavailable() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_270_000)
    let menuID = UUID()
    let recipeID = UUID()
    let removedID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now) }.execute(db)
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      _ = try MenuRepository.addNoteItem(menuID: menuID, title: "Old dish", notes: nil, dayOffset: 0, mealSlot: .breakfast, in: db, now: now, uuid: { removedID })
    }
    let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 0, items: [
      .init(recipeID: recipeID, title: "Pasta", dayOffset: 0, slot: .dinner, note: nil, scale: nil),
    ], dayAtStage: [])
    let plan = try database.read { db in try ChatMenuDayImport.plan(envelope, in: db) }
    try database.write { db in
      try Recipe.find(recipeID).update { $0.archived = true }.execute(db)
    }
    #expect(throws: MenuRepositoryError.recipeNotFound(recipeID)) {
      try database.write { db in try ChatMenuDayImport.apply(plan, keeping: [0], in: db, now: now, uuid: { UUID() }) }
    }
    #expect(try database.read { db in try MenuItem.find(removedID).fetchOne(db) != nil })
  }

  @Test func menuDayMatchesDuplicateRecipeRowsToTheirOwnSlots() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_280_000)
    let menuID = UUID(), recipeID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: now, dateModified: now) }.execute(db)
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      let breakfastID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .breakfast, notes: nil, in: db, now: now, uuid: { UUID() })
      let dinnerID = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let rows = try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db)
      let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 0, items: [
        .init(recipeID: recipeID, title: "Soup", dayOffset: 0, slot: .breakfast, note: nil, scale: nil),
        .init(recipeID: recipeID, title: "Soup", dayOffset: 0, slot: .dinner, note: nil, scale: nil),
      ], dayAtStage: rows.map { .init(kind: $0.kind, title: $0.title, recipeID: $0.recipeID, slot: $0.mealSlot, note: $0.notes, scale: $0.scale) })
      let plan = try ChatMenuDayImport.plan(envelope, in: db)
      guard case let .kept(breakfast, _) = plan.entries[0], case let .kept(dinner, _) = plan.entries[1] else {
        Issue.record("Each proposal should match the row in its own slot")
        return
      }
      #expect(breakfast.id == breakfastID)
      #expect(dinner.id == dinnerID)
    }
  }

  @Test func archivedRecipeBecomesAFlaggedNoteRowOnApply() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_290_000)
    let menuID = UUID(), archivedID = UUID(), removedID = UUID()
    try database.write { db in
      try Recipe.insert { Recipe(id: archivedID, title: "Old roast", archived: true, dateCreated: now, dateModified: now) }.execute(db)
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      _ = try MenuRepository.addNoteItem(menuID: menuID, title: "Remove", notes: nil, dayOffset: 0, mealSlot: .breakfast, in: db, now: now, uuid: { removedID })
      let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 0,
        items: [.init(recipeID: archivedID, title: "Old roast", dayOffset: 0, slot: .dinner, note: "Rare", scale: 2)], dayAtStage: [])
      let plan = try ChatMenuDayImport.plan(envelope, in: db)
      guard case let .new(item, .recipeMissing) = plan.entries[0] else { Issue.record("The unavailable recipe should be flagged as new"); return }
      #expect(item.title == "Old roast")
      try ChatMenuDayImport.apply(plan, keeping: [0], in: db, now: now, uuid: { UUID() })
      let rows = try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db)
      #expect(rows.count == 1)
      #expect(rows[0].kind == .note)
      #expect(rows[0].recipeID == nil)
      #expect(rows[0].title == "Old roast")
      #expect(rows[0].scale == 2)
      #expect(try MenuItem.find(removedID).fetchOne(db) == nil)
    }
  }

  @Test func menuDayRowsMovingIntoASlotAreOrderedWithThatSlotsProposal() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_300_000)
    let menuID = UUID(), firstRecipeID = UUID(), secondRecipeID = UUID()
    try database.write { db in
      try Recipe.insert {
        Recipe(id: firstRecipeID, title: "A", dateCreated: now, dateModified: now)
      }.execute(db)
      try Recipe.insert {
        Recipe(id: secondRecipeID, title: "B", dateCreated: now, dateModified: now)
      }.execute(db)
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 1, in: db, now: now, uuid: { menuID })
      _ = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: firstRecipeID, dayOffset: 0, mealSlot: .lunch, notes: nil, in: db, now: now, uuid: { UUID() })
      _ = try MenuRepository.addRecipeItem(menuID: menuID, recipeID: secondRecipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 0, items: [
        .init(recipeID: firstRecipeID, title: "A", dayOffset: 0, slot: .dinner, note: nil, scale: nil),
        .init(recipeID: secondRecipeID, title: "B", dayOffset: 0, slot: .dinner, note: nil, scale: nil),
      ], dayAtStage: [])
      let plan = try ChatMenuDayImport.plan(envelope, in: db)
      try ChatMenuDayImport.apply(plan, keeping: [0, 1], in: db, now: now, uuid: { UUID() })
      let rows = try MenuItem.where { $0.menuID.eq(menuID) && $0.dayOffset.eq(0) && $0.mealSlot.eq(MealPlanItemSlot.dinner) }
        .fetchAll(db).sorted { $0.sortOrder < $1.sortOrder }
      #expect(rows.map(\.title) == ["A", "B"])
      #expect(rows.map(\.sortOrder) == [0, 1])
    }
  }

  @Test func menuDayPlanAndApplyRejectDeletedMenusAndRemovedDays() throws {
    @Dependency(\.defaultDatabase) var database
    let now = Date(timeIntervalSinceReferenceDate: 840_310_000)
    let menuID = UUID()
    try database.write { db in
      _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
      _ = try MenuRepository.addNoteItem(menuID: menuID, title: "Day one", notes: nil, dayOffset: 0, mealSlot: .dinner, in: db, now: now, uuid: { UUID() })
    }
    let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Week", dayOffset: 1, items: [
      .init(recipeID: nil, title: "Supper", dayOffset: 1, slot: .dinner, note: nil, scale: nil),
    ], dayAtStage: [])
    let plan = try database.read { db in try ChatMenuDayImport.plan(envelope, in: db) }
    try database.write { db in try Menu.find(menuID).update { $0.dayCount = 1 }.execute(db) }
    #expect(throws: ChatMenuDayImport.Error.dayOutOfRange) {
      try database.read { db in try ChatMenuDayImport.plan(envelope, in: db) }
    }
    #expect(throws: ChatMenuDayImport.Error.dayOutOfRange) {
      try database.write { db in try ChatMenuDayImport.apply(plan, keeping: [0], in: db, now: now, uuid: { UUID() }) }
    }
    #expect(try database.read { db in try MenuItem.where { $0.menuID.eq(menuID) }.fetchAll(db).map(\.title) } == ["Day one"])

    try database.write { db in try Menu.find(menuID).delete().execute(db) }
    #expect(throws: ChatMenuDayImport.Error.menuUnavailable) {
      try database.read { db in try ChatMenuDayImport.plan(envelope, in: db) }
    }
    #expect(throws: ChatMenuDayImport.Error.menuUnavailable) {
      try database.write { db in try ChatMenuDayImport.apply(plan, keeping: [0], in: db, now: now, uuid: { UUID() }) }
    }
    #expect(try database.read { db in try Menu.fetchAll(db).isEmpty })
  }
}
