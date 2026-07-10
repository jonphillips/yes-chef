import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuNoteHarvestTests {
    @Test
    func parsesDistinctNotesFromJsonArray() {
      let plan = MenuNoteHarvestClient.parse(
        """
        ```json
        [
          {"title":"  Chile-lime cauliflower  ","body":"  Roast until browned.\\nFinish with lime.  "},
          {"title":"Cucumber salad","body":""},
          {"title":"   ","body":"Ignore this"},
          {"title":"No body"}
        ]
        ```
        """
      )

      expectNoDifference(
        plan,
        MenuNoteHarvestPlan(
          notes: [
            HarvestedNote(title: "Chile-lime cauliflower", body: "Roast until browned.\nFinish with lime."),
            HarvestedNote(title: "Cucumber salad"),
            HarvestedNote(title: "No body"),
          ]
        )
      )
    }

    @Test
    func harvestedNoteRoundTripsEditableReviewTextAndEditsBody() {
      let note = HarvestedNote(
        title: "Chile-lime cauliflower",
        body: "Roast until browned.\nFinish with lime."
      )

      expectNoDifference(note.applyingEditableReviewText(note.editableReviewText()), note)
      expectNoDifference(
        note.applyingEditableReviewText(
          """
          Charred cauliflower
          Roast until deeply browned.
          Finish with lime and cilantro.
          """
        ),
        HarvestedNote(
          title: "Charred cauliflower",
          body: "Roast until deeply browned.\nFinish with lime and cilantro."
        )
      )
    }

    @Test
    func clientUsesOnlyExplicitSelectionAndStillCallsModel() async throws {
      let recorder = MenuNoteHarvestRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: "[]")
        }
      } operation: {
        _ = try await MenuNoteHarvestClient.liveValue(
          selection: "The cauliflower paragraph.",
          messages: [
            RecipeChatMessage(role: .user, text: "Please suggest a menu."),
            RecipeChatMessage(role: .assistant, text: "The full assistant reply."),
          ],
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.anthropic))
      expectNoDifference(request?.reasoningEffort, .medium)
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.captureToNote.rawValue)
      #expect(request?.messages.first?.text.contains("The cauliflower paragraph.") == true)
      #expect(request?.messages.first?.text.contains("The full assistant reply.") == false)
      #expect(request?.messages.first?.text.contains("Please suggest a menu.") == false)
    }

    @Test
    func clientScansOnlyAssistantTurnsWhenSelectionIsAbsent() async throws {
      let recorder = MenuNoteHarvestRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: "[]")
        }
      } operation: {
        _ = try await MenuNoteHarvestClient.liveValue(
          selection: "",
          messages: [
            RecipeChatMessage(role: .user, text: "Make it spicy."),
            RecipeChatMessage(role: .assistant, text: "Roast the cauliflower with chile and lime."),
          ],
          tier: .onDevice
        )
      }

      let request = await recorder.first()
      #expect(request?.messages.first?.text.contains("Roast the cauliflower with chile and lime.") == true)
      #expect(request?.messages.first?.text.contains("Make it spicy.") == false)
    }

    @Test
    func capturedNoteUsesNoteKindWithoutRecipeIDAndMenuOrdering() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_800_000)
      let menuID = SampleUUIDSequence.uuid(15_600)
      var uuids = SampleUUIDSequence(start: 15_610)

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Harvest Menu", dayCount: 2, dateCreated: now, dateModified: now)
        }
        .execute(db)

        _ = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Existing dinner",
          notes: nil,
          dayOffset: 0,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )
        let capturedID = try MenuRepository.addNoteItem(
          menuID: menuID,
          title: "Chile-lime cauliflower",
          notes: "Roast until browned.",
          dayOffset: 0,
          mealSlot: .dinner,
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let captured = try #require(try MenuItem.find(capturedID).fetchOne(db))
        expectNoDifference(captured.kind, .note)
        expectNoDifference(captured.recipeID, nil)
        expectNoDifference(captured.notes, "Roast until browned.")
        expectNoDifference(captured.sortOrder, 1)
      }
    }
  }
}

private actor MenuNoteHarvestRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
