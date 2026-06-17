import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PaprikaHTMLImportTests {
    @Test
    func parseExportImportsPresentPagesAndReportsMissingFiles() throws {
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)

      expectNoDifference(
        result.recipes.map(\.title),
        [
          "Photo Board Curry",
          "Weeknight Tomato Pasta",
        ]
      )
      expectNoDifference(
        result.warnings.map(\.kind),
        [
          .missingRecipePages,
          .missingPhoto,
        ]
      )

      let indexWarning = try #require(result.warnings.first { $0.kind == .missingRecipePages })
      expectNoDifference(indexWarning.affectedCount, 1)
      expectNoDifference(indexWarning.examples, ["Recipes/Missing Recipe.html"])

      let curry = try #require(result.recipes.first { $0.title == "Photo Board Curry" })
      expectNoDifference(
        curry.photos.map(\.path),
        [
          "Images/curry/step1.jpg",
          "Images/curry/missing.jpg",
        ]
      )
      expectNoDifference(curry.photos.map(\.isAvailable), [true, false])
      expectNoDifference(curry.photos.map(\.kind), [.hero, .gallery])
      expectNoDifference(curry.photos.map(\.caption), ["Prep board", "Missing board"])
      expectNoDifference(curry.photos.first?.displayData != nil, true)
      expectNoDifference(curry.photos.last?.displayData, nil)
    }

    @Test
    func parseRecipeMapsPaprikaFieldsIntoRecipeBundle() throws {
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let pasta = try #require(result.recipes.first { $0.title == "Weeknight Tomato Pasta" })

      expectNoDifference(pasta.summary, "A synthetic parser fixture.")
      expectNoDifference(pasta.categoryNames, ["Dinner", "Pasta"])
      expectNoDifference(pasta.servingsText, "Serves 4")
      expectNoDifference(pasta.prepTimeMinutes, 12)
      expectNoDifference(pasta.cookTimeMinutes, 70)
      expectNoDifference(pasta.sourceName, "Example Kitchen")
      expectNoDifference(pasta.sourceURL, "https://example.com/pasta?from=fixture&unit=test")
      expectNoDifference(
        pasta.ingredients,
        [
          "1 1/2 cups crushed tomatoes",
          "Kosher salt, to taste",
        ]
      )
      expectNoDifference(
        pasta.instructions,
        [
          "Warm the oil.",
          "Cook the sauce.",
        ]
      )
      expectNoDifference(pasta.notes, ["Use the wide pan.\n\nLeftovers reheat well."])

      var uuids = SampleUUIDSequence(start: 1_000)
      let now = Date(timeIntervalSinceReferenceDate: 802_100_000)
      let bundle = try pasta.makeRecipeBundle(now: now, uuid: { uuids.next() })

      expectNoDifference(bundle.recipe.title, "Weeknight Tomato Pasta")
      expectNoDifference(bundle.recipe.summary, "A synthetic parser fixture.")
      expectNoDifference(bundle.recipe.servings, 4)
      expectNoDifference(bundle.recipe.servingsText, "Serves 4")
      expectNoDifference(bundle.recipe.prepTimeMinutes, 12)
      expectNoDifference(bundle.recipe.cookTimeMinutes, 70)
      expectNoDifference(bundle.recipe.totalTimeMinutes, 82)
      expectNoDifference(bundle.recipe.rating, 4)
      expectNoDifference(bundle.recipe.originalImportText?.contains("schema.org/Recipe"), true)
      expectNoDifference(bundle.source?.name, "Example Kitchen")
      expectNoDifference(bundle.source?.url, "https://example.com/pasta?from=fixture&unit=test")
      expectNoDifference(bundle.source?.importedFrom, "Paprika HTML")
      expectNoDifference(bundle.ingredients, pasta.ingredients)
      expectNoDifference(bundle.ingredientLines.first?.quantity, 1.5)
      expectNoDifference(bundle.instructions, pasta.instructions)
      expectNoDifference(bundle.notes, pasta.notes)
      expectNoDifference(bundle.categoryNames, ["Dinner", "Pasta"])

      let snapshotData = try #require(bundle.recipe.originalSnapshot)
      let snapshot = try RecipeBundleCoding.decodeSnapshot(snapshotData)
      expectNoDifference(snapshot.recipe.title, "Weeknight Tomato Pasta")
      expectNoDifference(snapshot.ingredients, pasta.ingredients)
      expectNoDifference(snapshot.categories, ["Dinner", "Pasta"])
    }

    @Test
    func recipeBundleKeepsOnlyAvailableImportedPhotos() throws {
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let curry = try #require(result.recipes.first { $0.title == "Photo Board Curry" })
      var uuids = SampleUUIDSequence(start: 2_000)
      let bundle = try curry.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 802_100_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(
        bundle.photos.map(\.imageDataReference),
        bundle.photos.map { "recipePhotos/\($0.id.uuidString)" }
      )
      expectNoDifference(bundle.photos.map(\.originalSourcePath), ["Images/curry/step1.jpg"])
      expectNoDifference(bundle.photos.map(\.kind), [.hero])
      expectNoDifference(bundle.photos.map { $0.displayData != nil }, [true])
      expectNoDifference(bundle.photos.map(\.source), [.imported])
    }

    @Test
    func importBundleWritesPaprikaRecipeIntoLibrary() throws {
      @Dependency(\.defaultDatabase) var database
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let curry = try #require(result.recipes.first { $0.title == "Photo Board Curry" })
      let now = Date(timeIntervalSinceReferenceDate: 802_100_000)
      var importUUIDs = SampleUUIDSequence(start: 3_000)
      let bundle = try curry.makeRecipeBundle(now: now, uuid: { importUUIDs.next() })

      let recipeID = try database.write { db in
        var categoryUUIDs = SampleUUIDSequence(start: 4_000)
        return try RecipeRepository.importBundle(
          bundle,
          in: db,
          now: now,
          uuid: { categoryUUIDs.next() }
        )
      }

      let detail = try database.read { db in
        try RecipeRepository.fetchDetail(recipeID: recipeID, in: db)
      }
      let imported = try #require(detail)

      expectNoDifference(imported.recipe.title, "Photo Board Curry")
      expectNoDifference(imported.recipe.originalImportText?.contains("Photo Board Curry"), true)
      expectNoDifference(imported.ingredientLines.map(\.originalText), ["see attached photo"])
      expectNoDifference(imported.instructionSteps.map(\.text), ["See attached photo."])
      expectNoDifference(imported.categories.map(\.name), ["Import Fixture"])
      expectNoDifference(imported.photos.map(\.originalSourcePath), ["Images/curry/step1.jpg"])
      expectNoDifference(imported.photos.map(\.kind), [.hero])
      expectNoDifference(imported.photos.map(\.source), [.imported])
      expectNoDifference(
        imported.photos.map { $0.imageDataReference == $0.originalSourcePath },
        [false]
      )
      expectNoDifference(imported.photos.map { $0.displayData != nil }, [true])

      let recipeRows = try database.read { db in
        try RecipeListRequest().fetch(db)
      }
      let row = try #require(recipeRows.first { $0.recipe.id == recipeID })
      expectNoDifference(row.thumbnailData != nil, true)
    }

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/PaprikaHTML/SyntheticExport", isDirectory: true)
    }
  }
}
