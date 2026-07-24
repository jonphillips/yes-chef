import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipeDeliberationLogTests {
    @Test
    func adjustmentCommitsStoreTheirProseWithoutSynthesizingMissingRationales() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_330_000)
      let recipeID = SampleUUIDSequence.uuid(33_701)
      var uuids = SampleUUIDSequence(start: 33_800)
      let overwriteBody = "  Brown the butter first — it gives the sauce more depth.  \n"
      let variationBody = "Use lime instead of lemon so the dish stays bright."

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        _ = try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          RecipeAdjustmentProposal(),
          recipeID: recipeID,
          deliberationBody: overwriteBody,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let variation = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(),
          recipeID: recipeID,
          name: "Lime",
          deliberationBody: variationBody,
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
        _ = try RecipeRepository.overwriteRecipeWithAdjustmentProposal(
          RecipeAdjustmentProposal(),
          recipeID: recipeID,
          deliberationBody: nil,
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { uuids.next() }
        )

        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(
          detail.deliberationLogEntries.map(\.body),
          [variationBody, overwriteBody]
        )
        expectNoDifference(
          detail.deliberationLogEntries.map(\.variationID),
          [variation.id, nil]
        )
      }
    }

    @Test
    func splitOffCopiesDeliberationLogAndDropsTheCrossRecipeVariationReference() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_340_000)
      let recipeID = SampleUUIDSequence.uuid(33_901)
      var uuids = SampleUUIDSequence(start: 34_000)

      let variation = try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        let variation = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(),
          recipeID: recipeID,
          name: "Lime",
          deliberationBody: nil,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try RecipeRepository.addDeliberationLogEntry(
          body: "Keep the lemon version as the baseline.",
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try RecipeRepository.addDeliberationLogEntry(
          body: "Lime makes the dish brighter.",
          recipeID: recipeID,
          variationID: variation.id,
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
        return variation
      }

      let standaloneID = try database.write { db in
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        return try RecipeRepository.splitVariationOff(
          variation.id,
          resolvedDetail: try detail.resolved(applying: variation),
          name: "Lime Pasta",
          in: db,
          now: now.addingTimeInterval(120),
          uuid: { uuids.next() }
        )
      }

      try database.read { db in
        let originalEntries = try RecipeDeliberationLogEntry
          .where { $0.recipeID.eq(recipeID) }
          .order { $0.dateCreated }
          .fetchAll(db)
        let copiedEntries = try RecipeDeliberationLogEntry
          .where { $0.recipeID.eq(standaloneID) }
          .order { $0.dateCreated }
          .fetchAll(db)

        expectNoDifference(copiedEntries.map(\.body), originalEntries.map(\.body))
        expectNoDifference(copiedEntries.map(\.dateCreated), originalEntries.map(\.dateCreated))
        #expect(originalEntries.contains { $0.variationID == variation.id })
        #expect(copiedEntries.allSatisfy { $0.variationID == nil })
        let originalIDs = Set(originalEntries.map(\.id))
        #expect(copiedEntries.allSatisfy { !originalIDs.contains($0.id) })
      }
    }

    @Test
    func deletingARecipeCascadesItsDeliberationLog() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_350_000)
      let recipeID = SampleUUIDSequence.uuid(34_101)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try RecipeRepository.addDeliberationLogEntry(
          body: "The sauce needs more depth.",
          recipeID: recipeID,
          in: db,
          now: now,
          uuid: { SampleUUIDSequence.uuid(34_102) }
        )
        try Recipe.find(recipeID).delete().execute(db)
        #expect(try RecipeDeliberationLogEntry.fetchAll(db).isEmpty)
      }
    }
  }
}
