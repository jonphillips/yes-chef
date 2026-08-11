import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct CreateRecipeExtractionTests {
    /// The common paste case: ordinary prose routes through the LLM extraction engine and the result
    /// maps onto `RecipeEditorDraft`, the shared sink, with every named section preserved.
    @Test
    func pastedProseRoutesThroughTheLLMEngineAndMapsToTheSink() async throws {
      let extraction = RecipeExtraction(
        title: "Weeknight Dal",
        summary: "A quick lentil supper.",
        author: "A. Cook",
        servingsText: "Serves 4",
        prepTime: "10 minutes",
        cookTime: "PT25M",
        ingredientSections: [
          .init(name: "For the dal", lines: ["1 cup red lentils", "3 cups water"]),
          .init(name: "To finish", lines: ["1 tbsp ghee"]),
        ],
        instructionSections: [
          .init(name: "Cook", steps: ["Simmer the lentils.", "Season to taste."]),
        ]
      )

      let result = try await withDependencies {
        $0.recipeExtractionClient = RecipeExtractionClient { _ in extraction }
      } operation: {
        try await CreateRecipeExtraction.extract(text: "about a cup of red lentils, simmered")
      }

      expectNoDifference(result, extraction)

      let draft = result.editorDraft(uuid: { UUID() })
      #expect(draft.title == "Weeknight Dal")
      #expect(draft.summary == "A quick lentil supper.")
      #expect(draft.sourceAuthor == "A. Cook")
      #expect(draft.servingsText == "Serves 4")
      #expect(draft.prepTimeMinutes == 10)
      #expect(draft.cookTimeMinutes == 25)
      #expect(draft.ingredientSections.map(\.name) == ["For the dal", "To finish"])
      #expect(draft.ingredientSections[0].text == "1 cup red lentils\n3 cups water")
      #expect(draft.instructionSections.map(\.name) == ["Cook"])
      #expect(draft.instructionSections[0].text == "Simmer the lentils.\n\nSeason to taste.")
    }

    /// A paste that already *is* schema.org JSON-LD takes the free deterministic path. The LLM engine is
    /// wired to throw, so a successful return proves the model was never called.
    @Test
    func jsonLDPasteTakesTheDeterministicPathWithoutTheModel() async throws {
      let jsonLD = """
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Simple Broth",
          "recipeYield": "4 servings",
          "prepTime": "PT10M",
          "cookTime": "PT20M",
          "recipeIngredient": ["1 onion, halved", "2 quarts water"],
          "recipeInstructions": ["Combine in a pot.", "Simmer for twenty minutes."]
        }
        """

      let result = try await withDependencies {
        $0.recipeExtractionClient = .testValue  // throws if the deterministic path fails to short-circuit
      } operation: {
        try await CreateRecipeExtraction.extract(text: jsonLD)
      }

      #expect(result.title == "Simple Broth")
      #expect(result.ingredientSections.flatMap(\.lines) == ["1 onion, halved", "2 quarts water"])
      #expect(result.instructionSections.flatMap(\.steps) == ["Combine in a pot.", "Simmer for twenty minutes."])
      #expect(result.instructionSections.count == 1)
      #expect(result.instructionSections.first?.name == nil)

      let draft = result.editorDraft(uuid: { UUID() })
      #expect(draft.prepTimeMinutes == 10)
      #expect(draft.cookTimeMinutes == 20)
    }

    /// Direct HowToSteps are one ordered, unsectioned method. They must not become one unnamed
    /// section per step merely because the JSON-LD walker visits each array item independently.
    @Test
    func unsectionedJSONLDPasteKeepsStepsInOneOrderedSection() async throws {
      let jsonLD = """
        {"@context":"https://schema.org","@type":"Recipe","name":"Simple Salad","recipeIngredient":["1 cucumber"],"recipeInstructions":[{"@type":"HowToStep","text":"Slice the cucumber."},{"@type":"HowToStep","text":"Season and serve."}]}
        """

      let result = try await withDependencies {
        $0.recipeExtractionClient = .testValue
      } operation: {
        try await CreateRecipeExtraction.extract(text: jsonLD)
      }

      expectNoDifference(result.instructionSections, [
        .init(name: nil, steps: ["Slice the cucumber.", "Season and serve."]),
      ])
    }

    /// Create Recipe uses the same warning evidence as capture: choosing one complete recipe from an
    /// ambiguous graph and flattening a nested method must both be visible in its two-cue review budget.
    @Test
    func jsonLDPasteCarriesAmbiguityAndFlatteningWarningsIntoReviewIssues() async throws {
      let jsonLD = """
        {"@context":"https://schema.org","@graph":[
          {"@type":"Recipe","name":"Primary stew","recipeYield":"4 servings","recipeIngredient":["1 onion"],"recipeInstructions":[{"@type":"HowToSection","name":"Cook stew","itemListElement":[{"@type":"HowToStep","text":"Cook the onion."},{"@type":"HowToSection","name":"Finish","itemListElement":[{"@type":"HowToStep","text":"Serve the stew."}]}]}]},
          {"@type":"Recipe","name":"Second stew","recipeIngredient":["1 carrot"],"recipeInstructions":["Cook the carrot."]}
        ]}
        """

      let result = try await withDependencies {
        $0.recipeExtractionClient = .testValue
      } operation: {
        try await CreateRecipeExtraction.extract(text: jsonLD)
      }

      expectNoDifference(result.warnings, [.multipleRecipeCandidates, .nestedInstructionSectionsFlattened])
      expectNoDifference(RecipeExtractionIssueDetector.issues(in: result), [
        .init(kind: .multipleRecipeCandidates),
        .init(kind: .nestedInstructionSectionsFlattened),
      ])
    }

    /// Recover the first dogfood return shape, which incorrectly used HowToSection objects as
    /// `recipeIngredient` entries. The v2 source forbids it, but importing the actual return must
    /// retain the ingredient lines rather than saving only the group names.
    @Test
    func malformedHowToSectionsInsideRecipeIngredientsAreRecovered() async throws {
      let jsonLD = """
        {"@context":"https://schema.org","@type":"Recipe","name":"Mini Charred Cabbage with Lime Sauce","recipeIngredient":[{"@type":"HowToSection","name":"For the cabbage","itemListElement":["1/2 small green cabbage, cut into 2 wedges","1 tbsp neutral oil","1/4 tsp kosher salt"]},{"@type":"HowToSection","name":"For the lime sauce","itemListElement":["1 tbsp lime juice","1 tsp fish sauce","1 tsp brown sugar","1 tbsp chopped peanuts"]}],"recipeInstructions":[{"@type":"HowToStep","text":"Char the cabbage."}]}
        """

      let result = try await withDependencies {
        $0.recipeExtractionClient = .testValue
      } operation: {
        try await CreateRecipeExtraction.extract(text: jsonLD)
      }

      expectNoDifference(result.ingredientSections, [
        .init(name: "For the cabbage", lines: [
          "1/2 small green cabbage, cut into 2 wedges",
          "1 tbsp neutral oil",
          "1/4 tsp kosher salt",
        ]),
        .init(name: "For the lime sauce", lines: [
          "1 tbsp lime juice",
          "1 tsp fish sauce",
          "1 tsp brown sugar",
          "1 tbsp chopped peanuts",
        ]),
      ])
    }

    /// The Project-aware v2 extension keeps exact ingredient section labels without putting fake
    /// heading rows into schema.org's flat `recipeIngredient` fallback. This verifies every field
    /// survives the raw JSON-LD → review draft → canonical save path.
    @Test
    func v2JSONLDPastePreservesEditorialStructureThroughSave() async throws {
      @Dependency(\.defaultDatabase) var database
      let jsonLD = """
        {"@context":["https://schema.org",{"yesChef":"https://yeschef.app/ns#"}],"@type":"Recipe","yesChef:recipeContractVersion":"2","name":"Braised Cabbage","description":"Tangy cabbage with sesame sauce.","recipeCuisine":"Levantine","recipeCategory":"Main course","recipeYield":"4 servings","prepTime":"PT15M","cookTime":"PT30M","totalTime":"PT45M","recipeIngredient":["1 small cabbage","1 tsp salt","2 tbsp tahini"],"yesChef:ingredientSections":[{"name":"For the cabbage","recipeIngredient":["1 small cabbage","1 tsp salt"]},{"name":"For the sauce","recipeIngredient":["2 tbsp tahini"]}],"recipeInstructions":[{"@type":"HowToSection","name":"Prepare the cabbage","itemListElement":[{"@type":"HowToStep","text":"Slice the cabbage."},{"@type":"HowToStep","text":"Salt and rest for 10 minutes."}]},{"@type":"HowToSection","name":"Dress and serve","itemListElement":[{"@type":"HowToStep","text":"Whisk the tahini."},{"@type":"HowToStep","text":"Toss and serve."}]}]}
        """

      let result = try await withDependencies {
        $0.recipeExtractionClient = .testValue
      } operation: {
        try await CreateRecipeExtraction.extract(text: jsonLD)
      }

      #expect(result.cuisine == "Levantine")
      #expect(result.course == "Main course")
      expectNoDifference(result.ingredientSections, [
        .init(name: "For the cabbage", lines: ["1 small cabbage", "1 tsp salt"]),
        .init(name: "For the sauce", lines: ["2 tbsp tahini"]),
      ])
      expectNoDifference(result.instructionSections, [
        .init(name: "Prepare the cabbage", steps: ["Slice the cabbage.", "Salt and rest for 10 minutes."]),
        .init(name: "Dress and serve", steps: ["Whisk the tahini.", "Toss and serve."]),
      ])

      let draft = result.editorDraft(uuid: UUID.init)
      let now = Date(timeIntervalSinceReferenceDate: 831_000_000)
      try await database.write { db in
        let recipeID = try RecipeRepository.save(
          draft: draft,
          in: db,
          now: now,
          uuid: UUID.init
        )
        let detail = try #require(try RecipeRepository.fetchDetail(recipeID: recipeID, in: db))

        #expect(detail.recipe.title == "Braised Cabbage")
        #expect(detail.recipe.summary == "Tangy cabbage with sesame sauce.")
        #expect(detail.recipe.servingsText == "4 servings")
        #expect(detail.recipe.prepTimeMinutes == 15)
        #expect(detail.recipe.cookTimeMinutes == 30)
        #expect(detail.recipe.totalTimeMinutes == 45)
        #expect(detail.recipe.cuisine == "Levantine")
        #expect(detail.recipe.course == "Main course")
        #expect(detail.ingredientSections.map(\.name) == ["For the cabbage", "For the sauce"])
        #expect(detail.instructionSections.map(\.name) == ["Prepare the cabbage", "Dress and serve"])

        let ingredientLines = Dictionary(grouping: detail.ingredientLines, by: \.sectionID)
        let instructionSteps = Dictionary(grouping: detail.instructionSteps, by: \.sectionID)
        expectNoDifference(detail.ingredientSections.map { ingredientLines[$0.id, default: []].map(\.originalText) }, [
          ["1 small cabbage", "1 tsp salt"],
          ["2 tbsp tahini"],
        ])
        expectNoDifference(detail.instructionSections.map { instructionSteps[$0.id, default: []].map(\.text) }, [
          ["Slice the cabbage.", "Salt and rest for 10 minutes."],
          ["Whisk the tahini.", "Toss and serve."],
        ])
      }
    }

    @Test
    func recipeContractV2DeclaresTheProjectSourceAndCaptureRequest() {
      #expect(RecipeJSONLDContract.projectSource.contains(RecipeJSONLDContract.marker))
      #expect(RecipeJSONLDContract.projectSource.contains("yesChef:ingredientSections"))
      #expect(RecipeJSONLDContract.projectSource.contains("Never put `HowToSection`"))
      #expect(RecipeJSONLDContract.projectSource.contains("do not make one section per step"))

      let request = RecipeJSONLDContract.captureRequest(recipeName: "Braised Cabbage")
      #expect(request.contains("YC-PRODUCT: Recipe"))
      #expect(request.contains(RecipeJSONLDContract.marker))
      #expect(request.contains("Braised Cabbage"))
      #expect(!request.contains("YC-HANDOFF:"))
    }

    /// An empty paste degrades loudly rather than producing a blank recipe.
    @Test
    func emptyPasteDegradesLoud() async throws {
      await #expect(throws: RecipeExtractionError.emptyRecipe) {
        try await withDependencies {
          $0.recipeExtractionClient = .testValue
        } operation: {
          _ = try await CreateRecipeExtraction.extract(text: "   \n  ")
        }
      }
    }

    /// Ordinary prose the engine cannot read surfaces the engine's failure — never a silent partial.
    @Test
    func garbagePastePropagatesTheEngineFailure() async throws {
      await #expect(throws: RecipeExtractionError.responseUnreadable) {
        try await withDependencies {
          $0.recipeExtractionClient = .testValue  // `.testValue` throws `.responseUnreadable`
        } operation: {
          _ = try await CreateRecipeExtraction.extract(text: "just some words that are not a recipe")
        }
      }
    }

    /// The sink mapping preserves multiple named sections and reads whole minutes from ISO-8601, a
    /// spelled-out span, and a colon-terminated ingredient heading splits into its own card.
    @Test
    func editorDraftPreservesSectionsParsesTimesAndPromotesHeadings() {
      let extraction = RecipeExtraction(
        title: "Layered Bake",
        prepTime: "PT1H30M",
        cookTime: "45 min",
        ingredientSections: [
          .init(name: nil, lines: ["2 eggs", "For the topping:", "1 cup cheese"]),
        ],
        instructionSections: [
          .init(name: "Bake", steps: ["Assemble.", "Bake until golden."]),
        ]
      )

      let draft = extraction.editorDraft(uuid: { UUID() })

      #expect(draft.prepTimeMinutes == 90)
      #expect(draft.cookTimeMinutes == 45)
      // The colon heading is promoted into a second ingredient card.
      #expect(draft.ingredientSections.count == 2)
      #expect(draft.ingredientSections[0].lineDrafts.map(\.originalText) == ["2 eggs"])
      #expect(draft.ingredientSections[1].name == "For the topping")
      #expect(draft.ingredientSections[1].lineDrafts.map(\.originalText) == ["1 cup cheese"])
    }

    /// A model step that carries an internal line break stays **one** saved step — otherwise the sink's
    /// newline-splitting save path would re-segment a paragraph-shaped step and inflate the numbering.
    @Test
    func aParagraphShapedStepStaysASingleStep() {
      let extraction = RecipeExtraction(
        title: "Braise",
        instructionSections: [
          .init(name: nil, steps: [
            "Sear the beef on all sides.\nWork in batches so the pan stays hot.",
            "Add the wine and simmer.",
          ]),
        ]
      )

      let draft = extraction.editorDraft(uuid: { UUID() })

      // The editor text carries the two steps as blank-line-separated paragraphs, with the internal
      // break in the first flattened to a space — so the save path parses exactly two steps.
      let steps = InstructionParser.steps(
        from: draft.instructionSections[0].text,
        recipeID: UUID(),
        sectionID: draft.instructionSections[0].id,
        uuid: { UUID() }
      )
      #expect(steps.map(\.text) == [
        "Sear the beef on all sides. Work in batches so the pan stays hot.",
        "Add the wine and simmer.",
      ])
    }

    @Test
    func deterministicIssuePassRanksTheTwoMostActionableMismatches() {
      let extraction = RecipeExtraction(
        prepTime: "until tender",
        ingredientSections: [
          .init(lines: ["2 cups scallions", "salt", "1 cup scallions"]),
        ],
        instructionSections: [
          .init(steps: ["Stir in butter."]),
        ]
      )
      let issues = RecipeExtractionIssueDetector.issues(in: extraction)

      expectNoDifference(issues, [
        .init(kind: .missingTitle),
        .init(kind: .unparseablePrepTime, detail: "until tender"),
      ])
    }

    @Test
    func deterministicIssuePassIgnoresImplicitPantryAndGarnishIngredients() {
      let extraction = RecipeExtraction(
        title: "Roasted Vegetables",
        servingsText: "Serves 4",
        ingredientSections: [
          .init(lines: ["salt to taste", "olive oil", "garlic", "parsley, for garnish"]),
        ],
        instructionSections: [.init(steps: ["Roast the vegetables until browned."])]
      )

      expectNoDifference(RecipeExtractionIssueDetector.issues(in: extraction), [])
    }

    @Test
    func deterministicIssuePassDetectsMissingYield() {
      let extraction = RecipeExtraction(
        title: "Bean Salad",
        ingredientSections: [.init(lines: ["1 cup beans"])],
        instructionSections: [.init(steps: ["Serve the beans."])]
      )

      expectNoDifference(RecipeExtractionIssueDetector.issues(in: extraction), [.init(kind: .missingYield)])
    }

    @Test
    func deterministicIssuePassReportsEmptyRecipeHalves() {
      let issues = RecipeExtractionIssueDetector.issues(in: RecipeExtraction(title: "Only a title"))

      expectNoDifference(issues, [.init(kind: .emptyIngredients), .init(kind: .emptyInstructions)])
    }
  }
}
