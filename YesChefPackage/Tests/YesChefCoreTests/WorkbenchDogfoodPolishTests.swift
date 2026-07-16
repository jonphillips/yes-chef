import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchDogfoodPolishTests {
    @Test
    func workbenchChatUsesCandidateTitleAndSourceWithoutObjectIDs() {
      let candidateID = SampleUUIDSequence.uuid(22_900)
      let recipeID = SampleUUIDSequence.uuid(22_901)
      let serialized = WorkbenchChatContext(
        title: "Birria",
        candidates: [
          WorkbenchCandidateChatContext(
            id: candidateID,
            recipeID: recipeID,
            title: "Chile-Forward Birria",
            sourceName: "Serious Eats",
            sortOrder: 0
          )
        ]
      )
      .serialized(characterBudget: 100_000)

      #expect(serialized.contains("- Chile-Forward Birria"))
      #expect(serialized.contains("  - Source: Serious Eats"))
      #expect(!serialized.contains(candidateID.uuidString))
      #expect(!serialized.contains(recipeID.uuidString))
    }

    @Test
    func movingAllCandidatesToReferencePlacesRecipesAndClearsCandidateLinks() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_900_000)
      let firstRecipeID = SampleUUIDSequence.uuid(29_001)
      let secondRecipeID = SampleUUIDSequence.uuid(29_002)
      var uuids = SampleUUIDSequence(start: 29_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: firstRecipeID, title: "First", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try Recipe.insert {
          Recipe(id: secondRecipeID, title: "Second", dateCreated: now, dateModified: now)
        }
        .execute(db)
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Candidates",
          candidateRecipeIDs: [firstRecipeID, secondRecipeID],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try WorkbenchRepository.moveAllCandidatesToReference(
          for: workbenchID,
          in: db,
          now: now.addingTimeInterval(60)
        )

        let first = try #require(try Recipe.find(firstRecipeID).fetchOne(db))
        let second = try #require(try Recipe.find(secondRecipeID).fetchOne(db))
        expectNoDifference(first.libraryPlacement, .reference)
        expectNoDifference(second.libraryPlacement, .reference)
        #expect(!first.archived)
        #expect(!second.archived)
        let detail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        #expect(detail.candidateRows.isEmpty)
        expectNoDifference(detail.workbench.dateModified, now.addingTimeInterval(60))
      }
    }

    @Test
    func candidatePhotoSelectionCopiesBytesToWorkingRecipeAndSetsCover() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 807_000_000)
      let candidateRecipeID = SampleUUIDSequence.uuid(30_001)
      var uuids = SampleUUIDSequence(start: 30_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: candidateRecipeID, title: "Photo Candidate", dateCreated: now, dateModified: now)
        }
        .execute(db)
        let sourcePhotoID = SampleUUIDSequence.uuid(30_002)
        try RecipePhoto.insert {
          RecipePhoto(
            id: sourcePhotoID,
            recipeID: candidateRecipeID,
            imageDataReference: "photos/source",
            displayData: Data([1, 2, 3]),
            thumbnailData: Data([4, 5]),
            kind: .gallery,
            caption: "Candidate image",
            sortOrder: 0,
            dateCreated: now
          )
        }
        .execute(db)

        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Photo Workbench",
          candidateRecipeIDs: [candidateRecipeID],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let draftRecipeID = try WorkbenchRepository.createDraftRecipe(
          WorkbenchDraftRecipe(
            title: "Working Recipe",
            ingredientLines: ["1 ingredient"],
            instructionLines: ["Cook it."],
            rationale: "Uses the candidate image."
          ),
          for: workbenchID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let copiedPhotoID = try WorkbenchRepository.copyCandidatePhotoToDraft(
          photoID: sourcePhotoID,
          for: workbenchID,
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { uuids.next() }
        )
        let copied = try #require(try RecipePhoto.find(copiedPhotoID).fetchOne(db))
        let draft = try #require(try Recipe.find(draftRecipeID).fetchOne(db))
        expectNoDifference(copied.recipeID, draftRecipeID)
        expectNoDifference(copied.displayData, Data([1, 2, 3]))
        expectNoDifference(copied.thumbnailData, Data([4, 5]))
        expectNoDifference(copied.kind, .hero)
        expectNoDifference(draft.coverPhotoID, copiedPhotoID)
      }
    }

    @Test
    func promotedRecipeLinksBackToCandidatesAndFallsBackToSnapshot() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 807_100_000)
      let candidateRecipeID = SampleUUIDSequence.uuid(31_001)
      var uuids = SampleUUIDSequence(start: 31_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(id: candidateRecipeID, title: "Source Candidate", dateCreated: now, dateModified: now)
        }
        .execute(db)
        try RecipeSource.insert {
          RecipeSource(
            id: SampleUUIDSequence.uuid(31_002),
            recipeID: candidateRecipeID,
            name: "Cookbook"
          )
        }
        .execute(db)
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Links",
          candidateRecipeIDs: [candidateRecipeID],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let draftRecipeID = try WorkbenchRepository.createDraftRecipe(
          WorkbenchDraftRecipe(
            title: "Promoted",
            ingredientLines: ["1 ingredient"],
            instructionLines: ["Cook it."],
            rationale: "Keeps the source choice."
          ),
          for: workbenchID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        var links = try RecipeWorkbenchLinksRequest(recipeID: draftRecipeID).fetch(db)
        expectNoDifference(links.map(\.title), ["Source Candidate"])
        expectNoDifference(links.map(\.sourceName), ["Cookbook"])
        #expect(links[0].recipeID == candidateRecipeID)

        try Recipe.find(candidateRecipeID).delete().execute(db)
        links = try RecipeWorkbenchLinksRequest(recipeID: draftRecipeID).fetch(db)
        expectNoDifference(links.map(\.title), ["Source Candidate"])
        #expect(links[0].recipeID == nil)
      }
    }
  }
}
