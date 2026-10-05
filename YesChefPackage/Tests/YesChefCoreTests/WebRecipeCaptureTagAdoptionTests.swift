import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WebRecipeCaptureTagAdoptionTests {
    @Test
    func importWritesOnlyAdoptedTagsAndKeepsEveryHarvestedTagInSnapshot() async throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 804_500_000)
      let sourceURL = try #require(URL(string: "https://example.com/recipes/lemon-chicken"))
      var capturedDraft = try await WebRecipeCaptureClient(
        fetchHTML: { _ in
          #"<script type="application/ld+json">{"@type":"Recipe","name":"Soup","author":"Cook","keywords":"quick, weeknight","recipeIngredient":["1 cup water"],"recipeInstructions":["Boil"]}</script>"#
        },
        renderHTML: { _ in nil }
      ).capture(url: sourceURL, capturedAt: now)
      capturedDraft.adoptedTagNames = ["quick", "weeknight"]
      let draft = capturedDraft

      let uuids = LockedUUIDSequence(start: 24_500)
      let result = try await database.write { db in
        try RecipeRepository.importCapturedRecipe(draft, in: db, now: now, uuid: { uuids.next() })
      }

      try await database.read { db in
        let recipe = try #require(try Recipe.find(result.recipeID).fetchOne(db))
        let categories = try Category.fetchAll(db)
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let joins = try RecipeCategory.where { $0.recipeID.eq(recipe.id) }.fetchAll(db)
        expectNoDifference(
          joins.compactMap { categoriesByID[$0.categoryID]?.name }.sorted(),
          ["quick", "weeknight"]
        )
        let snapshot = try RecipeBundleCoding.decodeSnapshot(try #require(recipe.originalSnapshot))
        expectNoDifference(snapshot.tagNames, ["quick", "weeknight"])
      }
    }
  }
}

private final class LockedUUIDSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var nextValue: Int

  init(start: Int) {
    nextValue = start
  }

  func next() -> UUID {
    lock.withLock {
      defer { nextValue += 1 }
      return SampleUUIDSequence.uuid(nextValue)
    }
  }
}
