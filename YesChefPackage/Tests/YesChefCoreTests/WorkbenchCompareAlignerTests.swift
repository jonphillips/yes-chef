import CustomDump
import Dependencies
import Foundation
import LLMClientKit
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct WorkbenchCompareAlignerTests {
    @Test
    func alignerMergesSemanticRowsAndKeepsVerbatimCellsInModelOrder() async throws {
      let fixture = BirriaFixture()

      let comparison = try await alignedComparison(
        fixture: fixture,
        response: """
          {"rows":[
            {
              "label":"Chicken",
              "role":"protein",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(fixture.workingLine("2 pounds chicken breast, cubed").id.uuidString)",
                "\(fixture.candidate.recipe.id.uuidString)":"\(fixture.candidateLine("2 pounds boneless chicken thighs").id.uuidString)",
                "\(fixture.secondCandidate.recipe.id.uuidString)":"\(fixture.secondCandidateLine("2 lb chicken thigh meat").id.uuidString)"
              }
            },
            {
              "label":"Onion",
              "role":"aromatic",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(fixture.workingLine("1 white onion, chopped").id.uuidString)"
              }
            },
            {
              "label":"Garlic",
              "role":"aromatic",
              "assignments":{
                "\(fixture.candidate.recipe.id.uuidString)":"\(fixture.candidateLine("2 cloves garlic").id.uuidString)"
              }
            },
            {
              "label":"Guajillo chile",
              "role":"chile",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(fixture.workingLine("3 guajillo chilies, stemmed").id.uuidString)",
                "\(fixture.candidate.recipe.id.uuidString)":"\(fixture.candidateLine("4 guajillo chiles, seeded").id.uuidString)",
                "\(fixture.secondCandidate.recipe.id.uuidString)":"\(fixture.secondCandidateLine("5 guajillo chile").id.uuidString)"
              }
            }
          ]}
          """
      )

      expectNoDifference(
        comparison.columns.map(\.title),
        ["Working Birria", "Candidate Birria", "Notebook Birria"]
      )
      expectNoDifference(comparison.columns.map(\.role), [.working, .candidate, .candidate])
      expectNoDifference(
        comparison.rows.map(\.label),
        ["Chicken", "Onion", "Garlic", "Guajillo chile"]
      )
      expectNoDifference(
        comparison.rows.map(\.id),
        ["0-chicken", "1-onion", "2-garlic", "3-guajillo-chile"]
      )
      expectNoDifference(
        comparison.rows.map(\.cells),
        [
          [
            "2 pounds chicken breast, cubed",
            "2 pounds boneless chicken thighs",
            "2 lb chicken thigh meat",
          ],
          ["1 white onion, chopped", nil, nil],
          [nil, "2 cloves garlic", nil],
          [
            "3 guajillo chilies, stemmed",
            "4 guajillo chiles, seeded",
            "5 guajillo chile",
          ],
        ]
      )
    }

    @Test
    func alignerAccountsForEveryNonHeaderLinePerColumn() async throws {
      let fixture = BirriaFixture()

      let comparison = try await alignedComparison(
        fixture: fixture,
        response: fixture.semanticResponse
      )

      for columnIndex in comparison.columns.indices {
        let source = fixture.sources[columnIndex]
        let accountedTexts = comparison.rows.compactMap { $0.cells[columnIndex] }
          + comparison.columns[columnIndex].otherLines
        let accountedIDs = accountedTexts.compactMap { source.lineByOriginalText[$0]?.id }
        let expectedIDs = source.nonHeaderLines.map(\.id)

        expectNoDifference(Set(accountedIDs), Set(expectedIDs))
        expectNoDifference(accountedIDs.count, expectedIDs.count)
      }
      expectNoDifference(comparison.columns[0].otherLines, ["1 cup beef stock"])
      expectNoDifference(comparison.columns[1].otherLines, ["1 teaspoon Mexican oregano"])
      expectNoDifference(comparison.columns[2].otherLines, ["1 cinnamon stick"])
    }

    @Test
    func alignerRejectsFabricatedLineIDsAndKeepsRealUnassignedLinesInOther() async throws {
      let fixture = BirriaFixture()
      let fabricatedLineID = SampleUUIDSequence.uuid(61_999)

      let comparison = try await alignedComparison(
        fixture: fixture,
        response: """
          {"rows":[
            {
              "label":"Chicken",
              "role":"protein",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(fixture.workingLine("2 pounds chicken breast, cubed").id.uuidString)",
                "\(fixture.candidate.recipe.id.uuidString)":"\(fabricatedLineID.uuidString)"
              }
            }
          ]}
          """
      )

      expectNoDifference(comparison.rows.map(\.cells), [["2 pounds chicken breast, cubed", nil, nil]])
      #expect(comparison.columns[1].otherLines.contains("2 pounds boneless chicken thighs"))
    }

    @Test
    func alignerDedupesRepeatedLineAssignmentsWithFirstRowWinning() async throws {
      let fixture = BirriaFixture()
      let chickenBreastID = fixture.workingLine("2 pounds chicken breast, cubed").id

      let comparison = try await alignedComparison(
        fixture: fixture,
        response: """
          {"rows":[
            {
              "label":"Chicken",
              "role":"protein",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(chickenBreastID.uuidString)"
              }
            },
            {
              "label":"Duplicate chicken",
              "role":"protein",
              "assignments":{
                "\(fixture.working.recipe.id.uuidString)":"\(chickenBreastID.uuidString)"
              }
            }
          ]}
          """
      )

      expectNoDifference(comparison.rows.map(\.label), ["Chicken"])
      expectNoDifference(
        comparison.rows.flatMap { $0.cells.compactMap(\.self) },
        ["2 pounds chicken breast, cubed"]
      )
    }

    @Test
    func alignerFallsBackToDeterministicComparisonForMalformedModelOutput() async throws {
      let fixture = BirriaFixture()
      let expected = WorkbenchCompare.ingredientComparison(
        working: fixture.working,
        candidates: [fixture.candidate, fixture.secondCandidate]
      )

      let malformed = try await alignedComparison(fixture: fixture, response: "Here are some rows.")
      let empty = try await alignedComparison(fixture: fixture, response: #"{"rows":[]}"#)

      expectNoDifference(malformed, expected)
      expectNoDifference(empty, expected)
    }

    @Test
    func alignerRequestUsesMediumReasoningLargeTokenBudgetRawLinesAndNoPromptPreference() async throws {
      let recorder = ModelRequestRecorder()
      let recipeID = SampleUUIDSequence.uuid(62_000)
      let sectionID = SampleUUIDSequence.uuid(62_001)
      let lineID = SampleUUIDSequence.uuid(62_002)
      let detail = RecipeDetailData(
        recipe: Recipe(
          id: recipeID,
          title: "Raw Line Test",
          dateCreated: Date(timeIntervalSinceReferenceDate: 0),
          dateModified: Date(timeIntervalSinceReferenceDate: 0)
        ),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        ingredientLines: [
          IngredientLine(
            id: SampleUUIDSequence.uuid(62_003),
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "For the meat",
            isHeader: true,
            sortOrder: 0
          ),
          IngredientLine(
            id: lineID,
            recipeID: recipeID,
            sectionID: sectionID,
            originalText: "4 lb / 1.8 kg beef chuck roast",
            item: "wrong parsed item",
            sortOrder: 1
          ),
        ]
      )

      try await withDependencies {
        $0.modelClient = StubModelClient { request in
          await recorder.append(request)
          return ModelResponse(
            text: """
              {"rows":[{"label":"Beef (chuck)","role":"protein","assignments":{"\(recipeID.uuidString)":"\(lineID.uuidString)"}}]}
              """
          )
        }
      } operation: {
        let client = WorkbenchCompareAlignerClient.liveValue
        _ = try await client(working: detail, candidates: [], tier: .frontier(.openai))
      }

      let request = await recorder.first()
      expectNoDifference(request?.tier, .frontier(.openai))
      expectNoDifference(request?.reasoningEffort, .medium)
      expectNoDifference(request?.maxTokens, 4096)
      expectNoDifference(request?.promptPreferenceKey, nil)
      #expect(request?.messages.first?.text.contains("4 lb / 1.8 kg beef chuck roast") == true)
      #expect(request?.messages.first?.text.contains(lineID.uuidString) == true)
      #expect(request?.messages.first?.text.contains(recipeID.uuidString) == true)
      #expect(request?.messages.first?.text.contains("wrong parsed item") == false)
      #expect(request?.messages.first?.text.contains("For the meat") == false)
    }

    private func alignedComparison(
      fixture: BirriaFixture,
      response: String
    ) async throws -> IngredientComparison {
      try await withDependencies {
        $0.modelClient = StubModelClient.constant(response)
      } operation: {
        let client = WorkbenchCompareAlignerClient.liveValue
        return try await client(
          working: fixture.working,
          candidates: [fixture.candidate, fixture.secondCandidate],
          tier: .frontier(.anthropic)
        )
      }
    }
  }
}

