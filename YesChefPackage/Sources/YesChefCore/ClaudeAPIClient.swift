import Foundation

public enum ClaudeAPIClientError: Error, Equatable, LocalizedError, Sendable {
  case invalidHTTPStatus(Int, responseBody: String)
  case invalidEndpoint
  case invalidResponse
  case missingAPIKey
  case missingHTTPResponse

  public var errorDescription: String? {
    switch self {
    case let .invalidHTTPStatus(statusCode, _):
      "Claude request failed (HTTP \(statusCode))."
    case .invalidEndpoint:
      "Claude API is not configured correctly."
    case .invalidResponse:
      "Claude returned a response Yes Chef could not read."
    case .missingAPIKey:
      "Add a Claude API key in Settings before using AI features."
    case .missingHTTPResponse:
      "Claude returned an invalid HTTP response."
    }
  }
}

public struct ClaudeAPIClient: Sendable {
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public static let defaultModel = "claude-fable-5"
  public static let apiVersion = "2023-06-01"

  private var apiKey: @Sendable () throws -> String
  private var transport: Transport

  public init(
    apiKey: @escaping @Sendable () throws -> String,
    transport: @escaping Transport = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.apiKey = apiKey
    self.transport = transport
  }

  public var modelClient: ModelClient {
    ModelClient { request in
      try await complete(request)
    }
  }

  public func complete(_ request: ModelRequest) async throws -> ModelResponse {
    let apiKey = try apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else { throw ClaudeAPIClientError.missingAPIKey }

    let urlRequest = try Self.urlRequest(for: request, apiKey: apiKey)
    let (data, response) = try await transport(urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ClaudeAPIClientError.missingHTTPResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw ClaudeAPIClientError.invalidHTTPStatus(
        httpResponse.statusCode,
        responseBody: String(decoding: data, as: UTF8.self)
      )
    }
    return try Self.modelResponse(from: data)
  }

  public static func urlRequest(for request: ModelRequest, apiKey: String) throws -> URLRequest {
    guard let endpoint = URL(string: "https://api.anthropic.com/v1/messages") else {
      throw ClaudeAPIClientError.invalidEndpoint
    }
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
    urlRequest.httpBody = try JSONEncoder().encode(ClaudeMessagesRequest(request))
    return urlRequest
  }

  public static func modelResponse(from data: Data) throws -> ModelResponse {
    let response = try JSONDecoder().decode(ClaudeMessagesResponse.self, from: data)
    let text = response.content.compactMap(\.text).joined(separator: "\n\n")
    return ModelResponse(
      id: response.id,
      model: response.model,
      text: text,
      stopReason: response.stopReason,
      usage: response.usage.map {
        ModelUsage(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens)
      }
    )
  }
}

private struct ClaudeMessagesRequest: Encodable {
  var model: String
  var system: String?
  var messages: [Message]
  var maxTokens: Int

  init(_ request: ModelRequest) {
    self.model = request.model ?? ClaudeAPIClient.defaultModel
    self.system = request.system
    self.messages = request.messages.map(Message.init)
    self.maxTokens = request.maxOutputTokens
  }

  enum CodingKeys: String, CodingKey {
    case model
    case system
    case messages
    case maxTokens = "max_tokens"
  }

  struct Message: Encodable {
    var role: String
    var content: [Content]

    init(_ message: ModelMessage) {
      self.role = message.role.rawValue
      self.content = [Content(text: message.content)]
    }
  }

  struct Content: Encodable {
    var type = "text"
    var text: String
  }
}

private struct ClaudeMessagesResponse: Decodable {
  var id: String
  var model: String
  var content: [Content]
  var stopReason: String?
  var usage: Usage?

  enum CodingKeys: String, CodingKey {
    case id
    case model
    case content
    case stopReason = "stop_reason"
    case usage
  }

  struct Content: Decodable {
    var type: String
    var text: String?
  }

  struct Usage: Decodable {
    var inputTokens: Int
    var outputTokens: Int

    enum CodingKeys: String, CodingKey {
      case inputTokens = "input_tokens"
      case outputTokens = "output_tokens"
    }
  }
}
