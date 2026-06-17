import CustomDump
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
        curry.photos,
        [
          PaprikaHTMLPhotoReference(path: "Images/curry/hero.jpg", isAvailable: true),
          PaprikaHTMLPhotoReference(path: "Images/curry/step1.jpg", caption: "Prep board", isAvailable: true),
          PaprikaHTMLPhotoReference(path: "Images/curry/missing.jpg", caption: "Missing board", isAvailable: false),
        ]
      )
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
        [
          "Images/curry/hero.jpg",
          "Images/curry/step1.jpg",
        ]
      )
      expectNoDifference(bundle.photos.map(\.source), [.imported, .imported])
    }

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/PaprikaHTML/SyntheticExport", isDirectory: true)
    }
  }
}
