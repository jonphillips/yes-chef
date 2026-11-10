import ChatAccessKit
import Dependencies
import Foundation

struct ChatAccessInboxFileClient: Sendable {
  var read: @Sendable (URL) async throws -> String
  var openAndClaim: @Sendable (ChatAccessFolder, URL) async throws -> String
  var claim: @Sendable (ChatAccessFolder, URL) async throws -> Void
  var maintain: @Sendable (ChatAccessFolder, Date, Bool) async throws -> Void
  var cleanupLegacyDevExport: @Sendable (ChatAccessFolder, String) async throws -> Void = { _, _ in }
}

extension ChatAccessInboxFileClient: DependencyKey {
  static var liveValue: Self {
    let client = ChatInboxFileClient.live
    let recipe = ChatInboxItemKind(fileExtension: "json", expiresUnclaimed: false, datesProcessedByClaim: false)
    let handoff = ChatInboxItemKind(fileExtension: "ycreturn", expiresUnclaimed: true, datesProcessedByClaim: true)
    let recipeReturn = ChatInboxItemKind(fileExtension: "ycrecipereturn", expiresUnclaimed: false, datesProcessedByClaim: false)
    let menu = ChatInboxItemKind(fileExtension: "ycmenu", expiresUnclaimed: false, datesProcessedByClaim: false)
    let menuDay = ChatInboxItemKind(fileExtension: "ycmenuday", expiresUnclaimed: false, datesProcessedByClaim: false)
    let kinds = [recipe, handoff, recipeReturn, menu, menuDay]
    return Self(
      read: client.read,
      openAndClaim: { folder, url in
        let text = try await client.read(url)
        try await client.claim(folder, url, recipe)
        return text
      },
      claim: { folder, url in
        let kind = kinds.first { $0.fileExtension == url.pathExtension } ?? recipe
        try await client.claim(folder, url, kind)
      },
      maintain: { folder, now, removesProbe in
        try await client.maintain(folder, kinds, now)
        if removesProbe {
          try await Task.detached(priority: .utility) {
            let url = folder.url.appending(path: "Probe", directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            var coordinationError: NSError?
            var deletionError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
              do { try FileManager.default.removeItem(at: url) } catch { deletionError = error }
            }
            if let deletionError { throw deletionError }
            if let coordinationError { throw coordinationError }
          }.value
        }
      },
      cleanupLegacyDevExport: { folder, installationID in
        guard let id = UUID(uuidString: installationID) else { return }
        try await Task.detached(priority: .utility) {
          let container = folder.url.deletingLastPathComponent()
          let url = ChatAccessFolder(containerURL: container, isDevelopment: false)
            .exportsURL.appending(path: "\(id.uuidString).json")
          guard FileManager.default.fileExists(atPath: url.path) else { return }
          var coordinationError: NSError?
          var deletionError: Error?
          NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            do { try FileManager.default.removeItem(at: url) } catch { deletionError = error }
          }
          if let deletionError { throw deletionError }
          if let coordinationError { throw coordinationError }
        }.value
      }
    )
  }
}

extension DependencyValues {
  var chatAccessInboxFileClient: ChatAccessInboxFileClient {
    get { self[ChatAccessInboxFileClient.self] }
    set { self[ChatAccessInboxFileClient.self] = newValue }
  }
}
