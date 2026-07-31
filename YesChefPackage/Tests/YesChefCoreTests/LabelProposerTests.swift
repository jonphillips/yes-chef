import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct LabelProposerTests {
    @Test
    func proposesAgainstTheExistingTreeOnDevice() async throws {
      let cuisineID = SampleUUIDSequence.uuid(70_001)
      let italianID = SampleUUIDSequence.uuid(70_002)
      let categories = [
        Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: .distantPast),
        Category(id: italianID, name: "Italian", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: .distantPast),
      ]
      let recorder = LabelProposalRequestRecorder()
      let callRecords = ModelCallRecordCollector()

      let suggestions = try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"suggestions":[{"kind":"existingCategory","path":["Cuisine","Italian"]},{"kind":"loose","path":["weeknight"]}]}"#)
        }
        $0.modelCallRecordSink = .inMemory(callRecords)
        $0.labelProposer = .liveValue
      } operation: {
        try await LabelProposer.liveValue(
          recipe: .init(title: "Italian Weeknight Pasta", ingredientLines: ["spaghetti", "tomatoes"]),
          existingTree: categories
        )
      }

      expectNoDifference(suggestions, [
        SuggestedLabel(kind: .existingCategory, path: ["Cuisine", "Italian"]),
        SuggestedLabel(kind: .loose, path: ["weeknight"]),
      ])

      let request = await recorder.first()
      expectNoDifference(request?.tier, .onDevice)
      expectNoDifference(request?.reasoningEffort, .low)
      expectNoDifference(request?.maxTokens, LabelProposer.maxTokens)
      #expect(request?.messages.first?.text.contains("Cuisine > Italian") == true)
      #expect(request?.messages.first?.text.contains("Italian Weeknight Pasta") == true)

      let record = await callRecords.records().first
      expectNoDifference(record?.surface, .capture)
      expectNoDifference(record?.task, .categorization)
      expectNoDifference(record?.tier, .onDevice)
      expectNoDifference(record?.contextLayers, ModelCallContextLayers(included: [.recipe, .candidates]))
    }

    @Test
    func rejectsAnUnmappableSuggestionLoudly() {
      let cuisineID = SampleUUIDSequence.uuid(70_101)
      let categories = [Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)]

      #expect(throws: LabelProposerError.invalidSuggestion("Unknown is not an existing parent")) {
        try LabelProposer.parse(
          #"{"suggestions":[{"kind":"newChild","path":["Unknown","Korean"]}]}"#,
          categories: categories
        )
      }
    }

    @Test
    func rejectsConflictingKindsAtTheSameCategoryDestination() {
      #expect(throws: LabelProposerError.invalidSuggestion("the response repeated a category destination")) {
        try LabelProposer.parse(
          #"{"suggestions":[{"kind":"loose","path":["weeknight"]},{"kind":"namespace","path":["weeknight"]}]}"#,
          categories: []
        )
      }
    }

    @Test
    func truncatedResponseFailsLoudly() async {
      await #expect(throws: LabelProposerError.responseTruncated) {
        try await withDependencies {
          $0.modelClient = StubModelClient { _ in ModelResponse(text: "{", stopReason: "max_tokens") }
          $0.labelProposer = .liveValue
        } operation: {
          try await LabelProposer.liveValue(
            recipe: .init(title: "Soup"),
            existingTree: []
          )
        }
      }
    }
  }
}

private actor LabelProposalRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
