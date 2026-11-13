import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct RecipePlainTextRendererTests {
    @Test
    func rendersBaseRecipeWithSectionsAndLocalStepNumbering() {
      let now = Date(timeIntervalSinceReferenceDate: 900_030_000)
      let recipeID = SampleUUIDSequence.uuid(90_530)
      let ingredients = [
        IngredientSection(id: SampleUUIDSequence.uuid(90_531), recipeID: recipeID, name: "For the dough", sortOrder: 0),
        IngredientSection(id: SampleUUIDSequence.uuid(90_532), recipeID: recipeID, sortOrder: 1),
      ]
      let doughID = ingredients[0].id
      let sauceID = ingredients[1].id
      let directions = [
        InstructionSection(id: SampleUUIDSequence.uuid(90_535), recipeID: recipeID, name: "Prepare", sortOrder: 0),
        InstructionSection(id: SampleUUIDSequence.uuid(90_536), recipeID: recipeID, name: "Bake", sortOrder: 1),
      ]
      let steps = [
        InstructionStep(id: SampleUUIDSequence.uuid(90_537), recipeID: recipeID, sectionID: directions[0].id, text: "Mix the dough.", sortOrder: 0),
        InstructionStep(id: SampleUUIDSequence.uuid(90_538), recipeID: recipeID, sectionID: directions[1].id, text: "Bake until golden.", sortOrder: 0),
      ]
      let variationID = SampleUUIDSequence.uuid(90_542)
      let detail = RecipeDetailData(
        recipe: Recipe(
          id: recipeID,
          title: "Sourdough Flatbread",
          servings: 4,
          servingsText: "Makes 4 flatbreads",
          prepTimeMinutes: 20,
          cookTimeMinutes: 8,
          dateCreated: now,
          dateModified: now,
          viewScale: 3
        ),
        source: RecipeSource(id: SampleUUIDSequence.uuid(90_539), recipeID: recipeID, name: "Jon's Kitchen", url: "https://example.com/flatbread"),
        ingredientSections: ingredients,
        ingredientLines: [
          IngredientLine(id: SampleUUIDSequence.uuid(90_533), recipeID: recipeID, sectionID: doughID, originalText: "1 cup flour", quantity: 1, quantityText: "1", unit: "cup", item: "flour", sortOrder: 0),
          IngredientLine(id: SampleUUIDSequence.uuid(90_534), recipeID: recipeID, sectionID: sauceID, originalText: "⅓ cup yogurt", quantity: 1.0 / 3, quantityText: "⅓", unit: "cup", item: "yogurt", sortOrder: 0),
        ],
        instructionSections: directions,
        instructionSteps: steps,
        notes: [RecipeNote(id: SampleUUIDSequence.uuid(90_540), recipeID: recipeID, text: "Rest the dough overnight.", dateCreated: now, dateModified: now)],
        learnings: [Learning(
          id: SampleUUIDSequence.uuid(90_541),
          sourceType: .recipe,
          sourceID: recipeID,
          text: "This is a learning.",
          provenance: .inApp,
          dateCreated: now,
          dateModified: now
        )],
        variations: [RecipeVariation(
          id: variationID,
          recipeID: recipeID,
          name: "Olive Oil Version",
          sortIndex: 0,
          dateCreated: now,
          dateModified: now
        )],
        activeVariationID: variationID
      )

      expectNoDifference(
        RecipePlainTextRenderer.render(detail),
        """
        Sourdough Flatbread
        Jon's Kitchen
        https://example.com/flatbread
        Makes 4 flatbreads
        Prep time: 20 minutes
        Cook time: 8 minutes

        Ingredients

        For the dough
        - 1 cup flour
        - ⅓ cup yogurt

        Directions

        Prepare
        1. Mix the dough.

        Bake
        1. Bake until golden.

        Notes
        Rest the dough overnight.
        """
      )
    }

    @Test
    func omitsEmptySectionsAndAbsentSourceAndNotes() {
      let now = Date(timeIntervalSinceReferenceDate: 900_040_000)
      let recipeID = SampleUUIDSequence.uuid(90_550)
      let sectionID = SampleUUIDSequence.uuid(90_551)
      let instructionID = SampleUUIDSequence.uuid(90_552)
      let detail = RecipeDetailData(
        recipe: Recipe(id: recipeID, title: "Toast", dateCreated: now, dateModified: now),
        ingredientSections: [IngredientSection(id: sectionID, recipeID: recipeID, sortOrder: 0)],
        instructionSections: [InstructionSection(id: instructionID, recipeID: recipeID, sortOrder: 0)]
      )

      expectNoDifference(RecipePlainTextRenderer.render(detail), "Toast")
    }
  }
}
