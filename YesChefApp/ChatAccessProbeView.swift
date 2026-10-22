import Foundation
import Observation
import SwiftUI
import UIKit
import YesChefCore

struct ChatAccessProbeView: View {
  @State private var model = ChatAccessProbeModel()

  var body: some View {
    List {
      Section {
        Button("Write Probe") {
          Task { await model.writeProbe(deviceName: UIDevice.current.name) }
        }
        .disabled(model.isWorking || model.folder == nil)

        Button("Write Large Probe (~10 MB)") {
          Task { await model.writeLargeProbe(deviceName: UIDevice.current.name) }
        }
        .disabled(model.isWorking || model.folder == nil)

        if model.isWorking { ProgressView() }
        if let message = model.message { Text(message).font(.footnote) }
      } header: {
        Text("iCloud Drive Transport")
      } footer: {
        Text("These temporary files test whether iCloud Drive carries small and large files between this device and the Mac helper.")
      }

      Section("Files") {
        if model.files.isEmpty {
          ContentUnavailableView("No Probe Files", systemImage: "icloud")
        } else {
          ForEach(model.files) { file in
            VStack(alignment: .leading, spacing: 4) {
              Text(file.name).font(.headline)
              Text("\(file.status) · first seen \(file.firstSeen.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
              if let contents = file.contents {
                Text(contents).font(.caption.monospaced()).textSelection(.enabled)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Chat Access Probe")
    .task { await model.prepare() }
    .onReceive(NotificationCenter.default.publisher(for: .NSMetadataQueryDidFinishGathering, object: model.query)) { _ in
      model.metadataQueryDidChange()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate, object: model.query)) { _ in
      model.metadataQueryDidChange()
    }
    .onDisappear { model.stopQuery() }
  }
}

@Observable @MainActor
private final class ChatAccessProbeModel {
  struct File: Identifiable {
    let url: URL
    let name: String
    let status: String
    let firstSeen: Date
    let contents: String?

    var id: String { url.path }
  }

  private(set) var folder: ChatAccessFolder?
  private(set) var files: [File] = []
  private(set) var message: String?
  private(set) var isWorking = false
  @ObservationIgnored private(set) var query: NSMetadataQuery?
  @ObservationIgnored private var firstSeenAt: [URL: Date] = [:]

  func prepare() async {
    if folder == nil {
      isWorking = true
      defer { isWorking = false }
      do {
        folder = try await ChatAccessFolderClient.resolveAndCreate()
      } catch {
        message = error.localizedDescription
      }
    }
    if folder != nil, query == nil {
      startQuery()
      message = "Watching \(folder?.probeURL.lastPathComponent ?? "Probe") for iCloud Drive files."
    }
  }

  func writeProbe(deviceName: String) async {
    await writeFile(prefix: "from", deviceName: deviceName, contents: "Device: \(deviceName)\nTime: \(Self.timestamp())\n")
  }

  func writeLargeProbe(deviceName: String) async {
    await writeFile(prefix: "large", deviceName: deviceName, contents: String(repeating: "Yes Chef iCloud Drive probe.\n", count: 390_000))
  }

  func metadataQueryDidChange() {
    guard let query else { return }
    query.disableUpdates()
    let items = query.results.compactMap { $0 as? NSMetadataItem }
    files = items.compactMap { item in
      guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
      let url = URL(fileURLWithPath: path)
      let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
      let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
      let isCurrent = downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent
      if !isCurrent { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
      let firstSeen = firstSeenAt[url] ?? Date()
      firstSeenAt[url] = firstSeen
      let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      let contents: String?
      if isCurrent, fileSize < 4_096 {
        contents = (try? Self.readText(at: url)).map { String($0.prefix(200)) }
      } else {
        contents = nil
      }
      return File(
        url: url,
        name: name,
        status: downloadStatus ?? "Status unknown",
        firstSeen: firstSeen,
        contents: contents
      )
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    query.enableUpdates()
  }

  func stopQuery() {
    query?.stop()
    query = nil
  }

  private func startQuery() {
    guard let folder else { return }
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, folder.probeURL.path + "/")
    query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
    self.query = query
    query.start()
  }

  private func writeFile(prefix: String, deviceName: String, contents: String) async {
    guard let folder else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let suffix = prefix == "large" ? "" : "-\(Self.filenameTimestamp(Date()))"
      let name = "\(prefix)-\(Self.safeFileComponent(deviceName))\(suffix).txt"
      let url = folder.probeURL.appending(path: name)
      try await Task.detached(priority: .utility) {
        try FileManager.default.createDirectory(at: folder.probeURL, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
      }.value
      message = "Wrote \(name)."
    } catch {
      message = "Couldn’t write the probe: \(error.localizedDescription)"
    }
  }

  private static func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }

  private static func filenameTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.formatOptions.remove(.withDashSeparatorInDate)
    formatter.formatOptions.remove(.withColonSeparatorInTime)
    return formatter.string(from: date)
  }

  private static func safeFileComponent(_ value: String) -> String {
    value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  }

  private static func readText(at url: URL) throws -> String {
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<String, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
      result = Result { try String(contentsOf: coordinatedURL, encoding: .utf8) }
    }
    if let coordinationError { throw coordinationError }
    return try result?.get() ?? ""
  }
}

private enum ChatAccessFolderClient {
  static func resolveAndCreate() async throws -> ChatAccessFolder {
    try await Task.detached(priority: .utility) {
      guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.jonphillips.yeschef") else {
        throw ChatAccessFolderClientError.containerUnavailable
      }
      // ADR-0059's development variant has not landed yet, so every current build uses MCP/.
      let folder = ChatAccessFolder(containerURL: containerURL)
      try FileManager.default.createDirectory(at: folder.probeURL, withIntermediateDirectories: true)
      return folder
    }.value
  }
}

private enum ChatAccessFolderClientError: LocalizedError {
  case containerUnavailable

  var errorDescription: String? {
    "The Yes Chef iCloud Drive container is unavailable. Check that this device is signed in to iCloud and iCloud Drive is enabled."
  }
}
