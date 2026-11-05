import ChatAccessKit
import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import UIKit
import YesChefCore

@Observable
@MainActor
final class ChatAccessInboxModel {
  static let probeCleanupDefaultsKey = "chatAccessProbeCleanupCompleted"

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessFolderClient) private var folderClient
  @ObservationIgnored @Dependency(\.chatAccessInboxFileClient) private var fileClient
  @ObservationIgnored @Dependency(\.createRecipeCoordinator) private var createRecipeCoordinator
  @ObservationIgnored @Dependency(\.handoffReviewCoordinator) private var handoffReviewCoordinator
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored weak var toastCenter: AppToastCenter?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var watcher: ChatInboxWatcher?
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var latestSnapshots: [ChatInboxSnapshot] = []
  @ObservationIgnored private var isPreparing = false
  @ObservationIgnored private var recipeNamesByID: [String: String] = [:]
  @ObservationIgnored private var nameReadIDs: Set<String> = []
  @ObservationIgnored private var nameReadsInProgress: Set<String> = []
  @ObservationIgnored private var metadataGeneration = 0

  private(set) var folder: ChatAccessFolder?
  private(set) var rows: [ChatAccessInbox.Row] = []
  private(set) var returnRows: [ChatAccessInbox.ReturnRow] = []
  private(set) var rowErrors: [String: String] = [:]
  private(set) var workingIDs: Set<String> = []
  private(set) var message: String?

  var inboxCount: Int { rows.count + returnRows.filter { if case .openable = $0.destination { true } else { false } }.count }

  init(folder: ChatAccessFolder? = nil, defaults: UserDefaults = .standard) {
    self.folder = folder
    self.defaults = defaults
  }

  func prepare() async {
    guard !isPreparing else { return }
    isPreparing = true
    defer { isPreparing = false }
    do {
      let folder = try await resolveFolderIfNeeded()
      let shouldRemoveProbe = !defaults.bool(forKey: Self.probeCleanupDefaultsKey)
      try await fileClient.maintain(folder, now, shouldRemoveProbe)
      if shouldRemoveProbe {
        defaults.set(true, forKey: Self.probeCleanupDefaultsKey)
      }
      startWatcher(for: folder)
      message = nil
    } catch {
      message = error.localizedDescription
    }
  }

  func open(_ row: ChatAccessInbox.Row) async {
    guard row.downloadState == .current,
      let folder,
      !workingIDs.contains(row.id)
    else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      let text = try await fileClient.openAndClaim(folder, row.url)
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
      await createRecipeCoordinator.stage(text: text)
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  func discard(_ row: ChatAccessInbox.Row) async {
    guard let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      try await fileClient.claim(folder, row.url)
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  func open(_ row: ChatAccessInbox.ReturnRow) async {
    guard case let .openable(handoff) = row.destination, row.downloadState == .current,
      let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      let text = try await fileClient.read(row.url)
      let staged = try await HandoffAppOperations.stageReview(
        handoffID: handoff.id, result: text, in: database, now: now, allowRestage: true
      )
      let hasMarker = text.components(separatedBy: .newlines).contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("YC-CONTRACT:") }
      let result = AIHandoffReviewResult(review: staged.review, warning: hasMarker ? staged.warning : nil)
      await handoffReviewCoordinator.presentStaged(result, toastCenter: toastCenter)
      if case .recipeNew = staged.review { toastCenter?.postSuccess("New recipe sent to Create Recipe.") }
      try await claim(row, in: folder)
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      returnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  func discard(_ row: ChatAccessInbox.ReturnRow) async {
    guard case .openable = row.destination, let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      try await claim(row, in: folder)
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      returnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  func copy(_ row: ChatAccessInbox.ReturnRow) async {
    guard row.downloadState == .current, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      UIPasteboard.general.string = try await fileClient.read(row.url)
      rowErrors[row.id] = nil
      toastCenter?.postSuccess("Return copied.")
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  private func claim(_ row: ChatAccessInbox.ReturnRow, in folder: ChatAccessFolder) async throws {
    for url in [row.url] + row.superseded {
      do { try await fileClient.claim(folder, url) }
      catch HandoffInboxError.alreadyClaimed { continue }
    }
    metadataGeneration += 1
    returnRows.removeAll { $0.id == row.id }
    rowErrors[row.id] = nil
  }

  private func rebuildRows() {
    let snapshots = latestSnapshots.map { snapshot in
      if !snapshot.isCurrent { rowErrors[snapshot.url.path] = snapshot.downloadError }
      return ChatAccessInbox.MetadataSnapshot(url: snapshot.url, name: snapshot.name,
        isCurrent: snapshot.isCurrent, recipeName: recipeNamesByID[snapshot.url.path])
    }
    updateRows(from: snapshots)
    metadataGeneration += 1
    let generation = metadataGeneration
    Task { await updateReturnRows(from: snapshots, generation: generation) }
    loadNames(for: snapshots)
  }

  func updateRows(from snapshots: [ChatAccessInbox.MetadataSnapshot]) {
    rows = ChatAccessInbox.rows(from: snapshots)
    let visibleIDs = Set(rows.map(\.id) + returnRows.map(\.id))
    rowErrors = rowErrors.filter { visibleIDs.contains($0.key) }
  }

  func updateReturnRows(from snapshots: [ChatAccessInbox.MetadataSnapshot], generation: Int? = nil) async {
    do {
      let ids = Set(snapshots.compactMap { snapshot -> UUID? in
        guard snapshot.url.pathExtension == "ycreturn", let staged = StagedHandoff(url: snapshot.url) else { return nil }
        return UUID(uuidString: staged.slug)
      })
      let handoffs = try await database.read { db in
        try ids.compactMap { try AIHandoffRepository.handoff(id: $0, in: db) }
      }
      guard generation == nil || generation == metadataGeneration else { return }
      let lookup = Dictionary(uniqueKeysWithValues: handoffs.map { ($0.id, $0) })
      returnRows = ChatAccessInbox.returnRows(from: snapshots) { lookup[$0] }
    } catch {
      message = error.localizedDescription
    }
  }

  private func loadNames(for snapshots: [ChatAccessInbox.MetadataSnapshot]) {
    for snapshot in snapshots where snapshot.isCurrent && snapshot.url.pathExtension == "json" {
      let id = snapshot.url.path
      guard !nameReadIDs.contains(id), nameReadsInProgress.insert(id).inserted else { continue }
      Task { await loadName(for: snapshot.url, id: id) }
    }
  }

  private func loadName(for url: URL, id: String) async {
    defer { nameReadsInProgress.remove(id) }
    do {
      let text = try await fileClient.read(url)
      nameReadIDs.insert(id)
      if let name = ChatAccessInbox.recipeName(from: text) {
        recipeNamesByID[id] = name
      }
      rebuildRows()
    } catch {
      // Keep the slug-derived label. A later metadata update can retry the coordinated read.
    }
  }

  private func resolveFolderIfNeeded() async throws -> ChatAccessFolder {
    if let folder { return folder }
    let folder = try await folderClient.resolveAndCreateInbox()
    self.folder = folder
    return folder
  }

  private func startWatcher(for folder: ChatAccessFolder) {
    if watcher == nil {
      let watcher = ChatInboxWatcher(folder: folder)
      self.watcher = watcher
      watcherTask = Task { [weak self] in
        for await snapshots in watcher.snapshots {
          guard let self else { return }
          self.latestSnapshots = snapshots
          self.rebuildRows()
        }
      }
    }
    watcher?.start()
  }
}
