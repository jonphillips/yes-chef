import Foundation

public struct ChatApplyReviewItem: Identifiable {
  public let id: UUID
  public var title: String
  public var summary: String
  public var presentation: ChatApplyReviewPresentation
  public var editableTitle: String
  public var editableText: String?
  public var supportingEvidenceTitle: String?
  public var supportingEvidenceRows: [String]
  public var commitTitle: String
  public var committingTitle: String
  public var committedTitle: String
  public var commit: @MainActor (_ approvedText: String) async throws -> Void
  public var secondaryCommit: ChatApplyReviewSecondaryCommit?

  public init(
    id: UUID = UUID(),
    title: String,
    summary: String,
    presentation: ChatApplyReviewPresentation = .sheet,
    editableTitle: String = "Proposal",
    editableText: String? = nil,
    supportingEvidenceTitle: String? = nil,
    supportingEvidenceRows: [String] = [],
    commitTitle: String,
    committingTitle: String,
    committedTitle: String,
    secondaryCommit: ChatApplyReviewSecondaryCommit? = nil,
    commit: @escaping @MainActor () async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.presentation = presentation
    self.editableTitle = editableTitle
    self.editableText = editableText
    self.supportingEvidenceTitle = supportingEvidenceTitle
    self.supportingEvidenceRows = supportingEvidenceRows
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.secondaryCommit = secondaryCommit
    self.commit = { _ in try await commit() }
  }

  public init(
    id: UUID = UUID(),
    title: String,
    summary: String,
    presentation: ChatApplyReviewPresentation = .sheet,
    editableTitle: String = "Proposal",
    editableText: String? = nil,
    supportingEvidenceTitle: String? = nil,
    supportingEvidenceRows: [String] = [],
    commitTitle: String,
    committingTitle: String,
    committedTitle: String,
    secondaryCommit: ChatApplyReviewSecondaryCommit? = nil,
    commit: @escaping @MainActor (_ approvedText: String) async throws -> Void
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.presentation = presentation
    self.editableTitle = editableTitle
    self.editableText = editableText
    self.supportingEvidenceTitle = supportingEvidenceTitle
    self.supportingEvidenceRows = supportingEvidenceRows
    self.commitTitle = commitTitle
    self.committingTitle = committingTitle
    self.committedTitle = committedTitle
    self.secondaryCommit = secondaryCommit
    self.commit = commit
  }

  public func commit(_ approvedText: String, usingSecondaryCommit: Bool) async throws {
    if usingSecondaryCommit, let secondaryCommit {
      try await secondaryCommit.commit(approvedText)
    } else {
      try await commit(approvedText)
    }
  }
}

public struct ChatApplyReviewSecondaryCommit {
  public var title: String
  public var commit: @MainActor (_ approvedText: String) async throws -> Void

  public init(
    title: String,
    commit: @escaping @MainActor (_ approvedText: String) async throws -> Void
  ) {
    self.title = title
    self.commit = commit
  }
}

public enum ChatApplyReviewPresentation: Sendable, Equatable {
  case inline
  case sheet
}
