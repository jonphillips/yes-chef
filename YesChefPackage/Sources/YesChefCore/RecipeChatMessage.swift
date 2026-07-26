import Foundation
import LLMClientKit
import SQLiteData

public struct RecipeChatMessage: Identifiable, Sendable, Equatable {
  public enum Role: String, Codable, QueryBindable, QueryDecodable, Sendable, Equatable {
    case user
    case assistant
  }

  public let id: UUID
  public var role: Role
  public var text: String
  /// The tier that actually produced an assistant turn. `nil` keeps pre-provenance rows honest.
  public var resolvedTier: RecipeChatMessageTier?

  public init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    resolvedTier: RecipeChatMessageTier? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.resolvedTier = resolvedTier
  }
}

public enum RecipeChatMessageTier: String, Codable, QueryBindable, QueryDecodable, Sendable, Equatable {
  case onDevice
  case anthropic
  case openai

  public init(resolvedTier: ModelTier) {
    switch resolvedTier {
    case .onDevice, .frontierPreferred:
      self = .onDevice
    case .frontier(.anthropic):
      self = .anthropic
    case .frontier(.openai):
      self = .openai
    }
  }

  public var displayName: String {
    switch self {
    case .onDevice:
      "On-device"
    case .anthropic:
      FrontierProvider.anthropic.displayName
    case .openai:
      FrontierProvider.openai.displayName
    }
  }
}
