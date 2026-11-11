import CustomDump
import Dependencies
import Foundation
import Testing
@testable import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct PrepPlanMakeAheadWindowTests {
    @Test
    func windowSurvivesJsonAndEditableReviewText() throws {
      let oldData = Data(#"[{"session":"Friday","task":"Make sauce"}]"#.utf8)
      #expect(try JSONDecoder().decode([PrepPlanStep].self, from: oldData).first?.makeAheadWindow == nil)

      let parsed = MenuPrepPlanClient.parse(#"{"steps":[{"session":"Friday","task":"Make sauce","makeAheadWindow":"  Up to 3 days ahead  "},{"session":"Saturday","task":"Toast spices","makeAheadWindow":"  "}]}"#)
      expectNoDifference(parsed.steps.map(\.makeAheadWindow), ["Up to 3 days ahead", nil])
      #expect(parsed.editableReviewText() == "Friday:\n- Make sauce\n  Keeps: Up to 3 days ahead\nSaturday:\n- Toast spices")
      expectNoDifference(
        MenuPrepPlan().parsingEditableReviewText("Friday:\nKeeps: Up to 3 days ahead").unparsedLines,
        ["Keeps: Up to 3 days ahead"]
      )
      #expect(MenuPrepPlan(steps: [.init(session: "Friday", task: "Make sauce")]).editableReviewText() == "Friday:\n- Make sauce")
      #expect(MenuPrepPlanClient.instructions.contains(MenuPrepPlanClient.makeAheadAndLeftoversGuidance))
    }

    @Test
    func replaceTreatsWindowAsStepIdentity() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_550_000)
      let menuID = SampleUUIDSequence.uuid(15_340)
      let firstID = SampleUUIDSequence.uuid(15_341)
      let changedID = SampleUUIDSequence.uuid(15_342)
      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Window Identity", dayCount: 1, dateCreated: now, dateModified: now)
        }.execute(db)
        try PrepPlanStepRepository.replace(
          [.init(session: "Friday", task: "Make sauce", makeAheadWindow: "Up to 3 days ahead")],
          for: menuID, in: db, now: now, uuid: { firstID }
        )
        try PrepPlanStepRepository.replace(
          [.init(session: "Friday", task: "Make sauce", makeAheadWindow: "No more than 24 hours")],
          for: menuID, in: db, now: now, uuid: { changedID }
        )
        #expect(try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.id) == [changedID])
        try PrepPlanStepRepository.replace(
          [.init(session: "Friday", task: "Make sauce", makeAheadWindow: "No more than 24 hours")],
          for: menuID, in: db, now: now, uuid: {
            Issue.record("Unchanged contents must keep their ID")
            return UUID()
          }
        )
        #expect(try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.id) == [changedID])
      }
    }
  }
}
