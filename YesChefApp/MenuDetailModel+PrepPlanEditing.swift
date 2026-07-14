import Foundation
import YesChefCore

extension MenuDetailModel {
  func createPrepPlanStep(_ draft: PrepPlanStep) {
    do {
      try database.write { db in
        try PrepPlanStepRepository.create(draft, for: menuID, in: db, now: now, uuid: { uuid() })
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func updatePrepPlanStep(_ draft: PrepPlanStep, id: PrepPlanStepRecord.ID) {
    do {
      try database.write { db in
        try PrepPlanStepRepository.update(
          id: id, session: draft.session, task: draft.task, serves: draft.serves, in: db, now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deletePrepPlanStep(_ id: PrepPlanStepRecord.ID) {
    do {
      try database.write { db in try PrepPlanStepRepository.delete(id: id, in: db, now: now) }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func reorderPrepPlanStep(_ id: PrepPlanStepRecord.ID, direction: MenuItemMoveDirection) {
    do {
      try database.write { db in
        _ = try PrepPlanStepRepository.reorder(id: id, direction: direction, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func updateLearning(_ learning: Learning, text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    do {
      try database.write { db in try LearningRepository.update(id: learning.id, text: text, in: db, now: now) }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteLearning(_ id: Learning.ID) {
    do {
      try database.write { db in try LearningRepository.delete(id: id, in: db) }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}
