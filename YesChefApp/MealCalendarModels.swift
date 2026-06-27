import CasePaths
import Dependencies
import Foundation
import Observation
import SQLiteData
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class MealCalendarModel {
  @CasePathable
  enum Destination {
    case itemEditor(MealPlanItemDraftContext)
    case deleteItem(MealPlanItem.ID)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(MealCalendarRequest(), animation: .default) private var fetchedItemRows: [MealPlanItemRowData] = []
  @ObservationIgnored
  @Fetch(RecipeListRequest(), animation: .default) var recipeRows: [RecipeListRowData] = []

  private var optimisticItemRowsByID: [MealPlanItem.ID: MealPlanItemRowData] = [:]
  private var optimisticDeletedItemIDs: Set<MealPlanItem.ID> = []

  var destination: Destination?
  var displayMode = MealCalendarDisplayMode.month
  var selectedDate: Date
  var errorMessage: String?
  var isShowingError = false

  init(selectedDate: Date = Date()) {
    self.selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: selectedDate)
  }

  var periodTitle: String {
    switch displayMode {
    case .month:
      return selectedMonthStart.formatted(.dateTime.month(.wide).year())
    case .week:
      guard let lastDate = visibleWeekDates.last else { return "" }
      return "\(selectedWeekStart.formatted(.dateTime.month(.abbreviated).day())) - \(lastDate.formatted(.dateTime.month(.abbreviated).day()))"
    case .day:
      return selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
  }

  var selectedDateTitle: String {
    selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
  }

  var selectedDateShortTitle: String {
    selectedDate.formatted(.dateTime.month(.abbreviated).day())
  }

  var weekdaySymbols: [String] {
    let symbols = calendar.shortStandaloneWeekdaySymbols
    let startIndex = calendar.firstWeekday - 1
    return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
  }

  var visibleMonthSummaries: [MealCalendarDaySummary] {
    visibleMonthDates.map { date in
      MealCalendarDaySummary(
        date: date,
        isInDisplayedMonth: isDateInDisplayedMonth(date),
        rows: rows(on: date)
      )
    }
  }

  var visibleWeekSummaries: [MealCalendarDaySummary] {
    visibleWeekDates.map { date in
      MealCalendarDaySummary(
        date: date,
        isInDisplayedMonth: true,
        rows: rows(on: date)
      )
    }
  }

  var selectedDayRows: [MealPlanItemRowData] {
    rows(on: selectedDate)
  }

  var itemRows: [MealPlanItemRowData] {
    let pendingItemRows = optimisticItemRowsByID.filter { itemID, row in
      fetchedItemRows.first { !$0.isFromMenu && $0.item.id == itemID } != row
    }
    let pendingDeletedItemIDs = optimisticDeletedItemIDs.filter { itemID in
      fetchedItemRows.contains { !$0.isFromMenu && $0.item.id == itemID }
    }
    guard !pendingItemRows.isEmpty || !pendingDeletedItemIDs.isEmpty else {
      return fetchedItemRows
    }

    var rows = fetchedItemRows.filter { row in
      guard !row.isFromMenu else { return true }
      return pendingItemRows[row.item.id] == nil
        && !pendingDeletedItemIDs.contains(row.item.id)
    }
    rows.append(contentsOf: pendingItemRows.values)
    return rows.sorted(by: areMealPlanRowsInIncreasingOrderForCalendarModel)
  }

  var availableRecipeRows: [RecipeListRowData] {
    recipeRows
      .filter { !$0.recipe.archived }
      .sorted {
        $0.recipe.title.localizedStandardCompare($1.recipe.title) == .orderedAscending
      }
  }

  func selectDisplayMode(_ mode: MealCalendarDisplayMode) {
    displayMode = mode
  }

  func selectDateButtonTapped(_ date: Date) {
    selectedDate = startOfDay(date)
  }

  func previousPeriodButtonTapped() {
    moveSelectedDate(by: previousNextComponent, value: -1)
  }

  func nextPeriodButtonTapped() {
    moveSelectedDate(by: previousNextComponent, value: 1)
  }

  func todayButtonTapped() {
    selectedDate = startOfDay(now)
  }

  func addItemButtonTapped(
    kind: MealPlanItemKind = .recipe,
    mealSlot: MealPlanItemSlot = .dinner,
    recipeID: Recipe.ID? = nil
  ) {
    destination = .itemEditor(
      MealPlanItemDraftContext(
        kind: kind,
        recipeID: recipeID,
        date: startOfDay(selectedDate),
        mealSlot: mealSlot
      )
    )
  }

  func addRecipeToPlanButtonTapped(recipeID: Recipe.ID) {
    addItemButtonTapped(kind: .recipe, recipeID: recipeID)
  }

  func editButtonTapped(itemID: MealPlanItem.ID) {
    guard let row = itemRows.first(where: { $0.item.id == itemID }) else { return }
    destination = .itemEditor(
      MealPlanItemDraftContext(
        itemID: row.item.id,
        kind: row.item.kind,
        recipeID: row.item.recipeID,
        title: row.displayTitle,
        notes: row.item.notes ?? "",
        date: row.item.scheduledDate,
        mealSlot: row.item.mealSlot
      )
    )
  }

  func saveRecipeItemButtonTapped(
    itemID: MealPlanItem.ID? = nil,
    recipeID: Recipe.ID,
    date: Date,
    mealSlot: MealPlanItemSlot,
    notes: String
  ) -> Bool {
    do {
      let scheduledDate = startOfDay(date)
      let result = try database.write { db in
        let savedItemID: MealPlanItem.ID
        if let itemID {
          try MealCalendarRepository.updateRecipeItem(
            itemID: itemID,
            recipeID: recipeID,
            on: scheduledDate,
            mealSlot: mealSlot,
            notes: notes,
            in: db,
            now: now
          )
          savedItemID = itemID
        } else {
          savedItemID = try MealCalendarRepository.addRecipeItem(
            recipeID: recipeID,
            on: scheduledDate,
            mealSlot: mealSlot,
            notes: notes,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
        return (savedItemID, try MealCalendarRequest().fetch(db))
      }
      applyOptimisticRows(result.1, updatedItemIDs: [result.0])
      selectedDate = scheduledDate
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveRecipeItemsButtonTapped(
    recipeIDs: Set<Recipe.ID>,
    date: Date,
    mealSlot: MealPlanItemSlot,
    notes: String
  ) -> Bool {
    let orderedRecipeIDs = availableRecipeRows
      .map(\.recipe.id)
      .filter { recipeIDs.contains($0) }
    guard !orderedRecipeIDs.isEmpty else {
      errorMessage = "Select at least one recipe."
      isShowingError = true
      return false
    }

    do {
      let scheduledDate = startOfDay(date)
      let result = try database.write { db in
        let itemIDs = try MealCalendarRepository.addRecipeItems(
          recipeIDs: orderedRecipeIDs,
          on: scheduledDate,
          mealSlot: mealSlot,
          notes: notes,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return (itemIDs, try MealCalendarRequest().fetch(db))
      }
      applyOptimisticRows(result.1, updatedItemIDs: Set(result.0))
      selectedDate = scheduledDate
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveNoteItemButtonTapped(
    itemID: MealPlanItem.ID? = nil,
    title: String,
    notes: String,
    date: Date,
    mealSlot: MealPlanItemSlot
  ) -> Bool {
    do {
      let scheduledDate = startOfDay(date)
      let result = try database.write { db in
        let savedItemID: MealPlanItem.ID
        if let itemID {
          try MealCalendarRepository.updateNoteItem(
            itemID: itemID,
            title: title,
            notes: notes,
            on: scheduledDate,
            mealSlot: mealSlot,
            in: db,
            now: now
          )
          savedItemID = itemID
        } else {
          savedItemID = try MealCalendarRepository.addNoteItem(
            title: title,
            notes: notes,
            on: scheduledDate,
            mealSlot: mealSlot,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
        return (savedItemID, try MealCalendarRequest().fetch(db))
      }
      applyOptimisticRows(result.1, updatedItemIDs: [result.0])
      selectedDate = scheduledDate
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func deleteButtonTapped(itemID: MealPlanItem.ID) {
    destination = .deleteItem(itemID)
  }

  func confirmDeleteItemButtonTapped(itemID: MealPlanItem.ID) {
    destination = nil

    do {
      let updatedRows = try database.write { db in
        try MealCalendarRepository.deleteItem(itemID: itemID, in: db)
        return try MealCalendarRequest().fetch(db)
      }
      applyOptimisticRows(updatedRows, deletedItemIDs: [itemID])
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func title(for itemID: MealPlanItem.ID) -> String {
    itemRows.first { $0.item.id == itemID }?.displayTitle ?? "this item"
  }

  func rows(on date: Date) -> [MealPlanItemRowData] {
    let day = startOfDay(date)
    return itemRows.filter { $0.item.scheduledDate == day }
  }

  func rows(on date: Date, mealSlot: MealPlanItemSlot) -> [MealPlanItemRowData] {
    rows(on: date).filter { $0.item.mealSlot == mealSlot }
  }

  func isSelectedDate(_ date: Date) -> Bool {
    calendar.isDate(startOfDay(date), inSameDayAs: selectedDate)
  }

  func isToday(_ date: Date) -> Bool {
    calendar.isDate(startOfDay(date), inSameDayAs: now)
  }

  private var calendar: Calendar {
    Calendar.autoupdatingCurrent
  }

  private var selectedMonthStart: Date {
    let components = calendar.dateComponents([.year, .month], from: selectedDate)
    return calendar.date(from: components).map(startOfDay) ?? selectedDate
  }

  private var selectedWeekStart: Date {
    weekStart(containing: selectedDate)
  }

  private var visibleMonthDates: [Date] {
    let gridStart = weekStart(containing: selectedMonthStart)
    return (0..<42).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: gridStart).map(startOfDay)
    }
  }

  private var visibleWeekDates: [Date] {
    (0..<7).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: selectedWeekStart).map(startOfDay)
    }
  }

  private var previousNextComponent: Calendar.Component {
    switch displayMode {
    case .month: .month
    case .week: .weekOfYear
    case .day: .day
    }
  }

  private func moveSelectedDate(by component: Calendar.Component, value: Int) {
    guard let date = calendar.date(byAdding: component, value: value, to: selectedDate) else { return }
    selectedDate = startOfDay(date)
  }

  private func weekStart(containing date: Date) -> Date {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components).map(startOfDay) ?? startOfDay(date)
  }

  private func isDateInDisplayedMonth(_ date: Date) -> Bool {
    calendar.isDate(date, equalTo: selectedMonthStart, toGranularity: .month)
  }

  private func startOfDay(_ date: Date) -> Date {
    calendar.startOfDay(for: date)
  }

  private func applyOptimisticRows(
    _ rows: [MealPlanItemRowData],
    updatedItemIDs: Set<MealPlanItem.ID> = [],
    deletedItemIDs: Set<MealPlanItem.ID> = []
  ) {
    optimisticItemRowsByID = optimisticItemRowsByID.filter { itemID, row in
      fetchedItemRows.first { !$0.isFromMenu && $0.item.id == itemID } != row
    }
    optimisticDeletedItemIDs = optimisticDeletedItemIDs.filter { itemID in
      fetchedItemRows.contains { !$0.isFromMenu && $0.item.id == itemID }
    }

    for itemID in updatedItemIDs {
      if let row = rows.first(where: { !$0.isFromMenu && $0.item.id == itemID }) {
        optimisticItemRowsByID[itemID] = row
        optimisticDeletedItemIDs.remove(itemID)
      }
    }
    for itemID in deletedItemIDs {
      optimisticItemRowsByID[itemID] = nil
      optimisticDeletedItemIDs.insert(itemID)
    }
  }
}

enum MealCalendarDisplayMode: String, CaseIterable, Identifiable {
  case month
  case week
  case day

  var id: Self { self }

  var title: String {
    switch self {
    case .month: "Month"
    case .week: "Week"
    case .day: "Day"
    }
  }
}

struct MealPlanItemDraftContext: Hashable, Sendable {
  var itemID: MealPlanItem.ID?
  var kind: MealPlanItemKind
  var recipeID: Recipe.ID?
  var title: String
  var notes: String
  var date: Date
  var mealSlot: MealPlanItemSlot

  init(
    itemID: MealPlanItem.ID? = nil,
    kind: MealPlanItemKind,
    recipeID: Recipe.ID? = nil,
    title: String = "",
    notes: String = "",
    date: Date,
    mealSlot: MealPlanItemSlot
  ) {
    self.itemID = itemID
    self.kind = kind
    self.recipeID = recipeID
    self.title = title
    self.notes = notes
    self.date = date
    self.mealSlot = mealSlot
  }

  var isEditing: Bool {
    itemID != nil
  }
}

struct MealCalendarDaySummary: Identifiable, Equatable {
  var date: Date
  var isInDisplayedMonth: Bool
  var rows: [MealPlanItemRowData]

  var id: Date { date }

  var mealSlots: [MealPlanItemSlot] {
    MealPlanItemSlot.allCases.filter { slot in
      rows.contains { $0.item.mealSlot == slot }
    }
  }
}

private func areMealPlanRowsInIncreasingOrderForCalendarModel(
  _ lhs: MealPlanItemRowData,
  _ rhs: MealPlanItemRowData
) -> Bool {
  if lhs.item.scheduledDate != rhs.item.scheduledDate {
    return lhs.item.scheduledDate < rhs.item.scheduledDate
  }
  if lhs.item.mealSlot.sortOrder != rhs.item.mealSlot.sortOrder {
    return lhs.item.mealSlot.sortOrder < rhs.item.mealSlot.sortOrder
  }
  if lhs.item.sortOrder != rhs.item.sortOrder {
    return lhs.item.sortOrder < rhs.item.sortOrder
  }
  if lhs.isFromMenu != rhs.isFromMenu {
    return !lhs.isFromMenu
  }
  let titleComparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
  if titleComparison != .orderedSame {
    return titleComparison == .orderedAscending
  }
  return lhs.id.rawValue < rhs.id.rawValue
}
