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

}
