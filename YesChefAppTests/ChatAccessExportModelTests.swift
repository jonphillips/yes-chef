import ChatAccessKit
import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct ChatAccessExportModelTests {
  @Test func exportIfDueChecksThrottleBeforeResolvingFolderAndExportsAtFifteenMinutes() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let folder = ChatAccessFolder(containerURL: temporary, isDevelopment: false)
    let suiteName = "ChatAccessExportModelTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let installationID = UUID()
    let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let seedWriter = ChatAccessExportWriter(defaults: defaults, makeUUID: { installationID })
    let previousData = Data("previous export".utf8)
    _ = try await seedWriter.write(previousData, to: folder, generatedAt: generatedAt.addingTimeInterval(-14 * 60), force: true)
    let exportURL = folder.exportsURL.appending(path: "\(installationID.uuidString).json")
    let resolver = FolderResolveCounter()
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: temporary)
    }

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = generatedAt
      $0.uuid = .incrementing
      $0.chatAccessFolderClient = ChatAccessFolderClient(
        resolveFolder: { await resolver.increment(); return folder },
        resolveAndCreateInbox: { folder }
      )
    } operation: {
      let model = ChatAccessExportModel(defaults: defaults)

      await model.exportIfDue()
      #expect(await resolver.count == 0)
      let unchangedData = try Data(contentsOf: exportURL)
      #expect(unchangedData == previousData)

      _ = try await seedWriter.write(previousData, to: folder, generatedAt: generatedAt.addingTimeInterval(-15 * 60), force: true)
      await model.exportIfDue()

      #expect(await resolver.count == 1)
      #expect(model.errorMessage == nil)
      #expect(model.lastExportDate == generatedAt)
      let writtenExport = try ChatAccessExportCoding.decode(Data(contentsOf: exportURL))
      #expect(writtenExport.generatedAt == generatedAt)
    }
  }

  @Test func refreshWritesThroughInjectedFolderResolution() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let folder = ChatAccessFolder(containerURL: temporary, isDevelopment: false)
    let suiteName = "ChatAccessExportModelTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: temporary)
    }
    let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)

    try await withDependencies {
      try $0.bootstrapDatabase()
      $0.date.now = generatedAt
      $0.uuid = .incrementing
      $0.chatAccessFolderClient = ChatAccessFolderClient(
        resolveFolder: { folder },
        resolveAndCreateInbox: { folder }
      )
    } operation: {
      let model = ChatAccessExportModel(defaults: defaults)
      await model.refresh()

      #expect(model.errorMessage == nil)
      #expect(model.lastExportDate == generatedAt)
      #expect(model.lastExportSize != nil)
      let files = try FileManager.default.contentsOfDirectory(at: folder.exportsURL, includingPropertiesForKeys: nil)
      let url = try #require(files.first)
      let data = try Data(contentsOf: url)
      let export = try ChatAccessExportCoding.decode(data)
      #expect(export.device == "iPhone" || export.device == "iPad")
    }
  }
}

private actor FolderResolveCounter {
  private(set) var count = 0
  func increment() { count += 1 }
}
