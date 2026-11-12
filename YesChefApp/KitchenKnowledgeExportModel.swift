import Dependencies
import Foundation
import Observation
import YesChefCore

@Observable
@MainActor
final class KitchenKnowledgeExportModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  private(set) var fileURL: URL?
  private(set) var export: KitchenKnowledgeExport?
  private(set) var isExporting = false
  var errorMessage: String?

  func exportWhatIveTaught() async {
    guard !isExporting else { return }
    isExporting = true
    errorMessage = nil
    defer { isExporting = false }
    do {
      let exportedAt = now
      #if DEBUG
      let variant: KitchenKnowledgeExport.Variant = .dev
      #else
      let variant: KitchenKnowledgeExport.Variant = .production
      #endif
      // Dev builds hold CloudKit Development test data, so they write beside the folder
      // scripts/promote-knowledge reads, never into it (the same split as MCP / MCP-Dev).
      let folderName = variant == .dev ? "Knowledge-Dev" : "Knowledge"
      let fileName = "YesChef-Knowledge-\(uuid().uuidString).json"
      let export = try await database.read { db in
        try KitchenKnowledgeExport.build(in: db, exportedAt: exportedAt, variant: variant)
      }
      let data = try export.encoded()
      // Resolving the ubiquity container can block, so it stays off the main actor.
      let url = try await Task.detached(priority: .utility) {
        guard let container = FileManager.default.url(
          forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef"
        ) else { throw ExportError.iCloudUnavailable }
        let directory = container
          .appending(path: "Documents", directoryHint: .isDirectory)
          .appending(path: folderName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName)
        try data.write(to: url, options: .atomic)
        return url
      }.value
      self.export = export
      fileURL = url
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private enum ExportError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? {
      "The Yes Chef iCloud Drive container is unavailable. Check that iCloud Drive is enabled."
    }
  }
}
