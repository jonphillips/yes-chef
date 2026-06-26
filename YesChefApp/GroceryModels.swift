import CasePaths
import Dependencies
import Foundation
import Observation
import SQLiteData
import YesChefCore

typealias CoreGroceryList = YesChefCore.GroceryList

@Observable
@MainActor
final class GroceryLibraryModel {
  @CasePathable
  enum Destination {
    case addCustomItem
    case addList
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(GroceryListRequest(), animation: .default) var listRows: [GroceryListRowData] = []
  @ObservationIgnored
  @Fetch(GroceryItemListRequest(), animation: .default) var itemRows: [GroceryItemRowData] = []
  @ObservationIgnored
  @Fetch(MenuListRequest(), animation: .default) var menuRows: [MenuRowData] = []

  var destination: Destination?
  var selectedListID: CoreGroceryList.ID?
  var errorMessage: String?
  var isShowingError = false

  var selectedListRow: GroceryListRowData? {
    if let selectedListID,
       let row = listRows.first(where: { $0.id == selectedListID }) {
      return row
    }
    return listRows.first
  }

  var selectedItemRows: [GroceryItemRowData] {
    guard let listID = selectedListRow?.id else { return [] }
    return itemRows.filter { $0.item.groceryListID == listID }
  }

  var availableMenuRows: [MenuRowData] {
    menuRows.sorted {
      $0.menu.title.localizedStandardCompare($1.menu.title) == .orderedAscending
    }
  }

  func ensureDefaultListIfNeeded() {
    do {
      let listID = try database.write { db in
        try GroceryRepository.ensureDefaultList(
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      if selectedListID == nil {
        selectedListID = listID
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addListButtonTapped() {
    destination = .addList
  }

  func addCustomItemButtonTapped() {
    destination = .addCustomItem
  }

  func saveListButtonTapped(title: String, remindersListName: String) -> Bool {
    do {
      let listID = try database.write { db in
        try GroceryRepository.addList(
          title: title,
          remindersListName: remindersListName,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      selectedListID = listID
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func saveCustomItemButtonTapped(
    title: String,
    quantityText: String,
    unit: String,
    aisle: String,
    notes: String
  ) -> Bool {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addCustomItem(
          title: title,
          quantityText: quantityText,
          unit: unit,
          aisle: aisle,
          notes: notes,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func togglePurchasedButtonTapped(itemID: GroceryItem.ID) {
    guard let row = itemRows.first(where: { $0.item.id == itemID }) else { return }

    do {
      try database.write { db in
        try GroceryRepository.updatePurchasedState(
          itemID: itemID,
          isPurchased: !row.item.isPurchased,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteButtonTapped(itemID: GroceryItem.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteItem(itemID: itemID, in: db)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteSourceButtonTapped(sourceID: GroceryItemSource.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteSource(
          sourceID: sourceID,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteContributionButtonTapped(sourceID: GroceryItemSource.ID) {
    do {
      try database.write { db in
        try GroceryRepository.deleteContribution(
          containingSourceID: sourceID,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addSelectedMealRowsButtonTapped(_ rows: [MealPlanItemRowData]) {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addMealPlanRows(
          rows,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addMenuButtonTapped(menuID: CoreMenu.ID) {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addMenu(
          menuID: menuID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addRecipeButtonTapped(recipeID: Recipe.ID) {
    do {
      let selectedListID = selectedListID
      let listID = try database.write { db in
        let listID = try selectedOrDefaultGroceryListID(
          selectedListID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        try GroceryRepository.addRecipe(
          recipeID: recipeID,
          groceryListID: listID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
        return listID
      }
      self.selectedListID = listID
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

private func selectedOrDefaultGroceryListID(
  _ selectedListID: CoreGroceryList.ID?,
  in db: Database,
  now: Date,
  uuid: () -> UUID
) throws -> CoreGroceryList.ID {
  if let selectedListID,
     try GroceryList.find(selectedListID).fetchOne(db) != nil {
    return selectedListID
  }

  return try GroceryRepository.ensureDefaultList(
    in: db,
    now: now,
    uuid: uuid
  )
}
