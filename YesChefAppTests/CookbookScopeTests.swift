import Dependencies
import CloudKit
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct CookbookScopeTests {
  @Test
  func cookbookSurfaceStartsOnLensesOnlyWhenTheMirrorHasOne() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let lensMirror = try CookbookMirror(id: UUID(), directory: root)
    let recipeMirror = try CookbookMirror(id: UUID(), directory: root)
    defer {
      try? lensMirror.deleteMirror()
      try? recipeMirror.deleteMirror()
      try? FileManager.default.removeItem(at: root)
    }
    try await withDependencies { try $0.bootstrapDatabase() } operation: {
      let client = CookbookFetchClient(
        sharedZones: { [] },
        fetchPage: { _, _ in CookbookFetchedPage(records: [], deletions: [], changeToken: Data(), moreComing: false) },
        fetchDisplayImage: { _, _ in Data() }
      )
      let model = CookbookLibraryModel(fetchClient: client, directory: root)
      let lensContext = CookbookContext(ownerName: "Jon", mirror: lensMirror, zoneOwnerName: "lens-owner")
      let recipesContext = CookbookContext(ownerName: "Wendy", mirror: recipeMirror, zoneOwnerName: "recipe-owner")
      model.resolveInitialSurface(for: lensContext, lensCount: 1)
      model.resolveInitialSurface(for: recipesContext, lensCount: 0)
      #expect(model.surface(for: lensContext) == .lenses)
      #expect(model.surface(for: recipesContext) == .recipes)
    }
  }

  @Test
  func detailReadsFromMirrorAndScaleDoesNotPersistToLibrary() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_000)
    let recipeID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let bundle = RecipeBundleCoding.RecipeBundle(
      version: RecipeBundleCoding.currentVersion,
      recipe: Recipe(id: recipeID, title: "Mirror Recipe", dateCreated: now, dateModified: now)
    )
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      try mirror.apply(upserting: [bundle], deleting: [])
      @Dependency(\.defaultDatabase) var libraryDatabase
      try await libraryDatabase.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Library Recipe", dateCreated: now, dateModified: now)
        }.execute(db)
      }

      let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now)
      let model = withDependencies {
        $0.defaultDatabase = mirror.database
      } operation: {
        RecipeDetailModel(recipeID: recipeID, scope: .cookbook(context))
      }
      try await model.$detail.load()
      #expect(model.detail?.recipe.title == "Mirror Recipe")

      model.scaleWholePart = 2
      model.scalePickerChanged()
      #expect(model.scaleFactor == 2)
      let libraryRecipe = try await libraryDatabase.read { try Recipe.find(recipeID).fetchOne($0) }
      #expect(libraryRecipe?.title == "Library Recipe")
      #expect(libraryRecipe?.viewScale == 1)
    }
  }

  @Test
  func copyWritesToLibraryAndExistingCopyOffersOpenMineOrCopyAnyway() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_100)
    let recipeID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let bundle = RecipeBundleCoding.RecipeBundle(
      version: RecipeBundleCoding.currentVersion,
      recipe: Recipe(id: recipeID, title: "Family Pie", dateCreated: now, dateModified: now)
    )
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      try mirror.apply(upserting: [bundle], deleting: [])
      @Dependency(\.defaultDatabase) var libraryDatabase
      let copyModel = CookbookCopyModel()
      await copyModel.copyButtonTapped(context: context, sourceID: recipeID)

      #expect(copyModel.copiedSourceIDsByCookbook[context.zoneOwnerName]?.contains(recipeID) == true)
      let libraryIDs = try await libraryDatabase.read { try Recipe.fetchAll($0).map(\.id) }
      #expect(libraryIDs.count == 1)
      #expect(!libraryIDs.contains(recipeID))
      let mirrorRecipe = try await mirror.database.read { try Recipe.find(recipeID).fetchOne($0) }
      #expect(mirrorRecipe?.title == "Family Pie")

      await copyModel.copyButtonTapped(context: context, sourceID: recipeID)
      guard case let .existingCopies(_, promptedRecipeID, matches)? = copyModel.prompt else {
        Issue.record("Expected the existing-copy choice")
        return
      }
      #expect(promptedRecipeID == recipeID)
      #expect(matches == libraryIDs)
      #expect(await copyModel.newestCopy(of: matches) == libraryIDs.first)
      copyModel.promptDismissed()  // SwiftUI dismisses the alert before the button's action runs.
      await copyModel.copyAnywayButtonTapped()
      let copiesAfterCopyAnyway = try await libraryDatabase.read { try Recipe.fetchAll($0) }
      #expect(copiesAfterCopyAnyway.count == 2)
    }
  }

  @Test
  func copyShelfSkipsExistingCopiesAndContinuesAfterMissingRecipe() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_150)
    let firstID = UUID()
    let secondID = UUID()
    let missingID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let photoID = UUID()
    let bundles = [firstID, secondID].map { id in
      let photo = id == secondID ? RecipePhoto(id: photoID, recipeID: id, imageDataReference: "photo",
        thumbnailData: Data([1]), mediaType: "image/jpeg", pixelWidth: 1, pixelHeight: 1, sortOrder: 0,
        dateCreated: now) : nil
      let recipe = Recipe(id: id, title: "Recipe \(id.uuidString.prefix(4))", dateCreated: now,
        dateModified: now, coverPhotoID: photo?.id)
      return RecipeBundleCoding.RecipeBundle(version: RecipeBundleCoding.currentVersion,
        recipe: recipe, photos: photo.map { [$0] } ?? [])
    }
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now, zoneOwnerName: "copy-shelf")
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      try mirror.apply(upserting: bundles, deleting: [])
      let model = CookbookCopyModel(fetchClient: photoFetchClient { throw CocoaError(.fileReadUnknown) })
      await model.copyButtonTapped(context: context, sourceID: firstID)
      let report = await model.copyShelf(context: context, shelfID: UUID(), sourceIDs: [firstID, missingID, secondID])
      #expect(report.copied == 1)
      #expect(report.failures.count == 1)
      #expect(report.warnings.contains { $0.contains("Recipe \(secondID.uuidString.prefix(4))") && $0.contains("thumbnail") })
      @Dependency(\.defaultDatabase) var database
      #expect(try await database.read { try Recipe.fetchCount($0) } == 2)
    }
  }

  @Test
  func copyThemTooCopiesMirrorTargetsAndRelinksThemWhileNamingMissingTargets() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_150)
    let sourceID = UUID(), targetID = UUID(), missingID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let source = Recipe(id: sourceID, title: "Stew", dateCreated: now, dateModified: now)
    let target = Recipe(id: targetID, title: "Rice", dateCreated: now, dateModified: now)
    let missing = Recipe(id: missingID, title: "Bread", dateCreated: now, dateModified: now)
    let targetRelation = RecipeRelatedRecipe(id: UUID(), recipeID: sourceID, relatedRecipeID: targetID, dateCreated: now)
    let sourceBundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: source,
      serveWith: [
        RecipeServeWith(id: UUID(), recipeID: sourceID, linkedRecipeID: targetID, title: "Rice", sortOrder: 0,
          provenance: .handAuthored, dateCreated: now, dateModified: now),
        RecipeServeWith(id: UUID(), recipeID: sourceID, linkedRecipeID: missingID, title: "Bread", sortOrder: 1,
          provenance: .handAuthored, dateCreated: now, dateModified: now),
      ], relatedRecipes: [
        targetRelation,
        RecipeRelatedRecipe(id: UUID(), recipeID: sourceID, relatedRecipeID: missingID, dateCreated: now),
      ], linkTargets: [
        .init(recipeID: targetID, title: target.title, sourceURL: nil),
        .init(recipeID: missingID, title: missing.title, sourceURL: nil),
      ])
    let targetVariation = RecipeVariation(id: UUID(), recipeID: targetID, name: "Unreadable", sortIndex: 0,
      deltas: Data([255]), dateCreated: now, dateModified: now)
    let targetBundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: target,
      relatedRecipes: [targetRelation], variations: [targetVariation])
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now, zoneOwnerName: "owner")

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      try mirror.apply(upserting: [sourceBundle, targetBundle], deleting: [])
      @Dependency(\.defaultDatabase) var libraryDatabase
      let model = CookbookCopyModel()
      await model.copyButtonTapped(context: context, sourceID: sourceID)
      guard case let .copyResult(result)? = model.prompt else {
        Issue.record("Expected the first copy result")
        return
      }
      #expect(Set(result.uncopiedTargets) == [targetID, missingID])

      model.promptDismissed()
      await model.copyThemTooButtonTapped(result)
      guard case let .missingTargets(copyResult)? = model.prompt else {
        Issue.record("Expected the missing-target result")
        return
      }
      #expect(copyResult.warnings.contains { $0.contains("Not available in this cookbook: Bread") })
      #expect(copyResult.warnings.contains { $0.contains("Variation Unreadable has unreadable deltas") })

      let mirroredTarget = try #require(try await mirror.database.read {
        try CookbookPayload.bundle(for: targetID, in: $0)
      })
      let copiedSourceIDs = try await libraryDatabase.read { try RecipeRepository.existingCopies(of: sourceBundle, in: $0) }
      let copiedTargetIDs = try await libraryDatabase.read { try RecipeRepository.existingCopies(of: mirroredTarget, in: $0) }
      let copiedSourceID = try #require(copiedSourceIDs.first)
      let copiedTargetID = try #require(copiedTargetIDs.first)
      #expect(copiedTargetIDs.count == 1)
      let linkedRows = try await libraryDatabase.read { db in
        try RecipeServeWith.where { $0.recipeID.eq(copiedSourceID) }.fetchAll(db)
      }
      #expect(linkedRows.first { $0.title == "Rice" }?.linkedRecipeID == copiedTargetID)
      #expect(linkedRows.first { $0.title == "Bread" }?.linkedRecipeID == nil)
      let relatedCount = try await libraryDatabase.read { try RecipeRelatedRecipe.fetchCount($0) }
      #expect(relatedCount == 1)
    }
  }

  @Test
  func failedDisplayPhotoFetchStillCopiesWithWarning() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_175)
    let recipeID = UUID(), photoID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let recipe = Recipe(id: recipeID, title: "Roast", dateCreated: now, dateModified: now, coverPhotoID: photoID)
    let photo = RecipePhoto(id: photoID, recipeID: recipeID, imageDataReference: "photo", thumbnailData: Data([1]),
      mediaType: "image/jpeg", pixelWidth: 1, pixelHeight: 1, sortOrder: 0, dateCreated: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: recipe, photos: [photo])
    let client = photoFetchClient { throw CKError(.networkFailure) }
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now, zoneOwnerName: "owner")

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      try mirror.apply(upserting: [bundle], deleting: [])
      @Dependency(\.defaultDatabase) var libraryDatabase
      let model = CookbookCopyModel(fetchClient: client)
      await model.copyButtonTapped(context: context, sourceID: recipeID)
      guard case let .copyResult(result)? = model.prompt else {
        Issue.record("Expected the photo warning")
        return
      }
      #expect(result.warnings.contains("The full photo couldn’t load; the copy has the thumbnail."))
      #expect(try await libraryDatabase.read { try Recipe.fetchCount($0) } == 1)
    }
  }

  @Test
  func missingPublishedDisplayImageUsesThumbnailWithoutWarning() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_180)
    let recipeID = UUID(), photoID = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let recipe = Recipe(id: recipeID, title: "Roast", dateCreated: now, dateModified: now, coverPhotoID: photoID)
    let photo = RecipePhoto(id: photoID, recipeID: recipeID, imageDataReference: "photo", thumbnailData: Data([1]),
      mediaType: "image/jpeg", pixelWidth: 1, pixelHeight: 1, sortOrder: 0, dateCreated: now)
    let bundle = RecipeBundleCoding.RecipeBundle(version: 2, recipe: recipe, photos: [photo])
    let client = photoFetchClient { throw CookbookFetchError.missingDisplayImage(recipeID.uuidString) }
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now, zoneOwnerName: "owner")

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      try mirror.apply(upserting: [bundle], deleting: [])
      let model = CookbookCopyModel(fetchClient: client)
      await model.copyButtonTapped(context: context, sourceID: recipeID)
      #expect(model.prompt == nil)
      @Dependency(\.defaultDatabase) var libraryDatabase
      #expect(try await libraryDatabase.read { try Recipe.fetchCount($0) } == 1)
    }
  }

  @Test
  func cookbookLensCanBeSelectedAndEveryLensWriteIsBlocked() async throws {
    let now = Date(timeIntervalSinceReferenceDate: 920_000_200)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer {
      try? mirror.deleteMirror()
      try? FileManager.default.removeItem(at: directory)
    }
    let query = try RecipeLensQueryCodec.encode(RecipeBrowserQuery())
    let lens = RecipeLens(id: UUID(), name: "Weeknight", baseQuery: query, sortOrder: 0, dateCreated: now, dateModified: now)
    let shelf = RecipeLensShelf(id: UUID(), lensID: lens.id, title: "Quick", query: query, sortOrder: 0)
    let lensBundle = CookbookLensBundle(lenses: [lens], shelves: [shelf], categories: [], facets: [])

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.defaultDatabase = mirror.database
      $0.date.now = now
    } operation: {
      try mirror.apply(page: CookbookMirrorPage(lensBundle: lensBundle))
      let baseline = try await mirror.database.read { db in
        (try RecipeLens.fetchAll(db), try RecipeLensShelf.fetchAll(db))
      }
      let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now, zoneOwnerName: "owner-zone")
      let model = withDependencies { $0.defaultDatabase = mirror.database } operation: {
        LensesModel(scope: .cookbook(context))
      }
      try await model.browser.$lensLibrary.load()
      #expect(model.lensLibrary.lenses == baseline.0)
      model.open(lens, editing: true)
      #expect(model.openLens?.id == lens.id)
      #expect(!model.isEditing)

      model.saveQuery(RecipeBrowserQuery(text: "Do not save"), target: .editBase(lens.id))
      model.deleteLens(lens)
      let cookbookBrowser = withDependencies { $0.defaultDatabase = mirror.database } operation: {
        PowerBrowserModel(scope: .cookbook(context))
      }
      var callbackID: RecipeLens.ID?
      #expect(cookbookBrowser.saveLensButtonTapped(name: "Do not save", onLensCreated: { callbackID = $0 }) == nil)
      #expect(callbackID == nil)
      model.renameLens(lens, to: "Do not rename")
      model.deleteShelf(shelf)
      model.renameShelf(shelf, to: "Do not rename")
      model.reorderShelves([])
      model.setShowsRemainder(false)
      #expect(model.recipeTapped(UUID()).scope == .cookbook(context))

      let saved = try await mirror.database.read { db in
        (try RecipeLens.fetchAll(db), try RecipeLensShelf.fetchAll(db))
      }
      #expect(saved.0 == baseline.0)
      #expect(saved.1 == baseline.1)
    }
  }
}

private func photoFetchClient(
  fetchDisplayImage: @escaping @Sendable () async throws -> Data
) -> CookbookFetchClient {
  CookbookFetchClient(
    sharedZones: { [] },
    fetchPage: { _, _ in CookbookFetchedPage(records: [], deletions: [], changeToken: Data(), moreComing: false) },
    fetchDisplayImage: { _, _ in try await fetchDisplayImage() }
  )
}
