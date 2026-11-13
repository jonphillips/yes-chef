import Dependencies
import Foundation
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
    #expect(throws: (any Error).self) {
      try mirror.database.write { db in
        try db.execute(sql: "CREATE TABLE forbidden (value TEXT)")
      }
    }
    try mirror.deleteMirror()
    #expect(!FileManager.default.fileExists(atPath: url.path))
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
      try mirror.apply(upserting: [one, two], deleting: [])
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
}
