import Dependencies
import Foundation
import LLMHandoffKit
import Testing
import YesChefCore
@testable import YesChef

@Suite
@MainActor
struct ChatAccessInboxModelTests {
  @Test
  func openClaimsTheFileThenStagesItsOriginalText() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: temporary)
    }
    let coordinator = CreateRecipeCoordinator()

    try await withDependencies {
      $0.uuid = .incrementing
      $0.createRecipeCoordinator = coordinator
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        openAndClaim: { _, _ in "original recipe JSON-LD" },
        claim: { _, _ in },
        maintain: { _, _, _ in }
      )
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let row = makeRow(in: folder)
      model.updateRows(from: [ChatAccessInbox.MetadataSnapshot(url: row.url, name: row.url.lastPathComponent, isCurrent: true)])

      await model.open(try #require(model.rows.first))

      #expect(model.rows.isEmpty)
      #expect(coordinator.stagedText?.text == "original recipe JSON-LD")
    }
  }

  @Test
  func failedReadKeepsTheRowAndShowsItsError() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: temporary)
    }

    try await withDependencies {
      $0.createRecipeCoordinator = CreateRecipeCoordinator()
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        openAndClaim: { _, _ in throw InboxReadFailure.unavailable },
        claim: { _, _ in },
        maintain: { _, _, _ in }
      )
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let row = makeRow(in: folder)
      model.updateRows(from: [ChatAccessInbox.MetadataSnapshot(url: row.url, name: row.url.lastPathComponent, isCurrent: true)])

      await model.open(try #require(model.rows.first))

      #expect(model.rows.count == 1)
      #expect(model.rowErrors[model.rows[0].id] == InboxReadFailure.unavailable.localizedDescription)
    }
  }

  @Test
  func alreadyClaimedDropsTheRowQuietly() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: temporary)
    }

    try await withDependencies {
      $0.createRecipeCoordinator = CreateRecipeCoordinator()
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        openAndClaim: { _, _ in throw HandoffInboxError.alreadyClaimed },
        claim: { _, _ in throw HandoffInboxError.alreadyClaimed },
        maintain: { _, _, _ in }
      )
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let row = makeRow(in: folder)
      model.updateRows(from: [ChatAccessInbox.MetadataSnapshot(url: row.url, name: row.url.lastPathComponent, isCurrent: true)])

      await model.open(try #require(model.rows.first))

      #expect(model.rows.isEmpty)
      #expect(model.rowErrors.isEmpty)
    }
  }

  private func fixture() throws -> (ChatAccessFolder, UserDefaults, String, URL) {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let suiteName = "ChatAccessInboxModelTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return (ChatAccessFolder(containerURL: temporary), defaults, suiteName, temporary)
  }

  private func makeRow(in folder: ChatAccessFolder) -> ChatAccessInbox.Row {
    let url = folder.inboxURL.appending(path: "20261022T200000Z-soup.json")
    return ChatAccessInbox.Row(url: url, name: "Soup", stagedAt: Date(timeIntervalSince1970: 1_800_000_000), downloadState: .current)
  }
}

private enum InboxReadFailure: Error {
  case unavailable
}
