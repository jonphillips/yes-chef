import Foundation

/// The shared iCloud Drive location used by the macOS helper and the app.
public struct ChatAccessFolder: Sendable {
  public let url: URL

  public init(containerURL: URL, isDevelopment: Bool = false) {
    url = containerURL.appending(
      path: isDevelopment ? "MCP-Dev" : "MCP",
      directoryHint: .isDirectory
    )
  }

  public var probeURL: URL {
    url.appending(path: "Probe", directoryHint: .isDirectory)
  }
}