private struct BirriaFixture {
  let workingSource = RecipeDetailSource(
    seed: 60_000,
    title: "Working Birria",
    lines: [
      .header("For the meat"),
      .ingredient("2 pounds chicken breast, cubed"),
      .ingredient("1 white onion, chopped"),
      .ingredient("3 guajillo chilies, stemmed"),
      .ingredient("1 cup beef stock"),
    ]
  )
  let candidateSource = RecipeDetailSource(
    seed: 61_000,
    title: "Candidate Birria",
    lines: [
      .ingredient("2 pounds boneless chicken thighs"),
      .ingredient("4 guajillo chiles, seeded"),
      .ingredient("2 cloves garlic"),
      .ingredient("1 teaspoon Mexican oregano"),
    ]
  )
  let secondCandidateSource = RecipeDetailSource(
    seed: 62_100,
    title: "Notebook Birria",
    lines: [
      .ingredient("2 lb chicken thigh meat"),
      .ingredient("5 guajillo chile"),
      .ingredient("1 cinnamon stick"),
    ]
  )

  var sources: [RecipeDetailSource] { [workingSource, candidateSource, secondCandidateSource] }

  var semanticResponse: String {
    """
    {"rows":[
      {
        "label":"Chicken",
        "role":"protein",
        "assignments":{
          "\(working.recipe.id.uuidString)":"\(workingLine("2 pounds chicken breast, cubed").id.uuidString)",
          "\(candidate.recipe.id.uuidString)":"\(candidateLine("2 pounds boneless chicken thighs").id.uuidString)",
          "\(secondCandidate.recipe.id.uuidString)":"\(secondCandidateLine("2 lb chicken thigh meat").id.uuidString)"
        }
      },
      {
        "label":"Onion",
        "role":"aromatic",
        "assignments":{
          "\(working.recipe.id.uuidString)":"\(workingLine("1 white onion, chopped").id.uuidString)"
        }
      },
      {
        "label":"Garlic",
        "role":"aromatic",
        "assignments":{
          "\(candidate.recipe.id.uuidString)":"\(candidateLine("2 cloves garlic").id.uuidString)"
        }
      },
      {
        "label":"Guajillo chile",
        "role":"chile",
        "assignments":{
          "\(working.recipe.id.uuidString)":"\(workingLine("3 guajillo chilies, stemmed").id.uuidString)",
          "\(candidate.recipe.id.uuidString)":"\(candidateLine("4 guajillo chiles, seeded").id.uuidString)",
          "\(secondCandidate.recipe.id.uuidString)":"\(secondCandidateLine("5 guajillo chile").id.uuidString)"
        }
      }
    ]}
    """
  }

