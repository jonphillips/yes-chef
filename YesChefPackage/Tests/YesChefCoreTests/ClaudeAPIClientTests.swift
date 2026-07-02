import Foundation
import Testing
import YesChefCore

extension RecipeCoreTests {
  @Suite
  struct ClaudeAPIClientTests {
    @Test
    func urlRequestUsesClaudeMessagesAPIShape() throws {
      let request = try ClaudeAPIClient.urlRequest(
        for: ModelRequest(
          system: "Select useful reader tips.",
          messages: [
            ModelMessage(role: .user, content: "Comment text")
          ],
          maxOutputTokens: 512
        ),
        apiKey: "test-api-key"
      )

      #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
      #expect(request.httpMethod == "POST")
      #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-api-key")
      #expect(request.value(forHTTPHeaderField: "anthropic-version") == ClaudeAPIClient.apiVersion)
      #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

      let body = try #require(request.httpBody)
      let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      #expect(json["model"] as? String == ClaudeAPIClient.defaultModel)
      #expect(json["system"] as? String == "Select useful reader tips.")
      #expect(json["max_tokens"] as? Int == 512)

      let messages = try #require(json["messages"] as? [[String: Any]])
      #expect(messages.count == 1)
      #expect(messages[0]["role"] as? String == "user")
      let content = try #require(messages[0]["content"] as? [[String: Any]])
      #expect(content.count == 1)
      #expect(content[0]["type"] as? String == "text")
      #expect(content[0]["text"] as? String == "Comment text")
    }

    @Test
    func completeDecodesTextAndUsageWithoutNetwork() async throws {
      let client = ClaudeAPIClient(
        apiKey: { "test-api-key" },
        transport: { request in
          #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-api-key")
          let responseURL = try #require(URL(string: "https://api.anthropic.com/v1/messages"))
          let response = try #require(HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          ))
          return (
            Data(
              """
              {
                "id": "msg_123",
                "type": "message",
                "role": "assistant",
                "model": "claude-fable-5",
                "content": [
                  { "type": "text", "text": "Tip one." },
                  { "type": "text", "text": "Tip two." }
                ],
                "stop_reason": "end_turn",
                "stop_sequence": null,
                "usage": {
                  "input_tokens": 42,
                  "output_tokens": 9
                }
              }
              """.utf8
            ),
            response
          )
        }
      )

      let response = try await client.complete(
        ModelRequest(
          model: "claude-sonnet-5",
          messages: [ModelMessage(role: .user, content: "Hello")],
          maxOutputTokens: 128
        )
      )

      #expect(
        response == ModelResponse(
          id: "msg_123",
          model: "claude-fable-5",
          text: "Tip one.\n\nTip two.",
          stopReason: "end_turn",
          usage: ModelUsage(inputTokens: 42, outputTokens: 9)
        )
      )
    }

    @Test
    func completeRejectsMissingAPIKeyBeforeTransport() async throws {
      let client = ClaudeAPIClient(
        apiKey: { "  " },
        transport: { _ in
          Issue.record("Transport should not run without an API key.")
          return (Data(), URLResponse())
        }
      )

      await #expect(throws: ClaudeAPIClientError.missingAPIKey) {
        try await client.complete(
          ModelRequest(
            messages: [ModelMessage(role: .user, content: "Hello")],
            maxOutputTokens: 128
          )
        )
      }
    }

    @Test
    func completeSurfacesHTTPErrorBody() async throws {
      let client = ClaudeAPIClient(
        apiKey: { "test-api-key" },
        transport: { _ in
          let responseURL = try #require(URL(string: "https://api.anthropic.com/v1/messages"))
          let response = try #require(HTTPURLResponse(
            url: responseURL,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
          ))
          return (
            Data(#"{"error":{"message":"invalid request"}}"#.utf8),
            response
          )
        }
      )

      await #expect(
        throws: ClaudeAPIClientError.invalidHTTPStatus(
          400,
          responseBody: #"{"error":{"message":"invalid request"}}"#
        )
      ) {
        try await client.complete(
          ModelRequest(
            messages: [ModelMessage(role: .user, content: "Hello")],
            maxOutputTokens: 128
          )
        )
      }
    }
  }
}
