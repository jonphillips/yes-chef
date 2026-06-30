import SwiftUI
import YesChefCore

struct ExternalDatabaseChangeReloadModifier: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase

  let recipeModel: RecipeLibraryModel
  let browserModel: BrowserModel
  let mealCalendarModel: MealCalendarModel
  let menuModel: MenuLibraryModel
  let groceryModel: GroceryLibraryModel

  func body(content: Content) -> some View {
    content
      .task {
        for await _ in NotificationCenter.default.notifications(named: DatabaseChangeBeacon.didChange) {
          await reloadObservingModels()
        }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task {
          await reloadObservingModels()
        }
      }
  }

  @MainActor private func reloadObservingModels() async {
    await recipeModel.reloadAfterExternalChange()
    await browserModel.reloadAfterExternalChange()
    await mealCalendarModel.reloadAfterExternalChange()
    await menuModel.reloadAfterExternalChange()
    await groceryModel.reloadAfterExternalChange()
  }
}

extension View {
  func externalDatabaseChangeReload(
    recipeModel: RecipeLibraryModel,
    browserModel: BrowserModel,
    mealCalendarModel: MealCalendarModel,
    menuModel: MenuLibraryModel,
    groceryModel: GroceryLibraryModel
  ) -> some View {
    modifier(
      ExternalDatabaseChangeReloadModifier(
        recipeModel: recipeModel,
        browserModel: browserModel,
        mealCalendarModel: mealCalendarModel,
        menuModel: menuModel,
        groceryModel: groceryModel
      )
    )
  }
}
