import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct DepositNoteTests {
    @Test
    func parsesSingleNoteFromJsonObject() {
      let plan = MenuDepositClient.parse(
        """
        ```json
        {"text":"  Use the note as the base; skip the romesco and push it Mexican.  "}
        ```
        """
      )

      expectNoDifference(
        plan,
        DepositNotePlan(note: DepositedNote(text: "Use the note as the base; skip the romesco and push it Mexican."))
      )
    }

    @Test
    func parsesEmptyPlanWhenTextIsBlankOrMissing() {
      expectNoDifference(MenuDepositClient.parse(#"{"text":"   "}"#), DepositNotePlan())
      expectNoDifference(MenuDepositClient.parse(#"{"other":"x"}"#), DepositNotePlan())
      expectNoDifference(MenuDepositClient.parse("not json"), DepositNotePlan())
    }

    @Test
    func depositedNoteRoundTripsEditableReviewText() {
      let note = DepositedNote(text: "Steal the taco intent; keep it in the menu's Mexican lane.")
      expectNoDifference(note.applyingEditableReviewText(note.editableReviewText()), note)
      expectNoDifference(
        note.applyingEditableReviewText("  Edited: lean harder on lime.  "),
        DepositedNote(text: "Edited: lean harder on lime.")
      )
    }

    @Test
    func clientPrefersExplicitSelectionOverTranscript() async throws {
      let recorder = DepositRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        _ = try await MenuDepositClient.liveValue(
          intelligence: "Use the note as the base.",
          messages: [
            RecipeChatMessage(role: .user, text: "Compare the recipe to the note."),
            RecipeChatMessage(role: .assistant, text: "The full compare verdict."),
          ],
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.captureToNote.rawValue)
      #expect(request?.messages.first?.text.contains("Use the note as the base.") == true)
      #expect(request?.messages.first?.text.contains("The full compare verdict.") == false)
    }

    @Test
    func clientFallsBackToLatestAssistantTurnWhenSelectionAbsent() async throws {
      let recorder = DepositRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        _ = try await MenuDepositClient.liveValue(
          intelligence: "",
          messages: [
            RecipeChatMessage(role: .assistant, text: "An earlier reply."),
            RecipeChatMessage(role: .user, text: "Adjust the note."),
            RecipeChatMessage(role: .assistant, text: "Push it toward the Mexican lane."),
          ],
          tier: .onDevice
        )
      }

      let request = await recorder.first()
      #expect(request?.messages.first?.text.contains("Push it toward the Mexican lane.") == true)
      #expect(request?.messages.first?.text.contains("An earlier reply.") == false)
      #expect(request?.messages.first?.text.contains("Adjust the note.") == false)
    }

    @Test
    func reviseSendsOriginalNoteBodyAndExplicitSelection() async throws {
      let recorder = DepositRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        _ = try await MenuDepositClient.liveValue(
          intelligence: "Push it toward the Mexican lane.",
          currentNoteBody: "Use the Milk Street romesco as written.",
          messages: [
            RecipeChatMessage(role: .user, text: "Compare the recipe to the note."),
            RecipeChatMessage(role: .assistant, text: "The full compare verdict."),
          ],
          tier: .frontier(.anthropic)
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.promptPreferenceKey, AIPromptPreferenceKind.captureToNote.rawValue)
      #expect(request?.messages.first?.text.contains("Use the Milk Street romesco as written.") == true)
      #expect(request?.messages.first?.text.contains("Push it toward the Mexican lane.") == true)
      #expect(request?.messages.first?.text.contains("The full compare verdict.") == false)
    }

    @Test
    func reviseFallsBackToLatestAssistantTurnWhenSelectionAbsent() async throws {
      let recorder = DepositRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        _ = try await MenuDepositClient.liveValue(
          intelligence: "",
          currentNoteBody: "Use the Milk Street romesco as written.",
          messages: [
            RecipeChatMessage(role: .assistant, text: "An earlier reply."),
            RecipeChatMessage(role: .user, text: "Adjust the note."),
            RecipeChatMessage(role: .assistant, text: "Push it toward the Mexican lane."),
          ],
          tier: .onDevice
        )
      }

      let request = await recorder.first()
      #expect(request?.messages.first?.text.contains("Push it toward the Mexican lane.") == true)
      #expect(request?.messages.first?.text.contains("An earlier reply.") == false)
      #expect(request?.messages.first?.text.contains("Use the Milk Street romesco as written.") == true)
    }

    @Test
    func reviseHandlesEmptyOriginalNote() async throws {
      let recorder = DepositRequestRecorder()

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"text":""}"#)
        }
      } operation: {
        _ = try await MenuDepositClient.liveValue(
          intelligence: "Push it toward the Mexican lane.",
          currentNoteBody: "",
          messages: [],
          tier: .onDevice
        )
      }

      let request = await recorder.first()
      #expect(request?.messages.first?.text.contains("The note is currently empty.") == true)
    }
  }
}

private actor DepositRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
