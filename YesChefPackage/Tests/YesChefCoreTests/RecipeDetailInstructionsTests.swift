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

  @Test
  func instructionGroupsKeepStepsWhoseSectionsHaveNotSyncedYet() {
    let recipeID = SampleUUIDSequence.uuid(41_001)
    let knownSectionID = SampleUUIDSequence.uuid(41_002)
    let missingSectionID = SampleUUIDSequence.uuid(41_003)
    let detail = RecipeDetailData(
      recipe: Recipe(id: recipeID, title: "Syncing Supper", dateCreated: .distantPast, dateModified: .distantPast),
      instructionSections: [
        InstructionSection(id: knownSectionID, recipeID: recipeID, name: "Cook", sortOrder: 0)
      ],
      instructionSteps: [
        InstructionStep(
          id: SampleUUIDSequence.uuid(41_004),
          recipeID: recipeID,
          sectionID: knownSectionID,
          text: "Cook the sauce.",
          sortOrder: 0
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(41_005),
          recipeID: recipeID,
          sectionID: missingSectionID,
          text: "Rest before serving.",
          sortOrder: 0
        ),
      ]
    )

    expectNoDifference(detail.instructionGroups.map(\.id), [knownSectionID, missingSectionID])
    expectNoDifference(detail.instructionGroups.map(\.name), ["Cook", nil])
    expectNoDifference(
      detail.instructionGroups.flatMap(\.steps).map(\.text),
      ["Cook the sauce.", "Rest before serving."]
    )
  }

  @Test
  func instructionGroupsClusterOrphanSectionsAndRecipeAdjustmentsUseTheirOrder() throws {
    let recipeID = SampleUUIDSequence.uuid(42_001)
    let knownSectionID = SampleUUIDSequence.uuid(42_002)
    let firstOrphanSectionID = SampleUUIDSequence.uuid(42_003)
    let secondOrphanSectionID = SampleUUIDSequence.uuid(42_004)
    let detail = RecipeDetailData(
      recipe: Recipe(id: recipeID, title: "Syncing Supper", dateCreated: .distantPast, dateModified: .distantPast),
      instructionSections: [
        InstructionSection(id: knownSectionID, recipeID: recipeID, name: "Cook", sortOrder: 0)
      ],
      instructionSteps: [
        InstructionStep(
          id: SampleUUIDSequence.uuid(42_005),
          recipeID: recipeID,
          sectionID: knownSectionID,
          text: "Cook the sauce.",
          sortOrder: 0
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(42_006),
          recipeID: recipeID,
          sectionID: firstOrphanSectionID,
          text: "First orphan step.",
          sortOrder: 1
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(42_007),
          recipeID: recipeID,
          sectionID: secondOrphanSectionID,
          text: "Second orphan step.",
          sortOrder: 1
        ),
        InstructionStep(
          id: SampleUUIDSequence.uuid(42_008),
          recipeID: recipeID,
          sectionID: firstOrphanSectionID,
          text: "First orphan's later step.",
          sortOrder: 10
        ),
      ]
    )

    expectNoDifference(
      detail.instructionGroups.map(\.id),
      [knownSectionID, firstOrphanSectionID, secondOrphanSectionID]
    )
    expectNoDifference(detail.instructionGroups.map(\.name), ["Cook", nil, nil])
    expectNoDifference(
      detail.instructionGroups.flatMap(\.steps).map(\.text),
      ["Cook the sauce.", "First orphan step.", "First orphan's later step.", "Second orphan step."]
    )

    let proposed = try RecipeAdjustmentProposal().proposedDetail(
      applyingTo: detail,
      now: .distantPast,
      uuid: { SampleUUIDSequence.uuid(42_009) }
    )
    expectNoDifference(
      proposed.instructionSteps.map(\.text),
      ["Cook the sauce.", "First orphan step.", "First orphan's later step.", "Second orphan step."]
    )
  }
}
