import LLMClientKit
import YesChefCore

/// A host's complete contract with the shared chat panel.
///
/// The three structural choices have no defaults. In particular, presentation owns dismissal, so
/// a host cannot accidentally combine an embedded header with an absent close affordance.
struct ChatSurface {
  struct Content {
    let applyActions: [AnyChatApplyAction]
    var finalization: ChatFinalizeConfiguration? = nil
    var focusesInputOnAppear = false
    var activeTierChanged: (ModelTier) -> Void = { _ in }
  }

  enum Sections {
    case none
    case switchable(select: (PlaybookSectionKind) -> Void, active: PlaybookSectionKind?)

    var resolution: ChatSurfaceResolution.Sections {
      switch self {
      case .none: .none
      case .switchable: .switchable
      }
    }
  }

  enum Presentation {
    case modalSheet(onDismiss: () -> Void)
    case embeddedHeader(onDismiss: () -> Void)
    case column(detent: ChatSurfaceResolution.DetentIdentity)

    var resolution: ChatSurfaceResolution.Presentation {
      switch self {
      case .modalSheet: .modalSheet
      case .embeddedHeader: .embeddedHeader
      case let .column(detent): .column(detent: detent)
      }
    }

    var onDismiss: (() -> Void)? {
      switch self {
      case let .modalSheet(onDismiss), let .embeddedHeader(onDismiss): onDismiss
      case .column: nil
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

  var resolution: ChatSurfaceResolution {
    ChatSurfaceResolution(sections: sections.resolution, presentation: presentation.resolution)
  }
}
