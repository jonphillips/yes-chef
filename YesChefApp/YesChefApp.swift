import SwiftUI
import YesChefCore

@main
struct YesChefApp: App {
  init() {
    let legacyPantryText = UserDefaults.standard.string(forKey: GroceryPantryStorage.storageKey)
    let legacyPantryItems = legacyPantryText.map(GroceryPantryStorage.items(from:))
    prepareDependencies {
      try! $0.bootstrapDatabase()
      try! $0.seedPantryItemsIfNeeded(titles: legacyPantryItems)
      try! $0.seedSampleDataIfNeeded()
    }
  }

  var body: some Scene {
    WindowGroup {
      AppContainer()
    }
  }
}
