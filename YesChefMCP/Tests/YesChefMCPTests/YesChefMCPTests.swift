import Foundation
import LLMHandoffKit
import MCPServerKit
import Testing
import YesChefCore
import YesChefMCPServer

struct YesChefMCPTests {
  @Test func listsOnlyStageRecipeAndStagesAValidatedColonFreeFile() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let fixedDate = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let server = YesChefMCPServer.make(containerURL: container) { fixedDate }
    let list = try #require(await server.handle(line: request("tools/list")))
    let tools = try object(list)["result"]?.objectValue?["tools"]?.arrayValue ?? []
    #expect(tools.count == 1)
    #expect(tools.first?.objectValue?["name"] == .string("stage_recipe"))

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] != .bool(true))
    let content = responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue
    #expect(content?.contains("\"staged\":\"Braised Beans\"") == true)
    #expect(content?.contains("\"next\":\"Jon reviews and saves it in Yes Chef → Create Recipe.\"") == true)
    #expect(!content.orEmpty.contains(container.path))

    let inboxURL = ChatAccessFolder(containerURL: container).inboxURL
    let inbox = HandoffInbox(root: inboxURL, fileExtension: "json")
    let staged = try #require(try inbox.list().first)
    #expect(!staged.url.lastPathComponent.contains(":"))
    #expect(staged.url.pathExtension == "json")
    let stagedText = try inbox.read(staged)
    let parsed = try RecipeContractStaging.validate(stagedText)
    #expect(parsed.title == "Braised Beans")
    #expect(try inbox.list().count == 1)
  }

  @Test func invalidRecipeReturnsErrorAndStagesNothing() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let server = YesChefMCPServer.make(containerURL: container)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: .object(["@type": .string("Recipe")]))))
    let responseObject = try object(response)["result"]?.objectValue ?? [:]
    #expect(responseObject["isError"] == .bool(true))
    #expect(responseObject["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("ingredients and instructions") == true)
    #expect(!FileManager.default.fileExists(atPath: ChatAccessFolder(containerURL: container).inboxURL.path))
  }

  @Test func missingContainerReturnsErrorWithoutCreatingIt() async throws {
    let container = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let server = YesChefMCPServer.make(containerURL: container)

    let response = try #require(await server.handle(line: toolCall("stage_recipe", recipe: validRecipe)))
    #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
    #expect(try object(response)["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains(container.path) == true)
    #expect(!FileManager.default.fileExists(atPath: container.path))
  }

  private var validRecipe: MCPValue {
    .object([
      "@context": .string("https://schema.org"),
      "@type": .string("Recipe"),
      "name": .string("Braised Beans"),
      "recipeIngredient": .array([.string("1 cup beans")]),
      "recipeInstructions": .array([.object(["@type": .string("HowToStep"), "text": .string("Cook the beans.")])]),
    ])
  }

  private func request(_ method: String) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object(["jsonrpc": .string("2.0"), "id": .integer(1), "method": .string(method)])), as: UTF8.self)
  }

  private func toolCall(_ name: String, recipe: MCPValue) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object([
      "jsonrpc": .string("2.0"),
      "id": .integer(1),
      "method": .string("tools/call"),
      "params": .object(["name": .string(name), "arguments": .object(["recipe": recipe])]),
    ])), as: UTF8.self)
  }

  private func object(_ json: String) throws -> [String: MCPValue] {
    try JSONDecoder().decode(MCPValue.self, from: Data(json.utf8)).objectValue ?? [:]
  }
}

private extension MCPValue {
  var arrayValue: [MCPValue]? {
    guard case let .array(value) = self else { return nil }
    return value
  }
}

private extension Optional where Wrapped == String {
  var orEmpty: String { self ?? "" }
}
