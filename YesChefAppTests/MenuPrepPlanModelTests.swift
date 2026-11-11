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

  @Test
  func movePrepPlanStepToNextDayUsesTodayOffsetAndPreservesFields() throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000007621")!
    let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000007622")!
    let now = Date(timeIntervalSinceReferenceDate: 900_700_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let placementStart = calendar.date(byAdding: .day, value: -1, to: now)!

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
            serves: "Saturday breakfast",
            makeAheadWindow: "Up to 3 days ahead",
            timeOfDay: 19 * 60,
            workDayOffset: 0,
            completedAt: now.addingTimeInterval(-300)
          )
        }.execute(db)
      }

      let step = try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      let layout = TodayPrepLayout.make(
        steps: [step],
        dayCount: 3,
        placements: [MenuPlacement(id: UUID(), menuID: menuID, startDate: placementStart, dateCreated: now, dateModified: now)],
        today: now,
        calendar: calendar
      )
      let targetOffset = try #require(MenuDetailModel.nextPrepPlanDayOffset(layout: layout, selectedBand: nil))
      #expect(targetOffset == 2)
      #expect(MenuDetailModel.canMovePrepPlanStepToNextDay(step, targetOffset: targetOffset, dayCount: 3))
      #expect(!MenuDetailModel.canMovePrepPlanStepToNextDay(step, targetOffset: 0, dayCount: 3))
      #expect(!MenuDetailModel.canMovePrepPlanStepToNextDay(step, targetOffset: 3, dayCount: 3))

      let model = MenuDetailModel(menuID: menuID)
      model.movePrepPlanStepToNextDay(step, targetOffset: targetOffset)
      let savedStep = try #require(database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db) })
      #expect(savedStep.workDayOffset == 2)
      #expect(savedStep.task == "Make the dough")
      #expect(savedStep.serves == "Saturday breakfast")
      #expect(savedStep.makeAheadWindow == "Up to 3 days ahead")
      #expect(savedStep.timeOfDay == 19 * 60)
      #expect(savedStep.completedAt == now.addingTimeInterval(-300))
      #expect(model.isShowingError == false)
    }
  }

  @Test
  func prepChecksPersistAndUncheckAllTouchesOnlyThatMenu() throws {
    let menuID = UUID(uuidString: "00000000-0000-0000-0000-000000007611")!
    let otherMenuID = UUID(uuidString: "00000000-0000-0000-0000-000000007612")!
    let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000007613")!
    let otherStepID = UUID(uuidString: "00000000-0000-0000-0000-000000007614")!
    let now = Date(timeIntervalSinceReferenceDate: 900_700_000)

    try withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try database.write { db in
        try Menu.insert {
          Menu(id: menuID, title: "Menu", dayCount: 3, dateCreated: now, dateModified: now)
        }.execute(db)
        try Menu.insert {
          Menu(id: otherMenuID, title: "Other", dayCount: 2, dateCreated: now, dateModified: now)
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(id: stepID, menuID: menuID, sortOrder: 0, session: "Today", task: "Salt", workDayOffset: 0)
        }.execute(db)
        try PrepPlanStepRecord.insert {
          PrepPlanStepRecord(id: otherStepID, menuID: otherMenuID, sortOrder: 0, session: "Today", task: "Roast", workDayOffset: 0, completedAt: now)
        }.execute(db)
      }
      let model = MenuDetailModel(menuID: menuID)
      let menuModified = try #require(database.read { db in try Menu.find(menuID).fetchOne(db)?.dateModified })
      model.setPrepPlanStepCompleted(stepID, at: now)
      #expect(try database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db)?.completedAt } == now)
      #expect(try database.read { db in try Menu.find(menuID).fetchOne(db)?.dateModified } == menuModified)
      model.uncheckAllPrepPlanSteps()
      #expect(try database.read { db in try PrepPlanStepRecord.find(stepID).fetchOne(db)?.completedAt } == nil)
      #expect(try database.read { db in try PrepPlanStepRecord.find(otherStepID).fetchOne(db)?.completedAt } == now)
      #expect(try database.read { db in try Menu.find(menuID).fetchOne(db)?.dateModified } == menuModified)
      #expect(model.isShowingError == false)
    }
  }
}
