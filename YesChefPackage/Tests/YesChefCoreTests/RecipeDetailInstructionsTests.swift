import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Test
  func instructionGroupsSortSectionsBeforeStepsWithSharedStepOrders() {
    let recipeID = SampleUUIDSequence.uuid(40_001)
    let prepSectionID = SampleUUIDSequence.uuid(40_002)
    let cookSectionID = SampleUUIDSequence.uuid(40_003)
    let detail = RecipeDetailData(
      recipe: Recipe(
        id: recipeID,
        title: "Sectioned Supper",
        dateCreated: .distantPast,
        dateModified: .distantPast
      ),
      instructionSections: [
        InstructionSection(id: cookSectionID, recipeID: recipeID, name: "Cook", sortOrder: 1),
        InstructionSection(id: prepSectionID, recipeID: recipeID, name: "Prep", sortOrder: 0),
      ],
      instructionSteps: [
        InstructionStep(
          id: SampleUUIDSequence.uuid(40_004),
          recipeID: recipeID,
          sectionID: cookSectionID,
          text: "Roast until browned.",
          sortOrder: 0
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(40_005),
          recipeID: recipeID,
          sectionID: prepSectionID,
          text: "Season the chicken.",
          sortOrder: 1
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(40_006),
          recipeID: recipeID,
          sectionID: prepSectionID,
          text: "Heat the oven.",
          sortOrder: 0
        ),
      ]
    )

    expectNoDifference(detail.instructionGroups.map(\.name), ["Prep", "Cook"])
    expectNoDifference(
      detail.instructionGroups.flatMap(\.steps).map(\.text),
      ["Heat the oven.", "Season the chicken.", "Roast until browned."]
    )
  }
}
