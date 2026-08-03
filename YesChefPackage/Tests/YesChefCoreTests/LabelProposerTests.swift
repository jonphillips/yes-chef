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
    func proposesAgainstVisibleTypedVocabularyOnDevice() async throws {
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_001), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)
      let italian = Category(id: SampleUUIDSequence.uuid(70_002), name: "Italian", facetID: cuisine.id, sortOrder: 0, dateCreated: .distantPast)
      let vocabulary = LabelVocabulary(facets: [cuisine], categories: [italian])
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
          vocabulary: vocabulary
        )
      }

      expectNoDifference(suggestions.accepted, [
        .existingCategory(italian),
        .loose("weeknight"),
      ])
      #expect(suggestions.rejected.isEmpty)

      let request = await recorder.first()
      expectNoDifference(request?.tier, .onDevice)
      expectNoDifference(request?.reasoningEffort, .low)
      expectNoDifference(request?.maxTokens, LabelProposer.maxTokens)
      #expect(request?.messages.first?.text.contains("Cuisine:\n  - Italian") == true)
      #expect(request?.messages.first?.text.contains("Italian Weeknight Pasta") == true)

      let record = await callRecords.records().first
      expectNoDifference(record?.surface, .capture)
      expectNoDifference(record?.task, .categorization)
      expectNoDifference(record?.tier, .onDevice)
      expectNoDifference(record?.contextLayers, ModelCallContextLayers(included: [.recipe, .candidates]))
    }

    @Test
    func excludesHiddenFacetsAndValuesFromVocabulary() {
      let visibleFacet = Facet(id: SampleUUIDSequence.uuid(70_011), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)
      let hiddenFacet = Facet(id: SampleUUIDSequence.uuid(70_012), name: "Season", sortOrder: 1, hidden: true, dateCreated: .distantPast)
      let visible = Category(id: SampleUUIDSequence.uuid(70_013), name: "Italian", facetID: visibleFacet.id, sortOrder: 0, dateCreated: .distantPast)
      let hiddenValue = Category(id: SampleUUIDSequence.uuid(70_014), name: "French", facetID: visibleFacet.id, hidden: true, sortOrder: 1, dateCreated: .distantPast)
      let hiddenFacetValue = Category(id: SampleUUIDSequence.uuid(70_015), name: "Summer", facetID: hiddenFacet.id, sortOrder: 0, dateCreated: .distantPast)

      let prompt = LabelProposer.prompt(
        recipe: .init(title: "Pasta"),
        vocabulary: .init(facets: [visibleFacet, hiddenFacet], categories: [visible, hiddenValue, hiddenFacetValue])
      )

      #expect(prompt.contains("Cuisine:\n  - Italian"))
      #expect(!prompt.contains("French"))
      #expect(!prompt.contains("Season"))
      #expect(!prompt.contains("Summer"))
    }

    @Test
    func surfacesAnUnmappableSuggestionWithoutDiscardingTheGoodOnes() throws {
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_101), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)
      let italian = Category(id: SampleUUIDSequence.uuid(70_102), name: "Italian", facetID: cuisine.id, sortOrder: 0, dateCreated: .distantPast)

      let proposal = try LabelProposer.parse(
        #"""
        {"suggestions":[
          {"kind":"existingCategory","path":["Cuisine","Italian"]},
          {"kind":"newChild","path":["Unknown","Korean"]}
        ]}
        """#,
        vocabulary: .init(facets: [cuisine], categories: [italian])
      )

      expectNoDifference(proposal.accepted, [.existingCategory(italian)])
      expectNoDifference(
        proposal.rejected,
        [RejectedLabelSuggestion(raw: "Unknown > Korean", reason: "Unknown is not an existing category group")]
      )
    }

    @Test
    func resolvesNewValuesAgainstFacetIdentityBeforeCommit() throws {
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_121), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)

      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"newChild","path":["Cuisine","Korean"]}]}"#,
        vocabulary: .init(facets: [cuisine], categories: [])
      )

      expectNoDifference(proposal.accepted, [
        .newChild(.init(facet: cuisine, parentCategory: nil, name: "Korean")),
      ])
    }

    @Test
    func acceptsANamespaceAsANewFacetAndItsFirstValue() throws {
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_131), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)

      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"namespace","path":["Season","Summer"]}]}"#,
        vocabulary: .init(facets: [cuisine], categories: [])
      )
      expectNoDifference(proposal.accepted, [
        .namespace(.init(facetName: "Season", firstValueName: "Summer")),
      ])
      #expect(proposal.rejected.isEmpty)
    }

    @Test
    func rejectsABareNamespaceRoot() throws {
      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"namespace","path":["Season"]}]}"#,
        vocabulary: .init(facets: [], categories: [])
      )
      #expect(proposal.accepted.isEmpty)
      expectNoDifference(
        proposal.rejected,
        [RejectedLabelSuggestion(raw: "Season", reason: "a new category group must name a new dimension and its first value")]
      )
    }

    @Test
    func threadsAnEscalatedTierThroughToTheModelCall() async throws {
      let recorder = LabelProposalRequestRecorder()

      _ = try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(text: #"{"suggestions":[]}"#)
        }
        $0.modelCallRecordSink = .liveValue
        $0.labelProposer = .liveValue
      } operation: {
        try await LabelProposer.liveValue(
          recipe: .init(title: "Soup"),
          vocabulary: .init(facets: [], categories: []),
          tier: .frontierPreferred
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontierPreferred)
    }

    @Test
    func canonicalizesAccentedExistingValueByIdentity() throws {
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_201), name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)
      let cafe = Category(id: SampleUUIDSequence.uuid(70_202), name: "Café", facetID: cuisine.id, sortOrder: 0, dateCreated: .distantPast)

      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"existingCategory","path":["Cuisine","Cafe"]}]}"#,
        vocabulary: .init(facets: [cuisine], categories: [cafe])
      )

      expectNoDifference(proposal.accepted, [.existingCategory(cafe)])
    }

    @Test
    func keepsTheFirstOfADuplicatedDestinationAndSurfacesTheRepeat() throws {
      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"loose","path":["weeknight"]},{"kind":"loose","path":["Weeknight"]}]}"#,
        vocabulary: .init(facets: [], categories: [])
      )
      expectNoDifference(proposal.accepted, [.loose("weeknight")])
      expectNoDifference(
        proposal.rejected,
        [RejectedLabelSuggestion(raw: "Weeknight", reason: "duplicates an earlier suggestion")]
      )
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
            vocabulary: .init(facets: [], categories: [])
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
