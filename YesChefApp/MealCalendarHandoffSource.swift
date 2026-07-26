import Foundation
import YesChefCore

extension MealCalendarDayAgendaView {
  var handoffSource: HandoffExportSource? {
    HandoffExportSource.mealPlanSources(on: model.selectedDate, rows: model.selectedDayRows)?.makeAhead
  }

  var complementHandoffSource: HandoffExportSource? {
    HandoffExportSource.mealPlanSources(on: model.selectedDate, rows: model.selectedDayRows)?.complement
  }
}

extension HandoffExportSource {
  struct MealPlanSources: Sendable {
    let makeAhead: HandoffExportSource
    let complement: HandoffExportSource
  }

  static func mealPlanSources(
    on date: Date,
    rows: [MealPlanItemRowData]
  ) -> MealPlanSources? {
    rows
      .filter { Calendar.autoupdatingCurrent.isDate($0.item.scheduledDate, inSameDayAs: date) }
      .sorted { lhs, rhs in
        if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
          return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
        }
        if lhs.item.sortOrder != rhs.item.sortOrder {
          return lhs.item.sortOrder < rhs.item.sortOrder
        }
        return lhs.item.id.uuidString < rhs.item.id.uuidString
      }
      .first
      .map { item in
        MealPlanSources(
          makeAhead: .mealPlan(item.item.id),
          complement: .mealPlanComplement(item.item.id)
        )
      }
  }
}
