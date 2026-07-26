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
        steps: [PrepPlanStep(session: "Saturday", task: "Soak the beans", sourceDish: saturdayDishID)]
      ),
      currentPlan: currentPlan
    )

    expectNoDifference(
      evidence,
      ["Existing prep step missing from returned plan: Friday: Salt the pizza dough"]
    )
    expectNoDifference(
      AIHandoffReturn.droppedSourceDishEvidence(
        proposedPlan: MenuPrepPlan(
          steps: [PrepPlanStep(session: "Saturday", task: "Soak the beans", sourceDish: saturdayDishID)]
        ),
        currentPlan: currentPlan
      ),
      []
    )
  }

  @Test
  func verbatimDishLinkedStepProducesDroppedLinkButNoOmissionEvidence() {
    let dishID = UUID(uuidString: "00000000-0000-0000-0000-000000003953")!
    let currentPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough", sourceDish: dishID)]
    )

    let proposedPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough")]
    )
    expectNoDifference(
      AIHandoffReturn.omittedCurrentPrepStepEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      []
    )
    expectNoDifference(
      AIHandoffReturn.droppedSourceDishEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      ["Kept the step but dropped its recipe link (pasted plans can't carry links): Friday: Salt the pizza dough"]
    )
  }

  @Test
  func verbatimUnlinkedStepProducesNoReviewEvidence() {
    let currentPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough")]
    )
    let proposedPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough")]
    )

    expectNoDifference(
      AIHandoffReturn.omittedCurrentPrepStepEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      []
    )
    expectNoDifference(
      AIHandoffReturn.droppedSourceDishEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      []
    )
  }

  @Test
  func jsonReturnThatCarriesSourceDishProducesNoReviewEvidence() {
    let dishID = UUID(uuidString: "00000000-0000-0000-0000-000000003954")!
    let currentPlan = MenuPrepPlan(
      steps: [PrepPlanStep(session: "Friday", task: "Salt the pizza dough", sourceDish: dishID)]
    )
    let proposedPlan = MenuPrepPlanClient.parse(
      """
      {"steps":[{"session":"Friday","task":"Salt the pizza dough","sourceDish":"\(dishID.uuidString)"}]}
      """
    )

    expectNoDifference(
      AIHandoffReturn.omittedCurrentPrepStepEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      []
    )
    expectNoDifference(
      AIHandoffReturn.droppedSourceDishEvidence(
        proposedPlan: proposedPlan,
        currentPlan: currentPlan
      ),
      []
    )
  }
}
