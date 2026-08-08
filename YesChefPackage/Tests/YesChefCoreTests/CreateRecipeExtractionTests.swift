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

      let draft = result.editorDraft(uuid: { UUID() })
      #expect(draft.prepTimeMinutes == 10)
      #expect(draft.cookTimeMinutes == 20)
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
    func deterministicIssuePassFindsConcreteExtractionMismatches() {
      let attributedSourceID = SampleUUIDSequence.uuid(54_001)
      let unattributedSourceID = SampleUUIDSequence.uuid(54_002)
      let extraction = RecipeExtraction(
        prepTime: "until tender",
        ingredientSections: [
          .init(lines: ["2 cups scallions", "salt", "1 cup scallions"]),
        ],
        instructionSections: [
          .init(steps: ["Stir in butter."]),
        ]
      )
      let issues = RecipeExtractionIssueDetector.issues(
        in: extraction,
        sources: [
          .init(id: attributedSourceID, kind: .pastedText, content: "Scallions and salt"),
          .init(id: unattributedSourceID, kind: .typedText, content: "Aardvark xylophone"),
        ]
      )

      expectNoDifference(issues, [
        .init(kind: .missingTitle),
        .init(kind: .unparseablePrepTime, detail: "until tender"),
        .init(kind: .missingIngredientQuantity, detail: "salt"),
        .init(kind: .duplicateIngredient, detail: "green onions"),
        .init(kind: .ingredientNotReferenced, detail: "green onions"),
        .init(kind: .ingredientNotReferenced, detail: "salt"),
        .init(kind: .referencedIngredientNotListed, detail: "butter"),
        .init(kind: .unattributedSource, sourceID: unattributedSourceID),
      ])
    }

    @Test
    func deterministicIssuePassReportsEmptyRecipeHalves() {
      let issues = RecipeExtractionIssueDetector.issues(
        in: RecipeExtraction(title: "Only a title"),
        sources: []
      )

      expectNoDifference(issues, [.init(kind: .emptyIngredients), .init(kind: .emptyInstructions)])
    }
  }
}
