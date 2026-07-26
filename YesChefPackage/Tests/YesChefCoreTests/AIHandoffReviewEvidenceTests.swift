import CustomDump
import Foundation
import Testing
import YesChefCore

@Suite
struct AIHandoffReviewEvidenceTests {
  @Test
  func menuPrepPlanSurfacesOmittedCurrentStepsAsReviewEvidence() {
    let fridayDishID = UUID(uuidString: "00000000-0000-0000-0000-000000003951")!
    let saturdayDishID = UUID(uuidString: "00000000-0000-0000-0000-000000003952")!
    let currentPlan = MenuPrepPlan(
      steps: [
        PrepPlanStep(session: "Friday", task: "Salt the pizza dough", sourceDish: fridayDishID),
        PrepPlanStep(session: "Saturday", task: "Soak the beans", sourceDish: saturdayDishID),
      ]
    )
    let evidence = AIHandoffReturn.omittedCurrentPrepStepEvidence(
      proposedPlan: MenuPrepPlan(
        steps: [PrepPlanStep(session: "Saturday", task: "Soak the beans")]
      ),
      currentPlan: currentPlan
    )

    expectNoDifference(
      evidence,
      ["Existing prep step missing from returned plan: Friday: Salt the pizza dough"]
    )
  }

  @Test
  func verbatimDishLinkedStepDoesNotProduceOmissionEvidence() {
    let dishID = UUID(uuidString: "00000000-0000-0000-0000-000000003953")!
    let currentPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough", sourceDish: dishID)]
    )

    expectNoDifference(
      AIHandoffReturn.omittedCurrentPrepStepEvidence(
        proposedPlan: MenuPrepPlan(
          steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough")]
        ),
        currentPlan: currentPlan
      ),
      []
    )
  }
}
