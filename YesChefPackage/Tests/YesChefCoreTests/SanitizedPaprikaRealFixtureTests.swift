import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct SanitizedPaprikaRealFixtureTests {
    @Test
    func sanitizedRealFixtureExercisesParsePreviewImportIdempotencyAndImages() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)

      expectNoDifference(
        parseResult.recipes.map(\.title),
        [
          "Base Curry Sauce",
          "Garlicky Spiced Chicken and Potato Traybake",
          "Ginger-Scallion Sauce (Jiāngcōngróng / 薑蔥蓉)",
          "Kung Pao Chicken",
          "Missing Image Beans",
        ]
      )
      expectNoDifference(parseResult.warnings.map(\.kind), [.missingPhoto])

      let missingImageRecipe = try #require(parseResult.recipes.first { $0.title == "Missing Image Beans" })
      expectNoDifference(missingImageRecipe.photos.map(\.path), ["Images/missing/beans.jpg"])
      expectNoDifference(missingImageRecipe.photos.map(\.isAvailable), [false])
      expectNoDifference(missingImageRecipe.photos.map(\.displayData), [nil])

      let importDate = Date(timeIntervalSinceReferenceDate: 803_100_000)
      var firstBundleUUIDs = SampleUUIDSequence(start: 30_000)
      let firstBundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: importDate, uuid: { firstBundleUUIDs.next() })
      }

      let preview = try database.read { db in
        RecipeRepository.previewImportBundles(
          firstBundles,
          against: try RecipeImportRef.fetchAll(db)
        )
      }
      expectNoDifference(preview.newCount, 5)
      expectNoDifference(preview.alreadyImportedCount, 0)
      expectNoDifference(preview.titleOnlyCollisionCount, 0)
      expectNoDifference(preview.warnings, [])

      let kungPao = try #require(firstBundles.first { $0.recipe.title == "Kung Pao Chicken" })
      expectNoDifference(kungPao.recipe.rating, 5)
      expectNoDifference(kungPao.recipe.difficulty, .medium)
      expectNoDifference(kungPao.source?.name, "Cook's Illustrated")
      expectNoDifference(kungPao.ingredientSections.map(\.name), ["CHICKEN", "SAUCE"])
      expectNoDifference(
        kungPao.ingredientLines.map(\.originalText),
        [
          "1 1/2 pounds boneless chicken thighs",
          "2 tablespoons soy sauce",
          "2 tablespoons black vinegar",
          "1 tablespoon toasted sesame oil",
        ]
      )

      let traybake = try #require(
        firstBundles.first { $0.recipe.title == "Garlicky Spiced Chicken and Potato Traybake" }
      )
      expectNoDifference(traybake.recipe.rating, nil)
      expectNoDifference(traybake.recipe.difficulty, nil)
      expectNoDifference(traybake.source?.name, "Milk Street")
      expectNoDifference(traybake.ingredientSections.map(\.name), [nil])
      expectNoDifference(
        traybake.ingredientLines.map(\.originalText),
        [
          "1/4 CUP EXTRA-VIRGIN OLIVE OIL",
          "2 TEASPOONS POMEGRANATE MOLASSES",
          "KOSHER SALT AND GROUND BLACK PEPPER",
          "3 POUNDS BONE-IN CHICKEN PARTS",
        ]
      )

      let referenceRecipe = try #require(firstBundles.first { $0.recipe.title == "Base Curry Sauce" })
      expectNoDifference(referenceRecipe.photos.map(\.originalSourcePath), ["Images/base-curry/scan-page.jpg"])
      expectNoDifference(referenceRecipe.photos.map(\.kind), [.referenceDocument])
      expectNoDifference(referenceRecipe.photos.map { $0.displayData != nil }, [true])
      expectNoDifference(referenceRecipe.photos.map { $0.thumbnailData != nil }, [true])
      expectNoDifference(referenceRecipe.photos.map(\.pixelWidth), [1_200])
      expectNoDifference(referenceRecipe.photos.map(\.pixelHeight), [900])

      let unicodeRecipe = try #require(
        firstBundles.first { $0.recipe.title == "Ginger-Scallion Sauce (Jiāngcōngróng / 薑蔥蓉)" }
      )
      expectNoDifference(unicodeRecipe.recipe.rating, nil)
      expectNoDifference(unicodeRecipe.recipe.difficulty, nil)
      expectNoDifference(unicodeRecipe.source?.name, "America's Test Kitchen")
      expectNoDifference(unicodeRecipe.photos.map(\.originalSourcePath), ["Images/simple/hero.jpg"])
      expectNoDifference(unicodeRecipe.photos.map(\.kind), [.hero])
      expectNoDifference(unicodeRecipe.photos.map { $0.displayData != nil }, [true])
      expectNoDifference(unicodeRecipe.recipe.originalImportText?.contains("薑蔥蓉"), true)
      let unicodeSnapshotData = try #require(unicodeRecipe.recipe.originalSnapshot)
      let unicodeSnapshot = try RecipeBundleCoding.decodeSnapshot(unicodeSnapshotData)
      expectNoDifference(unicodeSnapshot.recipe.title, "Ginger-Scallion Sauce (Jiāngcōngróng / 薑蔥蓉)")

      let firstSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 31_000)
        return try RecipeRepository.importBundles(
          firstBundles,
          in: db,
          now: importDate,
          uuid: { repositoryUUIDs.next() }
        )
      }
      let countsAfterFirstImport = try database.read { db in
        try SanitizedRealFixtureEntityCounts.fetch(in: db)
      }

      var secondBundleUUIDs = SampleUUIDSequence(start: 32_000)
      let secondBundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: importDate.addingTimeInterval(60), uuid: { secondBundleUUIDs.next() })
      }
      let secondPreview = try database.read { db in
        RecipeRepository.previewImportBundles(
          secondBundles,
          against: try RecipeImportRef.fetchAll(db)
        )
      }
      let secondSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 33_000)
        return try RecipeRepository.importBundles(
          secondBundles,
          in: db,
          now: importDate.addingTimeInterval(60),
          uuid: { repositoryUUIDs.next() }
        )
      }
      let countsAfterSecondImport = try database.read { db in
        try SanitizedRealFixtureEntityCounts.fetch(in: db)
      }

      expectNoDifference(firstSummary.importedCount, 5)
      expectNoDifference(firstSummary.alreadyImportedCount, 0)
      expectNoDifference(firstSummary.warnings, [])
      expectNoDifference(secondPreview.newCount, 0)
      expectNoDifference(secondPreview.alreadyImportedCount, 5)
      expectNoDifference(secondSummary.importedCount, 0)
      expectNoDifference(secondSummary.alreadyImportedCount, 5)
      expectNoDifference(secondSummary.warnings, [])
      expectNoDifference(
        countsAfterFirstImport,
        SanitizedRealFixtureEntityCounts(
          recipes: 5,
          recipeSources: 4,
          recipeImportRefs: 5,
          ingredientSections: 6,
          ingredientLines: 14,
          instructionSections: 5,
          instructionSteps: 7,
          recipeNotes: 0,
          recipePhotos: 2,
          tags: 0,
          categories: 5,
          equipment: 0,
          recipeTags: 0,
          recipeCategories: 5,
          recipeEquipment: 0
        )
      )
      expectNoDifference(countsAfterSecondImport, countsAfterFirstImport)

      let importedDetails = try database.read { db in
        try firstSummary.importedIDs.compactMap { try RecipeRepository.fetchDetail(recipeID: $0, in: db) }
      }
      let detailsByTitle = Dictionary(uniqueKeysWithValues: importedDetails.map { ($0.recipe.title, $0) })
      let importedReferenceRecipe = try #require(detailsByTitle["Base Curry Sauce"])
      expectNoDifference(importedReferenceRecipe.photos.map(\.originalSourcePath), ["Images/base-curry/scan-page.jpg"])
      expectNoDifference(importedReferenceRecipe.photos.map(\.kind), [.referenceDocument])

      let importedMissingImageRecipe = try #require(detailsByTitle["Missing Image Beans"])
      expectNoDifference(importedMissingImageRecipe.photos, [])

      let rows = try database.read { db in
        try RecipeListRequest().fetch(db)
      }
      let referenceRow = try #require(rows.first { $0.recipe.title == "Base Curry Sauce" })
      expectNoDifference(referenceRow.thumbnailData, nil)
      let unicodeRow = try #require(rows.first { $0.recipe.title == "Ginger-Scallion Sauce (Jiāngcōngróng / 薑蔥蓉)" })
      expectNoDifference(unicodeRow.thumbnailData != nil, true)
    }

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/PaprikaHTML/SanitizedRealExport", isDirectory: true)
    }
  }
}

