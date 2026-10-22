import Foundation
import MCPServerKit
import YesChefCore

private struct ProbeWriteInput: Decodable, Sendable {
  var note: String
}

private struct ProbeListing: Encodable, Sendable {
  struct File: Encodable, Sendable {
    var name: String
    var sizeBytes: Int
    var modifiedAt: String?
    var materializedOnMac: Bool
    var preview: String?
    var readBytes: Int?
    var readMilliseconds: Double?
  }

  var files: [File]
}

private struct ProbeWriteResult: Encodable, Sendable {
  var fileName: String
}

private struct ProbeContext: Sendable {
  let containerURL: URL
  let now: @Sendable () -> Date

  var folder: ChatAccessFolder { ChatAccessFolder(containerURL: containerURL) }

  func list() throws -> ProbeListing {
    try requireContainer()
    let directory = folder.probeURL
    guard FileManager.default.fileExists(atPath: directory.path) else { return ProbeListing(files: []) }
    let urls = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    return ProbeListing(files: try urls.map { url in
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey])
      let size = values.fileSize ?? 0
      let materialized = values.ubiquitousItemDownloadingStatus == .current
      if url.lastPathComponent.hasPrefix("large-") {
        let start = ContinuousClock.now
        let data = try Data(contentsOf: url)
        let duration = start.duration(to: ContinuousClock.now)
        return ProbeListing.File(
          name: url.lastPathComponent,
          sizeBytes: size,
          modifiedAt: values.contentModificationDate.map(Self.iso8601),
          materializedOnMac: materialized,
          preview: nil,
          readBytes: data.count,
          readMilliseconds: Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        )
      }
      let preview: String?
      if size < 4_096 {
        let text = try String(contentsOf: url, encoding: .utf8)
        preview = String(text.prefix(200))
      } else {
        preview = nil
      }
      return ProbeListing.File(
        name: url.lastPathComponent,
        sizeBytes: size,
        modifiedAt: values.contentModificationDate.map(Self.iso8601),
        materializedOnMac: materialized,
        preview: preview,
        readBytes: nil,
        readMilliseconds: nil
      )
    })
  }

  func write(note: String) throws -> ProbeWriteResult {
    try requireContainer()
    let directory = folder.probeURL
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileName = "from-mac-\(Self.filenameTimestamp(now())).txt"
    let contents = "Device: Mac helper\nTime: \(Self.iso8601(now()))\nNote: \(note)\n"
    try Data(contents.utf8).write(to: directory.appending(path: fileName), options: .atomic)
    return ProbeWriteResult(fileName: fileName)
  }

  private func requireContainer() throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: containerURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw ProbeContainerUnavailable(path: containerURL.path)
    }
  }

  private static func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private static func filenameTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.formatOptions.remove(.withDashSeparatorInDate)
    formatter.formatOptions.remove(.withColonSeparatorInTime)
    return formatter.string(from: date)
  }
}

private struct ProbeContainerUnavailable: LocalizedError {
  let path: String
  var errorDescription: String? { "The Yes Chef iCloud container is not present at \(path). The helper will not create it." }
}

public enum YesChefMCPServer {
  public static func make(
    containerURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~yeschef", directoryHint: .isDirectory),
    now: @escaping @Sendable () -> Date = { Date() }
  ) -> MCPServer {
    let context = ProbeContext(containerURL: containerURL, now: now)
    let noteSchema: MCPValue = .object([
      "type": .string("object"),
      "properties": .object(["note": .object(["type": .string("string")])]),
      "required": .array([.string("note")]),
      "additionalProperties": .bool(false),
    ])
    return MCPServer(
      name: "yeschef",
      version: "0.1.0",
      instructions: "These tools probe the Yes Chef iCloud Drive transport. They are temporary diagnostics, not recipe tools.",
      tools: [
        MCPTool(
          name: "probe_list",
          description: "List Yes Chef iCloud Drive probe files, their sizes, modification times, and Mac materialization status. Reads large probe files in full to measure eviction recovery.",
          inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
          annotations: .init(readOnly: true, openWorld: false)
        ) { _ in
          do { return .json(try context.list()) }
          catch { return .error(error.localizedDescription) }
        },
        MCPTool(
          name: "probe_write",
          description: "Write a small note into the Yes Chef iCloud Drive probe folder.",
          inputSchema: noteSchema,
          annotations: .init(readOnly: false, destructive: false, openWorld: false)
        ) { input in
          guard let data = try? JSONEncoder().encode(input), let payload = try? JSONDecoder().decode(ProbeWriteInput.self, from: data) else {
            return .error("Provide a note string.")
          }
          do { return .json(try context.write(note: payload.note)) }
          catch { return .error(error.localizedDescription) }
        },
      ]
    )
  }
}
