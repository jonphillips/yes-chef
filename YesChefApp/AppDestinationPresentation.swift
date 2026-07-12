import SwiftUI

private struct MealCalendarItemEditorDestinationModifier: ViewModifier {
  let mealCalendarModel: MealCalendarModel
  var isPresentationEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var mealCalendarModel = mealCalendarModel

    content
      .sheet(
        item: gatedBinding($mealCalendarModel.destination.itemEditor, enabled: isPresentationEnabled),
        id: \.self
      ) { context in
        NavigationStack {
          MealPlanItemEditorView(model: mealCalendarModel, context: context)
        }
      }
  }
}

private struct GroceryDestinationsModifier: ViewModifier {
  let groceryModel: GroceryLibraryModel
  let mealCalendarModel: MealCalendarModel
  var isPresentationEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var groceryModel = groceryModel

    content
      .sheet(isPresented: gatedBinding($groceryModel.destination.addList, enabled: isPresentationEnabled)) {
        NavigationStack {
          GroceryListEditorView(model: groceryModel)
        }
      }
      .sheet(item: gatedBinding($groceryModel.destination.editList, enabled: isPresentationEnabled), id: \.self) { listID in
        NavigationStack {
          GroceryListEditorView(model: groceryModel, listID: listID)
        }
      }
      .sheet(isPresented: gatedBinding($groceryModel.destination.addCustomItem, enabled: isPresentationEnabled)) {
        NavigationStack {
          GroceryItemEditorView(model: groceryModel)
        }
      }
      .sheet(item: gatedBinding($groceryModel.destination.editItem, enabled: isPresentationEnabled), id: \.self) { itemID in
        NavigationStack {
          GroceryItemEditorView(model: groceryModel, itemID: itemID)
        }
      }
      .sheet(isPresented: gatedBinding($groceryModel.destination.addPantryItem, enabled: isPresentationEnabled)) {
        NavigationStack {
          PantryItemEditorView(model: groceryModel)
        }
      }
      .sheet(item: gatedBinding($groceryModel.destination.editPantryItem, enabled: isPresentationEnabled), id: \.self) { itemID in
        NavigationStack {
          PantryItemEditorView(model: groceryModel, itemID: itemID)
        }
      }
      .sheet(item: gatedBinding($groceryModel.destination.selectIngredients, enabled: isPresentationEnabled), id: \.id) { presentation in
        NavigationStack {
          GroceryIngredientSelectionView(
            model: groceryModel,
            context: presentation.context,
            choices: presentation.choices,
            mealRows: mealCalendarModel.itemRows,
            pantryStaples: groceryModel.pantryStapleNames
          )
        }
      }
      .confirmationDialog(
        "Clear Purchased?",
        item: gatedBinding($groceryModel.destination.clearPurchased, enabled: isPresentationEnabled),
        titleVisibility: .visible
      ) { listID in
        Button("Clear Purchased", role: .destructive) {
          groceryModel.confirmClearPurchasedButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Remove purchased items from \(groceryModel.title(forList: listID))?")
      }
      .confirmationDialog(
        "Clear Grocery List?",
        item: gatedBinding($groceryModel.destination.clearAll, enabled: isPresentationEnabled),
        titleVisibility: .visible
      ) { listID in
        Button("Clear All", role: .destructive) {
          groceryModel.confirmClearAllButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Remove every item from \(groceryModel.title(forList: listID))?")
      }
      .confirmationDialog(
        "Delete Grocery List?",
        item: gatedBinding($groceryModel.destination.deleteList, enabled: isPresentationEnabled),
        titleVisibility: .visible
      ) { listID in
        Button("Delete List", role: .destructive) {
          groceryModel.confirmDeleteListButtonTapped(listID: listID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { listID in
        Text("Delete \(groceryModel.title(forList: listID)) and its grocery items?")
      }
  }

}

private struct RecipeDetailDestinationsModifier: ViewModifier {
  let recipeModel: RecipeLibraryModel
  var isPresentationEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var recipeModel = recipeModel

    content
      .sheet(item: gatedBinding($recipeModel.destination.editRecipe, enabled: isPresentationEnabled), id: \.self) { recipeID in
        NavigationStack {
          RecipeEditorView(recipeID: recipeID)
        }
      }
      .sheet(item: gatedBinding($recipeModel.destination.cookingMode, enabled: isPresentationEnabled), id: \.self) { recipeID in
        NavigationStack {
          CookingModeView(model: CookingModeModel(recipeID: recipeID))
        }
      }
      .sheet(item: gatedBinding($recipeModel.destination.originalSnapshot, enabled: isPresentationEnabled), id: \.self) { recipeID in
        NavigationStack {
          OriginalSnapshotView(recipe: recipeModel.recipeRows.first { $0.recipe.id == recipeID }?.recipe)
        }
      }
      .confirmationDialog(
        "Archive Recipe?",
        item: gatedBinding($recipeModel.destination.deleteRecipe, enabled: isPresentationEnabled),
        titleVisibility: .visible
      ) { recipeID in
        Button("Archive", role: .destructive) {
          recipeModel.confirmDeleteRecipeButtonTapped(recipeID: recipeID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { recipeID in
        Text("Archive \(recipeModel.title(for: recipeID))? It will be removed from meal plans and menus.")
      }
      .confirmationDialog(
        "Delete Permanently?",
        item: gatedBinding($recipeModel.destination.deleteArchivedRecipe, enabled: isPresentationEnabled),
        titleVisibility: .visible
      ) { recipeID in
        Button("Delete Permanently", role: .destructive) {
          recipeModel.confirmDeleteArchivedRecipeButtonTapped(recipeID: recipeID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { recipeID in
        Text("Permanently delete \(recipeModel.title(for: recipeID))? This cannot be undone.")
      }
  }
}

extension View {
  func mealCalendarItemEditorDestination(
    mealCalendarModel: MealCalendarModel,
    isPresentationEnabled: Bool = true
  ) -> some View {
    modifier(
      MealCalendarItemEditorDestinationModifier(
        mealCalendarModel: mealCalendarModel,
        isPresentationEnabled: isPresentationEnabled
      )
    )
  }

  func groceryDestinations(
    groceryModel: GroceryLibraryModel,
    mealCalendarModel: MealCalendarModel,
    isPresentationEnabled: Bool = true
  ) -> some View {
    modifier(
      GroceryDestinationsModifier(
        groceryModel: groceryModel,
        mealCalendarModel: mealCalendarModel,
        isPresentationEnabled: isPresentationEnabled
      )
    )
  }

  func recipeDetailDestinations(
    recipeModel: RecipeLibraryModel,
    isPresentationEnabled: Bool = true
  ) -> some View {
    modifier(
      RecipeDetailDestinationsModifier(
        recipeModel: recipeModel,
        isPresentationEnabled: isPresentationEnabled
      )
    )
  }
}
