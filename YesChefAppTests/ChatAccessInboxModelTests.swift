import ChatAccessKit
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
  func hasContentIncludesUnopenableMenuDayWithoutCountingIt() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let menuID = UUID()
    let envelope = ChatAccessStagedMenuDay(
      menuID: menuID, menuTitle: "Missing Menu", dayOffset: 0, items: [], dayAtStage: []
    )
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, _ in }, maintain: { _, _, _ in })
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      #expect(!model.hasContent)

      let url = folder.inboxURL.appending(path: "20261110T120000Z-missing-menu.ycmenuday")
      model.receiveSnapshots([ChatInboxSnapshot(url: url, name: url.lastPathComponent, isCurrent: true)])
      for _ in 0..<100 where model.menuDayRows.first?.hasMenuMetadata != true {
        try await Task.sleep(for: .milliseconds(10))
      }

      #expect(model.menuDayRows.count == 1)
      #expect(!model.menuDayRows[0].canOpen)
      #expect(model.hasContent)
      #expect(model.inboxCount == 0)
    }
  }

  @Test
  func snapshotsReportDownloadErrorsAndPreserveCurrentRowErrors() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.createRecipeCoordinator = CreateRecipeCoordinator()
      $0.chatAccessInboxFileClient = .init(read: { _ in "" }, openAndClaim: { _, _ in throw InboxReadFailure.unavailable },
        claim: { _, _ in }, maintain: { _, _, _ in })
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let url = makeRow(in: folder).url
      let returnURL = folder.inboxURL.appending(path: "20261022T200000Z-\(UUID().uuidString).ycreturn")
      model.receiveSnapshots([
        .init(url: url, name: url.lastPathComponent, isCurrent: false, downloadError: "Download failed"),
        .init(url: returnURL, name: returnURL.lastPathComponent, isCurrent: false, downloadError: "Return download failed"),
      ])
      #expect(model.rowErrors[url.path] == "Download failed")
      #expect(model.rowErrors[returnURL.path] == "Return download failed")
      model.receiveSnapshots([.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      await model.open(try #require(model.rows.first))
      #expect(model.rowErrors[url.path] == InboxReadFailure.unavailable.localizedDescription)
      model.receiveSnapshots([.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      #expect(model.rowErrors[url.path] == InboxReadFailure.unavailable.localizedDescription)
    }
  }

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

  @Test func liveMaintenancePreservesOldUnclaimedRecipesAndDatesReturnsByClaim() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let now = Date()
    let old = now.addingTimeInterval(-31 * 24 * 60 * 60)
    let recipeInbox = HandoffInbox(root: folder.inboxURL, fileExtension: "json")
    let returnInbox = HandoffInbox(root: folder.inboxURL, fileExtension: "ycreturn")
    let recipe = try recipeInbox.stage("recipe", slug: "recipe", now: old)
    let expiredReturn = try returnInbox.stage("return", slug: "old", now: old)
    let claimedReturn = try returnInbox.stage("return", slug: "claimed", now: old)
    let client = ChatAccessInboxFileClient.liveValue
    try await client.claim(folder, claimedReturn.url)
    try await client.maintain(folder, now, false)
    #expect(FileManager.default.fileExists(atPath: recipe.url.path))
    #expect(!FileManager.default.fileExists(atPath: expiredReturn.url.path))
    for staged in [expiredReturn, claimedReturn] {
      let processed = folder.processedURL.appending(path: staged.url.lastPathComponent)
      let modified = try #require(processed.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      #expect(abs(modified.timeIntervalSince(now)) < 5)
    }
  }

  @Test func watcherStartsWhenMaintenanceFails() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.chatAccessInboxFileClient = .init(read: { _ in "" }, openAndClaim: { _, _ in "" },
        claim: { _, _ in }, maintain: { _, _, _ in throw InboxReadFailure.unavailable })
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.prepare()
      #expect(model.watcher != nil)
      #expect(model.message == InboxReadFailure.unavailable.localizedDescription)
    }
  }

  @Test func prepareRemovesThisDevInstallLegacyExport() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let id = UUID()
    defaults.set(id.uuidString, forKey: ChatAccessExportWriter.installationIDKey)
    let legacy = folder.exportsURL.appending(path: "\(id.uuidString).json")
    try FileManager.default.createDirectory(at: folder.exportsURL, withIntermediateDirectories: true)
    try Data("legacy".utf8).write(to: legacy)
    let dev = ChatAccessFolder(containerURL: temporary, isDevelopment: true)
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.chatAccessInboxFileClient = .liveValue
    } operation: {
      let model = ChatAccessInboxModel(folder: dev, defaults: defaults)
      await model.prepare()
      #expect(!FileManager.default.fileExists(atPath: legacy.path))
      #expect(defaults.bool(forKey: ChatAccessInboxModel.legacyDevExportCleanupDefaultsKey))
    }
  }

  @Test func legacyDevCleanupOnlyRemovesThisInstall() async throws {
    let (_, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let id = UUID(), other = UUID()
    let production = ChatAccessFolder(containerURL: temporary, isDevelopment: false)
    let dev = ChatAccessFolder(containerURL: temporary, isDevelopment: true)
    try FileManager.default.createDirectory(at: production.exportsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dev.exportsURL, withIntermediateDirectories: true)
    let old = production.exportsURL.appending(path: "\(id.uuidString).json")
    let otherExport = production.exportsURL.appending(path: "\(other.uuidString).json")
    let devExport = dev.exportsURL.appending(path: "\(id.uuidString).json")
    for url in [old, otherExport, devExport] { try Data("export".utf8).write(to: url) }
    try await ChatAccessInboxFileClient.liveValue.cleanupLegacyDevExport(dev, id.uuidString)
    try await ChatAccessInboxFileClient.liveValue.cleanupLegacyDevExport(dev, id.uuidString)
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: otherExport.path))
    #expect(FileManager.default.fileExists(atPath: devExport.path))
  }

  @Test func discardedRecipeDoesNotReturnFromCachedOrStaleSnapshots() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.chatAccessInboxFileClient = .init(read: { _ in "" }, openAndClaim: { _, _ in "" }, claim: { _, _ in }, maintain: { _, _, _ in })
    } operation: {
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let url = makeRow(in: folder).url
      let snapshot = ChatInboxSnapshot(url: url, name: url.lastPathComponent, isCurrent: true)
      model.receiveSnapshots([snapshot])
      await model.discard(try #require(model.rows.first))
      model.receiveSnapshots([snapshot])
      #expect(model.rows.isEmpty)
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

  @Test func recipeReturnOpensLiveRecipeReviewThenClaimsItsFile() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let recipeID = UUID()
    let envelope = ChatAccessStagedRecipeReturn(recipeID: recipeID, recipeTitle: "Soup", text: "YC-REVISION:\nToast the spices")
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    let url = folder.inboxURL.appending(path: "20261110T120000Z-\(recipeID.uuidString).ycrecipereturn")
    let coordinator = HandoffReviewCoordinator()
    let recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = coordinator
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Soup", dateCreated: .now, dateModified: .now) }.execute(db)
      }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      let row = try #require(model.recipeReturnRows.first)
      #expect(row.title == "Changes · Soup")
      await model.open(row)
      guard case .recipeAdjustmentBrief = coordinator.review else { Issue.record("Expected the recipe revision review"); return }
      #expect(model.recipeReturnRows.isEmpty)
      #expect(await recorder.urls == [url])
      #expect(try await database.read { db in try AIHandoff.fetchAll(db).count } == 1)
    }
  }

  @Test func menuReviewCreatesAndClaimsOneMenuWithKeptItems() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let recipeID = UUID()
    let envelope = ChatAccessStagedMenu(title: "Sunday Supper", dayCount: 2, items: [
      .init(recipeID: recipeID, title: "Beans", dayOffset: 0, slot: .dinner, note: "Warm gently", scale: 2),
      .init(recipeID: nil, title: "Green salad", dayOffset: 1, slot: .lunch, note: "Dress late", scale: nil),
    ])
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    let url = folder.inboxURL.appending(path: "20261110T120000Z-sunday-supper.ycmenu")
    let recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: .now, dateModified: .now) }.execute(db)
      }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      let row = try #require(model.menuRows.first)
      #expect(row.title == "Menu · Sunday Supper")
      await model.open(row)
      let review = try #require(model.menuReview)
      review.setKept(false, at: 1)
      var selectedMenuID: UUID?
      model.onMenuSelected = { selectedMenuID = $0 }
      await model.createMenu(from: review)
      #expect(model.menuReview == nil)
      #expect(await recorder.urls == [url])
      #expect(selectedMenuID != nil)
      let rows = try await database.read { db in try MenuItem.fetchAll(db) }
      #expect(rows.count == 1)
      #expect(rows.first?.kind == .recipe)
      #expect(rows.first?.recipeID == recipeID)
      #expect(rows.first?.scale == 2)
    }
  }

  @Test func menuDayReviewAppliesReplacementThenClaimsTheStagedFile() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let recipeID = UUID()
    let menuID = UUID()
    let envelope = ChatAccessStagedMenuDay(menuID: menuID, menuTitle: "Thanksgiving Week", dayOffset: 0, items: [
      .init(recipeID: recipeID, title: "Beans", dayOffset: 0, slot: .dinner, note: "Serve separately", scale: nil),
    ], dayAtStage: [
      .init(kind: .recipe, title: "Beans", recipeID: recipeID, slot: .dinner, note: nil, scale: 1),
    ])
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    let url = folder.inboxURL.appending(path: "20261110T120000Z-week-day-1.ycmenuday")
    let recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = now
      $0.uuid = .incrementing
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let liveID = try await database.write { db -> UUID in
        try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
        _ = try MenuRepository.addMenu(title: "Thanksgiving Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
        return try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let row = try #require(ChatAccessInbox.menuDayRows(from: [
        .init(url: url, name: url.lastPathComponent, isCurrent: true, menuTitle: envelope.menuTitle, menuDayMenuID: menuID, menuDayOffset: 0),
      ], resolve: { _, _ in (true, nil) }).first)
      await model.open(row)
      let review = try #require(model.menuDayReview)
      review.setKept(false, at: 0)
      review.setKept(true, at: 0)
      await model.applyMenuDay(from: review)
      #expect(model.menuDayReview == nil)
      #expect(await recorder.urls == [url])
      #expect(try await database.read { db in try MenuItem.find(liveID).fetchOne(db) }?.notes == "Serve separately")
    }
  }

  @Test func prepPlanReviewAppliesAndClaimsTheStagedFile() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let now = Date(timeIntervalSince1970: 1_800_000_000), recipeID = UUID(), menuID = UUID()
    let envelope = ChatAccessStagedPrepPlan(menuID: menuID, menuTitle: "Week", dishes: [
      .init(dayOffset: 0, recipeID: recipeID, title: "Beans", steps: [.init(workDayOffset: -1, session: "Day before", task: "Toast spices")]),
    ], planAtStage: [])
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    let url = folder.inboxURL.appending(path: "20261110T120000Z-week.ycprepplan"), recorder = InboxClaims()
    try await withDependencies {
      try $0.bootstrapDatabase(); $0.date.now = now; $0.uuid = .incrementing
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" }, claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      let dishID = try await database.write { db -> UUID in
        try Recipe.insert { Recipe(id: recipeID, title: "Beans", dateCreated: now, dateModified: now) }.execute(db)
        _ = try MenuRepository.addMenu(title: "Week", notes: nil, dayCount: 2, in: db, now: now, uuid: { menuID })
        return try MenuRepository.addRecipeItem(menuID: menuID, recipeID: recipeID, dayOffset: 0, mealSlot: .dinner, notes: nil, in: db, now: now, uuid: { UUID() })
      }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      let row = try #require(ChatAccessInbox.prepPlanRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true, menuTitle: "Week", prepPlanMenuID: menuID)], resolve: { _ in true }).first)
      await model.open(row)
      let review = try #require(model.prepPlanReview)
      model.onMenuSelected = { _ in }
      await model.applyPrepPlan(from: review)
      #expect(model.prepPlanReview == nil)
      #expect(await recorder.urls == [url])
      let steps = try await database.read { db in try PrepPlanStepRepository.steps(for: menuID, in: db) }
      #expect(steps.count == 1)
      #expect(steps.first?.sourceDish == dishID)
      #expect(steps.first?.task == "Toast spices")
    }
  }

  @Test func archivedRecipeReturnStaysUnclaimedUntilDiscarded() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let recipeID = UUID(), recorder = InboxClaims()
    let envelope = ChatAccessStagedRecipeReturn(recipeID: recipeID, recipeTitle: "Old Soup", text: "YC-REVISION:\nToast it")
    let text = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    let url = folder.inboxURL.appending(path: "20261110T120000Z-\(recipeID.uuidString).ycrecipereturn")
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, url in await recorder.add(url) }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      try await database.write { db in
        try Recipe.insert { Recipe(id: recipeID, title: "Old Soup", archived: true, dateCreated: .now, dateModified: .now) }.execute(db)
      }
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      let row = try #require(model.recipeReturnRows.first)
      #expect(row.title == "Recipe not found on this device")
      await model.open(row)
      #expect(await recorder.urls.isEmpty)
      #expect(model.recipeReturnRows.count == 1)
      await model.discard(row)
      #expect(await recorder.urls == [url])
      #expect(model.recipeReturnRows.isEmpty)
    }
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

  @Test func dayScopedComplementReturnStaysOnItsDay() async throws {
    let (folder, defaults, suiteName, temporary) = try fixture()
    defer { defaults.removePersistentDomain(forName: suiteName); try? FileManager.default.removeItem(at: temporary) }
    let handoffID = UUID(), menuID = UUID()
    let text = "YC-HANDOFF: \(handoffID.uuidString)\nNote: Charred cucumber salad\nDay 1 - Dinner"
    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = Date(timeIntervalSince1970: 1_800_000_000)
      $0.uuid = .incrementing
      $0.handoffReviewCoordinator = HandoffReviewCoordinator()
      $0.chatAccessInboxFileClient = .init(read: { _ in text }, openAndClaim: { _, _ in "" },
        claim: { _, _ in }, maintain: { _, _, _ in })
    } operation: {
      @Dependency(\.defaultDatabase) var database
      @Dependency(\.handoffReviewCoordinator) var coordinator
      try await database.write { db in
        try Menu.insert { Menu(id: menuID, title: "Dinner", dayCount: 3, dateCreated: .now, dateModified: .now) }.execute(db)
        try AIHandoffRepository.create(AIHandoff(id: handoffID, sourceType: .menu, sourceID: menuID,
          taskType: .menuComplement, dayOffset: 2, createdAt: .now, exportedPrompt: "Complement: Dinner, Day 3"), in: db)
      }
      let url = folder.inboxURL.appending(path: "20261022T180000Z-\(handoffID.uuidString).ycreturn")
      let model = ChatAccessInboxModel(folder: folder, defaults: defaults)
      await model.updateReturnRows(from: [.init(url: url, name: url.lastPathComponent, isCurrent: true)])
      await model.open(try #require(model.returnRows.first))
      guard case let .menuComplement(review) = coordinator.review else {
        Issue.record("expected a menu complement review")
        return
      }
      #expect(review.plan.items.map(\.dayOffset) == [2])
    }
  }

  private func fixture() throws -> (ChatAccessFolder, UserDefaults, String, URL) {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let suiteName = "ChatAccessInboxModelTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return (ChatAccessFolder(containerURL: temporary, isDevelopment: false), defaults, suiteName, temporary)
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
