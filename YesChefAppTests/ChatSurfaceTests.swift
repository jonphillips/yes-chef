import CustomDump
import Testing
@testable import YesChef

@Suite
struct ChatSurfaceTests {
  @Test
  func factoriesResolveEveryHostContract() {
    let content = ChatSurface.Content(applyActions: [])
    let selectSection: (PlaybookSectionKind) -> Void = { _ in }
    let dismiss = {}

    let surfaces = [
      ChatSurface.recipeAskSheet(
        content: content,
        selectSection: selectSection,
        activeSection: nil,
        onDismiss: dismiss
      ),
      ChatSurface.recipeAskInspector(
        content: content,
        selectSection: selectSection,
        activeSection: nil,
        onDismiss: dismiss
      ),
      ChatSurface.menuTool(content: content, onDismiss: dismiss),
      ChatSurface.calendarWorkspaceColumn(content: content),
      ChatSurface.workbenchDetailColumn(content: content),
      ChatSurface.workbenchCompareColumn(content: content),
      ChatSurface.calendarCompactSheet(content: content, onDismiss: dismiss),
      ChatSurface.calendarDayCompactSheet(content: content, onDismiss: dismiss),
      ChatSurface.workbenchCompactSheet(content: content, onDismiss: dismiss),
      ChatSurface.workbenchCompareCompactSheet(content: content, onDismiss: dismiss),
    ]

    expectNoDifference(
      surfaces.map(\.resolvedContract),
      [
        .init(sections: .switchable, dismissal: .panelOwned, presentation: .modalSheet),
        .init(sections: .switchable, dismissal: .panelOwned, presentation: .embeddedHeader),
        .init(sections: .none, dismissal: .panelOwned, presentation: .embeddedHeader),
        .init(sections: .none, dismissal: .hostOwned, presentation: .column(detent: .calendar)),
        .init(sections: .none, dismissal: .hostOwned, presentation: .column(detent: .workbenchDetail)),
        .init(sections: .none, dismissal: .hostOwned, presentation: .column(detent: .workbenchCompare)),
        .init(sections: .none, dismissal: .panelOwned, presentation: .modalSheet),
        .init(sections: .none, dismissal: .panelOwned, presentation: .modalSheet),
        .init(sections: .none, dismissal: .panelOwned, presentation: .modalSheet),
        .init(sections: .none, dismissal: .panelOwned, presentation: .modalSheet),
      ]
    )
    expectNoDifference(
      surfaces.map { $0.presentation.drawsEmbeddedHeader },
      [false, true, true, true, true, true, false, false, false, false]
    )
    expectNoDifference(
      surfaces.map { $0.presentation.panelOwnsActiveTierPropagation },
      [true, true, true, false, false, false, true, true, true, true]
    )
  }
}
