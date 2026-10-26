import Foundation
import Testing
import YesChefCore

struct ChatAccessExportTests {
  @Test func roundTripsTextOnlyExportAndRejectsNewerVersion() throws {
    var recipe = Recipe(id: UUID(), title: "Beans", dateCreated: .now, dateModified: .now)
    recipe.originalSnapshot = Data("private snapshot".utf8)
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: recipe)
    let export = ChatAccessExport(generatedAt: .now, device: "iPhone", recipes: [bundle], menus: [], mealPlan: [])
    let data = try ChatAccessExportCoding.encode(export)
    let decoded = try ChatAccessExportCoding.decode(data)
    #expect(decoded.recipes.first?.photos.isEmpty == true)
    #expect(decoded.recipes.first?.recipe.originalSnapshot == nil)
    #expect(decoded.format == "yc-library-export")
    #expect(decoded.version == 1)

    let newer = Data("{\"format\":\"yc-library-export\",\"version\":2,\"generatedAt\":0,\"device\":\"iPhone\",\"recipes\":[],\"menus\":[],\"mealPlan\":[]}".utf8)
    #expect(throws: ChatAccessExportError.unsupportedVersion(found: 2, supported: 1)) {
      try ChatAccessExportCoding.decode(newer)
    }
  }
}
