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
    try mirror.apply(upserting: [bundle], deleting: [])

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
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
    try mirror.apply(upserting: [bundle], deleting: [])
    let context = CookbookContext(ownerName: "Jon", mirror: mirror, loadedAt: now)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
    } operation: {
      @Dependency(\.defaultDatabase) var libraryDatabase
      let copyModel = CookbookCopyModel()
      await copyModel.copyButtonTapped(context: context, sourceID: recipeID)

      let copyIDs = copyModel.copyIDsBySource[recipeID] ?? []
      #expect(copyIDs.count == 1)
      #expect(copyIDs.first != recipeID)
      let libraryIDs = try await libraryDatabase.read { try Recipe.fetchAll($0).map(\.id) }
      #expect(libraryIDs == copyIDs)
      let mirrorRecipe = try await mirror.database.read { try Recipe.find(recipeID).fetchOne($0) }
      #expect(mirrorRecipe?.title == "Family Pie")

      await copyModel.copyButtonTapped(context: context, sourceID: recipeID)
      guard case let .existingCopies(_, promptedRecipeID, matches)? = copyModel.prompt else {
        Issue.record("Expected the existing-copy choice")
        return
      }
      #expect(promptedRecipeID == recipeID)
      #expect(matches == copyIDs)
      #expect(await copyModel.newestCopy(of: matches) == copyIDs.first)
    }
  }
}
