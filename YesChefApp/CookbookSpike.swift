#if DEBUG
// ADR-0071 S0 spike, DEBUG-only; S3/S4 replace it.
import CloudKit
import Foundation
import Observation
import SwiftUI
import UIKit
import YesChefCore

private enum CookbookSpikeConfiguration {
  static let containerIdentifier = "iCloud.com.jonphillips.yeschef.cookbook"
  static let zoneName = "Cookbook"
  static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
  static let tokenPrefix = "CookbookSpike.changeToken."
  static let logKey = "CookbookSpike.log"
}

private enum CookbookSpikeLog {
  static func append(_ message: String, defaults: UserDefaults = .standard) {
    var lines = defaults.stringArray(forKey: CookbookSpikeConfiguration.logKey) ?? []
    lines.append("\(Date.now.formatted(date: .abbreviated, time: .standard)) · \(message)")
    defaults.set(lines, forKey: CookbookSpikeConfiguration.logKey)
  }

  static func lines(defaults: UserDefaults = .standard) -> [String] {
    defaults.stringArray(forKey: CookbookSpikeConfiguration.logKey) ?? []
  }
}

@Observable
@MainActor
final class CookbookSpikeModel {
  @ObservationIgnored private let container = CKContainer(identifier: CookbookSpikeConfiguration.containerIdentifier)
  @ObservationIgnored private let defaults: UserDefaults

  private(set) var logLines: [String]
  private(set) var isWorking = false
  var errorMessage: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    logLines = CookbookSpikeLog.lines(defaults: defaults)
  }


  func refreshLog() {
    logLines = CookbookSpikeLog.lines(defaults: defaults)
  }

  func fetchChangesButtonTapped() {
    run("Fetch Changes") { try await self.fetchChanges() }
  }

  func resetTokenButtonTapped() {
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(CookbookSpikeConfiguration.tokenPrefix) {
      defaults.removeObject(forKey: key)
    }
    appendLog("Reset all shared-zone change tokens")
  }

  func tryToWriteButtonTapped() {
    run("Try to Write") { try await self.tryToWrite() }
  }

  func deleteCookbookButtonTapped() {
    run("Delete My Cookbook") { try await self.deleteCookbook() }
  }

  private func run(_ name: String, operation: @escaping () async throws -> Void) {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    Task { @MainActor in
      defer { isWorking = false }
      do {
        try await operation()
      } catch {
        let message = "\(name) failed: \(Self.describe(error))"
        appendLog(message)
        errorMessage = message
      }
    }
  }

  private func fetchChanges() async throws {
    let database = container.sharedCloudDatabase
    let zones = try await database.allRecordZones().filter { $0.zoneID.zoneName != CKRecordZone.default().zoneID.zoneName }
    guard !zones.isEmpty else {
      appendLog("No shared cookbook zones found")
      return
    }
    let startedAt = Date.now
    for zone in zones {
      var token = loadToken(for: zone.zoneID)
      var changed = 0
      var deleted = 0
      var moreComing = true
      let zoneStartedAt = Date.now
      while moreComing {
        let page = try await database.recordZoneChanges(
          inZoneWith: zone.zoneID,
          since: token,
          // All keys: a real viewer downloads each payload asset, so the timing must include it.
          desiredKeys: nil,
          resultsLimit: 400
        )
        for result in page.modificationResultsByID.values {
          if case let .failure(error) = result { throw error }
        }
        changed += page.modificationResultsByID.count
        deleted += page.deletions.count
        token = page.changeToken
        moreComing = page.moreComing
      }
      if let token { try saveToken(token, for: zone.zoneID) }
      appendLog("Zone \(zone.zoneID.zoneName): \(changed) changed, \(deleted) deleted in \(Self.duration(Date.now.timeIntervalSince(zoneStartedAt)))")
    }
    appendLog("Fetch complete in \(Self.duration(Date.now.timeIntervalSince(startedAt)))")
  }

  private func tryToWrite() async throws {
    let database = container.sharedCloudDatabase
    let zones = try await database.allRecordZones()
    guard let zone = zones.first(where: { $0.zoneID.zoneName != CKRecordZone.default().zoneID.zoneName }) else {
      throw CookbookSpikeError.noSharedZones
    }
    let record = CKRecord(recordType: "CookbookRecipe", recordID: CKRecord.ID(recordName: "write-test-\(UUID().uuidString)", zoneID: zone.zoneID))
    do {
      _ = try await database.save(record)
      appendLog("Try to Write unexpectedly succeeded")
    } catch let error as CKError where error.code == .permissionFailure {
      appendLog("Try to Write failed with the expected permission error: \(Self.describe(error))")
    } catch {
      let message = "Try to Write failed: \(Self.describe(error))"
      appendLog(message)
      throw error
    }
  }

  private func deleteCookbook() async throws {
    _ = try await container.privateCloudDatabase.deleteRecordZone(withID: CookbookSpikeConfiguration.zoneID)
    appendLog("Deleted the private Cookbook zone and its share")
  }

  private func loadToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
    let key = tokenKey(for: zoneID)
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
  }

  private func saveToken(_ token: CKServerChangeToken, for zoneID: CKRecordZone.ID) throws {
    let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    defaults.set(data, forKey: tokenKey(for: zoneID))
  }

  private func tokenKey(for zoneID: CKRecordZone.ID) -> String {
    "\(CookbookSpikeConfiguration.tokenPrefix)\(zoneID.ownerName).\(zoneID.zoneName)"
  }

  private func appendLog(_ message: String) {
    CookbookSpikeLog.append(message, defaults: defaults)
    refreshLog()
  }

  private static func describe(_ error: Error) -> String {
    if let error = error as? CKError { return "CKError \(error.code.rawValue) (\(error.code)): \(error.localizedDescription)" }
    return error.localizedDescription
  }

  static func describeForDelegate(_ error: Error) -> String { describe(error) }

  private static func duration(_ interval: TimeInterval) -> String {
    String(format: "%.2f s", interval)
  }
}

