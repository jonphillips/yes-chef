import SwiftUI
import YesChefCore

struct GrocerySelectItemsMenuButton: View {
  let model: GroceryLibraryModel

  var body: some View {
    Button {
      model.selectItemsButtonTapped()
    } label: {
      Label("Select Items", systemImage: "checkmark.square")
    }
  }
}

struct GrocerySelectionToolbar: View {
  let model: GroceryLibraryModel
  let selectedListID: CoreGroceryList.ID

  var body: some View {
    Menu {
      ForEach(model.listRows.filter { $0.id != selectedListID }) { row in
        Button(row.list.title) {
          model.moveSelectedItemsButtonTapped(toListID: row.id)
        }
      }
    } label: {
      Label("Move to", systemImage: "arrowshape.turn.up.right")
    }
    .disabled(model.selectedItemIDs.isEmpty || model.listRows.count <= 1)

    Button(model.areAllItemsSelected ? "Deselect All" : "Select All") {
      model.selectAllButtonTapped()
    }
    .disabled(model.allVisibleItemIDs.isEmpty)

    Button("Done") { model.doneSelectingButtonTapped() }
  }
}
