import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  /// ADR-0021 Amd2-D4: deleting a variation, and the cross-device tolerance for a dangling active
  /// selection that outlives the synced row it points at.
  @Suite
  struct RecipeVariationDeleteTests {
    @Test
    func deleteVariationRemovesRowAndClearsActiveOnlyWhenItWasActive() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_330_000)
      let recipeID = SampleUUIDSequence.uuid(34_001)
      let sectionID = SampleUUIDSequence.uuid(34_002)
      let lineID = SampleUUIDSequence.uuid(34_003)
      var uuids = SampleUUIDSequence(start: 34_100)

      let variations = try database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now) }.execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0)
        }
        .execute(db)
        let smoky = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "1 tablespoon smoked lemon juice")]
          ),
          recipeID: recipeID, name: "Smoky", deliberationBody: nil, in: db, now: now, uuid: { uuids.next() }
        )
        let lime = try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "2 tablespoons lime juice")]
          ),
          recipeID: recipeID, name: "Lime", deliberationBody: nil, in: db, now: now, uuid: { uuids.next() }
        )
        // Make Smoky the active selection so a non-active delete has something to leave alone.
        try RecipeRepository.setActiveVariation(smoky.id, recipeID: recipeID, in: db, now: now, uuid: { uuids.next() })
        return (smoky, lime)
      }

      // Deleting the non-active variation removes its row and leaves the active selection intact.
      try database.write { db in
        try RecipeRepository.deleteVariation(variations.1.id, in: db, now: now.addingTimeInterval(60), uuid: { uuids.next() })
      }
      try database.read { db in
        #expect(try RecipeVariation.find(variations.1.id).fetchOne(db) == nil)
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.variations.map(\.name), ["Smoky"])
        expectNoDifference(detail.activeVariationID, variations.0.id)
      }

      // Deleting the active variation removes its row and clears the active selection.
      try database.write { db in
        try RecipeRepository.deleteVariation(variations.0.id, in: db, now: now.addingTimeInterval(120), uuid: { uuids.next() })
      }
      try database.read { db in
        #expect(try RecipeVariation.find(variations.0.id).fetchOne(db) == nil)
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))
        expectNoDifference(detail.variations.map(\.name), [])
        expectNoDifference(detail.activeVariationID, nil)
        // The active row is genuinely gone, not merely filtered out at read time.
        let activeRows = try RecipeActiveVariation.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
        expectNoDifference(activeRows, [])
      }
    }

    @Test
    func fetchDetailApplyingActiveVariationDegradesToBaseWhenActiveVariationIsMissing() throws {
      // Cross-device (Amd4-D5): device A deletes a variation and the delete syncs; on device B
      // the local, unsynced active-selection row still points at the now-missing variation. The
      // read path must degrade to the base recipe rather than crash or fold a stale overlay.
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 819_340_000)
      let recipeID = SampleUUIDSequence.uuid(34_501)
      let sectionID = SampleUUIDSequence.uuid(34_502)
      let lineID = SampleUUIDSequence.uuid(34_503)
      var uuids = SampleUUIDSequence(start: 34_600)

      let variation = try database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Pasta", dateCreated: now, dateModified: now) }.execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: "Sauce", sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(id: lineID, recipeID: recipeID, sectionID: sectionID, originalText: "1 tablespoon lemon juice", sortOrder: 0)
        }
        .execute(db)
        return try RecipeRepository.keepAdjustmentProposalAsVariation(
          RecipeAdjustmentProposal(
            ingredientOps: [.substitute(RecipeIngredientReference(id: lineID), line: "2 tablespoons lime juice")]
          ),
          recipeID: recipeID, name: "Lime", deliberationBody: nil, in: db, now: now, uuid: { uuids.next() }
        )
      }

      // Delete the synced row directly, leaving the local active-selection row dangling.
      try database.write { db in
        try RecipeVariation.find(variation.id).delete().execute(db)
      }

      try database.read { db in
        let resolved = try #require(
          try RecipeRepository.fetchDetailApplyingActiveVariation(recipeID: recipeID, in: db)
        )
        expectNoDifference(resolved.variation, nil)
        expectNoDifference(resolved.unresolvedAnchors, [])
        expectNoDifference(resolved.detail.ingredientLines.map(\.originalText), ["1 tablespoon lemon juice"])
        expectNoDifference(resolved.detail.activeVariationID, nil)
        // The dangling active row is still present — it is unsynced local state, not cleaned up here.
        let activeRows = try RecipeActiveVariation.where { $0.recipeID.eq(recipeID) }.fetchAll(db)
        #expect(activeRows.count == 1)
      }
    }
  }
}
