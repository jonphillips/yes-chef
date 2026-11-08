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
    #expect(context.compareHandoffPrompt().contains("schema.org `Recipe` JSON-LD"))
    #expect(context.experimentsHandoffPrompt().contains("schema.org `Recipe` JSON-LD"))
  }
}
