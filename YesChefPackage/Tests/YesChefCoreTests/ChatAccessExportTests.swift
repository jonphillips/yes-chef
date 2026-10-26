import Dependencies
import DependenciesTestSupport
import Foundation
import Testing
import YesChefCore

@Suite(.serialized, .dependencies { try $0.bootstrapDatabase() })
struct ChatAccessExportTests {
  @Test func roundTripsTextOnlyExportAndRejectsNewerVersion() throws {
    let recipeID = UUID()
    var recipe = Recipe(id: recipeID, title: "Beans", dateCreated: .now, dateModified: .now)
    recipe.originalSnapshot = Data("private snapshot".utf8)
    let photo = RecipePhoto(
      id: UUID(), recipeID: recipeID, imageDataReference: "recipePhotos/image",
      displayData: Data([1, 2, 3]), thumbnailData: Data([4, 5]), sortOrder: 0, dateCreated: .now
    )
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: recipe, photos: [photo])
    let export = ChatAccessExport(generatedAt: .now, device: "iPhone", recipes: [bundle], menus: [], mealPlan: [])
    let data = try ChatAccessExportCoding.encode(export)
    let decoded = try ChatAccessExportCoding.decode(data)
    #expect(decoded.recipes.first?.photos.isEmpty == true)
    #expect(decoded.recipes.first?.recipe.originalSnapshot == nil)
    #expect(decoded.format == "yc-library-export")
    #expect(decoded.version == 1)

    let newer = Data("{\"format\":\"yc-library-export\",\"version\":2,\"generatedAt\":0,\"device\":\"iPhone\",\"recipes\":{\"renamed\":true},\"menus\":[],\"mealPlan\":[]}".utf8)
    #expect(throws: ChatAccessExportError.unsupportedVersion(found: 2, supported: 1)) {
      try ChatAccessExportCoding.decode(newer)
    }
    let wrongFormat = Data("{\"format\":\"other\",\"version\":1}".utf8)
    #expect(throws: ChatAccessExportError.unsupportedFormat(found: "other")) {
      try ChatAccessExportCoding.decode(wrongFormat)
    }
  }

  @Test func builderStripsMediaOrdersMenuItemsAndIncludesLocalMealPlanWindow() throws {
    @Dependency(\.defaultDatabase) var database
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let generatedAt = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))!
    let today = calendar.startOfDay(for: generatedAt)
    let recipeID = UUID()
    let menuID = UUID()
    let sectionID = UUID()
    let photoID = UUID()
    let outside31 = calendar.date(byAdding: .day, value: -31, to: today)!
    let firstDay = calendar.date(byAdding: .day, value: -30, to: today)!
    let lastDay = calendar.date(byAdding: .day, value: 60, to: today)!
    let outside61 = calendar.date(byAdding: .day, value: 61, to: today)!
    var persistedRecipe = Recipe(id: recipeID, title: "Beans", dateCreated: generatedAt, dateModified: generatedAt)
    persistedRecipe.originalSnapshot = Data([9])

    try database.write { db in
      try Recipe.insert { persistedRecipe }.execute(db)
      try RecipePhoto.insert { RecipePhoto(id: photoID, recipeID: recipeID, imageDataReference: "photo", displayData: Data([1]), thumbnailData: Data([2]), sortOrder: 0, dateCreated: generatedAt) }.execute(db)
      try IngredientSection.insert { IngredientSection(id: sectionID, recipeID: recipeID, name: "Main", sortOrder: 0) }.execute(db)
      try Menu.insert { Menu(id: menuID, title: "Dinner", dayCount: 2, dateCreated: generatedAt, dateModified: generatedAt) }.execute(db)
      try MenuItem.insert {
        [
          MenuItem(id: UUID(), menuID: menuID, kind: .note, title: "Dinner note", dayOffset: 0, mealSlot: .dinner, sortOrder: 0, dateCreated: generatedAt, dateModified: generatedAt),
          MenuItem(id: UUID(), menuID: menuID, kind: .note, title: "Lunch note", dayOffset: 0, mealSlot: .lunch, sortOrder: 0, dateCreated: generatedAt, dateModified: generatedAt),
          MenuItem(id: UUID(), menuID: menuID, kind: .recipe, recipeID: recipeID, title: "Beans", dayOffset: 1, mealSlot: .breakfast, sortOrder: 0, dateCreated: generatedAt, dateModified: generatedAt),
        ]
      }.execute(db)
      for (index, date) in [outside31, firstDay, lastDay, outside61].enumerated() {
        try MealPlanItem.insert {
          MealPlanItem(id: UUID(), kind: .note, title: "Plan \(index)", scheduledDate: date, mealSlot: .dinner, sortOrder: index, dateCreated: generatedAt, dateModified: generatedAt)
        }.execute(db)
      }
    }

    let export = try database.read { db in
      try ChatAccessExportBuilder.build(in: db, generatedAt: generatedAt, device: "iPad", calendar: calendar)
    }
    let bundle = try #require(export.recipes.first)
    #expect(bundle.photos.isEmpty)
    #expect(bundle.recipe.originalSnapshot == nil)
    #expect(export.menus.first?.items.map(\.title) == ["Lunch note", "Dinner note", "Beans"])
    #expect(export.mealPlan.map(\.title) == ["Plan 1", "Plan 2"])
  }
}
