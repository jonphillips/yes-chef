import Dependencies
import Foundation
import Testing
import YesChefCore

extension AIHandoffTests {
  @Test
  func compareAndExperimentsRecipeReturnsStageTheWorkingRecipeReview() throws {
    @Dependency(\.defaultDatabase) var database
    let workbenchID = SampleUUIDSequence.uuid(38_010)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_000)
    let recipeJSON = """
    {"@context":"https://schema.org","@type":"Recipe","name":"Brown Butter Cookies","recipeIngredient":["2 cups flour"],"recipeInstructions":[{"@type":"HowToStep","text":"Brown the butter."}]}
    """

    try database.write { db in
      try Workbench.insert {
        Workbench(id: workbenchID, title: "Cookie Study", sortOrder: 0, dateCreated: now, dateModified: now)
      }.execute(db)

      for (index, task) in [AIHandoffTaskType.workbenchCompare, .workbenchExperiments].enumerated() {
        let handoffID = SampleUUIDSequence.uuid(38_011 + index)
        try AIHandoffRepository.create(
          AIHandoff(id: handoffID, sourceType: .workbench, sourceID: workbenchID, taskType: task,
            createdAt: now, exportedPrompt: ""),
          in: db
        )
        let review = try AIHandoffIntentImport.stageReview(
          handoffID: handoffID,
          result: """
          \(recipeJSON)
          Rationale: Keep the brown butter base and a shorter bake.
          YC-LEARNINGS:
          - Chill the dough before baking.
          """,
          in: db,
          now: now
        )
        guard case let .workbenchDraft(draftReview) = review else {
          Issue.record("Expected recipe review for \(task)")
          continue
        }
        #expect(draftReview.draftRecipe.title == "Brown Butter Cookies")
        #expect(draftReview.draftRecipe.rationale == "Keep the brown butter base and a shorter bake.")
        #expect(draftReview.learnings == ["Chill the dough before baking."])
        #expect(try WorkbenchLogEntry.fetchAll(db).isEmpty)
      }
    }
  }

  @Test
  func comparePromptUsesItsOwnFinalizeClauseAndBothAsksAllowRecipeOutcome() {
    let context = WorkbenchChatContext(title: "Cookie Study", candidates: [])
    let compare = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_020),
      title: "Compare: Cookie Study",
      context: context.compareHandoffPrompt(),
      mode: .discuss,
      deliverableFormat: .workbenchCompare
    )
    #expect(!compare.localizedCaseInsensitiveContains("prep plan"))
    #expect(compare.contains("When the user asks you to finalize, return the named candidate differences"))
    #expect(compare.contains("if the cook has settled on a recipe, that recipe as the schema.org Recipe JSON-LD"))
    let experiments = AIHandoffToken.prompt(
      handoffID: SampleUUIDSequence.uuid(38_021),
      title: "Experiments: Cookie Study",
      context: context.experimentsHandoffPrompt(),
      mode: .discuss,
      deliverableFormat: .workbenchExperiments
    )
    #expect(experiments.contains("When the user asks you to finalize, return the proposed experiments"))
    #expect(experiments.contains("if the cook has settled on a recipe, that recipe as the schema.org Recipe JSON-LD"))
    #expect(context.compareHandoffPrompt().contains("schema.org `Recipe` JSON-LD"))
    #expect(context.experimentsHandoffPrompt().contains("schema.org `Recipe` JSON-LD"))
  }

  @Test
  func compareProseWithStrayBraceStaysAnObservationAndRationaleMayPrecedeRecipeJSON() throws {
    @Dependency(\.defaultDatabase) var database
    let workbenchID = SampleUUIDSequence.uuid(38_030)
    let handoffID = SampleUUIDSequence.uuid(38_031)
    let now = Date(timeIntervalSinceReferenceDate: 840_000_100)
    let recipeJSON = """
    {"@context":"https://schema.org","@type":"Recipe","name":"Crisp Potatoes","recipeIngredient":["2 potatoes"],"recipeInstructions":[{"@type":"HowToStep","text":"Roast until crisp."}]}
    """

    try database.write { db in
      try Workbench.insert {
        Workbench(id: workbenchID, title: "Potato Study", sortOrder: 0, dateCreated: now, dateModified: now)
      }.execute(db)
      try AIHandoffRepository.create(
        AIHandoff(id: handoffID, sourceType: .workbench, sourceID: workbenchID,
          taskType: .workbenchCompare, createdAt: now, exportedPrompt: ""),
        in: db
      )

      let prose = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: "Candidate B uses more oil {slightly}, which should improve browning.",
        in: db,
        now: now
      )
      guard case let .workbenchCompare(comparison) = prose else {
        Issue.record("Expected prose comparison to remain an observation")
        return
      }
      #expect(comparison.comparison.contains("{slightly}"))

      let recipe = try AIHandoffIntentImport.stageReview(
        handoffID: handoffID,
        result: """
        Rationale: Keep the pieces large so they stay fluffy inside.
        ```json
        \(recipeJSON)
        ```
        """,
        in: db,
        now: now,
        allowRestage: true
      )
      guard case let .workbenchDraft(draft) = recipe else {
        Issue.record("Expected fenced recipe return to stage the working-recipe review")
        return
      }
      #expect(draft.draftRecipe.title == "Crisp Potatoes")
      #expect(draft.draftRecipe.rationale == "Keep the pieces large so they stay fluffy inside.")
    }
  }
}
