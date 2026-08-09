import Foundation

/// The structural contract shared by every host of the recipe chat surface.
public struct ChatSurfaceResolution: Equatable, Sendable {
  public enum Sections: Equatable, Sendable {
    case none
    case starters
  }

  public enum Dismissal: Equatable, Sendable {
    case panelOwned
  }

  public enum Presentation: Equatable, Sendable {
    case modalSheet
    case embeddedHeader

    public var drawsEmbeddedHeader: Bool {
      switch self {
      case .modalSheet: false
      case .embeddedHeader: true
      }
    }

    public var panelOwnsActiveTierPropagation: Bool {
      switch self {
      case .modalSheet, .embeddedHeader: true
      }
    }
  }

  public let sections: Sections
  public let dismissal: Dismissal
  public let presentation: Presentation

  public init(sections: Sections, presentation: Presentation) {
    self.sections = sections
    self.presentation = presentation
    dismissal = .panelOwned
  }
}
