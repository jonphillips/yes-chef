import YesChefCore

extension MealCalendarDayAgendaView {
  var handoffSource: HandoffExportSource? {
    handoffAnchorItemID.map { .mealPlan($0) }
  }

  var complementHandoffSource: HandoffExportSource? {
    handoffAnchorItemID.map { .mealPlanComplement($0) }
  }

  private var handoffAnchorItemID: MealPlanItem.ID? {
    model.selectedDayRows
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
      .map(\.item.id)
  }
}
