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

  public var inboxURL: URL {
    url.appending(path: "Inbox", directoryHint: .isDirectory)
  }

  public var processedURL: URL {
    inboxURL.appending(path: "Processed", directoryHint: .isDirectory)
  }
}
