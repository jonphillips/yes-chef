import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PrepPlanTimeTests {
    @Test
    func wireTimesRoundTripAndMalformedValuesBecomeAbsent() throws {
      #expect(PrepPlanTime.minutes(from: "07:05") == 425)
      #expect(PrepPlanTime.minutes(from: "7:05") == 425)
      for invalid in ["24:00", "9am", "12:5", "12:60"] {
        #expect(PrepPlanTime.minutes(from: invalid) == nil)
      }
      let decoded = try JSONDecoder().decode(PrepPlanStep.self, from: Data(#"{"session":"Day of","task":"Warm pie","time":"15:15","workDay":2}"#.utf8))
      #expect(decoded.timeOfDay == 915)
      let encoded = try JSONEncoder().encode(decoded)
      let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(object["time"] as? String == "15:15")
      let staged = ChatAccessStagedPrepPlan.Dish.Step(workDayOffset: 1, session: "Dinner", task: "Warm pie", timeOfDay: 915)
      let stagedObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(staged)) as? [String: Any])
      #expect(stagedObject["time"] as? String == "15:15")
      #expect(try JSONDecoder().decode(ChatAccessStagedPrepPlan.Dish.Step.self, from: Data(#"{"session":"Dinner","task":"Warm pie","time":"24:00"}"#.utf8)).timeOfDay == nil)
      #expect(try JSONDecoder().decode(PrepPlanStep.self, from: Data(#"{"session":"Day of","task":"Warm pie","time":"24:00"}"#.utf8)).timeOfDay == nil)
      #expect(try JSONDecoder().decode(PrepPlanStep.self, from: Data(#"{"session":"Day of","task":"Warm pie"}"#.utf8)).timeOfDay == nil)
    }

    @Test
    func editableReviewTimeAndWindowRoundTripInEitherOrder() {
      let text = "Day 2 · Dinner:\n- Warm pie\n  Time: 15:15\n  Keeps: 3 days"
      let parsed = MenuPrepPlan().parsingEditableReviewText(text, dayCount: 3)
      #expect(parsed.plan.steps.first?.timeOfDay == 915)
      #expect(parsed.plan.steps.first?.makeAheadWindow == "3 days")
      #expect(parsed.plan.editableReviewText(dayCount: 3) == "Day 2 · Dinner:\n- Warm pie\n  Keeps: 3 days\n  Time: 15:15")

      let reversed = MenuPrepPlan().parsingEditableReviewText("Dinner:\n- Warm pie\n  Keeps: 3 days\n  Time: 15:15")
      #expect(reversed.plan.steps.first?.timeOfDay == 915)
      #expect(reversed.plan.steps.first?.makeAheadWindow == "3 days")
      #expect(MenuPrepPlan(steps: [.init(session: "Dinner", task: "Warm pie")]).editableReviewText() == "Dinner:\n- Warm pie")
    }

    @Test
    func placementInsertsTimedStepBeforeFirstLaterStepOnItsDay() {
      let menuID = UUID()
      func row(_ order: Int, _ day: Int?, _ time: Int?) -> PrepPlanStepRecord {
        PrepPlanStepRecord(id: UUID(), menuID: menuID, sortOrder: order, session: "Dinner", task: "Step", timeOfDay: time, workDayOffset: day)
      }
      let steps = [row(0, 1, 18 * 60 + 57), row(1, 1, 18 * 60 + 43), row(2, 1, 10 * 60), row(3, 1, nil), row(4, 2, 20 * 60)]
      #expect(PrepPlanPlacement.insertionIndex(of: row(99, 1, 15 * 60 + 15), into: steps, dayCount: 7, fallbackIndex: steps.count) == 0)
      #expect(PrepPlanPlacement.insertionIndex(of: row(99, 1, 22 * 60), into: steps, dayCount: 7, fallbackIndex: steps.count) == 4)
      #expect(PrepPlanPlacement.insertionIndex(of: row(99, 3, 12 * 60), into: steps, dayCount: 7, fallbackIndex: 2) == 2)
    }

    @Test
    func replaceOrdersTimedDraftsAndKeepsUntimedRelativeOrderAndIdentity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_555_000)
      let menuID = UUID()
      let drafts = [
        PrepPlanStep(session: "Evening", task: "Chicken", timeOfDay: 18 * 60 + 57, workDayOffset: 1),
        PrepPlanStep(session: "Evening", task: "Köfte", timeOfDay: 18 * 60 + 43, workDayOffset: 1),
        PrepPlanStep(session: "Morning", task: "Tzatziki", timeOfDay: 10 * 60, workDayOffset: 1),
        PrepPlanStep(session: "Flexible", task: "Set table"),
      ]
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Time order", dayCount: 7, dateCreated: now, dateModified: now) }.execute(db)
        try PrepPlanStepRepository.replace(drafts, for: menuID, in: db, now: now, uuid: UUID.init)
        #expect(try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.task) == ["Tzatziki", "Köfte", "Chicken", "Set table"])
        let originalIDs = try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.id)
        try PrepPlanStepRepository.replace(drafts, for: menuID, in: db, now: now, uuid: { Issue.record("Identical replacement must keep IDs"); return UUID() })
        #expect(try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.id) == originalIDs)
      }
    }

    @Test
    func createPlacesTimedStepWithinItsWorkDay() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_556_000)
      let menuID = UUID()
      try database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Time order", dayCount: 3, dateCreated: now, dateModified: now) }.execute(db)
        try PrepPlanStepRecord.insert {
          [
            PrepPlanStepRecord(id: UUID(), menuID: menuID, sortOrder: 0, session: "Dinner", task: "Later", timeOfDay: 18 * 60, workDayOffset: 1),
            PrepPlanStepRecord(id: UUID(), menuID: menuID, sortOrder: 1, session: "Dinner", task: "Other day", timeOfDay: 12 * 60, workDayOffset: 2),
          ]
        }.execute(db)
        try PrepPlanStepRepository.create(.init(session: "Dinner", task: "Earlier", timeOfDay: 16 * 60, workDayOffset: 1), for: menuID, in: db, now: now, uuid: { UUID() })
        #expect(try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.task) == ["Earlier", "Later", "Other day"])
      }
    }
  }
}
