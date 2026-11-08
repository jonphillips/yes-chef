import CustomDump
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuPrepPlanWorkDayTests {
    @Test
    func workDaysDecodeEncodeAndOutOfRangeJSONStaysFlexible() throws {
      let decoded = try JSONDecoder().decode(
        PrepPlanStep.self,
        from: Data(#"{"session":"Morning","task":"Brine turkey","workDay":3}"#.utf8)
      )
      #expect(decoded.workDayOffset == 2)
      let encoded = try JSONEncoder().encode(decoded)
      let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(object["workDay"] as? Int == 3)

      expectNoDifference(
        MenuPrepPlanClient.parse(
          #"{"steps":[{"session":"Morning","task":"In range","workDay":3},{"session":"Anytime","task":"Too late","workDay":4}]}"#,
          dayCount: 3
        ),
        MenuPrepPlan(
          steps: [
            PrepPlanStep(session: "Morning", task: "In range", workDayOffset: 2),
            PrepPlanStep(session: "Anytime", task: "Too late"),
          ],
          outOfRangeDayCount: 1
        )
      )
    }

    @Test
    func editableTextRoundTripsDaysAndReportsOutOfRangeHeaders() {
      let plan = MenuPrepPlan(steps: [
        PrepPlanStep(session: "Evening", task: "Salt turkey", workDayOffset: 1),
        PrepPlanStep(session: "Morning", task: "Set table"),
      ])
      let text = """
      Day 2 · Evening:
      - Salt turkey
      Morning:
      - Set table
      Day 8 · Late task:
      - Chill dessert
      """
      let parsed = MenuPrepPlan().parsingEditableReviewText(text, dayCount: 3)
      #expect(parsed.plan.steps.map(\.workDayOffset) == [1, nil, nil])
      #expect(parsed.outOfRangeDayCount == 1)
      #expect(parsed.unparsedLines.isEmpty)

      expectNoDifference(plan.editableReviewText(dayCount: 3), """
        Day 2 · Evening:
        - Salt turkey
        Morning:
        - Set table
        """)
      #expect(plan.applyingEditableReviewText(plan.editableReviewText(dayCount: 3), dayCount: 3) == plan)
    }

    @Test
    func oneDayEditableTextRemainsUnchanged() {
      let plan = MenuPrepPlan(steps: [PrepPlanStep(session: "The day before", task: "Make stock")])
      #expect(plan.editableReviewText(dayCount: 1) == "The day before:\n- Make stock")
      #expect(plan.applyingEditableReviewText(plan.editableReviewText(dayCount: 1), dayCount: 1) == plan)
    }

    @Test
    func dayHeaderAllowsWhitespaceSeparatorBeforeSession() {
      let parsed = MenuPrepPlan().parsingEditableReviewText(
        "Day 2 Morning:\n- Prepare the bread",
        dayCount: 3
      )
      #expect(parsed.plan.steps == [PrepPlanStep(session: "Morning", task: "Prepare the bread", workDayOffset: 1)])
      #expect(parsed.unparsedLines.isEmpty)
    }

    @Test
    func oneDayMenuKeepsDayNumberHeaderAsSessionText() {
      let parsed = MenuPrepPlan().parsingEditableReviewText(
        "Day 2 prep:\n- Set the oven",
        dayCount: 1
      )
      #expect(parsed.plan.steps == [PrepPlanStep(session: "Day 2 prep", task: "Set the oven")])
    }
  }
}
