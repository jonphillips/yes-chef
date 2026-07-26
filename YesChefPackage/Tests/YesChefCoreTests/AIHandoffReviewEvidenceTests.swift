import CustomDump
import Testing
import YesChefCore

@Suite
struct AIHandoffReviewEvidenceTests {
  @Test
  func menuPrepPlanSurfacesOmittedCurrentStepsAsReviewEvidence() {
    let currentPlan = MenuPrepPlan(
      steps: [
        PrepPlanStep(session: "Friday", task: "Salt the pizza dough"),
        PrepPlanStep(session: "Saturday", task: "Soak the beans"),
      ]
    )
    let evidence = AIHandoffReturn.omittedCurrentPrepStepEvidence(
      proposedPlan: MenuPrepPlan(steps: [PrepPlanStep(session: "Saturday", task: "Soak the beans")]),
      currentPlan: currentPlan
    )

    expectNoDifference(
      evidence,
      ["Existing prep step missing from returned plan: Friday: Salt the pizza dough"]
    )
  }
}
