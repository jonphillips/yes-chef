import Dependencies
import Foundation
import YesChefCore

struct ChatAccessFolderClient: Sendable {
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
    Self(resolveAndCreateInbox: {
      try await Task.detached(priority: .utility) {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef") else {
          throw ChatAccessFolderClientError.containerUnavailable
        }
        // ADR-0059's development variant has not landed yet, so every current build uses MCP/.
        let folder = ChatAccessFolder(containerURL: containerURL)
        try FileManager.default.createDirectory(at: folder.inboxURL, withIntermediateDirectories: true)
        return folder
      }.value
    })
  }
}

extension DependencyValues {
  var chatAccessFolderClient: ChatAccessFolderClient {
    get { self[ChatAccessFolderClient.self] }
    set { self[ChatAccessFolderClient.self] = newValue }
  }
}
