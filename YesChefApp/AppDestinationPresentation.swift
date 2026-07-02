import SwiftUI

private struct MealCalendarItemEditorDestinationModifier: ViewModifier {
  let mealCalendarModel: MealCalendarModel
  var isPresentationEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var mealCalendarModel = mealCalendarModel

    content
      .sheet(
        item: presentationBinding($mealCalendarModel.destination.itemEditor),
        id: \.self
      ) { context in
        NavigationStack {
          MealPlanItemEditorView(model: mealCalendarModel, context: context)
        }
      }
      .alert(
        "Added to Meal Calendar",
        item: presentationBinding($mealCalendarModel.destination.addRecipeConfirmation)
      ) { _ in
        Button("OK") {}
      } message: { confirmation in
        Text(confirmation.message)
      }
  }

  private func presentationBinding<Value>(_ binding: Binding<Value?>) -> Binding<Value?> {
    Binding {
      isPresentationEnabled ? binding.wrappedValue : nil
    } set: { newValue in
      binding.wrappedValue = newValue
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
      .sheet(isPresented: presentationBinding($groceryModel.destination.addList)) {
        NavigationStack {
          GroceryListEditorView(model: groceryModel)
        }
      }
      .sheet(item: presentationBinding($groceryModel.destination.editList), id: \.self) { listID in
        NavigationStack {
          GroceryListEditorView(model: groceryModel, listID: listID)
        }
      }
      .sheet(isPresented: presentationBinding($groceryModel.destination.addCustomItem)) {
        NavigationStack {
          GroceryItemEditorView(model: groceryModel)
        }
      }
      .sheet(isPresented: presentationBinding($groceryModel.destination.addPantryItem)) {
        NavigationStack {
          PantryItemEditorView(model: groceryModel)
        }
      }
      .sheet(item: presentationBinding($groceryModel.destination.editPantryItem), id: \.self) { itemID in
        NavigationStack {
          PantryItemEditorView(model: groceryModel, itemID: itemID)
        }
      }
      .sheet(item: presentationBinding($groceryModel.destination.selectIngredients), id: \.self) { context in
        NavigationStack {
          GroceryIngredientSelectionView(
            model: groceryModel,
            context: context,
            choices: groceryModel.ingredientChoices(
              for: context,
              mealRows: mealCalendarModel.itemRows
            ),
            mealRows: mealCalendarModel.itemRows,
            pantryStaples: groceryModel.pantryStapleNames
          )
        }
      }
      .alert(
        "Added to Grocery List",
        item: presentationBinding($groceryModel.destination.addConfirmation)
      ) { _ in
        Button("OK") {}
      } message: { confirmation in
        Text(confirmation.message)
      }
      .confirmationDialog(
        "Clear Purchased?",
        item: presentationBinding($groceryModel.destination.clearPurchased),
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
        item: presentationBinding($groceryModel.destination.clearAll),
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
        item: presentationBinding($groceryModel.destination.deleteList),
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

  private func presentationBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
    Binding {
      isPresentationEnabled && binding.wrappedValue
    } set: { newValue in
      binding.wrappedValue = newValue
    }
  }

  private func presentationBinding<Value>(_ binding: Binding<Value?>) -> Binding<Value?> {
    Binding {
      isPresentationEnabled ? binding.wrappedValue : nil
    } set: { newValue in
      binding.wrappedValue = newValue
    }
  }
}

private struct RecipeDetailDestinationsModifier: ViewModifier {
  let recipeModel: RecipeLibraryModel
  var isPresentationEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var recipeModel = recipeModel

    content
      .sheet(item: presentationBinding($recipeModel.destination.editRecipe), id: \.self) { recipeID in
        NavigationStack {
          RecipeEditorView(recipeID: recipeID)
        }
      }
      .sheet(item: presentationBinding($recipeModel.destination.cookingMode), id: \.self) { recipeID in
        NavigationStack {
          CookingModeView(model: CookingModeModel(recipeID: recipeID))
        }
      }
      .sheet(item: presentationBinding($recipeModel.destination.originalSnapshot), id: \.self) { recipeID in
        NavigationStack {
          OriginalSnapshotView(recipe: recipeModel.recipeRows.first { $0.recipe.id == recipeID }?.recipe)
        }
      }
      .confirmationDialog(
        "Delete Recipe?",
        item: presentationBinding($recipeModel.destination.deleteRecipe),
        titleVisibility: .visible
      ) { recipeID in
        Button("Delete Recipe", role: .destructive) {
          recipeModel.confirmDeleteRecipeButtonTapped(recipeID: recipeID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { recipeID in
        Text("Delete \(recipeModel.title(for: recipeID)) from your recipe library?")
      }
  }

  private func presentationBinding<Value>(_ binding: Binding<Value?>) -> Binding<Value?> {
    Binding {
      isPresentationEnabled ? binding.wrappedValue : nil
    } set: { newValue in
      binding.wrappedValue = newValue
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
