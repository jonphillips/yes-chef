import Dependencies
import Foundation

public struct ModelMessage: Equatable, Sendable {
  public enum Role: String, Equatable, Sendable {
    case user
    case assistant
  }

  public var role: Role
  public var content: String

  public init(role: Role, content: String) {
    self.role = role
    self.content = content
  }
}

public struct ModelRequest: Equatable, Sendable {
  public var model: String?
  public var system: String?
  public var messages: [ModelMessage]
  public var maxOutputTokens: Int

  public init(
    model: String? = nil,
    system: String? = nil,
    messages: [ModelMessage],
    maxOutputTokens: Int
  ) {
    self.model = model
    self.system = system
    self.messages = messages
    self.maxOutputTokens = maxOutputTokens
  }
}

public struct ModelResponse: Equatable, Sendable {
  public var id: String
  public var model: String
  public var text: String
  public var stopReason: String?
  public var usage: ModelUsage?

  public init(
    id: String,
    model: String,
    text: String,
    stopReason: String?,
    usage: ModelUsage?
  ) {
    self.id = id
    self.model = model
    self.text = text
    self.stopReason = stopReason
    self.usage = usage
  }
}

public struct ModelUsage: Equatable, Sendable {
  public var inputTokens: Int
  public var outputTokens: Int

  public init(inputTokens: Int, outputTokens: Int) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
  }
}

public enum ModelClientError: Error, Equatable, LocalizedError, Sendable {
  case unimplemented

  public var errorDescription: String? {
    switch self {
    case .unimplemented:
      "Model access is not configured."
    }
  }
}

public struct ModelClient: Sendable {
  public var complete: @Sendable (ModelRequest) async throws -> ModelResponse

  public init(
    complete: @escaping @Sendable (ModelRequest) async throws -> ModelResponse
  ) {
    self.complete = complete
  }
}

extension ModelClient: TestDependencyKey {
  public static var testValue: Self {
    Self { _ in throw ModelClientError.unimplemented }
  }
}

extension DependencyValues {
  public var modelClient: ModelClient {
    get { self[ModelClient.self] }
    set { self[ModelClient.self] = newValue }
  }
}
