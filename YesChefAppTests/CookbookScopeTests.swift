import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct CookbookScopeTests {
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
        PowerBrowserModel(scope: .cookbook(context))
      }
      try await model.$lensLibrary.load()
      #expect(model.lensLibrary.lenses == baseline.0)
      model.lensSelectionChanged(lens.id)
      #expect(model.selectedLens?.id == lens.id)

      model.editLensBaseQueryButtonTapped(lens)
      model.saveQueryEditsButtonTapped()
      model.deleteLensButtonTapped(lens)
      model.saveLensButtonTapped(name: "Do not save")
      #expect(model.addShelfButtonTapped(lensID: lens.id, title: "Do not add", query: RecipeBrowserQuery()) == nil)
      model.renameLensButtonTapped(lens, name: "Do not rename")
      model.deleteShelfButtonTapped(shelf)
      model.renameShelfButtonTapped(shelf, title: "Do not rename")
      model.reorderShelvesButtonTapped([], lensID: lens.id)
      model.showsRemainderChanged(false, lens: lens)

      let saved = try await mirror.database.read { db in
        (try RecipeLens.fetchAll(db), try RecipeLensShelf.fetchAll(db))
      }
      #expect(saved.0 == baseline.0)
      #expect(saved.1 == baseline.1)
    }
  }
}
