#if DEBUG
// ADR-0071 S0 spike, DEBUG-only; S3/S4 replace it.
import CloudKit
import CryptoKit
import Dependencies
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
  @ObservationIgnored @Dependency(\.defaultDatabase) private var libraryDatabase
  @ObservationIgnored private let container = CKContainer(identifier: CookbookSpikeConfiguration.containerIdentifier)
  @ObservationIgnored private let defaults: UserDefaults

  var publishCount = 2000
  private(set) var logLines: [String]
  private(set) var isWorking = false
  private(set) var share: CKShare?
  private(set) var sharePresentationRequest = 0
  var errorMessage: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    logLines = CookbookSpikeLog.lines(defaults: defaults)
  }

  var shareContainer: CKContainer { container }

  func refreshLog() {
    logLines = CookbookSpikeLog.lines(defaults: defaults)
  }

  func createShareButtonTapped() {
    run("Create Share") { try await self.createShare() }
  }

  func publishButtonTapped() {
    let count = max(0, publishCount)
    run("Publish \(count)") { try await self.publish(count: count) }
  }

  func republishOneButtonTapped() {
    run("Republish One") { try await self.republishOne() }
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

  private func createShare() async throws {
    let database = container.privateCloudDatabase
    let zone: CKRecordZone
    do {
      zone = try await database.recordZone(for: CookbookSpikeConfiguration.zoneID)
    } catch let error as CKError where error.code == .zoneNotFound {
      zone = try await database.save(CKRecordZone(zoneID: CookbookSpikeConfiguration.zoneID))
    }

    let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)
    let record: CKRecord
    do {
      record = try await database.record(for: shareRecordID)
    } catch let error as CKError where error.code == .unknownItem {
      let newShare = CKShare(recordZoneID: zone.zoneID)
      newShare[CKShare.SystemFieldKey.title] = "\(UIDevice.current.name)'s Recipes" as CKRecordValue
      newShare.publicPermission = .none
      record = try await database.save(newShare)
    }
    guard let share = record as? CKShare else {
      throw CookbookSpikeError.unexpectedShareRecord
    }
    self.share = share
    sharePresentationRequest += 1
    let participantSummary = share.participants.map { participant in
      "\(participant.role): \(participant.permission) (\(participant.acceptanceStatus))"
    }.joined(separator: ", ")
    appendLog("Share ready for zone \(zone.zoneID.zoneName); participants: \(participantSummary.isEmpty ? "none" : participantSummary)")
  }

  private func publish(count: Int) async throws {
    let publishStartedAt = Date.now
    let generatedAt = Date.now
    let deviceName = UIDevice.current.name
    let export = try await libraryDatabase.read { db in
      try ChatAccessExportBuilder.build(in: db, generatedAt: generatedAt, device: deviceName)
    }
    guard !export.recipes.isEmpty || count == 0 else { throw CookbookSpikeError.noRecipes }

    var records: [CKRecord] = []
    records.reserveCapacity(count + 1)
    defer {
      for record in records {
        if let asset = record["payload"] as? CKAsset, let fileURL = asset.fileURL {
          try? FileManager.default.removeItem(at: fileURL)
        }
      }
    }
    for index in 0..<count {
      let bundle = export.recipes[index % export.recipes.count]
      let suffix = index < export.recipes.count ? "" : "-\(index / export.recipes.count + 1)"
      let recordID = CKRecord.ID(recordName: "\(bundle.recipe.id.uuidString)\(suffix)", zoneID: CookbookSpikeConfiguration.zoneID)
      records.append(try makeRecipeRecord(bundle, recordID: recordID))
    }

    let profile = CKRecord(
      recordType: "CookbookProfile",
      recordID: CKRecord.ID(recordName: "profile", zoneID: CookbookSpikeConfiguration.zoneID)
    )
    profile["displayName"] = UIDevice.current.name as CKRecordValue
    profile["recipeCount"] = count as CKRecordValue
    records.append(profile)

    let database = container.privateCloudDatabase
    for (batchIndex, start) in stride(from: 0, to: records.count, by: 400).enumerated() {
      let batch = Array(records[start..<min(start + 400, records.count)])
      let startedAt = Date.now
      do {
        let result = try await database.modifyRecords(
          saving: batch,
          deleting: [],
          savePolicy: .changedKeys,
          atomically: false
        )
        for saveResult in result.saveResults.values {
          if case let .failure(error) = saveResult { throw error }
        }
      } catch {
        appendLog("Batch \(batchIndex + 1) failed after \(Self.duration(Date.now.timeIntervalSince(startedAt))): \(Self.describe(error))")
        throw error
      }
      let duration = Date.now.timeIntervalSince(startedAt)
      appendLog("Batch \(batchIndex + 1): saved \(batch.count) records in \(Self.duration(duration))")
    }
    appendLog("Publish complete: \(count) recipes + profile in \(Self.duration(Date.now.timeIntervalSince(publishStartedAt))); source library has \(export.recipes.count) recipes")
  }

  private func makeRecipeRecord(_ bundle: RecipeBundleCoding.RecipeBundle, recordID: CKRecord.ID) throws -> CKRecord {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(bundle)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("cookbook-\(UUID().uuidString).json")
    try data.write(to: fileURL, options: .atomic)
    let record = CKRecord(recordType: "CookbookRecipe", recordID: recordID)
    record["payload"] = CKAsset(fileURL: fileURL)
    record["contentHash"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as CKRecordValue
    return record
  }

  private func republishOne() async throws {
    let database = container.privateCloudDatabase
    let zones = try await database.allRecordZones()
    guard let zone = zones.first(where: { $0.zoneID.zoneName == CookbookSpikeConfiguration.zoneName }) else {
      throw CookbookSpikeError.cookbookZoneMissing
    }
    let records = try await database.records(
      matching: CKQuery(recordType: "CookbookRecipe", predicate: NSPredicate(value: true)),
      inZoneWith: zone.zoneID,
      desiredKeys: ["payload"],
      resultsLimit: 1
    )
    guard let match = records.matchResults.first, case let .success(record) = match.1,
          let asset = record["payload"] as? CKAsset, let fileURL = asset.fileURL else {
      throw CookbookSpikeError.noPublishedRecipes
    }
    var bundle = try JSONDecoder().decode(RecipeBundleCoding.RecipeBundle.self, from: Data(contentsOf: fileURL))
    bundle.recipe.title += " [Republished]"
    let updated = try makeRecipeRecord(bundle, recordID: record.recordID)
    _ = try await database.modifyRecords(saving: [updated], deleting: [], savePolicy: .changedKeys, atomically: true)
    appendLog("Republished \(record.recordID.recordName) with updated title and content hash")
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
          desiredKeys: [],
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
    share = nil
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
  case unexpectedShareRecord
  case noRecipes
  case cookbookZoneMissing
  case noPublishedRecipes
  case noSharedZones

  var errorDescription: String? {
    switch self {
    case .unexpectedShareRecord: "CloudKit returned a record that wasn't a share."
    case .noRecipes: "The library has no recipes to publish."
    case .cookbookZoneMissing: "Create the Cookbook share before publishing."
    case .noPublishedRecipes: "The Cookbook zone has no recipe record to republish."
    case .noSharedZones: "Accept a cookbook share before trying a write."
    }
  }
}

struct CookbookSpikeView: View {
  @State private var model = CookbookSpikeModel()
  @State private var isShowingShareController = false
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Form {
      Section("Share") {
        Button("Create Share") { model.createShareButtonTapped() }
        if model.share != nil {
          Button("Show Participants") { isShowingShareController = true }
        }
      }
      Section("Publish") {
        TextField("Recipe count", value: $model.publishCount, format: .number)
          .keyboardType(.numberPad)
        Button("Publish N") { model.publishButtonTapped() }
        Button("Republish One") { model.republishOneButtonTapped() }
      }
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
    .onChange(of: model.sharePresentationRequest) { _, _ in
      isShowingShareController = true
    }
    .sheet(isPresented: $isShowingShareController) {
      if let share = model.share {
        CookbookSharingController(share: share, container: model.shareContainer)
      }
    }
  }
}

private struct CookbookSharingController: UIViewControllerRepresentable {
  let share: CKShare
  let container: CKContainer

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIViewController(context: Context) -> UICloudSharingController {
    let controller = UICloudSharingController(share: share, container: container)
    controller.availablePermissions = [.allowPrivate, .allowReadOnly]
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

  final class Coordinator: NSObject, UICloudSharingControllerDelegate {
    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
      CookbookSpikeLog.append("Sharing controller failed: \(CookbookSpikeModel.describeForDelegate(error))")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
      "\(UIDevice.current.name)'s Recipes"
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
