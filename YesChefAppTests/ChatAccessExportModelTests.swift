import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@Suite(.serialized)
@MainActor
struct ChatAccessExportModelTests {
  @Test func refreshWritesThroughInjectedFolderResolution() async throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let folder = ChatAccessFolder(containerURL: temporary)
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