private enum CookbookSpikeError: LocalizedError {
  case noSharedZones

  var errorDescription: String? {
    switch self {
    case .noSharedZones: "Accept a cookbook share before trying a write."
    }
  }
}

struct CookbookSpikeView: View {
  @State private var model = CookbookSpikeModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Form {
      Section("Fetch") {
        Button("Fetch Changes") { model.fetchChangesButtonTapped() }
        Button("Reset Token") { model.resetTokenButtonTapped() }
        Button("Try to Write") { model.tryToWriteButtonTapped() }
      }
      Section("Reset") {
        Button("Delete My Cookbook", role: .destructive) { model.deleteCookbookButtonTapped() }
      }
      Section("Log") {
        if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
        Text(model.logLines.reversed().joined(separator: "\n"))
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
        Button {
          UIPasteboard.general.string = model.logLines.joined(separator: "\n")
        } label: {
          Label("Copy Log", systemImage: "doc.on.doc")
        }
      }
    }
    .navigationTitle("Cookbook Spike")
    .toolbar {
      if model.isWorking { ProgressView() }
    }
    .disabled(model.isWorking)
    .onAppear { model.refreshLog() }
    .task {
      for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
        model.refreshLog()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshLog() }
    }
  }
}

struct CookbookSharingController: UIViewControllerRepresentable {
  let share: CKShare
  let container: CKContainer

  func makeCoordinator() -> Coordinator {
    Coordinator(title: share[CKShare.SystemFieldKey.title] as? String)
  }

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.availablePermissions = [.allowPrivate, .allowReadOnly]
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    let title: String?

    init(title: String?) { self.title = title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
      CookbookSpikeLog.append("Sharing controller failed: \(CookbookSpikeModel.describeForDelegate(error))")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
      title
    }

    func cloudSharingController(_ csc: UICloudSharingController, share: CKShare, willSaveShareWithPreparationHandler handler: @escaping (CKShare?, (any Error)?) -> Void) {
      share.publicPermission = .none
      handler(share, nil)
    }

    func cloudSharingController(_ csc: UICloudSharingController, shouldPresentShare: CKShare) -> Bool { true }

    func cloudSharingController(_ csc: UICloudSharingController, didSaveShare share: CKShare) {
      CookbookSpikeLog.append("Share saved with \(share.participants.count) participant(s)")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
      CookbookSpikeLog.append("Sharing stopped")
    }

    func cloudSharingController(_ csc: UICloudSharingController, allowedSharingOptionsForShare share: CKShare) -> UICloudSharingController.PermissionOptions {
      [.allowPrivate, .allowReadOnly]
    }
  }
}

@MainActor
final class CookbookSpikeAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    configuration.delegateClass = CookbookSpikeSceneDelegate.self
    return configuration
  }
}

@MainActor
final class CookbookSpikeSceneDelegate: NSObject, UIWindowSceneDelegate {
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
  }

  func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
    accept(metadata)
  }

  private func accept(_ metadata: CKShare.Metadata) {
    guard metadata.containerIdentifier == CookbookSpikeConfiguration.containerIdentifier else {
      CookbookSpikeLog.append("Ignored share invitation for container \(metadata.containerIdentifier)")
      return
    }
    Task { @MainActor in
      do {
        _ = try await CKContainer(identifier: CookbookSpikeConfiguration.containerIdentifier).accept(metadata)
        CookbookSpikeLog.append("Accepted cookbook share for zone \(metadata.share.recordID.zoneID.zoneName)")
      } catch {
        CookbookSpikeLog.append("Share acceptance failed: \(CookbookSpikeModel.describeForDelegate(error))")
      }
    }
  }
}
#endif
