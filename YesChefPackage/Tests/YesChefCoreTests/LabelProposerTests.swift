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

      expectNoDifference(suggestions.accepted, [
        SuggestedLabel(kind: .existingCategory, path: ["Cuisine", "Italian"]),
        SuggestedLabel(kind: .loose, path: ["weeknight"]),
      ])
      #expect(suggestions.rejected.isEmpty)

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
    func surfacesAnUnmappableSuggestionWithoutDiscardingTheGoodOnes() throws {
      let cuisineID = SampleUUIDSequence.uuid(70_101)
      let italianID = SampleUUIDSequence.uuid(70_102)
      let categories = [
        Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: .distantPast),
        Category(id: italianID, name: "Italian", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: .distantPast),
      ]

      // One sloppy path out of two is the expected on-device case: the good suggestion must survive and
      // the bad one must be surfaced, never dropped (ADR-0049 D2).
      let proposal = try LabelProposer.parse(
        #"""
        {"suggestions":[
          {"kind":"existingCategory","path":["Cuisine","Italian"]},
          {"kind":"newChild","path":["Unknown","Korean"]}
        ]}
        """#,
        categories: categories
      )

      expectNoDifference(proposal.accepted, [SuggestedLabel(kind: .existingCategory, path: ["Cuisine", "Italian"])])
      expectNoDifference(
        proposal.rejected,
        [RejectedLabelSuggestion(raw: "Unknown > Korean", reason: "Unknown is not an existing parent")]
      )
    }

    @Test
    func acceptsANamespaceAsANewDimensionAndItsFirstValue() throws {
      let cuisineID = SampleUUIDSequence.uuid(70_121)
      let categories = [Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: .distantPast)]

      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"namespace","path":["Season","Summer"]}]}"#,
        categories: categories
      )
      expectNoDifference(proposal.accepted, [SuggestedLabel(kind: .namespace, path: ["Season", "Summer"])])
      #expect(proposal.rejected.isEmpty)
      // The join written on accept files the recipe under the child, not a bare dimension root.
      expectNoDifference(proposal.accepted.first?.categoryName, "Season > Summer")
    }

    @Test
    func rejectsABareNamespaceRootThatWouldReadAsALooseLabel() throws {
      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"namespace","path":["Season"]}]}"#,
        categories: []
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
          existingTree: [],
          tier: .frontierPreferred
        )
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontierPreferred)
    }

    @Test
    func canonicalizesAccentedExistingPathSoReconcileFindsItWithoutDuplicating() throws {
      @Dependency(\.defaultDatabase) var database
      let cuisineID = SampleUUIDSequence.uuid(70_201)
      let cafeID = SampleUUIDSequence.uuid(70_202)
      let categories = [
        Category(id: cuisineID, name: "Cuisine", sortOrder: 0, dateCreated: .distantPast),
        Category(id: cafeID, name: "Café", parentCategoryID: cuisineID, sortOrder: 0, dateCreated: .distantPast),
      ]

      // The model echoes the path without the diacritic; the proposer must hand back the tree's
      // stored spelling so the diacritic-sensitive reconciler reuses `Café` instead of creating `Cafe`.
      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"existingCategory","path":["Cuisine","Cafe"]}]}"#,
        categories: categories
      )
      expectNoDifference(proposal.accepted, [SuggestedLabel(kind: .existingCategory, path: ["Cuisine", "Café"])])

      let now = Date(timeIntervalSinceReferenceDate: 802_360_000)
      var uuids = SampleUUIDSequence(start: 70_210)
      try database.write { db in
        try Category.insert { categories[0] }.execute(db)
        try Category.insert { categories[1] }.execute(db)

        let recipeID = try RecipeRepository.save(
          draft: RecipeEditorDraft(title: "Espresso Tart", categoryNames: proposal.accepted[0].categoryName),
          in: db,
          now: now,
          uuid: { uuids.next() }
        )

        let recipeCategory = try #require(
          (try RecipeCategory.fetchAll(db)).first { $0.recipeID == recipeID }
        )
        #expect(recipeCategory.categoryID == cafeID)
        let cafeChildren = try Category.fetchAll(db).filter { $0.parentCategoryID == cuisineID }
        #expect(cafeChildren.map(\.id) == [cafeID])
      }
    }

    @Test
    func canonicalizesExistingParentOfANewChild() throws {
      let cafeID = SampleUUIDSequence.uuid(70_301)
      let categories = [
        Category(id: cafeID, name: "Café", sortOrder: 0, dateCreated: .distantPast),
      ]

      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"newChild","path":["Cafe","Espresso"]}]}"#,
        categories: categories
      )
      expectNoDifference(proposal.accepted, [SuggestedLabel(kind: .newChild, path: ["Café", "Espresso"])])
    }

    @Test
    func keepsTheFirstOfADuplicatedDestinationAndSurfacesTheRepeat() throws {
      let proposal = try LabelProposer.parse(
        #"{"suggestions":[{"kind":"loose","path":["weeknight"]},{"kind":"loose","path":["Weeknight"]}]}"#,
        categories: []
      )
      expectNoDifference(proposal.accepted, [SuggestedLabel(kind: .loose, path: ["weeknight"])])
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
