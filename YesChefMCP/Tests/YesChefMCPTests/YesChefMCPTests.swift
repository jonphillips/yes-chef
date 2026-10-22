import Foundation
import MCPServerKit
import Testing
import YesChefMCPServer

struct YesChefMCPTests {
  @Test func listsToolsWritesAndListsProbeFile() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let container = temporary.appending(path: "container", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let fixedDate = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00Z")!
    let server = YesChefMCPServer.make(containerURL: container) { fixedDate }
    let list = try #require(await server.handle(line: request("tools/list")))
    #expect(try object(list)["result"]?.objectValue?["tools"]?.arrayValue?.count == 2)

    let write = try #require(await server.handle(line: toolCall("probe_write", arguments: .object(["note": .string("hello from mac")]))))
    #expect(try object(write)["result"]?.objectValue?["isError"] != .bool(true))
    #expect(try object(write)["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("from-mac-20261021T120000.000Z.txt") == true)

    let listing = try #require(await server.handle(line: toolCall("probe_list", arguments: .object([:]))))
    let response = try object(listing)
    #expect(response["result"]?.objectValue?["isError"] != .bool(true))
    #expect(response["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains("hello from mac") == true)
  }

  @Test func reportsMissingContainerWithoutCreatingIt() async throws {
    let container = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let server = YesChefMCPServer.make(containerURL: container)

    let response = try #require(await server.handle(line: toolCall("probe_list", arguments: .object([:]))))
    #expect(try object(response)["result"]?.objectValue?["isError"] == .bool(true))
    #expect(try object(response)["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue?.contains(container.path) == true)
    #expect(!FileManager.default.fileExists(atPath: container.path))
  }

  private func request(_ method: String) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object(["jsonrpc": .string("2.0"), "id": .integer(1), "method": .string(method)])), as: UTF8.self)
  }

  private func toolCall(_ name: String, arguments: MCPValue) -> String {
    String(decoding: try! JSONEncoder().encode(MCPValue.object([
      "jsonrpc": .string("2.0"),
      "id": .integer(1),
      "method": .string("tools/call"),
      "params": .object(["name": .string(name), "arguments": arguments]),
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
