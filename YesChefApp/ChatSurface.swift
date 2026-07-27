import LLMClientKit
import YesChefCore

/// A host's complete contract with the shared chat panel.
///
/// The three structural choices have no defaults. In particular, panel-owned presentations cannot
/// omit their dismissal choice, while a column is explicitly embedded and host-owned.
struct ChatSurface {
  typealias DetentIdentity = ChatSurfaceResolution.DetentIdentity

  struct Content {
    let applyActions: [AnyChatApplyAction]
    var finalization: ChatFinalizeConfiguration? = nil
    var focusesInputOnAppear = false
    var activeTierChanged: (ModelTier) -> Void = { _ in }
  }

  enum Sections {
    case none
    case switchable(select: (PlaybookSectionKind) -> Void, active: PlaybookSectionKind?)
  }

  enum Presentation {
    case modalSheet(onDismiss: () -> Void)
    case embeddedHeader(onDismiss: () -> Void)
    case column(detent: DetentIdentity)

    var drawsEmbeddedHeader: Bool {
      resolvedPresentation.drawsEmbeddedHeader
    }

    var onDismiss: (() -> Void)? {
      switch self {
      case let .modalSheet(onDismiss), let .embeddedHeader(onDismiss): onDismiss
      case .column: nil
      }
    }

    var panelOwnsActiveTierPropagation: Bool {
      resolvedPresentation.panelOwnsActiveTierPropagation
    }

    var resolvedPresentation: ChatSurfaceResolution.Presentation {
      switch self {
      case .modalSheet: .modalSheet
      case .embeddedHeader: .embeddedHeader
      case let .column(detent): .column(detent: detent)
      }
    }
  }

  let content: Content
  let sections: Sections
  let presentation: Presentation

  init(content: Content, sections: Sections, presentation: Presentation) {
    self.content = content
    self.sections = sections
    self.presentation = presentation
  }

  static func recipeAskSheet(
    content: Content,
    selectSection: @escaping (PlaybookSectionKind) -> Void,
    activeSection: PlaybookSectionKind?,
    onDismiss: @escaping () -> Void
  ) -> Self {
    Self(
      content: content,
      sections: .switchable(select: selectSection, active: activeSection),
      presentation: .modalSheet(onDismiss: onDismiss)
    )
  }

  static func recipeAskInspector(
    content: Content,
    selectSection: @escaping (PlaybookSectionKind) -> Void,
    activeSection: PlaybookSectionKind?,
    onDismiss: @escaping () -> Void
  ) -> Self {
    Self(
      content: content,
      sections: .switchable(select: selectSection, active: activeSection),
      presentation: .embeddedHeader(onDismiss: onDismiss)
    )
  }

  static func menuTool(content: Content, onDismiss: @escaping () -> Void) -> Self {
    Self(content: content, sections: .none, presentation: .embeddedHeader(onDismiss: onDismiss))
  }

  static func calendarWorkspaceColumn(content: Content) -> Self {
    column(content: content, detent: .calendar)
  }

  static func workbenchDetailColumn(content: Content) -> Self {
    column(content: content, detent: .workbenchDetail)
  }

  static func workbenchCompareColumn(content: Content) -> Self {
    column(content: content, detent: .workbenchCompare)
  }

  static func calendarCompactSheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    sheet(content: content, onDismiss: onDismiss)
  }

  static func calendarDayCompactSheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    sheet(content: content, onDismiss: onDismiss)
  }

  static func workbenchCompactSheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    sheet(content: content, onDismiss: onDismiss)
  }

  static func workbenchCompareCompactSheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    sheet(content: content, onDismiss: onDismiss)
  }

  var resolvedContract: ChatSurfaceResolution {
    let resolvedSections: ChatSurfaceResolution.Sections
    switch sections {
    case .none: resolvedSections = .none
    case .switchable: resolvedSections = .switchable
    }

    return ChatSurfaceResolution(
      sections: resolvedSections,
      presentation: presentation.resolvedPresentation
    )
  }

  private static func column(content: Content, detent: DetentIdentity) -> Self {
    Self(content: content, sections: .none, presentation: .column(detent: detent))
  }

  private static func sheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    Self(content: content, sections: .none, presentation: .modalSheet(onDismiss: onDismiss))
  }
}
