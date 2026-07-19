import Foundation
import YesChefCore

extension MenuDetailModel {
  func createPrepPlanStep(_ draft: PrepPlanStep) {
    do {
      try database.write { db in
        try PrepPlanStepRepository.create(draft, for: menuID, in: db, now: now, uuid: { uuid() })
      }
      toastCenter?.postSuccess("Added prep step.")
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
      toastCenter?.postSuccess("Updated prep step.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deletePrepPlanStep(_ id: PrepPlanStepRecord.ID) {
    do {
      try database.write { db in try PrepPlanStepRepository.delete(id: id, in: db, now: now) }
      toastCenter?.postSuccess("Deleted prep step.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func reorderPrepPlanStep(_ id: PrepPlanStepRecord.ID, direction: MenuItemMoveDirection) {
    do {
      let moved = try database.write { db in
        try PrepPlanStepRepository.reorder(id: id, direction: direction, in: db, now: now)
      }
      guard moved else {
        errorMessage = direction == .earlier
          ? "That prep step is already at the beginning of the plan."
          : "That prep step is already at the end of the plan."
        isShowingError = true
        return
      }
      toastCenter?.postSuccess(direction == .earlier ? "Moved prep step earlier." : "Moved prep step later.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func updateLearning(_ learning: Learning, text: String) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      errorMessage = "A learning can't be blank."
      isShowingError = true
      return
    }
    do {
      try database.write { db in try LearningRepository.update(id: learning.id, text: text, in: db, now: now) }
      toastCenter?.postSuccess("Updated learning.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteLearning(_ id: Learning.ID) {
    do {
      try database.write { db in try LearningRepository.delete(id: id, in: db) }
      toastCenter?.postSuccess("Deleted learning.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func reorderLearnings(_ ids: [Learning.ID], destination: LearningReorderDestination) {
    do {
      _ = try database.write { db in
        try LearningRepository.reorder(
          sourceType: .menu,
          sourceID: menuID,
          movingIDs: ids,
          destination: destination,
          in: db,
          now: now
        )
      }
      toastCenter?.postSuccess("Reordered learning.")
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}
