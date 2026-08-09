import CustomDump
import Testing
import YesChefCore

@Suite
struct ChatSurfaceResolutionTests {
  @Test
  func preservesThePresentationContract() {
    assertPresentation(
      .modalSheet,
      dismissal: .panelOwned,
      drawsEmbeddedHeader: false,
      panelOwnsActiveTierPropagation: true
    )
    assertPresentation(
      .embeddedHeader,
      dismissal: .panelOwned,
      drawsEmbeddedHeader: true,
      panelOwnsActiveTierPropagation: true
    )
  }

  @Test
  func namesStarterContractsForEveryHost() {
    let resolution = ChatSurfaceResolution(sections: .starters, presentation: .modalSheet)

    expectNoDifference(resolution.sections, .starters)
  }

  private func assertPresentation(
    _ presentation: ChatSurfaceResolution.Presentation,
    dismissal: ChatSurfaceResolution.Dismissal,
    drawsEmbeddedHeader: Bool,
    panelOwnsActiveTierPropagation: Bool
  ) {
    let resolution = ChatSurfaceResolution(sections: .none, presentation: presentation)

    expectNoDifference(resolution.dismissal, dismissal)
    expectNoDifference(resolution.presentation.drawsEmbeddedHeader, drawsEmbeddedHeader)
    expectNoDifference(
      resolution.presentation.panelOwnsActiveTierPropagation,
      panelOwnsActiveTierPropagation
    )
  }
}
