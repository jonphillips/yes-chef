import ChatAccessKit
import Dependencies
import Foundation
import Observation
import UIKit
import YesChefCore

@Observable
@MainActor
final class ChatAccessExportModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessFolderClient) private var folderClient
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let writer: ChatAccessExportWriter

  private(set) var lastExportDate: Date?
  private(set) var lastExportSize: Int?
  private(set) var isRefreshing = false
  var errorMessage: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let makeUUID = DependencyValues._current.uuid
    let writer = ChatAccessExportWriter(defaults: defaults, makeUUID: { makeUUID() })
    self.writer = writer
    self.lastExportDate = writer.lastExport?.date
    self.lastExportSize = writer.lastExport?.size
  }

  func exportIfDue() async {
    guard writer.isDue(at: now) else { return }
    await refresh()
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    errorMessage = nil
    let backgroundTask = BackgroundTaskLease()
    backgroundTask.begin()
    defer {
      backgroundTask.end()
      isRefreshing = false
    }

    do {
      let folder = try await folderClient.resolveFolder()
      let generatedAt = now
      let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
      let export = try await database.read { db in
        try ChatAccessExportBuilder.build(in: db, generatedAt: generatedAt, device: device)
      }
      let data = try await Task.detached(priority: .utility) {
        try ChatAccessExportCoding.encode(export)
      }.value
      if case let .written(date, size) = try await writer.write(data, to: folder, generatedAt: generatedAt, force: true) {
        lastExportDate = date
        lastExportSize = size
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

}

@MainActor
private final class BackgroundTaskLease {
  private var identifier = UIBackgroundTaskIdentifier.invalid

  func begin() {
    identifier = UIApplication.shared.beginBackgroundTask(withName: "YesChefChatAccessExport") { [weak self] in
      Task { @MainActor in self?.end() }
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    let identifier = self.identifier
    self.identifier = .invalid
    UIApplication.shared.endBackgroundTask(identifier)
  }
}
