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
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.createRecipeCoordinator = coordinator
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        read: { _ in "" },
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
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.createRecipeCoordinator = CreateRecipeCoordinator()
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        read: { _ in "" },
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
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.createRecipeCoordinator = CreateRecipeCoordinator()
      $0.chatAccessInboxFileClient = ChatAccessInboxFileClient(
        read: { _ in "" },
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

  @Test(arguments: [false, true])
  func returnStagesAndClaimsAllSupersededFiles(olderMarker: Bool) async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let handoffID = UUID(), recipeID = UUID()
    let recorder = InboxClaims()
    let marker = olderMarker ? "YC-CONTRACT: v2\n" : ""
    let text = "YC-HANDOFF: \(handoffID.uuidString)\n\(marker)Brown the butter first."
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = HandoffReviewCoordinator()
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      @Dependency(\.handoffReviewCoordinator) var coordinator
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: .now, dateModified: .now) }.execute(db)
        try AIHandoffRepository.create(AIHandoff(id: handoffID, sourceType: .recipe, sourceID: recipeID,
          taskType: .adjustRecipe, createdAt: .now, exportedPrompt: "Adjust: Soup"), in: db)
      }
      let urls = ["180000", "190000"].map { folder.inboxURL.appending(path: "20261022T\($0)Z-\(handoffID.uuidString).ycreturn") }
      let snapshots = urls.map { ChatAccessInbox.MetadataSnapshot(url: $0, name: $0.lastPathComponent, isCurrent: true) }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: snapshots)
      let row = try #require(model.returnRows.first)
      await model.open(row)
      #expect(coordinator.review != nil)
      #expect((coordinator.contractWarning != nil) == olderMarker)
      #expect(await recorder.urls == [urls[1], urls[0]])
      #expect(model.returnRows.isEmpty)
    }
  }

  @Test func unknownReturnIsCopyOnlyAndDoesNotBadgeOrClaim() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.chatAccessInboxFileClient = .init(read: { _ in "return" }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      let url = folder.inboxURL.appending(path: "20261022T180000Z-\(UUID().uuidString).ycreturn")
      let snapshots = [ChatAccessInbox.MetadataSnapshot(url: url, name: url.lastPathComponent, isCurrent: true)]
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: snapshots)
      let row = try #require(model.returnRows.first)
      await model.open(row)
      await model.discard(row)
      await model.updateReturnRows(from: snapshots)
      #expect(model.inboxCount == 0)
      #expect(model.returnRows.count == 1)
      #expect(await recorder.urls.isEmpty)
    }
  }

  @Test func failedStagingKeepsReturnAndClaimsNothing() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let handoffID = UUID(), recipeID = UUID(), recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.chatAccessInboxFileClient = .init(read: { _ in "YC-HANDOFF: \(handoffID.uuidString)\nA revision" },
        openAndClaim: { _, _ in "" }, claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Archived", archived: true, dateCreated: .now, dateModified: .now) }.execute(db)
        try AIHandoffRepository.create(AIHandoff(id: handoffID, sourceType: .recipe, sourceID: recipeID,
          taskType: .adjustRecipe, createdAt: .now, exportedPrompt: "Adjust: Missing"), in: db)
      }
      let url = folder.inboxURL.appending(path: "20261022T180000Z-\(handoffID.uuidString).ycreturn")
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      let row = try #require(model.returnRows.first)
      await model.open(row)
      #expect(model.rowErrors[row.id] != nil)
      #expect(model.returnRows.count == 1)
      #expect(await recorder.urls.isEmpty)
    }
  }

  @Test func liveClaimKeepsReturnExtension() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createDirectory(at: folder.inboxURL, withIntermediateDirectories: true)
    let url = folder.inboxURL.appending(path: "20261022T180000Z-\(UUID().uuidString).ycreturn")
    try "return".write(to: url, atomically: true, encoding: .utf8)
    try await ChatAccessInboxFileClient.liveValue.claim(folder, url)
    let processed = try FileManager.default.contentsOfDirectory(at: folder.processedURL, includingPropertiesForKeys: nil)
    #expect(processed.count == 1)
    #expect(processed.first?.pathExtension == "ycreturn")
    #expect(try String(contentsOf: #require(processed.first), encoding: .utf8) == "return")
  }

  @Test(arguments: [AIHandoffTaskType.adjustRecipe, .recipe])
  func newRecipeReturnOpensCreateAndMarksImported(task: AIHandoffTaskType) async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let handoffID = UUID(), recipeID = UUID(), recorder = InboxClaims()
    let create = CreateRecipeCoordinator()
    let label = task == .recipe ? "YC-NEW-RECIPE:\n" : ""
    let text = "YC-HANDOFF: \(handoffID.uuidString)\n\(label){\"@context\":\"https://schema.org\",\"@type\":\"Recipe\",\"name\":\"Soup\",\"recipeIngredient\":[\"1 cup water\"],\"recipeInstructions\":[{\"@type\":\"HowToStep\",\"text\":\"Heat it.\"}]}"
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.createRecipeCoordinator = create
      $0.handoffReviewCoordinator = HandoffReviewCoordinator()
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Original", dateCreated: .now, dateModified: .now) }.execute(db)
        try AIHandoffRepository.create(AIHandoff(id: handoffID, sourceType: .recipe, sourceID: recipeID,
          taskType: task, createdAt: .now, exportedPrompt: "Recipe: Original"), in: db)
      }
      let url = folder.inboxURL.appending(path: "20261022T180000Z-\(handoffID.uuidString).ycreturn")
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      await model.open(try #require(model.returnRows.first))
      #expect(create.stagedText?.text.contains("Soup") == true)
      #expect(try await database.read { db in try AIHandoffRepository.handoff(id: handoffID, in: db)?.status } == .imported)
      #expect(await recorder.urls == [url])
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

private actor InboxClaims {
  private(set) var urls: [URL] = []
  func add(_ url: URL) { urls.append(url) }
}
