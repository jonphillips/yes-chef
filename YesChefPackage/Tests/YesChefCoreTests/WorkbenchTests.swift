import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchTests {
    @Test
    func createsWorkbenchWithCandidatesAndAnnotations() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_100_000)
      let recipeID = SampleUUIDSequence.uuid(20_001)
      let sectionID = SampleUUIDSequence.uuid(20_002)
      var uuids = SampleUUIDSequence(start: 20_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Birria One",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        try IngredientSection.insert {
          IngredientSection(id: sectionID, recipeID: recipeID, name: nil, sortOrder: 0)
        }
        .execute(db)
        try IngredientLine.insert {
          IngredientLine(
            id: SampleUUIDSequence.uuid(20_003),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "3 pounds chuck roast",
            sortOrder: 0
          )
        }
        .execute(db)

        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: " Birria  ",
          notes: "  compare chile technique  ",
          candidateRecipeIDs: [recipeID],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let detail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(detail.workbench.title, "Birria")
        expectNoDifference(detail.workbench.notes, "compare chile technique")
        expectNoDifference(detail.candidateRows.map(\.displayTitle), ["Birria One"])
        expectNoDifference(detail.candidateRows[0].recipeDetail?.ingredientLines.map(\.originalText), ["3 pounds chuck roast"])

        try WorkbenchRepository.updateWorkbenchTitle(
          workbenchID: workbenchID,
          title: "  Weeknight Birria  ",
          in: db,
          now: now.addingTimeInterval(30)
        )
        let renamedDetail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(renamedDetail.workbench.title, "Weeknight Birria")
        expectNoDifference(renamedDetail.workbench.dateModified, now.addingTimeInterval(30))

        try WorkbenchRepository.updateCandidateAnnotation(
          candidateID: detail.candidateRows[0].id,
          annotation: "  strong consommé  ",
          in: db,
          now: now.addingTimeInterval(60)
        )
        let updatedDetail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(updatedDetail.candidateRows.map(\.candidate.annotation), ["strong consommé"])
      }
    }

    @Test
    func workbenchDetailDeduplicatesCandidateRecipeReferencesAtReadTime() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_200_000)
      let recipeID = SampleUUIDSequence.uuid(21_001)
      var uuids = SampleUUIDSequence(start: 21_100)

      try database.write { db in
        try Recipe.insert {
          Recipe(
            id: recipeID,
            title: "Cookie A",
            dateCreated: now,
            dateModified: now
          )
        }
        .execute(db)
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Cookies",
          candidateRecipeIDs: [recipeID],
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        try WorkbenchCandidate.insert {
          WorkbenchCandidate(
            id: SampleUUIDSequence.uuid(21_999),
            workbenchID: workbenchID,
            recipeID: recipeID,
            recipeTitleSnapshot: "Duplicate Cookie",
            sortOrder: 100,
            dateCreated: now.addingTimeInterval(60)
          )
        }
        .execute(db)

        let detail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        expectNoDifference(detail.candidateRows.map(\.displayTitle), ["Cookie A"])
      }
    }

    @Test
    func workbenchChatSerializesFullIncludedCandidatesAndCapsBreadth() {
      let now = Date(timeIntervalSinceReferenceDate: 806_300_000)
      let candidates = (0..<6).map { index in
        WorkbenchCandidateChatContext(
          id: SampleUUIDSequence.uuid(22_100 + index),
          recipeID: SampleUUIDSequence.uuid(22_200 + index),
          title: "Candidate \(index)",
          annotation: index == 0 ? "Best texture." : nil,
          sortOrder: index,
          prepTimeMinutes: 10 + index,
          cookTimeMinutes: 20 + index,
          ingredientSections: [
            RecipeChatSection(name: "Sauce", lines: ["ingredient \(index)-0", "ingredient \(index)-1"])
          ],
          instructionSections: [
            RecipeChatSection(name: "Method", lines: ["Toast chiles \(index).", "Braise until tender \(index)."])
          ],
          notes: ["note \(index)"]
        )
      }
      let context = WorkbenchChatContext(
        workbenchID: SampleUUIDSequence.uuid(22_001),
        title: "Birria",
        notes: "Find the best consommé.",
        candidates: candidates
      )

      let serialized = context.serialized(characterBudget: 100_000)

      #expect(serialized.contains("- Title: Birria"))
      #expect(serialized.contains("- Workbench notes: Find the best consommé."))
      #expect(serialized.contains("- Candidate 0"))
      #expect(serialized.contains("  - Cook annotation: Best texture."))
      #expect(serialized.contains("      - Toast chiles 0."))
      #expect(serialized.contains("      - Braise until tender 0."))
      #expect(serialized.contains("- Candidate 4"))
      #expect(!serialized.contains("- Candidate 5"))
      #expect(
        serialized.contains(
          "1 lower-priority candidate(s) were omitted so included candidates keep full ingredients and instructions."
        )
      )
      _ = now
    }

    @Test @MainActor
    func workbenchPromptUsesTaskFraming() {
      let model = RecipeChatModel(
        context: .workbench(
          WorkbenchChatContext(
            title: "Cookies",
            candidates: [
              WorkbenchCandidateChatContext(
                id: SampleUUIDSequence.uuid(24_001),
                title: "Chewy Cookie",
                sortOrder: 0
              )
            ]
          )
        )
      )

      let prompt = model.systemPrompt()

      #expect(prompt.contains(RecipeChatContext.workbenchTaskFraming))
      #expect(prompt.contains("don't blend everything into a bland average"))
    }

    @Test
    func parsesWorkbenchDraftRecipeJSON() {
      let proposal = WorkbenchDraftRecipeClient.parse(
        """
        Here is the draft:
        {"title":"Weeknight Birria","summary":"Chile-forward and practical.","servingsText":"6 servings","prepTimeMinutes":30,"cookTimeMinutes":180,"ingredientSectionName":"Birria","ingredientLines":["3 lb chuck roast","4 guajillo chiles"],"instructionLines":["Toast and soak chiles.","Braise beef until tender."],"notes":["Variation: keep a hotter salsa on the side."],"rationale":"Borrows Candidate A's chile paste and Candidate B's oven braise; rejects Candidate C's watery blend."}
        """
      )

      expectNoDifference(proposal.title, "Weeknight Birria")
      expectNoDifference(proposal.prepTimeMinutes, 30)
      expectNoDifference(proposal.ingredientLines, ["3 lb chuck roast", "4 guajillo chiles"])
      expectNoDifference(proposal.instructionLines, ["Toast and soak chiles.", "Braise beef until tender."])
      #expect(proposal.rationale.contains("Candidate A"))
    }

    @Test
    func draftClientThrowsWhenResponseIsBudgetTruncated() async throws {
      // Reasoning ate the token budget: empty body with a truncation stop reason.
      await withDependencies {
        $0.modelClient = StubModelClient { _ in ModelResponse(text: "", stopReason: "length") }
      } operation: {
        await #expect(throws: WorkbenchDraftRecipeError.responseTruncated) {
          try await WorkbenchDraftRecipeClient.liveValue(
            selection: "",
            messages: [],
            context: "Workbench: Birria",
            tier: .frontier(.openai)
          )
        }
      }
    }

    @Test
    func draftClientThrowsWhenResponseHasNoReadableJSON() async throws {
      await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(text: "I can't build a recipe from this.", stopReason: "stop")
        }
      } operation: {
        await #expect(throws: WorkbenchDraftRecipeError.responseUnreadable) {
          try await WorkbenchDraftRecipeClient.liveValue(
            selection: "",
            messages: [],
            context: "Workbench: Birria",
            tier: .frontier(.openai)
          )
        }
      }
    }

    @Test
    func draftClientReturnsEmptyDraftForDeliberateNoRecipe() async throws {
      // A genuine "nothing to draft yet" is valid JSON with an empty title — not an error.
      let draft = try await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(
            text: #"{"title":"","ingredientLines":[],"instructionLines":[],"rationale":""}"#,
            stopReason: "stop"
          )
        }
      } operation: {
        try await WorkbenchDraftRecipeClient.liveValue(
          selection: "",
          messages: [],
          context: "Workbench: Birria",
          tier: .frontier(.openai)
        )
      }

      #expect(draft.isEmpty)
    }

    @Test
    func createsReferenceDraftRecipeLinksWorkbenchAndCapturesSnapshot() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_500_000)
      var uuids = SampleUUIDSequence(start: 25_000)

      let draft = WorkbenchDraftRecipe(
        title: "Weeknight Birria",
        summary: "Chile-forward and practical.",
        servingsText: "6 servings",
        prepTimeMinutes: 30,
        cookTimeMinutes: 180,
        ingredientSectionName: "Birria",
        ingredientLines: ["3 lb chuck roast", "4 guajillo chiles"],
        instructionLines: ["Toast and soak chiles.", "Braise beef until tender."],
        notes: ["Variation: keep a hotter salsa on the side."],
        rationale: "Borrows Candidate A's chile paste and Candidate B's oven braise."
      )

      try database.write { db in
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Birria",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let recipeID = try WorkbenchRepository.createDraftRecipe(
          draft,
          for: workbenchID,
          in: db,
          now: now.addingTimeInterval(10),
          uuid: { uuids.next() }
        )
        let detail = try #require(try WorkbenchDetailRequest(workbenchID: workbenchID).fetch(db))
        let recipe = try #require(detail.draftRecipeDetail?.recipe)

        expectNoDifference(detail.workbench.draftRecipeID, recipeID)
        expectNoDifference(recipe.title, "Weeknight Birria")
        expectNoDifference(recipe.libraryPlacement, .reference)
        #expect(recipe.originalSnapshot != nil)
        expectNoDifference(
          detail.draftRecipeDetail?.ingredientLines.map(\.originalText),
          ["3 lb chuck roast", "4 guajillo chiles"]
        )
        expectNoDifference(
          detail.draftRecipeDetail?.instructionSteps.map(\.text),
          ["Toast and soak chiles.", "Braise beef until tender."]
        )

        let snapshotData = try #require(recipe.originalSnapshot)
        let snapshot = try RecipeBundleCoding.decodeSnapshot(snapshotData)
        expectNoDifference(snapshot.recipe.libraryPlacement, .reference)
        #expect(snapshot.notes.contains { $0.contains("Borrows Candidate A") })
      }
    }

    @Test
    func promotesWorkbenchDraftRecipeToMainLibrary() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_600_000)
      var uuids = SampleUUIDSequence(start: 26_000)

      try database.write { db in
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Cookies",
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let recipeID = try WorkbenchRepository.createDraftRecipe(
          WorkbenchDraftRecipe(
            title: "Brown Butter Cookies",
            ingredientLines: ["1 cup brown butter"],
            instructionLines: ["Bake until set."],
            rationale: "Uses Candidate A's brown butter."
          ),
          for: workbenchID,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        try WorkbenchRepository.promoteDraftRecipe(
          workbenchID: workbenchID,
          in: db,
          now: now.addingTimeInterval(60)
        )

        let recipe = try #require(try Recipe.find(recipeID).fetchOne(db))
        expectNoDifference(recipe.libraryPlacement, .main)
        expectNoDifference(recipe.dateModified, now.addingTimeInterval(60))
      }
    }

    @Test
    func removingUnpromotedDraftDeletesRecipeAndClearsLink() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_700_000)
      var uuids = SampleUUIDSequence(start: 27_000)

      try database.write { db in
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Cookies", in: db, now: now, uuid: { uuids.next() }
        )
        let recipeID = try WorkbenchRepository.createDraftRecipe(
          WorkbenchDraftRecipe(
            title: "Brown Butter Cookies",
            ingredientLines: ["1 cup brown butter"],
            instructionLines: ["Bake until set."],
            rationale: "Uses Candidate A's brown butter."
          ),
          for: workbenchID, in: db, now: now, uuid: { uuids.next() }
        )

        let removed = try WorkbenchRepository.removeDraftRecipe(
          workbenchID: workbenchID, in: db, now: now.addingTimeInterval(30)
        )

        expectNoDifference(removed, recipeID)
        // Scratch draft is gone, and the link is cleared so the workbench can draft again.
        #expect(try Recipe.find(recipeID).fetchOne(db) == nil)
        let workbench = try #require(try Workbench.find(workbenchID).fetchOne(db))
        #expect(workbench.draftRecipeID == nil)
      }
    }

    @Test
    func removingPromotedDraftKeepsRecipeAndOnlyUnlinks() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 806_800_000)
      var uuids = SampleUUIDSequence(start: 28_000)

      try database.write { db in
        let workbenchID = try WorkbenchRepository.addWorkbench(
          title: "Cookies", in: db, now: now, uuid: { uuids.next() }
        )
        let recipeID = try WorkbenchRepository.createDraftRecipe(
          WorkbenchDraftRecipe(
            title: "Brown Butter Cookies",
            ingredientLines: ["1 cup brown butter"],
            instructionLines: ["Bake until set."],
            rationale: "Uses Candidate A's brown butter."
          ),
          for: workbenchID, in: db, now: now, uuid: { uuids.next() }
        )
        try WorkbenchRepository.promoteDraftRecipe(
          workbenchID: workbenchID, in: db, now: now
        )

        let removed = try WorkbenchRepository.removeDraftRecipe(
          workbenchID: workbenchID, in: db, now: now.addingTimeInterval(30)
        )

        // A promoted recipe is kept in the library; only the workbench link is cleared.
        #expect(removed == nil)
        #expect(try Recipe.find(recipeID).fetchOne(db) != nil)
        let workbench = try #require(try Workbench.find(workbenchID).fetchOne(db))
        #expect(workbench.draftRecipeID == nil)
      }
    }

    @Test @MainActor
    func recipeChatModelRefreshesWorkbenchContextWithoutReplacingThread() {
      let workbenchID = SampleUUIDSequence.uuid(23_001)
      let firstCandidateID = SampleUUIDSequence.uuid(23_101)
      let secondCandidateID = SampleUUIDSequence.uuid(23_102)

      withDependencies {
        $0.date.now = Date(timeIntervalSinceReferenceDate: 806_400_000)
      } operation: {
        let model = RecipeChatModel(
          context: .workbench(
            WorkbenchChatContext(
              workbenchID: workbenchID,
              title: "Cookies",
              candidates: [
                WorkbenchCandidateChatContext(
                  id: firstCandidateID,
                  title: "Crisp Cookie",
                  sortOrder: 0,
                  ingredientSections: [RecipeChatSection(name: nil, lines: ["butter"])],
                  instructionSections: [RecipeChatSection(name: nil, lines: ["Bake until crisp."])]
                )
              ]
            )
          )
        )

        model.updateContext(
          .workbench(
            WorkbenchChatContext(
              workbenchID: workbenchID,
              title: "Cookies",
              candidates: [
                WorkbenchCandidateChatContext(
                  id: firstCandidateID,
                  title: "Crisp Cookie",
                  sortOrder: 0,
                  ingredientSections: [RecipeChatSection(name: nil, lines: ["butter"])],
                  instructionSections: [RecipeChatSection(name: nil, lines: ["Bake until crisp."])]
                ),
                WorkbenchCandidateChatContext(
                  id: secondCandidateID,
                  title: "Chewy Cookie",
                  sortOrder: 1,
                  ingredientSections: [RecipeChatSection(name: nil, lines: ["brown sugar"])],
                  instructionSections: [RecipeChatSection(name: nil, lines: ["Rest the dough."])]
                )
              ]
            )
          )
        )

        let prompt = model.systemPrompt()
        #expect(prompt.contains("- Chewy Cookie"))
        #expect(prompt.contains("Rest the dough."))
      }
    }
  }
}
