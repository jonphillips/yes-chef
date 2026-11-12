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
      guard let container = FileManager.default.url(
        forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef"
      ) else { throw ExportError.iCloudUnavailable }
      let exportedAt = now
      #if DEBUG
      let variant: KitchenKnowledgeExport.Variant = .dev
      #else
      let variant: KitchenKnowledgeExport.Variant = .production
      #endif
      let export = try await database.read { db in
        try KitchenKnowledgeExport.build(in: db, exportedAt: exportedAt, variant: variant)
      }
      let data = try export.encoded()
      let directory = container
        .appending(path: "Documents", directoryHint: .isDirectory)
        .appending(path: "Knowledge", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appending(path: "YesChef-Knowledge-\(uuid().uuidString).json")
      try data.write(to: url, options: .atomic)
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
