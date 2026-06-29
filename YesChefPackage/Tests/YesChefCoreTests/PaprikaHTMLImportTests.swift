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
          "All Caps Traybake",
          "Layered Enchiladas",
          "Photo Board Curry",
          "Title Only Collision",
          "Title Only Collision",
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
      expectNoDifference(bundle.recipe.difficulty, nil)
      expectNoDifference(bundle.recipe.originalImportText?.contains("schema.org/Recipe"), true)
      expectNoDifference(bundle.source?.name, "Example Kitchen")
      expectNoDifference(bundle.source?.url, "https://example.com/pasta?from=fixture&unit=test")
      expectNoDifference(bundle.source?.author, nil)
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
    func parsePromotesIngredientSectionHeadingsAndRecoversDifficulty() throws {
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let enchiladas = try #require(result.recipes.first { $0.title == "Layered Enchiladas" })

      expectNoDifference(enchiladas.difficulty, .medium)
      expectNoDifference(
        enchiladas.ingredients,
        [
          "CHICKEN",
          "2 cups shredded chicken",
          "Kosher salt, to taste",
          "SAUCE",
          "1 can crushed tomatoes",
          "2 chipotle peppers",
        ]
      )

      var uuids = SampleUUIDSequence(start: 9_000)
      let bundle = try enchiladas.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 802_500_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(bundle.recipe.difficulty, .medium)
      expectNoDifference(bundle.ingredientSections.map(\.name), ["CHICKEN", "SAUCE"])
      expectNoDifference(bundle.ingredientSections.map(\.sortOrder), [0, 1])

      let chickenSection = try #require(bundle.ingredientSections.first { $0.name == "CHICKEN" })
      let sauceSection = try #require(bundle.ingredientSections.first { $0.name == "SAUCE" })
      expectNoDifference(
        bundle.ingredientLines.filter { $0.sectionID == chickenSection.id }.map(\.originalText),
        ["2 cups shredded chicken", "Kosher salt, to taste"]
      )
      expectNoDifference(
        bundle.ingredientLines.filter { $0.sectionID == sauceSection.id }.map(\.originalText),
        ["1 can crushed tomatoes", "2 chipotle peppers"]
      )
      // Section headings are not themselves shoppable ingredient lines.
      expectNoDifference(
        bundle.ingredientLines.map(\.originalText).contains("CHICKEN"),
        false
      )
      // sortOrder runs globally across sections.
      expectNoDifference(bundle.ingredientLines.map(\.sortOrder), [0, 1, 2, 3])
    }

    @Test
    func parseKeepsFullyUppercasedListAsOneSectionWithoutFalseHeadings() throws {
      let result = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let traybake = try #require(result.recipes.first { $0.title == "All Caps Traybake" })

      var uuids = SampleUUIDSequence(start: 9_500)
      let bundle = try traybake.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 802_600_000),
        uuid: { uuids.next() }
      )

      // Every line is uppercase, so casing carries no signal: no line is promoted to a
      // heading and the quantity-less "KOSHER SALT AND GROUND BLACK PEPPER" stays an
      // ingredient (preserve over interpret).
      expectNoDifference(bundle.ingredientSections.map(\.name), [nil])
      expectNoDifference(
        bundle.ingredientLines.map(\.originalText),
        [
          "2 POUNDS CHICKEN PARTS",
          "KOSHER SALT AND GROUND BLACK PEPPER",
          "1 POUND RED POTATOES",
        ]
      )
    }

    @Test
    func recipeBundleNormalizesKnownSourceDomainsWithoutInferringAuthor() throws {
      let recipe = PaprikaHTMLRecipe(
        title: "Kung Pao Chicken",
        sourceName: "www.cooksillustrated.com",
        sourceURL: "https://www.cooksillustrated.com/recipes/11227-kung-pao-chicken",
        originalHTML: "<html></html>"
      )

      var uuids = SampleUUIDSequence(start: 1_100)
      let bundle = try recipe.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 802_200_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(bundle.source?.name, "Cook's Illustrated")
      expectNoDifference(bundle.source?.url, "https://www.cooksillustrated.com/recipes/11227-kung-pao-chicken")
      expectNoDifference(bundle.source?.author, nil)
    }

    @Test
    func recipeBundleKeepsNonDomainSourceLabels() throws {
      let recipe = PaprikaHTMLRecipe(
        title: "Source Label Test",
        sourceName: "Example Kitchen",
        sourceURL: "https://example.com/recipe",
        originalHTML: "<html></html>"
      )

      var uuids = SampleUUIDSequence(start: 1_200)
      let bundle = try recipe.makeRecipeBundle(
        now: Date(timeIntervalSinceReferenceDate: 802_300_000),
        uuid: { uuids.next() }
      )

      expectNoDifference(bundle.source?.name, "Example Kitchen")
      expectNoDifference(bundle.source?.author, nil)
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

      let importResult = try database.write { db in
        var categoryUUIDs = SampleUUIDSequence(start: 4_000)
        return try RecipeRepository.importBundle(
          bundle,
          in: db,
          now: now,
          uuid: { categoryUUIDs.next() }
        )
      }

      let detail = try database.read { db in
        try RecipeRepository.fetchDetail(recipeID: importResult.recipeID, in: db)
      }
      let imported = try #require(detail)

      expectNoDifference(importResult.outcome, .imported)
      expectNoDifference(importResult.warnings, [])
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
      let row = try #require(recipeRows.first { $0.recipe.id == importResult.recipeID })
      expectNoDifference(row.thumbnailData != nil, true)
      expectNoDifference(row.categoryNames, ["Import Fixture"])
      expectNoDifference(row.tagNames, [])
    }

    @Test
    func importBundlesAreIdempotentPerEntityAndWarnOnTitleOnlyCollision() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let now = Date(timeIntervalSinceReferenceDate: 802_400_000)

      var firstBundleUUIDs = SampleUUIDSequence(start: 5_000)
      let firstBundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: now, uuid: { firstBundleUUIDs.next() })
      }
      let firstSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 6_000)
        return try RecipeRepository.importBundles(
          firstBundles,
          in: db,
          now: now,
          uuid: { repositoryUUIDs.next() }
        )
      }
      let countsAfterFirstImport = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }

      var secondBundleUUIDs = SampleUUIDSequence(start: 7_000)
      let secondBundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: now.addingTimeInterval(60), uuid: { secondBundleUUIDs.next() })
      }
      let secondSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 8_000)
        return try RecipeRepository.importBundles(
          secondBundles,
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { repositoryUUIDs.next() }
        )
      }
      let countsAfterSecondImport = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }

      expectNoDifference(firstSummary.importedCount, 6)
      expectNoDifference(firstSummary.alreadyImportedCount, 0)
      expectNoDifference(
        firstSummary.results.filter { $0.title == "Title Only Collision" }.map(\.outcome),
        [.imported, .imported]
      )
      expectNoDifference(firstSummary.warnings.map(\.kind), [.titleOnlyCollision])
      expectNoDifference(
        countsAfterFirstImport,
        LibraryEntityCounts(
          recipes: 6,
          recipeSources: 1,
          recipeImportRefs: 6,
          ingredientSections: 7,
          ingredientLines: 12,
          instructionSections: 6,
          instructionSteps: 8,
          recipeNotes: 1,
          recipePhotos: 1,
          tags: 0,
          categories: 3,
          equipment: 0,
          recipeTags: 0,
          recipeCategories: 3,
          recipeEquipment: 0
        )
      )

      expectNoDifference(secondSummary.importedCount, 0)
      expectNoDifference(secondSummary.alreadyImportedCount, 6)
      expectNoDifference(secondSummary.warnings, [])
      expectNoDifference(
        secondSummary.results.first { $0.title == "Weeknight Tomato Pasta" }?.outcome,
        .alreadyImported
      )
      expectNoDifference(countsAfterSecondImport, countsAfterFirstImport)
    }

    @Test
    func previewClassifiesImportWithoutWriting() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let now = Date(timeIntervalSinceReferenceDate: 802_700_000)
      let pasta = try #require(parseResult.recipes.first { $0.title == "Weeknight Tomato Pasta" })
      var existingBundleUUIDs = SampleUUIDSequence(start: 10_000)
      let existingBundle = try pasta.makeRecipeBundle(now: now, uuid: { existingBundleUUIDs.next() })

      try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 10_500)
        try RecipeRepository.importBundle(
          existingBundle,
          in: db,
          now: now,
          uuid: { repositoryUUIDs.next() }
        )
      }
      let countsBeforePreview = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }

      var previewBundleUUIDs = SampleUUIDSequence(start: 11_000)
      let previewBundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: now.addingTimeInterval(60), uuid: { previewBundleUUIDs.next() })
      }
      let preview = try database.read { db in
        RecipeRepository.previewImportBundles(
          previewBundles,
          against: try RecipeImportRef.fetchAll(db)
        )
      }
      let countsAfterPreview = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }

      expectNoDifference(
        preview.results.first { $0.title == "Weeknight Tomato Pasta" }?.status,
        .alreadyImported
      )
      expectNoDifference(
        preview.results.first { $0.title == "Photo Board Curry" }?.status,
        .new
      )
      expectNoDifference(
        preview.results.filter { $0.title == "Title Only Collision" }.map(\.status),
        [.new, .titleOnlyCollision]
      )
      expectNoDifference(preview.warnings.map(\.kind), [.titleOnlyCollision])
      expectNoDifference(countsAfterPreview, countsBeforePreview)
    }

    @Test
    func rollbackImportedBatchReturnsEntityCountsToBaseline() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let now = Date(timeIntervalSinceReferenceDate: 802_800_000)
      let baselineCounts = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }
      var bundleUUIDs = SampleUUIDSequence(start: 12_000)
      let bundles = try parseResult.recipes.map { recipe in
        try recipe.makeRecipeBundle(now: now, uuid: { bundleUUIDs.next() })
      }
      let importSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 12_500)
        return try RecipeRepository.importBundles(
          bundles,
          in: db,
          now: now,
          uuid: { repositoryUUIDs.next() }
        )
      }

      let rollback = try database.write { db in
        try RecipeRepository.rollbackImportedRecipes(recipeIDs: importSummary.importedIDs, in: db)
      }
      let countsAfterRollback = try database.read { db in
        try LibraryEntityCounts.fetch(in: db)
      }

      expectNoDifference(rollback.recipes, 6)
      expectNoDifference(rollback.recipeImportRefs, 6)
      expectNoDifference(rollback.categories, 3)
      expectNoDifference(countsAfterRollback, baselineCounts)
    }

    @Test
    func rollbackBatchLeavesDisjointBatchIntact() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let pasta = try #require(parseResult.recipes.first { $0.title == "Weeknight Tomato Pasta" })
      let curry = try #require(parseResult.recipes.first { $0.title == "Photo Board Curry" })
      let firstDate = Date(timeIntervalSinceReferenceDate: 802_900_000)
      let secondDate = firstDate.addingTimeInterval(60)
      var firstBundleUUIDs = SampleUUIDSequence(start: 13_000)
      let firstBundle = try pasta.makeRecipeBundle(now: firstDate, uuid: { firstBundleUUIDs.next() })
      var secondBundleUUIDs = SampleUUIDSequence(start: 13_500)
      let secondBundle = try curry.makeRecipeBundle(now: secondDate, uuid: { secondBundleUUIDs.next() })

      let firstSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 14_000)
        return try RecipeRepository.importBundles(
          [firstBundle],
          in: db,
          now: firstDate,
          uuid: { repositoryUUIDs.next() }
        )
      }
      let secondSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 14_500)
        return try RecipeRepository.importBundles(
          [secondBundle],
          in: db,
          now: secondDate,
          uuid: { repositoryUUIDs.next() }
        )
      }

      _ = try database.write { db in
        try RecipeRepository.rollbackImportedRecipes(recipeIDs: firstSummary.importedIDs, in: db)
      }

      let remainingRecipes = try database.read { db in
        try Recipe.fetchAll(db).map(\.id)
      }
      let remainingImportRefs = try database.read { db in
        try RecipeImportRef.fetchAll(db).map(\.recipeID)
      }

      expectNoDifference(remainingRecipes, secondSummary.importedIDs)
      expectNoDifference(remainingImportRefs, secondSummary.importedIDs)
    }

    @Test
    func rollbackPreservesLinkedEquipmentWithoutBatchProvenance() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let pasta = try #require(parseResult.recipes.first { $0.title == "Weeknight Tomato Pasta" })
      let now = Date(timeIntervalSinceReferenceDate: 802_950_000)
      let equipment = Equipment(
        id: SampleUUIDSequence.uuid(14_800),
        name: "Dutch oven",
        equipmentType: "Cookware"
      )
      var bundleUUIDs = SampleUUIDSequence(start: 14_900)
      var bundle = try pasta.makeRecipeBundle(now: now, uuid: { bundleUUIDs.next() })
      bundle.equipment = [equipment]
      bundle.recipeEquipment = [
        RecipeEquipment(
          id: SampleUUIDSequence.uuid(14_801),
          recipeID: bundle.recipe.id,
          equipmentID: equipment.id
        )
      ]

      let importSummary = try database.write { db in
        try Equipment.insert { equipment }.execute(db)
        var repositoryUUIDs = SampleUUIDSequence(start: 14_950)
        return try RecipeRepository.importBundles(
          [bundle],
          in: db,
          now: now,
          uuid: { repositoryUUIDs.next() }
        )
      }

      let rollback = try database.write { db in
        try RecipeRepository.rollbackImportedRecipes(recipeIDs: importSummary.importedIDs, in: db)
      }
      let remainingEquipment = try database.read { db in
        try Equipment.find(equipment.id).fetchOne(db)
      }

      expectNoDifference(rollback.recipeEquipment, 1)
      expectNoDifference(rollback.equipment, 0)
      expectNoDifference(remainingEquipment, equipment)
    }

    @Test
    func rollbackRecipeImportLeavesGroceryDanglingSourceReadable() throws {
      @Dependency(\.defaultDatabase) var database
      let parseResult = try PaprikaHTMLImporter.parseExport(at: Self.fixtureURL)
      let pasta = try #require(parseResult.recipes.first { $0.title == "Weeknight Tomato Pasta" })
      let now = Date(timeIntervalSinceReferenceDate: 803_000_000)
      var bundleUUIDs = SampleUUIDSequence(start: 15_000)
      let bundle = try pasta.makeRecipeBundle(now: now, uuid: { bundleUUIDs.next() })

      let importSummary = try database.write { db in
        var repositoryUUIDs = SampleUUIDSequence(start: 15_500)
        return try RecipeRepository.importBundles(
          [bundle],
          in: db,
          now: now,
          uuid: { repositoryUUIDs.next() }
        )
      }
      let recipeID = try #require(importSummary.importedIDs.first)

      try database.write { db in
        var groceryUUIDs = SampleUUIDSequence(start: 16_000)
        let listID = try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { groceryUUIDs.next() }
        )
        try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { groceryUUIDs.next() }
        )
        try RecipeRepository.rollbackImportedRecipes(recipeIDs: [recipeID], in: db)

        let rows = try GroceryItemListRequest().fetch(db)
        expectNoDifference(try Recipe.find(recipeID).fetchOne(db), nil)
        expectNoDifference(rows.isEmpty, false)
        expectNoDifference(rows.flatMap(\.sources).allSatisfy { $0.recipeID == recipeID }, true)
        expectNoDifference(rows.flatMap(\.sources).map(\.sourceTitle).contains("Weeknight Tomato Pasta"), true)
      }
    }

    private static var fixtureURL: URL {
      URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/PaprikaHTML/SyntheticExport", isDirectory: true)
    }
  }
}

private struct LibraryEntityCounts: Equatable {
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
