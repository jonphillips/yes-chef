import SwiftUI
import YesChefCore

struct ExternalDatabaseChangeReloadModifier: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase

  let recipeModel: RecipeLibraryModel
  let workbenchModel: WorkbenchLibraryModel
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
          await sceneBecameActive()
        }
      }
  }

  private func sceneBecameActive() async {
    async let pendingSyncRedrain = YesChefCloudSync
      .redrainPendingRecordZoneChangesIfManuallyEnabled()
    await reloadObservingModels()
    _ = await pendingSyncRedrain
  }

  @MainActor private func reloadObservingModels() async {
    await recipeModel.reloadAfterExternalChange()
    await workbenchModel.reloadAfterExternalChange()
    await browserModel.reloadAfterExternalChange()
    await mealCalendarModel.reloadAfterExternalChange()
    await menuModel.reloadAfterExternalChange()
    await groceryModel.reloadAfterExternalChange()
  }
}

extension View {
  func externalDatabaseChangeReload(
    recipeModel: RecipeLibraryModel,
    workbenchModel: WorkbenchLibraryModel,
    browserModel: BrowserModel,
    mealCalendarModel: MealCalendarModel,
    menuModel: MenuLibraryModel,
    groceryModel: GroceryLibraryModel
  ) -> some View {
    modifier(
      ExternalDatabaseChangeReloadModifier(
        recipeModel: recipeModel,
        workbenchModel: workbenchModel,
        browserModel: browserModel,
        mealCalendarModel: mealCalendarModel,
        menuModel: menuModel,
        groceryModel: groceryModel
      )
    )
  }
}
