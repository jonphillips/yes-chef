import Foundation

/// The UI-independent answer each chat host gives to the shared panel's three structural questions.
///
/// SwiftUI closures stay in the app target, while this resolved shape lives in Core so every host's
/// contract can be asserted by the package test suite.
public struct ChatSurfaceResolution: Equatable, Sendable {
  public enum Sections: Equatable, Sendable {
    case none
    case switchable
  }

  public enum Dismissal: Equatable, Sendable {
    case hostOwned
    case panelOwned
  }

  public enum DetentIdentity: String, Equatable, Sendable {
    /// The existing key deliberately remains Calendar's identity, preserving a cook's current detent.
    case calendar = "recipeChatWorkspaceDetent"
    case workbenchDetail = "workbenchDetailChatWorkspaceDetent"
    case workbenchCompare = "workbenchCompareChatWorkspaceDetent"
  }

  public enum Presentation: Equatable, Sendable {
    case modalSheet
    case embeddedHeader
    case column(detent: DetentIdentity)
  }

  public let sections: Sections
  public let dismissal: Dismissal
  public let presentation: Presentation

  public init(sections: Sections, presentation: Presentation) {
    self.sections = sections
    self.presentation = presentation
    switch presentation {
    case .modalSheet, .embeddedHeader:
      dismissal = .panelOwned
    case .column:
      dismissal = .hostOwned
    }
  }
}
