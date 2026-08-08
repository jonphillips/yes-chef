import LLMClientKit
import YesChefCore

/// A host's complete contract with the shared chat panel.
///
/// The three structural choices have no defaults. In particular, panel-owned presentations cannot
/// omit their dismissal choice, while a column is explicitly embedded and host-owned.
struct ChatSurface {
  typealias DetentIdentity = ChatSurfaceResolution.DetentIdentity

  struct ChatStarter: Identifiable, Equatable {
    let id: String
    let title: String
  }

  struct Content {
    let applyActions: [AnyChatApplyAction]
    var finalization: ChatFinalizeConfiguration? = nil
    var focusesInputOnAppear = false
    var activeTierChanged: (ModelTier) -> Void = { _ in }
  }

  enum Sections {
    case none
    case starters(
      [ChatStarter],
      active: ChatStarter.ID?,
      select: (ChatStarter.ID) -> Void
    )
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

  /// Private so the static factories below are the *only* construction path — the same rule
  /// `scripts/check-drift.sh` guards textually, enforced here by the compiler. A host that needs a
  /// new shape adds a named factory, which is what makes every surface's contract greppable.
  private init(content: Content, sections: Sections, presentation: Presentation) {
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
      sections: recipeStarters(selectSection: selectSection, activeSection: activeSection),
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
      sections: recipeStarters(selectSection: selectSection, activeSection: activeSection),
      presentation: .embeddedHeader(onDismiss: onDismiss)
    )
  }

  static func menuTool(
    content: Content,
    starters: [ChatStarter],
    activeStarterID: ChatStarter.ID?,
    selectStarter: @escaping (ChatStarter.ID) -> Void,
    onDismiss: @escaping () -> Void
  ) -> Self {
    Self(
      content: content,
      sections: .starters(starters, active: activeStarterID, select: selectStarter),
      presentation: .embeddedHeader(onDismiss: onDismiss)
    )
  }

  static func calendarWorkspaceInspector(content: Content, onDismiss: @escaping () -> Void) -> Self {
    inspector(content: content, onDismiss: onDismiss)
  }

  static func workbenchDetailInspector(content: Content, onDismiss: @escaping () -> Void) -> Self {
    inspector(content: content, onDismiss: onDismiss)
  }

  static func workbenchCompareInspector(content: Content, onDismiss: @escaping () -> Void) -> Self {
    inspector(content: content, onDismiss: onDismiss)
  }

  static func calendarCompactSheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
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
    case .starters: resolvedSections = .starters
    }

    return ChatSurfaceResolution(
      sections: resolvedSections,
      presentation: presentation.resolvedPresentation
    )
  }

  private static func inspector(content: Content, onDismiss: @escaping () -> Void) -> Self {
    Self(content: content, sections: .none, presentation: .embeddedHeader(onDismiss: onDismiss))
  }

  private static func sheet(content: Content, onDismiss: @escaping () -> Void) -> Self {
    Self(content: content, sections: .none, presentation: .modalSheet(onDismiss: onDismiss))
  }

  private static func recipeStarters(
    selectSection: @escaping (PlaybookSectionKind) -> Void,
    activeSection: PlaybookSectionKind?
  ) -> Sections {
    .starters(
      PlaybookSectionKind.allCases.map { ChatStarter(id: $0.rawValue, title: $0.chatMenuTitle) },
      active: activeSection?.rawValue
    ) { starterID in
      guard let section = PlaybookSectionKind(rawValue: starterID) else { return }
      selectSection(section)
    }
  }
}
