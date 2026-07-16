import CoreGraphics
import Testing
@testable import YesChef

@Suite
struct MenuWideColumnLayoutTests {
  @Test
  func detentsDivideTheWidthRemainingAfterTheBodyFloor() {
    let layout = MenuWideColumnLayout(width: 1_000, isPlaybookVisible: true)
    let comfortable = layout.playbookWidth(for: .comfortable)
    let wide = layout.playbookWidth(for: .wide)

    #expect(comfortable * CGFloat(RecipePlaybookColumnDetent.allCases.count) == wide)
    #expect(layout.bodyWidth(playbookWidth: wide) == layout.bodyMinimumWidth)
  }

  @Test
  func hiddenPlaybookLeavesTheWholeWidthToTheBody() {
    let width: CGFloat = 1_000
    let layout = MenuWideColumnLayout(width: width, isPlaybookVisible: false)

    #expect(layout.playbookWidth(for: .comfortable) == 0)
    #expect(layout.bodyWidth(playbookWidth: 0) == width)
  }
}
