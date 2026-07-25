import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MakeAheadPlanRenderingTests {
    @Test
    func renderedPlanFlattensForRecipeStorage() {
      let plan = MakeAheadPlan(
        steps: [
          MakeAheadStep(when: "Day before", task: "Toast the nuts.", why: "They stay crisp once cooled."),
          MakeAheadStep(when: "Just before dinner", task: "Dress the salad."),
        ]
      )

      expectNoDifference(
        plan.rendered(),
        """
        Day before: Toast the nuts.
        Why: They stay crisp once cooled.

        Just before dinner: Dress the salad.
        """
      )
    }

    @Test
    func depositOrderingPlacesRecognizedTimingLabelsFirstAndKeepsUnknownLabelsStable() {
      let plan = MakeAheadPlan(
        steps: [
          MakeAheadStep(when: "Just before serving", task: "Dress the salad."),
          MakeAheadStep(when: "Whenever convenient", task: "Polish the serving spoon."),
          MakeAheadStep(when: "Morning of", task: "Toast the nuts."),
          MakeAheadStep(when: "Up to 2 days ahead", task: "Make the dressing."),
          MakeAheadStep(when: "Night before", task: "Wash the greens."),
          MakeAheadStep(when: "Day of", task: "Set the table."),
          MakeAheadStep(when: "After dinner", task: "Write down what worked."),
        ]
      )

      expectNoDifference(
        plan.orderedForDeposit().steps.map(\.when),
        [
          "Up to 2 days ahead",
          "Night before",
          "Morning of",
          "Day of",
          "Just before serving",
          "Whenever convenient",
          "After dinner",
        ]
      )
    }
  }
}
