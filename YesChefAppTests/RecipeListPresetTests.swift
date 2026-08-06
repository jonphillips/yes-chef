import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct RecipeListPresetTests {
  @Test
  func legacyTagSelectionMatchesDifferentlyCasedCanonicalCategory() async throws {
    let recipeID = SampleUUIDSequence.uuid(59_001)
    let categoryID = SampleUUIDSequence.uuid(59_002)
    let now = Date(timeIntervalSinceReferenceDate: 815_300_000)
    let state = try JSONDecoder().decode(
      RecipeListPresetState.self,
      from: Data(
        """
        {
          "libraryScope": "main",
          "searchText": "",
          "selectedAuthorNames": [],
          "selectedCategoryNames": [],
          "selectedCourse": null,
          "selectedCuisine": null,
          "selectedSourceNames": [],
          "selectedTagNames": ["Veg"],
          "showsFavoritesOnly": false,
          "showsPhotosOnly": false,
          "sortOrder": "title"
        }
        """.utf8
      )
    )

    expectNoDifference(state.selectedCategoryNames, ["Veg"])

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Vegetable Side", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Category.insert {
          Category(id: categoryID, name: "veg", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(
            id: SampleUUIDSequence.uuid(59_003),
            recipeID: recipeID,
            categoryID: categoryID
          )
        }
        .execute(db)
      }

      let model = RecipeLibraryModel()
      try await model.$recipeRows.load()
      expectNoDifference(model.recipeCount(for: state), 1)

      model.applyListPreset(
        RecipeListPreset(
          id: SampleUUIDSequence.uuid(59_004),
          name: "Vegetables",
          state: state,
          dateCreated: now,
          dateModified: now
        )
      )

      expectNoDifference(model.selectedCategoryNames, Set(["veg"]))
      expectNoDifference(model.visibleRecipeRows.map(\.recipe.id), [recipeID])
    }
  }
}
