import CustomDump
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct MenuLibraryDogfoodTests {
  @Test
  func newMenuSwitchesToUndatedAndStaysSelected() throws {
    let now = Date(timeIntervalSinceReferenceDate: 900_070_000)
    try withDependencies {
      try $0.bootstrapDatabase()
      $0.uuid = .incrementing
      $0.date.now = now
    } operation: {
      let model = MenuLibraryModel()
      expectNoDifference(model.menuListSegment, .dated)

      #expect(model.saveMenuButtonTapped(title: "Thanksgiving", notes: "", dayCount: 1))

      expectNoDifference(model.menuListSegment, .undated)
      #expect(model.selectedMenuID != nil)
    }
  }

  @Test
  func symbolRenderingCanBeOverriddenWithoutChangingTheStaticValue() {
    let baseSymbol = AppSymbol("cart", rendering: .hierarchical)
    let override = baseSymbol.rendering(.multicolor)

    #expect(baseSymbol.imageRenderingMode == .hierarchical)
    #expect(override.imageRenderingMode == .multicolor)
    #expect(AppSymbol("cart").imageRenderingMode == nil)
    let _ = baseSymbol.image
    let _ = override.image
  }
}
