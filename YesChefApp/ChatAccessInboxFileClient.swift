import Dependencies
import Foundation
import LLMHandoffKit
import YesChefCore

struct ChatAccessInboxFileClient: Sendable {
  var read: @Sendable (URL) async throws -> String
  var openAndClaim: @Sendable (ChatAccessFolder, URL) async throws -> String
  var claim: @Sendable (ChatAccessFolder, URL) async throws -> Void
  var maintain: @Sendable (ChatAccessFolder, Date, Bool) async throws -> Void
}

private enum ChatAccessInboxFileError: LocalizedError {
  case invalidStagedName
  case coordinatedReadFailed

  var errorDescription: String? {
    switch self {
    case .invalidStagedName:
      "This staged recipe has an unreadable filename."
    case .coordinatedReadFailed:
      "The staged recipe could not be read from iCloud Drive."
    }
  }
}

extension ChatAccessInboxFileClient: DependencyKey {
  static var liveValue: Self {
    Self(
      read: { url in
        try await Task.detached(priority: .utility) {
          try coordinatedRead(at: url)
        }.value
      },
      openAndClaim: { folder, url in
        try await Task.detached(priority: .utility) {
          let handoff = try stagedHandoff(at: url)
          let text = try coordinatedRead(at: url)
          _ = try HandoffInbox(root: folder.inboxURL, fileExtension: "json").markProcessed(handoff)
          return text
        }.value
      },
      claim: { folder, url in
        try await Task.detached(priority: .utility) {
          _ = try HandoffInbox(root: folder.inboxURL, fileExtension: "json").markProcessed(stagedHandoff(at: url))
        }.value
      },
      maintain: { folder, now, removesProbe in
        try await Task.detached(priority: .utility) {
          let processedItems: [ChatAccessInbox.ProcessedSnapshot]
          if FileManager.default.fileExists(atPath: folder.processedURL.path) {
            let urls = try FileManager.default.contentsOfDirectory(
              at: folder.processedURL,
              includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
              options: [.skipsHiddenFiles]
            )
            processedItems = try urls.compactMap { url in
              guard (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory != true else { return nil }
              let modifiedAt = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
              return ChatAccessInbox.ProcessedSnapshot(url: url, modifiedAt: modifiedAt)
            }
          } else {
            processedItems = []
          }
          for url in ChatAccessInbox.expired(processedItems, now: now) {
            try coordinatedDeleteIfPresent(at: url)
          }
          if removesProbe {
            let probeURL = folder.url.appending(path: "Probe", directoryHint: .isDirectory)
            try coordinatedDeleteIfPresent(at: probeURL)
          }
        }.value
      }
    )
  }

  private static func stagedHandoff(at url: URL) throws -> StagedHandoff {
    guard let handoff = StagedHandoff(url: url) else { throw ChatAccessInboxFileError.invalidStagedName }
    return handoff
  }

  private static func coordinatedRead(at url: URL) throws -> String {
    var coordinationError: NSError?
    var result: Result<String, Error>?
    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      result = Result { try String(contentsOf: coordinatedURL, encoding: .utf8) }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw ChatAccessInboxFileError.coordinatedReadFailed }
    return try result.get()
  }

  private static func coordinatedDeleteIfPresent(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    var coordinationError: NSError?
    var deletionError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
      do {
        try FileManager.default.removeItem(at: coordinatedURL)
      } catch {
        deletionError = error
      }
    }
    if let deletionError { throw deletionError }
    if let coordinationError { throw coordinationError }
  }
}

extension DependencyValues {
  var chatAccessInboxFileClient: ChatAccessInboxFileClient {
    get { self[ChatAccessInboxFileClient.self] }
    set { self[ChatAccessInboxFileClient.self] = newValue }
  }
}
