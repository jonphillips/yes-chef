import Foundation

/// The structural contract shared by every host of the recipe chat surface.
public struct ChatSurfaceResolution: Equatable, Sendable {
  public enum DetentIdentity: String, CaseIterable, Equatable, Sendable {
    /// This existing key deliberately remains Calendar's identity, preserving a cook's current detent.
    case calendar = "recipeChatWorkspaceDetent"
    case workbenchDetail = "workbenchDetailChatWorkspaceDetent"
    case workbenchCompare = "workbenchCompareChatWorkspaceDetent"
  }

  public enum Sections: Equatable, Sendable {
    case none
    case switchable
  }

  public enum Dismissal: Equatable, Sendable {
    case hostOwned
    case panelOwned
  }

  public enum Presentation: Equatable, Sendable {
    case modalSheet
    case embeddedHeader
    case column(detent: DetentIdentity)

    public var drawsEmbeddedHeader: Bool {
      switch self {
      case .modalSheet: false
      case .embeddedHeader, .column: true
      }
    }

    public var panelOwnsActiveTierPropagation: Bool {
      switch self {
      case .column: false
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

    switch presentation {
    case .column:
      dismissal = .hostOwned
    case .modalSheet, .embeddedHeader:
      dismissal = .panelOwned
    }
  }
}