private struct SanitizedRealFixtureEntityCounts: Equatable {
  var recipes: Int
  var recipeSources: Int
  var recipeImportRefs: Int
  var ingredientSections: Int
  var ingredientLines: Int
  var instructionSections: Int
  var instructionSteps: Int
  var recipeNotes: Int
  var recipePhotos: Int
  var tags: Int
  var categories: Int
  var equipment: Int
  var recipeTags: Int
  var recipeCategories: Int
  var recipeEquipment: Int

  static func fetch(in db: Database) throws -> Self {
    Self(
      recipes: try Recipe.fetchAll(db).count,
      recipeSources: try RecipeSource.fetchAll(db).count,
      recipeImportRefs: try RecipeImportRef.fetchAll(db).count,
      ingredientSections: try IngredientSection.fetchAll(db).count,
      ingredientLines: try IngredientLine.fetchAll(db).count,
      instructionSections: try InstructionSection.fetchAll(db).count,
      instructionSteps: try InstructionStep.fetchAll(db).count,
      recipeNotes: try RecipeNote.fetchAll(db).count,
      recipePhotos: try RecipePhoto.fetchAll(db).count,
      tags: try Tag.fetchAll(db).count,
      categories: try YesChefCore.Category.fetchAll(db).count,
      equipment: try Equipment.fetchAll(db).count,
      recipeTags: try RecipeTag.fetchAll(db).count,
      recipeCategories: try RecipeCategory.fetchAll(db).count,
      recipeEquipment: try RecipeEquipment.fetchAll(db).count
    )
  }
}
