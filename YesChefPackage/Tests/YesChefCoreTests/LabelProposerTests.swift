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
          return ModelResponse(
            text: #"{"suggestions":[{"kind":"existingCategory","path":["Cuisine","Italian"]},{"kind":"loose","path":["weeknight"]}]}"#,
            responseFormatStatus: .structured
          )
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
      expectNoDifference(request?.reasoningEffort, .high)
      expectNoDifference(request?.maxTokens, LabelProposer.maxTokens)
      expectNoDifference(
        request?.responseFormat,
        .jsonSchema(name: "label_suggestions", schema: LabelProposer.responseSchema)
      )
      #expect(request?.messages.first?.text.contains("Cuisine:\n  - Italian") == true)
      #expect(request?.messages.first?.text.contains("Italian Weeknight Pasta") == true)

      let record = await callRecords.records().first
      expectNoDifference(record?.surface, .capture)
      expectNoDifference(record?.task, .categorization)
      expectNoDifference(record?.tier, .onDevice)
      expectNoDifference(record?.contextLayers, ModelCallContextLayers(included: [.recipe, .candidates]))
      expectNoDifference(record?.responseFormatAttached, true)
      expectNoDifference(record?.responseFormatOutcome, .structuredHit)
    }

    @Test
    func recordsAReadableFreeTextFallback() async throws {
      let callRecords = ModelCallRecordCollector()

      _ = try await withDependencies {
        $0.modelClient = StubModelClient { _ in ModelResponse(text: #"{"suggestions":[]}"#) }
        $0.modelCallRecordSink = .inMemory(callRecords)
        $0.labelProposer = .liveValue
      } operation: {
        try await LabelProposer.liveValue(
          recipe: .init(title: "Soup"), vocabulary: .init(facets: [], categories: [])
        )
      }

      let record = await callRecords.records().first
      expectNoDifference(record?.responseFormatAttached, true)
      expectNoDifference(record?.responseFormatOutcome, .fellBack)
    }

    @Test
    func recordsAnUnreadableStructuredResponse() async {
      let callRecords = ModelCallRecordCollector()

      await #expect(throws: LabelProposerError.responseUnreadable) {
        try await withDependencies {
          $0.modelClient = StubModelClient { _ in ModelResponse(text: "not JSON") }
          $0.modelCallRecordSink = .inMemory(callRecords)
          $0.labelProposer = .liveValue
        } operation: {
          try await LabelProposer.liveValue(
            recipe: .init(title: "Soup"), vocabulary: .init(facets: [], categories: [])
          )
        }
      }

      let record = await callRecords.records().first
      expectNoDifference(record?.responseFormatAttached, true)
      expectNoDifference(record?.responseFormatOutcome, .unreadable)
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
    func deterministicFloorFindsOnlySurfaceEvidentKFCLabels() {
      let protein = Facet(id: SampleUUIDSequence.uuid(70_301), name: "Protein", sortOrder: 0, dateCreated: .distantPast)
      let technique = Facet(id: SampleUUIDSequence.uuid(70_302), name: "Technique", sortOrder: 1, dateCreated: .distantPast)
      let dishType = Facet(id: SampleUUIDSequence.uuid(70_303), name: "Dish Type", sortOrder: 2, dateCreated: .distantPast)
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_304), name: "Cuisine", sortOrder: 3, dateCreated: .distantPast)
      let chicken = Category(id: SampleUUIDSequence.uuid(70_305), name: "Chicken", facetID: protein.id, sortOrder: 0, dateCreated: .distantPast)
      let eggs = Category(id: SampleUUIDSequence.uuid(70_306), name: "Eggs", facetID: protein.id, sortOrder: 1, dateCreated: .distantPast)
      let fry = Category(id: SampleUUIDSequence.uuid(70_307), name: "Fry", facetID: technique.id, sortOrder: 0, dateCreated: .distantPast)
      let salad = Category(id: SampleUUIDSequence.uuid(70_308), name: "Salad", facetID: dishType.id, sortOrder: 0, dateCreated: .distantPast)
      let american = Category(id: SampleUUIDSequence.uuid(70_309), name: "American", facetID: cuisine.id, sortOrder: 0, dateCreated: .distantPast)
      let favorite = Category(id: SampleUUIDSequence.uuid(70_310), name: "Favorite", sortOrder: 0, dateCreated: .distantPast)

      let suggestions = LabelProposer.floor(
        recipe: .init(
          title: "KFC Fried Chicken",
          ingredientLines: ["1 whole chicken", "2 eggs, beaten for the breading"]
        ),
        vocabulary: .init(
          facets: [protein, technique, dishType, cuisine],
          categories: [chicken, eggs, fry, salad, american, favorite]
        )
      )

      expectNoDifference(suggestions, [.existingCategory(chicken), .existingCategory(fry)])
    }

    @Test
    func deterministicFloorPrefersStirFriedOverFry() {
      let technique = Facet(id: SampleUUIDSequence.uuid(70_321), name: "Technique", sortOrder: 0, dateCreated: .distantPast)
      let fry = Category(id: SampleUUIDSequence.uuid(70_322), name: "Fry", facetID: technique.id, sortOrder: 0, dateCreated: .distantPast)
      let stirFry = Category(id: SampleUUIDSequence.uuid(70_323), name: "Stir-Fry", facetID: technique.id, sortOrder: 1, dateCreated: .distantPast)

      let suggestions = LabelProposer.floor(
        recipe: .init(title: "Stir-Fried Chicken"),
        vocabulary: .init(facets: [technique], categories: [fry, stirFry])
      )

      expectNoDifference(suggestions, [.existingCategory(stirFry)])
    }

    @Test
    func liveProposalUnionsTheFloorWithTheModelAndRecordsSources() async throws {
      let protein = Facet(id: SampleUUIDSequence.uuid(70_341), name: "Protein", sortOrder: 0, dateCreated: .distantPast)
      let technique = Facet(id: SampleUUIDSequence.uuid(70_342), name: "Technique", sortOrder: 1, dateCreated: .distantPast)
      let cuisine = Facet(id: SampleUUIDSequence.uuid(70_343), name: "Cuisine", sortOrder: 2, dateCreated: .distantPast)
      let chicken = Category(id: SampleUUIDSequence.uuid(70_344), name: "Chicken", facetID: protein.id, sortOrder: 0, dateCreated: .distantPast)
      let fry = Category(id: SampleUUIDSequence.uuid(70_345), name: "Fry", facetID: technique.id, sortOrder: 0, dateCreated: .distantPast)
      let american = Category(id: SampleUUIDSequence.uuid(70_346), name: "American", facetID: cuisine.id, sortOrder: 0, dateCreated: .distantPast)
      let vocabulary = LabelVocabulary(facets: [protein, technique, cuisine], categories: [chicken, fry, american])

      let proposal = try await withDependencies {
        $0.modelClient = StubModelClient { _ in
          ModelResponse(
            text: #"{"suggestions":[{"kind":"existingCategory","path":["Protein","Chicken"]},{"kind":"existingCategory","path":["Cuisine","American"]}]}"#,
            responseFormatStatus: .structured
          )
        }
        $0.labelProposer = .liveValue
      } operation: {
        try await LabelProposer.liveValue(
          recipe: .init(title: "KFC Fried Chicken", ingredientLines: ["1 whole chicken"]),
          vocabulary: vocabulary
        )
      }

      expectNoDifference(proposal.accepted, [
        .existingCategory(chicken),
        .existingCategory(fry),
        .existingCategory(american),
      ])
      expectNoDifference(proposal.sources, [
        SuggestedLabel.existingCategory(chicken).id: .deterministic,
        SuggestedLabel.existingCategory(fry).id: .deterministic,
        SuggestedLabel.existingCategory(american).id: .model,
      ])
    }

    @Test
    func truncatedResponseFailsLoudly() async {
      let callRecords = ModelCallRecordCollector()

      await #expect(throws: LabelProposerError.responseTruncated) {
        try await withDependencies {
          $0.modelClient = StubModelClient { _ in ModelResponse(text: "{", stopReason: "max_tokens") }
          $0.modelCallRecordSink = .inMemory(callRecords)
          $0.labelProposer = .liveValue
        } operation: {
          try await LabelProposer.liveValue(
            recipe: .init(title: "Soup"),
            vocabulary: .init(facets: [], categories: [])
          )
        }
      }

      let record = await callRecords.records().first
      expectNoDifference(record?.responseFormatAttached, true)
      expectNoDifference(record?.responseFormatOutcome, .truncated)
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
