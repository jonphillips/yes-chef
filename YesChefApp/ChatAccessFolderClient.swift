import ChatAccessKit
import Dependencies

struct ChatAccessFolderClient: Sendable {
  var resolveFolder: @Sendable () async throws -> ChatAccessFolder
  var resolveAndCreateInbox: @Sendable () async throws -> ChatAccessFolder
}

extension ChatAccessFolderClient: DependencyKey {
  static var liveValue: Self {
    #if DEBUG
    let isDevelopment = true
    #else
    let isDevelopment = false
    #endif
    let client = ChatAccessContainerClient.live(
      containerIdentifier: "iCloud.com.jonphillips.yeschef", isDevelopment: isDevelopment, appName: "Yes Chef"
    )
    return Self(resolveFolder: client.resolveFolder, resolveAndCreateInbox: client.resolveAndCreateInbox)
  }
}

extension DependencyValues {
  var chatAccessFolderClient: ChatAccessFolderClient {
    get { self[ChatAccessFolderClient.self] }
    set { self[ChatAccessFolderClient.self] = newValue }
  }
}
