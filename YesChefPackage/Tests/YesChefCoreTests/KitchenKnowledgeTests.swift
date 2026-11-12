import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite(.serialized, .dependencies {
    $0.context = .live
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefKitchenKnowledgeTests-\(UUID().uuidString).sqlite").path
    try $0.bootstrapDatabase(path: path, syncMode: .disabled)
  })
  struct KitchenKnowledgeTests {
    @Test
    func cleanupDeletesOnlyRowsCoveredByBuiltInKnowledge() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_800_000)
      let knowledge = BuiltInKnowledge(
        aliases: ["tomato": "tomatoes"],
        areas: ["lemon": "Produce"],
        trips: ["mint": "fresh"],
        keepers: [],
        pantryStaples: []
      )
      try database.write { db in
        try IngredientNameFix.insert {
          IngredientNameFix(id: UUID(), fromName: "tomato", toName: "tomatoes", dateModified: now)
        }.execute(db)
        try IngredientNameFix.insert {
          IngredientNameFix(id: UUID(), fromName: "mint", toName: "herb", dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "lemon", area: "Produce", source: .user, dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "lemon", area: "Deli", source: .user, dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "lemon", area: "Deli", source: .model, dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "sumac", area: "Spices", source: .model, dateModified: now)
        }.execute(db)
        try GroceryTripAssignment.insert {
          GroceryTripAssignment(id: UUID(), canonicalName: "mint", trip: .fresh, dateModified: now)
        }.execute(db)
        try GroceryTripAssignment.insert {
          GroceryTripAssignment(id: UUID(), canonicalName: "onion", trip: .fresh, dateModified: now)
        }.execute(db)

        #expect(try BuiltInKnowledgeCleanup.run(in: db, knowledge: knowledge) == 4)
        #expect(try IngredientNameFix.fetchAll(db).map(\.fromName) == ["mint"])
        #expect(try GroceryAreaAssignment.fetchAll(db).map(\.canonicalName).sorted() == ["lemon", "sumac"])
        #expect(try GroceryTripAssignment.fetchAll(db).map(\.canonicalName) == ["onion"])
      }
    }

    @Test
    func exportContainsOnlyPromotableKnowledge() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 900_800_100)
      try database.write { db in
        try IngredientNameFix.insert {
          IngredientNameFix(id: UUID(), fromName: "mint", toName: "herb", dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "mint", area: "Produce", source: .user, dateModified: now)
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(
            id: UUID(), canonicalName: "sumac", area: "Spices", source: .model,
            dateModified: now, reviewedAt: now
          )
        }.execute(db)
        try GroceryAreaAssignment.insert {
          GroceryAreaAssignment(id: UUID(), canonicalName: "guess", area: "Deli", source: .model, dateModified: now)
        }.execute(db)
        try GroceryTripAssignment.insert {
          GroceryTripAssignment(id: UUID(), canonicalName: "mint", trip: .fresh, dateModified: now)
        }.execute(db)
        try PantryItem.insert {
          PantryItem(id: UUID(), title: "butter", sortOrder: 0, dateCreated: now, dateModified: now)
        }.execute(db)

        let export = try KitchenKnowledgeExport.build(in: db, exportedAt: now, variant: .dev)
        #expect(export.nameFixes.count == 1)
        #expect(export.areas.map(\.name).sorted() == ["mint", "sumac"])
        #expect(export.trips.count == 1)
        #expect(export.variant == .dev)
        let data = try export.encoded()
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("butter"))
        #expect(!json.contains("guess"))
      }
    }
  }
}
