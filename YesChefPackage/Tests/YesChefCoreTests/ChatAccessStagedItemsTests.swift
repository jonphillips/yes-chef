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
    let newer = Data("{\"format\":\"yc-menu\",\"version\":2,\"title\":\"Supper\",\"dayCount\":1,\"items\":[]}".utf8)
    #expect(throws: ChatAccessStagedEnvelopeError.unsupportedVersion(found: 2, supported: 1)) {
      try JSONDecoder().decode(ChatAccessStagedMenu.self, from: newer)
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
}