  var working: RecipeDetailData { workingSource.detail }
  var candidate: RecipeDetailData { candidateSource.detail }
  var secondCandidate: RecipeDetailData { secondCandidateSource.detail }

  func workingLine(_ originalText: String) -> IngredientLine {
    workingSource.line(originalText)
  }

  func candidateLine(_ originalText: String) -> IngredientLine {
    candidateSource.line(originalText)
  }

  func secondCandidateLine(_ originalText: String) -> IngredientLine {
    secondCandidateSource.line(originalText)
  }
}

private struct RecipeDetailSource {
  var detail: RecipeDetailData
  var nonHeaderLines: [IngredientLine]
  var lineByOriginalText: [String: IngredientLine]

  var recipe: Recipe { detail.recipe }

  init(seed: Int, title: String, lines: [FixtureLine]) {
    let recipeID = SampleUUIDSequence.uuid(seed)
    let sectionID = SampleUUIDSequence.uuid(seed + 1)
    let ingredientLines = lines.enumerated().map { offset, line in
      IngredientLine(
        id: SampleUUIDSequence.uuid(seed + 100 + offset),
        recipeID: recipeID,
        sectionID: sectionID,
        originalText: line.originalText,
        isHeader: line.isHeader,
        sortOrder: offset
      )
    }
    let recipe = Recipe(
      id: recipeID,
      title: title,
      dateCreated: Date(timeIntervalSinceReferenceDate: 0),
      dateModified: Date(timeIntervalSinceReferenceDate: 0)
    )
    self.detail = RecipeDetailData(
      recipe: recipe,
      ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
      ingredientLines: ingredientLines
    )
    self.nonHeaderLines = ingredientLines.filter { !$0.isHeader }
    self.lineByOriginalText = Dictionary(uniqueKeysWithValues: nonHeaderLines.map { ($0.originalText, $0) })
  }

  func line(_ originalText: String) -> IngredientLine {
    lineByOriginalText[originalText]!
  }
}

private struct FixtureLine {
  var originalText: String
  var isHeader: Bool

  static func header(_ text: String) -> FixtureLine {
    FixtureLine(originalText: text, isHeader: true)
  }

  static func ingredient(_ text: String) -> FixtureLine {
    FixtureLine(originalText: text, isHeader: false)
  }
}

private actor ModelRequestRecorder {
  private var requests: [ModelRequest] = []

  func append(_ request: ModelRequest) {
    requests.append(request)
  }

  func first() -> ModelRequest? {
    requests.first
  }
}
