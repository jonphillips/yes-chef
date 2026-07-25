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
          MakeAheadStep(when: "Before serving", task: "Dress the salad."),
          MakeAheadStep(when: "Whenever convenient", task: "Polish the serving spoon."),
          MakeAheadStep(when: "20 minutes ahead", task: "Slice the bread."),
          MakeAheadStep(when: "Morning of", task: "Toast the nuts."),
          MakeAheadStep(when: "Up to 2 days ahead", task: "Make the dressing."),
          MakeAheadStep(when: "4 hours ahead", task: "Set the butter out."),
          MakeAheadStep(when: "Day before", task: "Chill the wine."),
          MakeAheadStep(when: "Night before", task: "Wash the greens."),
          MakeAheadStep(when: "Day of", task: "Set the table."),
          MakeAheadStep(when: "After dinner", task: "Write down what worked."),
        ]
      )

      expectNoDifference(
        plan.orderedForDeposit().steps.map(\.when),
        [
          "Up to 2 days ahead",
          "Day before",
          "Night before",
          "Morning of",
          "Day of",
          "4 hours ahead",
          "20 minutes ahead",
          "Before serving",
          "Whenever convenient",
          "After dinner",
        ]
      )
    }
  }
}
