import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct MenuPrepPlanModelTests {
  @Test
  func savingAnEditedStepPersistsItsSelectedWorkDay() throws {
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
            task: "Make the dough"
          )
        }.execute(db)
      }

      let model = MenuDetailModel(menuID: menuID)
      var editorDraft = PrepPlanStepEditorDraft(
        step: try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      )
      editorDraft.workDayOffset = 1
      editorDraft.makeAheadWindow = "Up to 3 days ahead"
      model.updatePrepPlanStep(editorDraft.step, id: stepID)

      let savedStep = try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      #expect(savedStep.workDayOffset == 1)
      #expect(savedStep.makeAheadWindow == "Up to 3 days ahead")
      #expect(model.isShowingError == false)
    }
  }
}
