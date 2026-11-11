import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct MenuPrepPlanModelTests {
  @Test
  func savingAnEditedStepPersistsItsSelectedTimeAndMovesItIntoOrder() throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000007601")!
    let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000007602")!
    let now = Date(timeIntervalSinceReferenceDate: 900_700_000)

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Three Day Menu", dayCount: 3, dateCreated: now, dateModified: now)
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(
            id: stepID,
            menuID: menuID,
            sortOrder: 0,
            session: "Morning",
            task: "Make the dough",
            timeOfDay: 19 * 60,
            workDayOffset: 1
          )
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(id: UUID(), menuID: menuID, sortOrder: 1, session: "Evening", task: "Roast", timeOfDay: 18 * 60, workDayOffset: 1)
        }.execute(db)
      }

      let model = MenuDetailModel(menuID: menuID)
      var editorDraft = PrepPlanStepEditorDraft(
        step: try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      )
      editorDraft.workDayOffset = 1
      editorDraft.timeOfDay = 20 * 60
      editorDraft.makeAheadWindow = "Up to 3 days ahead"
      model.updatePrepPlanStep(editorDraft.step, id: stepID)

      let savedStep = try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      #expect(savedStep.workDayOffset == 1)
      #expect(savedStep.makeAheadWindow == "Up to 3 days ahead")
      #expect(savedStep.timeOfDay == 20 * 60)
      let orderedTasks = try database.read { db in try PrepPlanStepRepository.steps(for: menuID, in: db).map(\.task) }
      #expect(orderedTasks == ["Roast", "Make the dough"])
      #expect(model.isShowingError == false)
    }
  }
}
