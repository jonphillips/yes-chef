import Dependencies
import Foundation
import YesChefCore

struct ChatAccessFolderClient: Sendable {
  var resolveFolder: @Sendable () async throws -> ChatAccessFolder
  var resolveAndCreateInbox: @Sendable () async throws -> ChatAccessFolder
}

private enum ChatAccessFolderClientError: LocalizedError {
  case containerUnavailable

  var errorDescription: String? {
    "The Yes Chef iCloud Drive container is unavailable. Check that this device is signed in to iCloud and iCloud Drive is enabled."
  }
}

extension ChatAccessFolderClient: DependencyKey {
  static var liveValue: Self {
    let resolveFolder: @Sendable () async throws -> ChatAccessFolder = {
      try await Task.detached(priority: .utility) {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef") else {
          throw ChatAccessFolderClientError.containerUnavailable
        }
        // ADR-0059's development variant has not landed yet, so every current build uses MCP/.
        return ChatAccessFolder(containerURL: containerURL)
      }.value
    }
    return Self(
      resolveFolder: resolveFolder,
      resolveAndCreateInbox: {
        let folder = try await resolveFolder()
        try await Task.detached(priority: .utility) {
          try FileManager.default.createDirectory(at: folder.inboxURL, withIntermediateDirectories: true)
        }.value
        return folder
      }
    )
  }
}

extension DependencyValues {
  var chatAccessFolderClient: ChatAccessFolderClient {
    get { self[ChatAccessFolderClient.self] }
    set { self[ChatAccessFolderClient.self] = newValue }
  }
}
