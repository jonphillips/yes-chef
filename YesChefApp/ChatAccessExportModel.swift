import Dependencies
import Foundation
import Observation
import UIKit
import YesChefCore

@Observable
@MainActor
final class ChatAccessExportModel {
  private static let installationIDKey = "chatAccessInstallationID"
  private static let lastExportDateKey = "chatAccessLastExportDate"
  private static let lastExportSizeKey = "chatAccessLastExportSize"

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored private let defaults: UserDefaults

  private(set) var lastExportDate: Date?
  private(set) var lastExportSize: Int?
  private(set) var isRefreshing = false
  var errorMessage: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.lastExportDate = defaults.object(forKey: Self.lastExportDateKey) as? Date
    self.lastExportSize = defaults.object(forKey: Self.lastExportSizeKey) as? Int
  }

  func exportIfDue() async {
    if let lastExportDate, now.timeIntervalSince(lastExportDate) < 15 * 60 { return }
    await refresh()
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    errorMessage = nil
    let taskID = UIApplication.shared.beginBackgroundTask(withName: "YesChefChatAccessExport")
    defer {
      UIApplication.shared.endBackgroundTask(taskID)
      isRefreshing = false
    }

    do {
      guard let container = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef") else {
        throw ExportError.containerUnavailable
      }
      let generatedAt = now
      let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
      var installationID = defaults.string(forKey: Self.installationIDKey)
      if installationID == nil {
        installationID = uuid().uuidString
        defaults.set(installationID, forKey: Self.installationIDKey)
      }
      guard let installationID else { throw ExportError.containerUnavailable }
      let export = try await database.read { db in
        try ChatAccessExportBuilder.build(in: db, generatedAt: generatedAt, device: device)
      }
      let data = try await Task.detached(priority: .utility) {
        try ChatAccessExportCoding.encode(export)
      }.value
      let destination = ChatAccessFolder(containerURL: container).exportsURL
        .appending(path: "\(installationID).json")
      try await Task.detached(priority: .utility) {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
          do { try data.write(to: coordinatedURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
      }.value
      lastExportDate = generatedAt
      lastExportSize = data.count
      defaults.set(generatedAt, forKey: Self.lastExportDateKey)
      defaults.set(data.count, forKey: Self.lastExportSizeKey)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private enum ExportError: LocalizedError {
    case containerUnavailable
    var errorDescription: String? { "The Yes Chef iCloud Drive container is unavailable. Check that this device is signed in to iCloud and iCloud Drive is enabled." }
  }
}
