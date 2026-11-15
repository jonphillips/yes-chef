import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing
import YesChefCore

struct CookbookMirrorTests {
  @Test func oldMirrorIsRecreatedAndOrdinaryWritesAreReadOnly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let url = directory.appendingPathComponent(id.uuidString).appendingPathExtension("sqlite")
    let old = try DatabaseQueue(path: url.path)
    try old.write { db in
      try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
      try db.execute(sql: "INSERT INTO grdb_migrations VALUES (?)", arguments: [YesChefSchema.migrator().migrations[0]])
      try db.execute(sql: "CREATE TABLE obsolete (value TEXT)")
    }
    try old.close()
    let mirror = try CookbookMirror(id: id, directory: directory)
    let migrator = YesChefSchema.migrator()
    try mirror.database.read { db in
      let migrations = try migrator.appliedMigrations(db)
      let obsoleteExists = try db.tableExists("obsolete")
      #expect(migrations == migrator.migrations)
      #expect(!obsoleteExists)
    }
    do {
      try mirror.database.write { db in
        try db.execute(sql: "CREATE TABLE forbidden (value TEXT)")
      }
      Issue.record("Expected SQLITE_READONLY")
    } catch let error as DatabaseError {
      #expect(error.resultCode == .SQLITE_READONLY)
    }
    try mirror.deleteMirror()
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }
  @Test func currentMirrorReopensWithoutBeingRecreated() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let id = UUID()
    let now = Date(timeIntervalSince1970: 100)
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    try withDependencies { $0.context = .live } operation: {
      do {
        let mirror = try CookbookMirror(id: id, directory: directory)
        try mirror.apply(upserting: [.init(recipe: recipe)], deleting: [])
        try mirror.database.close()
      }
      let reopened = try CookbookMirror(id: id, directory: directory)
      defer { try? reopened.deleteMirror() }
      let saved = try reopened.database.read { try Recipe.find(recipe.id).fetchOne($0) }
      #expect(saved == recipe)
      do {
        try reopened.database.write { try $0.execute(sql: "CREATE TABLE forbidden (value TEXT)") }
        Issue.record("Expected SQLITE_READONLY")
      } catch let error as DatabaseError {
        #expect(error.resultCode == .SQLITE_READONLY)
      }
      let next = Recipe(id: UUID(), title: "Bread", dateCreated: now, dateModified: now)
      try reopened.apply(upserting: [.init(recipe: next)], deleting: [])
      let fetched = try reopened.database.read { try Recipe.find(next.id).fetchOne($0) }
      #expect(fetched == next)
    }
  }

  @Test func applyMaintainsChildrenLinksAndLabels() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let first = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    let second = Recipe(id: UUID(), title: "Bread", dateCreated: now, dateModified: now)
    let section = IngredientSection(id: UUID(), recipeID: first.id, sortOrder: 0)
    let line = IngredientLine(id: UUID(), recipeID: first.id, sectionID: section.id, originalText: "onion", sortOrder: 0)
    let pair = RecipeRelatedRecipe(id: UUID(), recipeID: first.id, relatedRecipeID: second.id, dateCreated: now)
    var one = RecipeBundleCoding.RecipeBundle(version: 2, recipe: first,
      ingredientSections: [section], ingredientLines: [line],
      labels: [.init(facet: "Cuisine", path: ["French", "Bistro"])], relatedRecipes: [pair])
    let two = RecipeBundleCoding.RecipeBundle(version: 2, recipe: second, relatedRecipes: [pair])
    try withDependencies {
      $0.context = .live
    } operation: {
      try mirror.apply(upserting: [one], deleting: [])
      try mirror.database.read { db in
        let pairs = try RecipeRelatedRecipe.fetchAll(db)
        #expect(pairs.isEmpty)
      }
      try mirror.apply(upserting: [two], deleting: [])
      let snapshot = try mirror.database.read { db in
        (try RecipeRelatedRecipe.fetchAll(db), try Category.fetchAll(db), try RecipeCategory.fetchAll(db))
      }
      #expect(snapshot.0 == [pair])
      let beforeChanges = try mirror.database.writeWithoutTransaction { try Int.fetchOne($0, sql: "SELECT total_changes()") }
      try mirror.apply(upserting: [one, two], deleting: [])
      let afterChanges = try mirror.database.writeWithoutTransaction { try Int.fetchOne($0, sql: "SELECT total_changes()") }
      #expect(afterChanges == beforeChanges)
      try mirror.database.read { db in
        let pairs = try RecipeRelatedRecipe.fetchAll(db)
        let categories = try Category.fetchAll(db)
        let joins = try RecipeCategory.fetchAll(db)
        #expect(pairs == snapshot.0)
        #expect(categories == snapshot.1)
        #expect(joins == snapshot.2)
      }
      one.ingredientLines = []
      one.labels = []
      try mirror.apply(upserting: [one], deleting: [])
      try mirror.database.read { db in
        let lines = try IngredientLine.fetchAll(db)
        let categories = try Category.fetchAll(db)
        let facets = try Facet.fetchAll(db)
        #expect(lines.isEmpty && categories.isEmpty && facets.isEmpty)
      }
      try mirror.apply(upserting: [], deleting: [first.id])
      try mirror.database.read { db in
        let pairs = try RecipeRelatedRecipe.fetchAll(db)
        let sections = try IngredientSection.fetchAll(db)
        let recipes = try Recipe.fetchAll(db)
        #expect(pairs.isEmpty && sections.isEmpty && recipes == [second])
      }
    }
  }

  @Test func fullFetchCommitsPagesAndSweepsOnlyAfterTheLastPage() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let retained = (0..<2).map { Recipe(id: UUID(), title: "Keep \($0)", dateCreated: now, dateModified: now) }
    let stale = Recipe(id: UUID(), title: "Stale", dateCreated: now, dateModified: now)
    try withDependencies { $0.context = .live; $0.date.now = now } operation: {
      try mirror.apply(upserting: (retained + [stale]).map { .init(recipe: $0) }, deleting: [])
      try mirror.apply(page: CookbookMirrorPage(
        bundles: [.init(recipe: retained[0])], seenRecordNames: [retained[0].id.uuidString],
        changeToken: Data("page-1".utf8), startsFullFetch: true
      ))
      let count = try mirror.database.read { try Recipe.fetchCount($0) }
      #expect(count == 3)
      #expect(try mirror.fetchState().fullFetchActive)
      let profile = CookbookPublishProfile(displayName: "Jon", recipeCount: 2, payloadVersion: 2, publishedAt: now)
      try mirror.apply(page: CookbookMirrorPage(
        bundles: [.init(recipe: retained[1])], seenRecordNames: [retained[1].id.uuidString],
        profile: profile, changeToken: Data("page-2".utf8), finishesFullFetch: true
      ))
      let saved = try mirror.database.read { try Recipe.fetchAll($0).map(\.id) }
      #expect(Set(saved) == Set(retained.map(\.id)))
      #expect(try mirror.fetchState().changeToken == Data("page-2".utf8))
      #expect(try mirror.fetchState().displayName == "Jon")
      #expect(!(try mirror.fetchState().fullFetchActive))
    }
  }

  @Test func observerSeesAppliedChangesOnTheSamePool() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    var values = ValueObservation.tracking { try Recipe.fetchCount($0) }
      .values(in: mirror.database).makeAsyncIterator()
    let initial = try await values.next()
    #expect(initial == 0)
    let now = Date(timeIntervalSince1970: 100)
    let recipe = Recipe(id: UUID(), title: "Soup", dateCreated: now, dateModified: now)
    try withDependencies { $0.context = .live } operation: {
      try mirror.apply(upserting: [.init(recipe: recipe)], deleting: [])
    }
    let updated = try await values.next()
    #expect(updated == 1)
  }

  @Test func relatedPairArrivesInEitherOrderAndDeletionClearsEitherEnd() throws {
    for reversed in [false, true] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let mirror = try CookbookMirror(id: UUID(), directory: directory)
      defer { try? mirror.deleteMirror() }
      let now = Date(timeIntervalSince1970: 100)
      let a = Recipe(id: UUID(), title: "A", dateCreated: now, dateModified: now)
      let b = Recipe(id: UUID(), title: "B", dateCreated: now, dateModified: now)
      let pair = RecipeRelatedRecipe(id: UUID(), recipeID: a.id, relatedRecipeID: b.id, dateCreated: now)
      let first = RecipeBundleCoding.RecipeBundle(version: 2, recipe: reversed ? b : a, relatedRecipes: [pair])
      let second = RecipeBundleCoding.RecipeBundle(version: 2, recipe: reversed ? a : b, relatedRecipes: [pair])
      try withDependencies { $0.context = .live } operation: {
        try mirror.apply(upserting: [first], deleting: [])
        try mirror.apply(upserting: [second], deleting: [])
        let pairs = try mirror.database.read { try RecipeRelatedRecipe.fetchAll($0) }
        #expect(pairs == [pair])
        try mirror.apply(upserting: [], deleting: [reversed ? b.id : a.id])
        let remainingPairs = try mirror.database.read { try RecipeRelatedRecipe.fetchAll($0) }
        #expect(remainingPairs.isEmpty)
      }
    }
  }

  @Test func malformedChildRollsBackTheBatchAndRestoresReadOnlyGuard() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let good = Recipe(id: UUID(), title: "Good", dateCreated: now, dateModified: now)
    let bad = Recipe(id: UUID(), title: "Bad", dateCreated: now, dateModified: now)
    let orphan = IngredientLine(id: UUID(), recipeID: bad.id, sectionID: UUID(), originalText: "onion", sortOrder: 0)
    withDependencies { $0.context = .live } operation: {
      #expect(throws: (any Error).self) {
        try mirror.apply(upserting: [.init(recipe: good), .init(recipe: bad, ingredientLines: [orphan])], deleting: [])
      }
    }
    let recipes = try mirror.database.read { try Recipe.fetchAll($0) }
    #expect(recipes.isEmpty)
    do {
      try mirror.database.write { try $0.execute(sql: "CREATE TABLE forbidden (value TEXT)") }
      Issue.record("Expected SQLITE_READONLY")
    } catch let error as DatabaseError {
      #expect(error.resultCode == .SQLITE_READONLY)
    }
  }

  @Test func failedPageLeavesExistingRowsAndChangeTokenUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let existing = Recipe(id: UUID(), title: "Existing", dateCreated: now, dateModified: now)
    try withDependencies { $0.context = .live } operation: {
      try mirror.apply(upserting: [.init(recipe: existing)], deleting: [])
      try mirror.apply(page: CookbookMirrorPage(changeToken: Data("committed".utf8)))
      let invalid = Recipe(id: UUID(), title: "Invalid", dateCreated: now, dateModified: now)
      let orphan = IngredientLine(id: UUID(), recipeID: invalid.id, sectionID: UUID(), originalText: "salt", sortOrder: 0)
      #expect(throws: (any Error).self) {
        try mirror.apply(page: CookbookMirrorPage(
          bundles: [.init(recipe: invalid, ingredientLines: [orphan])],
          changeToken: Data("uncommitted".utf8)
        ))
      }
      let recipes = try mirror.database.read { try Recipe.fetchAll($0) }
      #expect(recipes == [existing])
      #expect(try mirror.fetchState().changeToken == Data("committed".utf8))
    }
  }

  @Test func skippedRecipeIsCountedThenClearedByDecodeOrDeletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let recipeID = UUID()
    try withDependencies { $0.context = .live } operation: {
      try mirror.apply(page: CookbookMirrorPage(
        skippedRecords: [recipeID.uuidString: RecipeBundleCoding.currentVersion + 1]
      ))
      #expect(try mirror.skippedRecordCount() == 1)
      let recipe = Recipe(id: recipeID, title: "Now readable", dateCreated: .now, dateModified: .now)
      try mirror.apply(page: CookbookMirrorPage(
        bundles: [.init(recipe: recipe)], seenRecordNames: [recipeID.uuidString]
      ))
      #expect(try mirror.skippedRecordCount() == 0)
      try mirror.apply(page: CookbookMirrorPage(skippedRecords: [recipeID.uuidString: 999]))
      try mirror.apply(page: CookbookMirrorPage(deletedRecipeIDs: [recipeID]))
      #expect(try mirror.skippedRecordCount() == 0)
    }
  }

  @Test func lensReplacementKeepsUnresolvedReferencesAndCountsOnlyUndecodableLenses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let oldLens = RecipeLens(
      id: UUID(), name: "Old", baseQuery: try RecipeLensQueryCodec.encode(RecipeBrowserQuery()),
      sortOrder: 0, dateCreated: now, dateModified: now
    )
    let hiddenFacet = Facet(id: UUID(), name: "Hidden", sortOrder: 0, hidden: true, dateCreated: now)
    let hiddenCategory = Category(
      id: UUID(), name: "Retired", facetID: hiddenFacet.id, hidden: true, sortOrder: 0, dateCreated: now
    )
    let lens = RecipeLens(
      id: UUID(), name: "Unresolved but readable",
      baseQuery: try RecipeLensQueryCodec.encode(RecipeBrowserQuery(facetSelections: [
        .init(facetID: hiddenFacet.id, categoryIDs: [hiddenCategory.id])
      ])), sortOrder: 0, dateCreated: now, dateModified: now
    )
    let shelf = RecipeLensShelf(
      id: UUID(), lensID: lens.id, title: "Unresolved category", query: lens.baseQuery, sortOrder: 0
    )
    let badBase = RecipeLens(
      id: UUID(), name: "Bad base", baseQuery: "{", sortOrder: 1, dateCreated: now, dateModified: now
    )
    let badShelfLens = RecipeLens(
      id: UUID(), name: "Bad shelf", baseQuery: try RecipeLensQueryCodec.encode(RecipeBrowserQuery()),
      sortOrder: 2, dateCreated: now, dateModified: now
    )
    let badShelf = RecipeLensShelf(
      id: UUID(), lensID: badShelfLens.id, title: "Bad", query: "{", sortOrder: 0
    )
    try withDependencies { $0.context = .live } operation: {
      try mirror.apply(page: CookbookMirrorPage(lensBundle: .init(
        lenses: [oldLens], shelves: [], categories: [], facets: []
      )))
      try mirror.apply(page: CookbookMirrorPage(lensBundle: .init(
        lenses: [lens, badBase, badShelfLens], shelves: [shelf, badShelf],
        categories: [hiddenCategory], facets: [hiddenFacet]
      )))
      let saved = try mirror.database.read { db in
        (try RecipeLens.fetchAll(db), try RecipeLensShelf.fetchAll(db), try Category.fetchAll(db), try Facet.fetchAll(db))
      }
      #expect(saved.0.map(\.id) == [lens.id])
      #expect(saved.1.map(\.id) == [shelf.id])
      #expect(saved.2.map { [$0.name: $0.hidden] } == [["Retired": true]])
      #expect(saved.3.map { [$0.name: $0.hidden] } == [["Hidden": true]])
      let query = try RecipeLensQueryCodec.decode(saved.0[0].baseQuery)
      #expect(query.facetSelections == [.init(facetID: saved.3[0].id, categoryIDs: [saved.2[0].id])])
      #expect(try mirror.skippedRecordCount() == 2)
    }
  }

  @Test func lensShelvesUseTheLabelsRecipesArrivedWith() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let mirror = try CookbookMirror(id: UUID(), directory: directory)
    defer { try? mirror.deleteMirror() }
    let now = Date(timeIntervalSince1970: 100)
    let cuisine = Facet(id: UUID(), name: "Cuisine", sortOrder: 0, dateCreated: now)
    let mexican = YesChefCore.Category(id: UUID(), name: "Mexican", facetID: cuisine.id, sortOrder: 0, dateCreated: now)
    let moles = YesChefCore.Category(id: UUID(), name: "Moles", facetID: cuisine.id, parentCategoryID: mexican.id, sortOrder: 0, dateCreated: now)
    func shelfQuery(_ category: YesChefCore.Category) throws -> String {
      try RecipeLensQueryCodec.encode(RecipeBrowserQuery(facetSelections: [.init(facetID: cuisine.id, categoryIDs: [category.id])]))
    }
    let lens = RecipeLens(
      id: UUID(), name: "Cuisines", baseQuery: try RecipeLensQueryCodec.encode(RecipeBrowserQuery()),
      sortOrder: 0, dateCreated: now, dateModified: now
    )
    let mexicanShelf = RecipeLensShelf(id: UUID(), lensID: lens.id, title: "Mexican", query: try shelfQuery(mexican), sortOrder: 0)
    let molesShelf = RecipeLensShelf(id: UUID(), lensID: lens.id, title: "Moles", query: try shelfQuery(moles), sortOrder: 1)
    let tacos = Recipe(id: UUID(), title: "Tacos", dateCreated: now, dateModified: now)
    let mole = Recipe(id: UUID(), title: "Mole negro", dateCreated: now, dateModified: now)
    func mirrorLabels() throws -> (facets: [Facet], categories: [YesChefCore.Category], joins: [RecipeCategory], shelves: [RecipeLensShelf]) {
      try mirror.database.read { db in
        (try Facet.fetchAll(db), try Category.fetchAll(db), try RecipeCategory.fetchAll(db),
         try RecipeLensShelf.order { $0.sortOrder }.fetchAll(db))
      }
    }
    func shelfCategoryIDs(_ shelf: RecipeLensShelf) throws -> Set<YesChefCore.Category.ID> {
      try RecipeLensQueryCodec.decode(shelf.query).facetSelections.reduce(into: Set<YesChefCore.Category.ID>()) { $0.formUnion($1.categoryIDs) }
    }
    try withDependencies { $0.context = .live; $0.date.now = now; $0.uuid = .incrementing } operation: {
      // A full fetch brings the recipes before the lens record.
      try mirror.apply(page: CookbookMirrorPage(bundles: [
        .init(recipe: tacos, labels: [.init(facet: "Cuisine", path: ["Mexican"])])
      ]))
      try mirror.apply(page: CookbookMirrorPage(lensBundle: .init(
        lenses: [lens], shelves: [mexicanShelf, molesShelf], categories: [mexican, moles], facets: [cuisine]
      )))
      var labels = try mirrorLabels()
      #expect(labels.facets.map(\.name) == ["Cuisine"])
      #expect(labels.categories.map(\.name).sorted() == ["Mexican", "Moles"])
      let mirrorMexican = try #require(labels.categories.first { $0.name == "Mexican" })
      let mirrorMoles = try #require(labels.categories.first { $0.name == "Moles" })
      #expect(labels.joins.map(\.categoryID) == [mirrorMexican.id])
      #expect(mirrorMoles.parentCategoryID == mirrorMexican.id)
      #expect(try shelfCategoryIDs(labels.shelves[0]) == [mirrorMexican.id])
      #expect(try shelfCategoryIDs(labels.shelves[1]) == [mirrorMoles.id])
      #expect(try RecipeLensQueryCodec.decode(labels.shelves[0].query).facetSelections.map(\.facetID) == [labels.facets[0].id])
      let readBack = try mirror.database.read { try CookbookLensBundle.read(from: $0) }
      #expect(readBack.categories.count == Set(readBack.categories.map(\.id)).count)

      // A page without the lens record keeps the lens-only label, and a later recipe joins it.
      try mirror.apply(page: CookbookMirrorPage(changeToken: Data("quiet".utf8)))
      #expect(try mirrorLabels().categories.contains(mirrorMoles))
      try mirror.apply(page: CookbookMirrorPage(bundles: [
        .init(recipe: mole, labels: [.init(facet: "Cuisine", path: ["Mexican", "Moles"])])
      ]))
      labels = try mirrorLabels()
      #expect(labels.categories.count == 2)
      #expect(labels.joins.first { $0.recipeID == mole.id }?.categoryID == mirrorMoles.id)
    }
  }

}
