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
}
