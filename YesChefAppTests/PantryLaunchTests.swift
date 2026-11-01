import Dependencies
import SQLiteData
import Testing
import YesChefCore
@testable import YesChef

@Suite
struct PantryLaunchTests {
  @Test
  func liveContextStartsWithAnEmptyPantry() throws {
    try withDependencies {
      $0.context = .live
      // Use a fresh, unsynchronized database while retaining live dependency context.
      try $0.bootstrapDatabase(path: nil, syncMode: .disabled)
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let pantryCount = try database.read { db in
        try PantryItem.fetchCount(db)
      }
      #expect(pantryCount == 0)
    }
  }
}
