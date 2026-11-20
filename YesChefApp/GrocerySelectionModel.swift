import Foundation
import YesChefCore

extension GroceryLibraryModel {
  var allVisibleItemIDs: Set<GroceryItem.ID> {
    Set(selectedItemRows.map(\.id))
  }

  var areAllItemsSelected: Bool {
    !allVisibleItemIDs.isEmpty && allVisibleItemIDs.isSubset(of: selectedItemIDs)
  }

  func selectItemsButtonTapped() {
    selectedItemIDs = []
    isSelectingItems = true
  }

  func doneSelectingButtonTapped() {
    isSelectingItems = false
    selectedItemIDs = []
  }

  func toggleItemSelection(itemID: GroceryItem.ID) {
    guard isSelectingItems else { return }
    if selectedItemIDs.contains(itemID) {
      selectedItemIDs.remove(itemID)
    } else {
      selectedItemIDs.insert(itemID)
    }
  }

  func selectAllButtonTapped() {
    let visibleIDs = allVisibleItemIDs
    guard !visibleIDs.isEmpty else { return }
    selectedItemIDs = visibleIDs.isSubset(of: selectedItemIDs) ? [] : visibleIDs
  }

  func moveSelectedItemsButtonTapped(toListID destinationListID: CoreGroceryList.ID) {
    let itemIDs = selectedItemIDs
    guard !itemIDs.isEmpty else { return }

    do {
      _ = try database.write { db in
        try GroceryRepository.moveItems(itemIDs, toListID: destinationListID, in: db, now: now)
      }
      pantryAddBackItemIDsByListID = pantryAddBackItemIDsByListID.mapValues { $0.subtracting(itemIDs) }
      doneSelectingButtonTapped()
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}
