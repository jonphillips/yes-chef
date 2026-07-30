import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CategoryFoldTests {
    @Test
    func foldReusesTagAndJoinIdentifiersAndIsIdempotent() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_000_000)
      let recipeID = SampleUUIDSequence.uuid(49_001)
      let tagID = SampleUUIDSequence.uuid(49_002)
      let recipeTagID = SampleUUIDSequence.uuid(49_003)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Folded Tag", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Tag.insert {
          Tag(id: tagID, name: "Weeknight", color: "orange", sortOrder: 4, dateCreated: now)
        }
        .execute(db)
        try RecipeTag.insert {
          RecipeTag(id: recipeTagID, recipeID: recipeID, tagID: tagID, sortOrder: 0)
        }
        .execute(db)

        try CategoryRepository.foldDormantTagsIntoCategories(in: db)
        let afterFirstFold = try categoryFoldSnapshot(in: db)
        try CategoryRepository.foldDormantTagsIntoCategories(in: db)
        expectNoDifference(try categoryFoldSnapshot(in: db), afterFirstFold)
      }

      try database.read { db in
        let snapshot = try categoryFoldSnapshot(in: db)
        expectNoDifference(snapshot.categories.map(\.id), [tagID])
        expectNoDifference(snapshot.categories.map(\.name), ["Weeknight"])
        expectNoDifference(snapshot.categories.map(\.color), ["orange"])
        expectNoDifference(snapshot.recipeCategories.map(\.id), [recipeTagID])
        expectNoDifference(snapshot.recipeCategories.map(\.categoryID), [tagID])
        // The legacy source rows stay registered for CloudKit but are no longer touched by app code.
        expectNoDifference(snapshot.tags.map(\.id), [tagID])
        expectNoDifference(snapshot.recipeTags.map(\.id), [recipeTagID])
      }
    }

    @Test
    func foldMergesSameNamedRootAndDeduplicatesTheRecipePair() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_100_000)
      let recipeID = SampleUUIDSequence.uuid(49_101)
      let tagID = SampleUUIDSequence.uuid(49_102)
      let nativeCategoryID = SampleUUIDSequence.uuid(49_103)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Vegetable Side", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Tag.insert {
          Tag(id: tagID, name: "Veg", color: "green", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try RecipeTag.insert {
          RecipeTag(id: SampleUUIDSequence.uuid(49_104), recipeID: recipeID, tagID: tagID, sortOrder: 0)
        }
        .execute(db)
        try Category.insert {
          Category(id: nativeCategoryID, name: "veg", sortOrder: 0, dateCreated: now.addingTimeInterval(-1))
        }
        .execute(db)
        try RecipeCategory.insert {
          RecipeCategory(id: SampleUUIDSequence.uuid(49_105), recipeID: recipeID, categoryID: nativeCategoryID)
        }
        .execute(db)

        try CategoryRepository.foldDormantTagsIntoCategories(in: db)
      }

      try database.read { db in
        let snapshot = try categoryFoldSnapshot(in: db)
        expectNoDifference(snapshot.categories.map(\.id), [nativeCategoryID])
        expectNoDifference(snapshot.categories.map(\.color), ["green"])
        expectNoDifference(snapshot.recipeCategories.map(\.categoryID), [nativeCategoryID])
        expectNoDifference(snapshot.recipeCategories.count, 1)
      }
    }

    @Test
    func rerunConvergesAConcurrentTagCategoryWithTheNativeRoot() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 815_200_000)
      let recipeID = SampleUUIDSequence.uuid(49_201)
      let tagID = SampleUUIDSequence.uuid(49_202)
      let nativeCategoryID = SampleUUIDSequence.uuid(49_203)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Two Device Veg", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Tag.insert {
          Tag(id: tagID, name: "Veg", color: "green", sortOrder: 0, dateCreated: now)
        }
        .execute(db)
        try RecipeTag.insert {
          RecipeTag(id: SampleUUIDSequence.uuid(49_204), recipeID: recipeID, tagID: tagID, sortOrder: 0)
        }
        .execute(db)
        try CategoryRepository.foldDormantTagsIntoCategories(in: db)

        // This is the category independently created on a peer before both devices exchange rows.
        try Category.insert {
          Category(id: nativeCategoryID, name: "veg", sortOrder: 0, dateCreated: now.addingTimeInterval(-1))
        }
        .execute(db)
        try CategoryRepository.foldDormantTagsIntoCategories(in: db)
      }

      try database.read { db in
        let snapshot = try categoryFoldSnapshot(in: db)
        expectNoDifference(snapshot.categories.map(\.id), [nativeCategoryID])
        expectNoDifference(snapshot.categories.map(\.color), ["green"])
        expectNoDifference(Set(snapshot.recipeCategories.map(\.categoryID)), [nativeCategoryID])
      }
    }
  }
}

private struct CategoryFoldSnapshot: Equatable {
  var tags: [YesChefCore.Tag]
  var recipeTags: [YesChefCore.RecipeTag]
  var categories: [YesChefCore.Category]
  var recipeCategories: [YesChefCore.RecipeCategory]
}

private func categoryFoldSnapshot(in db: Database) throws -> CategoryFoldSnapshot {
  CategoryFoldSnapshot(
    tags: try Tag.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString },
    recipeTags: try RecipeTag.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString },
    categories: try Category.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString },
    recipeCategories: try RecipeCategory.fetchAll(db).sorted { $0.id.uuidString < $1.id.uuidString }
  )
}
