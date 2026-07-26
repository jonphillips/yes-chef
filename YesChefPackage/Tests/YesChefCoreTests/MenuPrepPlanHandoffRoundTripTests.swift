import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct MenuPrepPlanHandoffRoundTripTests {
    @Test
    func fullDayScopedReturnRetainsBothDaysAndExistingStepIDs() throws {
      @Dependency(\.defaultDatabase) var database
      let now = Date(timeIntervalSinceReferenceDate: 805_450_000)
      let menuID = SampleUUIDSequence.uuid(15_250)
      let dayOneStepID = SampleUUIDSequence.uuid(15_251)
      let dayTwoStepID = SampleUUIDSequence.uuid(15_252)

      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Weekend Menu", dayCount: 2, dateCreated: now, dateModified: now)
        }
        .execute(db)
        var initialIDs = [dayOneStepID, dayTwoStepID].makeIterator()
        try MenuRepository.applyPrepPlan(
          MenuPrepPlan(steps: [
            PrepPlanStep(session: "Friday", task: "Salt the pizza dough"),
            PrepPlanStep(session: "Saturday", task: "Soak the beans"),
          ]),
          to: menuID,
          in: db,
          now: now,
          uuid: { initialIDs.next()! }
        )

        let currentPlan = MenuPrepPlan(steps: try PrepPlanStepRepository.steps(for: menuID, in: db).map(PrepPlanStep.init))
        let returned = AIHandoffReturn.menuPrepPlan(
          from: """
          Friday:
          - Salt the pizza dough
          Saturday:
          - Soak the beans
          """,
          currentPlan: currentPlan
        )
        expectNoDifference(returned.unparsedLines, [])
        try MenuRepository.applyPrepPlan(
          returned.plan,
          to: menuID,
          in: db,
          now: now.addingTimeInterval(60),
          uuid: { SampleUUIDSequence.uuid(15_253) }
        )
      }

      try database.read { db in
        expectNoDifference(
          try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.id),
          [dayOneStepID, dayTwoStepID]
        )
      }
    }
  }
}
