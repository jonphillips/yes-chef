import SwiftUI
import YesChefCore

@main
struct YesChefApp: App {
  init() {
    prepareDependencies {
      try! $0.bootstrapDatabase()
      try! $0.seedSampleDataIfNeeded()
    }
  }

  var body: some Scene {
    WindowGroup {
      AppContainer()
    }
  }
}
