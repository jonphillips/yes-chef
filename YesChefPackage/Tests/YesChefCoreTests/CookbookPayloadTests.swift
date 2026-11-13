import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing
import YesChefCore

@Suite(.serialized, .dependencies { try $0.bootstrapDatabase() })
struct CookbookPayloadTests {
  private let now = Date(timeIntervalSince1970: 100)

  @Test func compatibilityAndVersionGate() throws {
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let v1 = RecipeBundleCoding.RecipeBundle(recipe: recipe)
    let data = try JSONEncoder().encode(v1)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["labels"] == nil)
    expectNoDifference(try RecipeBundleCoding.decodePayload(data), v1)
    var v2 = v1
    v2.version = 2
    v2.labels = [.init(facet: "Cuisine", path: ["Thai"])]
    expectNoDifference(try RecipeBundleCoding.decodePayload(JSONEncoder().encode(v2)), v2)
    v2.version = 3
    #expect(throws: RecipeBundleCoding.PayloadError.newerVersion(3)) {
      try RecipeBundleCoding.decodePayload(JSONEncoder().encode(v2))
    }
  }

  @Test func builderAndCopyPreserveContentAndRejectMalformedChildren() throws {
    @Dependency(\.defaultDatabase) var database
    let originalID = UUID(), sectionID = UUID(), lineID = UUID(), instructionID = UUID(), stepID = UUID()
    let targetID = UUID(), photoID = UUID(), facetID = UUID(), categoryID = UUID()
    let recipe = Recipe(id: originalID, title: "Soup", rating: 4, favorite: true, dateCreated: now, dateModified: now,
      originalSnapshot: Data("provenance".utf8), makeAhead: "tomorrow", coverPhotoID: photoID)
    let target = Recipe(id: targetID, title: "Bread", dateCreated: now, dateModified: now)
    let source = RecipeSource(id: UUID(), recipeID: originalID, url: "https://example.com/soup")
    let section = IngredientSection(id: sectionID, recipeID: originalID, sortOrder: 0)
    let line = IngredientLine(id: lineID, recipeID: originalID, sectionID: sectionID, originalText: "1 onion", sortOrder: 0)
    let duplicateLine = IngredientLine(id: UUID(), recipeID: originalID, sectionID: sectionID, originalText: "1 onion", sortOrder: 1)
    let instruction = InstructionSection(id: instructionID, recipeID: originalID, sortOrder: 0)
    let step = InstructionStep(id: stepID, recipeID: originalID, sectionID: instructionID, text: "Cook", sortOrder: 0)
    let note = RecipeNote(id: UUID(), recipeID: originalID, text: "A note", noteType: .wine, dateCreated: now, dateModified: now, pinned: true)
    let photo = RecipePhoto(id: photoID, recipeID: originalID, imageDataReference: "photo", displayData: Data([1]), thumbnailData: Data([2]), sortOrder: 0, dateCreated: now)
    let facet = Facet(id: facetID, name: "Cuisine", sortOrder: 0, dateCreated: now)
    let category = Category(id: categoryID, name: "Thai", facetID: facetID, sortOrder: 0, dateCreated: now)
    let join = RecipeCategory(id: UUID(), recipeID: originalID, categoryID: categoryID)
    let serve = RecipeServeWith(id: UUID(), recipeID: originalID, linkedRecipeID: targetID, title: "Bread", sortOrder: 0, provenance: .handAuthored, dateCreated: now, dateModified: now)
    let payload = RecipeVariationPayload(ingredientOps: [.substitute(.init(id: duplicateLine.id, originalText: "1 onion"), line: "2 onions")],
      methodStepReplacements: [.init(id: stepID, originalText: "Cook", replacementText: "Fry")],
      methodStepStructuralOps: [.insert(after: .init(id: stepID, originalText: "Cook"), sectionID: instructionID, text: "Serve")])
    let variation = RecipeVariation(id: UUID(), recipeID: originalID, name: "Variation", sortIndex: 0, deltas: try payload.encodedData(), dateCreated: now, dateModified: now)
    try database.write { db in
      try Recipe.insert { recipe }.execute(db)
      try Recipe.insert { target }.execute(db)
      try RecipeSource.insert { source }.execute(db)
      try IngredientSection.insert { section }.execute(db)
      try IngredientLine.insert { line }.execute(db)
      try IngredientLine.insert { duplicateLine }.execute(db)
      try InstructionSection.insert { instruction }.execute(db)
      try InstructionStep.insert { step }.execute(db)
      try RecipeNote.insert { note }.execute(db)
      try RecipePhoto.insert { photo }.execute(db)
      try Facet.insert { facet }.execute(db)
      try Category.insert { category }.execute(db)
      try RecipeCategory.insert { join }.execute(db)
      try RecipeServeWith.insert { serve }.execute(db)
      try RecipeVariation.insert { variation }.execute(db)
      let first = try #require(CookbookPayload.bundles(in: db).first { $0.recipe.id == originalID })
      let second = try #require(CookbookPayload.bundles(in: db).first { $0.recipe.id == originalID })
      expectNoDifference(try CookbookPayload.encodedPayload(first), try CookbookPayload.encodedPayload(second))
      expectNoDifference(try CookbookPayload.contentHash(first), try CookbookPayload.contentHash(second))
      expectNoDifference(first.labels, [.init(facet: "Cuisine", path: ["Thai"])])
      #expect(first.photos.first?.displayData == nil)
      #expect(first.photos.first?.thumbnailData == Data([2]))
      #expect(first.linkTargets.first?.recipeID == targetID)
      let copy = try RecipeRepository.copyCookbookRecipe(first, ownerName: "Jon", displayImages: [photoID: Data([3])], in: db, now: now, uuid: UUID.init)
      let saved = try #require(try Recipe.find(copy.recipeID).fetchOne(db))
      #expect(saved.id != originalID && saved.rating == nil && !saved.favorite)
      #expect(saved.originalSnapshot == recipe.originalSnapshot)
      #expect(copy.textOnlyServeWith == ["Bread"])
      let copiedLine = try #require(try IngredientLine.where { $0.recipeID.eq(copy.recipeID) }.fetchAll(db).first { $0.sortOrder == 1 })
      #expect(copiedLine.id != lineID && copiedLine.sectionID != sectionID && copiedLine.originalText == line.originalText)
      let copiedSource = try #require(try RecipeSource.where { $0.recipeID.eq(copy.recipeID) }.fetchOne(db))
      #expect(copiedSource.url == source.url && copiedSource.importedFrom == "Copied from Jon's cookbook")
      let copiedNote = try #require(try RecipeNote.where { $0.recipeID.eq(copy.recipeID) }.fetchOne(db))
      #expect(copiedNote.noteType == .wine && copiedNote.pinned)
      let copiedPhoto = try #require(try RecipePhoto.where { $0.recipeID.eq(copy.recipeID) }.fetchOne(db))
      #expect(copiedPhoto.id != photoID && copiedPhoto.displayData == Data([3]))
      let copiedVariation = try #require(try RecipeVariation.where { $0.recipeID.eq(copy.recipeID) }.fetchOne(db))
      let decoded = try RecipeVariationPayload.decode(copiedVariation.deltas, variationID: copiedVariation.id)
      guard case let .substitute(ref, _) = decoded.ingredientOps[0] else { Issue.record("Missing substitute"); return }
      #expect(ref.id == copiedLine.id)
      let copiedStep = try #require(try InstructionStep.where { $0.recipeID.eq(copy.recipeID) }.fetchOne(db))
      #expect(decoded.methodStepReplacements[0].id == copiedStep.id)
      guard case let .insert(after, mappedSection, _) = decoded.methodStepStructuralOps[0] else { Issue.record("Missing insert"); return }
      #expect(after?.id == copiedStep.id && mappedSection == copiedStep.sectionID)
      let originalDetail = try #require(try RecipeRepository.fetchDetail(recipeID: originalID, in: db))
      let copyDetail = try #require(try RecipeRepository.fetchDetail(recipeID: copy.recipeID, in: db))
      let originalResolved = try originalDetail.resolved(applying: variation).detail
      let copyResolved = try copyDetail.resolved(applying: copiedVariation).detail
      expectNoDifference(originalResolved.ingredientLines.map(\.originalText), copyResolved.ingredientLines.map(\.originalText))
      expectNoDifference(originalResolved.instructionSteps.map(\.text), copyResolved.instructionSteps.map(\.text))
      #expect(try RecipeRepository.existingCopies(of: first, in: db).contains(copy.recipeID))
      let count = try Recipe.fetchCount(db)
      var malformed = first
      malformed.ingredientLines = [IngredientLine(id: UUID(), recipeID: originalID, sectionID: UUID(), originalText: "bad", sortOrder: 0)]
      #expect(throws: (any Error).self) {
        try RecipeRepository.copyCookbookRecipe(malformed, ownerName: "Jon", displayImages: [:], in: db, now: now, uuid: UUID.init)
      }
      #expect(try Recipe.fetchCount(db) == count)
    }
  }

  @Test func independentCopiesAndAmbiguousLinks() throws {
    @Dependency(\.defaultDatabase) var database
    let sourceID = UUID(), targetID = UUID(), sectionID = UUID()
    let source = Recipe(id: sourceID, title: "Stew", dateCreated: now, dateModified: now)
    let target = Recipe(id: targetID, title: "Rice", dateCreated: now, dateModified: now)
    let section = IngredientSection(id: sectionID, recipeID: sourceID, sortOrder: 0)
    let line = IngredientLine(id: UUID(), recipeID: sourceID, sectionID: sectionID, originalText: "salt", sortOrder: 0)
    let targetBundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: target)
    let relation = RecipeRelatedRecipe(id: UUID(), recipeID: sourceID, relatedRecipeID: targetID, dateCreated: now)
    let serve = RecipeServeWith(id: UUID(), recipeID: sourceID, linkedRecipeID: targetID, title: "Rice", sortOrder: 0, provenance: .handAuthored, dateCreated: now, dateModified: now)
    let variation = RecipeVariation(id: UUID(), recipeID: sourceID, name: "Broken", sortIndex: 0, deltas: Data([255]), dateCreated: now, dateModified: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: source, ingredientSections: [section], ingredientLines: [line],
      labels: [.init(facet: "New facet", path: ["Parent", "Child"]), .init(facet: nil, path: ["Loose"])],
      serveWith: [serve], relatedRecipes: [relation], variations: [variation],
      linkTargets: [.init(recipeID: targetID, title: "Rice", sourceURL: nil)])
    try database.write { db in
      let firstTarget = try RecipeRepository.copyCookbookRecipe(targetBundle, ownerName: "Wendy", displayImages: [:], in: db, now: now, uuid: UUID.init)
      let first = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: "Wendy", displayImages: [:], in: db, now: now, uuid: UUID.init)
      #expect(first.textOnlyServeWith.isEmpty && first.unlinkedRelated.isEmpty && first.warnings.count == 1)
      let copiedServe = try #require(try RecipeServeWith.where { $0.recipeID.eq(first.recipeID) }.fetchOne(db))
      #expect(copiedServe.linkedRecipeID == firstTarget.recipeID)
      #expect(try RecipeRelatedRecipe.fetchCount(db) == 1)
      let copiedVariation = try #require(try RecipeVariation.where { $0.recipeID.eq(first.recipeID) }.fetchOne(db))
      #expect(copiedVariation.deltas == variation.deltas)
      _ = try RecipeRepository.copyCookbookRecipe(targetBundle, ownerName: "Wendy", displayImages: [:], in: db, now: now, uuid: UUID.init)
      let second = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: "Wendy", displayImages: [:], in: db, now: now, uuid: UUID.init)
      #expect(second.recipeID != first.recipeID)
      #expect(second.textOnlyServeWith == ["Rice"] && second.unlinkedRelated == ["Rice"])
      #expect(try Facet.fetchAll(db).filter { $0.name == "New facet" }.count == 1)
      #expect(try Category.fetchAll(db).filter { $0.name == "Child" }.count == 1)
      let sourceRow = try #require(try RecipeSource.where { $0.recipeID.eq(second.recipeID) }.fetchOne(db))
      #expect(sourceRow.importedFrom == "Copied from Wendy's cookbook")
      let firstLine = try #require(try IngredientLine.where { $0.recipeID.eq(first.recipeID) }.fetchOne(db))
      let secondLine = try #require(try IngredientLine.where { $0.recipeID.eq(second.recipeID) }.fetchOne(db))
      #expect(firstLine.id != secondLine.id && firstLine.sectionID != secondLine.sectionID)
      try IngredientLine.find(firstLine.id).update { $0.originalText = "pepper" }.execute(db)
      #expect(try IngredientLine.find(secondLine.id).fetchOne(db)?.originalText == "salt")
      let count = try Recipe.fetchCount(db)
      let matches = try RecipeRepository.existingCopies(of: targetBundle, in: db)
      #expect(matches.count == 2)
      #expect(try Recipe.fetchCount(db) == count)
    }
  }


  @Test func sourceURLLookupIsReadOnlyAndExcludesArchived() throws {
    @Dependency(\.defaultDatabase) var database
    let existing = Recipe(id: UUID(), title: "My title", dateCreated: now, dateModified: now)
    let archived = Recipe(id: UUID(), title: "Archived", archived: true, dateCreated: now, dateModified: now)
    let external = Recipe(id: UUID(), title: "Original title", dateCreated: now, dateModified: now)
    let url = "https://example.com/recipe?utm_source=test"
    let externalSource = RecipeSource(id: UUID(), recipeID: external.id, url: url)
    let existingSource = RecipeSource(id: UUID(), recipeID: existing.id, url: "https://example.com/recipe")
    let archivedSource = RecipeSource(id: UUID(), recipeID: archived.id, url: url)
    let bundle = RecipeBundleCoding.RecipeBundle(recipe: external, source: externalSource)
    try database.write { db in
      try Recipe.insert { existing }.execute(db)
      try Recipe.insert { archived }.execute(db)
      try RecipeSource.insert { existingSource }.execute(db)
      try RecipeSource.insert { archivedSource }.execute(db)
      let before = try RecipeImportRef.fetchCount(db)
      expectNoDifference(try RecipeRepository.existingCopies(of: bundle, in: db), [existing.id])
      #expect(try RecipeImportRef.fetchCount(db) == before)
      #expect(try Recipe.fetchCount(db) == 2)
    }
  }


  @Test func builderExcludesArchivedAndHashesOnlyChangedRecipes() throws {
    @Dependency(\.defaultDatabase) var database
    let a = Recipe(id: UUID(), title: "A", dateCreated: now, dateModified: now)
    let b = Recipe(id: UUID(), title: "B", dateCreated: now, dateModified: now)
    let archived = Recipe(id: UUID(), title: "Archived", archived: true, dateCreated: now, dateModified: now)
    try database.write { db in
      try Recipe.insert { a }.execute(db)
      try Recipe.insert { b }.execute(db)
      try Recipe.insert { archived }.execute(db)
      let before = try CookbookPayload.bundles(in: db)
      #expect(before.count == 2 && !before.contains { $0.recipe.id == archived.id })
      let hashes = try Dictionary(uniqueKeysWithValues: before.map { ($0.recipe.id, try CookbookPayload.contentHash($0)) })
      try Recipe.find(a.id).update { $0.title = "Changed" }.execute(db)
      let after = try CookbookPayload.bundles(in: db)
      let newHashes = try Dictionary(uniqueKeysWithValues: after.map { ($0.recipe.id, try CookbookPayload.contentHash($0)) })
      #expect(hashes[a.id] != newHashes[a.id] && hashes[b.id] == newHashes[b.id])
    }
  }

  @Test func textServeWithIsNotReportedAndPayloadBytesAreStable() throws {
    @Dependency(\.defaultDatabase) var database
    let recipe = Recipe(id: UUID(), title: "Roast", dateCreated: now, dateModified: now)
    let first = Recipe(id: UUID(), title: "Gravy", dateCreated: now, dateModified: now)
    let second = Recipe(id: UUID(), title: "Potatoes", dateCreated: now, dateModified: now)
    func serve(_ title: String, linked: Recipe.ID?, order: Int) -> RecipeServeWith {
      RecipeServeWith(id: UUID(), recipeID: recipe.id, linkedRecipeID: linked, title: title, sortOrder: order,
        provenance: .handAuthored, dateCreated: now, dateModified: now)
    }
    try database.write { db in
      try Recipe.insert { recipe }.execute(db)
      try Recipe.insert { first }.execute(db)
      try Recipe.insert { second }.execute(db)
      try RecipeServeWith.insert { serve("Gravy", linked: first.id, order: 0) }.execute(db)
      try RecipeServeWith.insert { serve("Green salad", linked: nil, order: 1) }.execute(db)
      try RecipeServeWith.insert { serve("Potatoes", linked: second.id, order: 2) }.execute(db)
      let bundle = try #require(try CookbookPayload.bundles(in: db).first { $0.recipe.id == recipe.id })
      let again = try #require(try CookbookPayload.bundles(in: db).first { $0.recipe.id == recipe.id })
      #expect(bundle.linkTargets.count == 2)
      #expect(try CookbookPayload.encodedPayload(bundle) == CookbookPayload.encodedPayload(again))
      try Recipe.find(first.id).delete().execute(db)
      try Recipe.find(second.id).delete().execute(db)
      let copy = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: "Jon", displayImages: [:], in: db, now: now, uuid: UUID.init)
      #expect(Set(copy.textOnlyServeWith) == ["Gravy", "Potatoes"])
    }
  }

  @Test func danglingVariationAnchorsKeepFallback() throws {
    @Dependency(\.defaultDatabase) var database
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let payload = RecipeVariationPayload(ingredientOps: [.remove(.init(id: UUID(), originalText: "salt"))],
      methodStepReplacements: [.init(id: UUID(), originalText: "Stir", replacementText: "Mix")],
      methodStepStructuralOps: [.insert(after: .init(id: UUID(), originalText: "Stir"), sectionID: UUID(), text: "Serve")])
    let variation = RecipeVariation(id: UUID(), recipeID: recipe.id, name: "Old", sortIndex: 0,
      deltas: try payload.encodedData(), dateCreated: now, dateModified: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: recipe, variations: [variation])
    try database.write { db in
      let result = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: "Jon", displayImages: [:], in: db, now: now, uuid: UUID.init)
      let row = try #require(try RecipeVariation.where { $0.recipeID.eq(result.recipeID) }.fetchOne(db))
      let copy = try RecipeVariationPayload.decode(row.deltas, variationID: row.id)
      guard case let .remove(ref) = copy.ingredientOps[0] else { Issue.record("Missing remove"); return }
      #expect(ref.id == nil && ref.originalText == "salt")
      #expect(copy.methodStepReplacements[0].id == nil && copy.methodStepReplacements[0].originalText == "Stir")
      guard case let .insert(after, sectionID, _) = copy.methodStepStructuralOps[0] else { Issue.record("Missing insert"); return }
      #expect(after?.id == nil && after?.originalText == "Stir" && sectionID == nil)
    }
  }


  @Test func labelsReuseExistingPathsAndVersionOneUsesLegacyLabels() throws {
    @Dependency(\.defaultDatabase) var database
    let recipe = Recipe(id: UUID(), title: "Pie", dateCreated: now, dateModified: now)
    let facet = Facet(id: UUID(), name: "Cuisine", sortOrder: 0, dateCreated: now)
    let category = Category(id: UUID(), name: "Thai", facetID: facet.id, sortOrder: 0, dateCreated: now)
    let loose = Category(id: UUID(), name: "Family", sortOrder: 0, dateCreated: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: recipe,
      labels: [.init(facet: "cuisine", path: ["thai"]), .init(facet: nil, path: ["family"])])
    try database.write { db in
      try Facet.insert { facet }.execute(db)
      try Category.insert { category }.execute(db)
      try Category.insert { loose }.execute(db)
      let result = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: "Jon", displayImages: [:], in: db, now: now, uuid: UUID.init)
      let joins = try RecipeCategory.where { $0.recipeID.eq(result.recipeID) }.fetchAll(db)
      #expect(Set(joins.map(\.categoryID)) == Set([category.id, loose.id]))
      var legacy = bundle
      legacy.version = 1
      legacy.categoryNames = ["Cuisine > Thai"]
      legacy.tagNames = ["Family"]
      let legacyResult = try RecipeRepository.copyCookbookRecipe(legacy, ownerName: "Jon", displayImages: [:], in: db, now: now, uuid: UUID.init)
      let legacyJoins = try RecipeCategory.where { $0.recipeID.eq(legacyResult.recipeID) }.fetchAll(db)
      #expect(Set(legacyJoins.map(\.categoryID)) == Set([category.id, loose.id]))
    }
  }

}
