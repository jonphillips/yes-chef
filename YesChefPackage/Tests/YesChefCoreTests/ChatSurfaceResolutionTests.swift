import CustomDump
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Test
  func chatSurfaceResolutionsStateEveryHostContract() {
    let resolutions: [ChatSurfaceResolution] = [
      .init(sections: .switchable, presentation: .modalSheet),
      .init(sections: .switchable, presentation: .embeddedHeader),
      .init(sections: .none, presentation: .embeddedHeader),
      .init(sections: .none, presentation: .column(detent: .calendar)),
      .init(sections: .none, presentation: .column(detent: .workbenchDetail)),
      .init(sections: .none, presentation: .column(detent: .workbenchCompare)),
      .init(sections: .none, presentation: .modalSheet),
      .init(sections: .none, presentation: .modalSheet),
      .init(sections: .none, presentation: .modalSheet),
      .init(sections: .none, presentation: .modalSheet),
    ]

    expectNoDifference(
      resolutions.map(\.dismissal),
      [.panelOwned, .panelOwned, .panelOwned, .hostOwned, .hostOwned, .hostOwned, .panelOwned, .panelOwned, .panelOwned, .panelOwned]
    )
    expectNoDifference(
      resolutions.map(\.sections),
      [.switchable, .switchable, .none, .none, .none, .none, .none, .none, .none, .none]
    )
    expectNoDifference(
      resolutions.map(\.presentation),
      [
        .modalSheet,
        .embeddedHeader,
        .embeddedHeader,
        .column(detent: .calendar),
        .column(detent: .workbenchDetail),
        .column(detent: .workbenchCompare),
        .modalSheet,
        .modalSheet,
        .modalSheet,
        .modalSheet,
      ]
    )

    let detentIdentities = resolutions.compactMap { resolution -> ChatSurfaceResolution.DetentIdentity? in
      guard case let .column(detent) = resolution.presentation else { return nil }
      return detent
    }
    expectNoDifference(detentIdentities, [.calendar, .workbenchDetail, .workbenchCompare])
  }
}
