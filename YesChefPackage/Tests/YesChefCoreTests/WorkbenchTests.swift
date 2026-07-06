import CustomDump
import Dependencies
import Foundation
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
