import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import YesChefCore

@Observable
@MainActor
final class ChatAccessInboxModel {
  static let probeCleanupDefaultsKey = "chatAccessProbeCleanupCompleted"

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessFolderClient) private var folderClient
  @ObservationIgnored @Dependency(\.chatAccessInboxFileClient) private var fileClient
  @ObservationIgnored @Dependency(\.createRecipeCoordinator) private var createRecipeCoordinator
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var query: NSMetadataQuery?
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var isPreparing = false
  @ObservationIgnored private var recipeNamesByID: [String: String] = [:]
  @ObservationIgnored private var nameReadIDs: Set<String> = []
  @ObservationIgnored private var nameReadsInProgress: Set<String> = []

  private(set) var folder: ChatAccessFolder?
  private(set) var rows: [ChatAccessInbox.Row] = []
  private(set) var rowErrors: [String: String] = [:]
  private(set) var workingIDs: Set<String> = []
  private(set) var message: String?

  var inboxCount: Int { rows.count }

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
      startQueryIfNeeded(for: folder)
      metadataQueryDidChange()
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

  func metadataQueryDidChange() {
    guard let query, let folder else { return }
    query.disableUpdates()
    defer { query.enableUpdates() }

    let snapshots = query.results.compactMap { value -> ChatAccessInbox.MetadataSnapshot? in
      guard let item = value as? NSMetadataItem,
        let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
      else { return nil }
      let url = URL(fileURLWithPath: path)
      guard url.deletingLastPathComponent().standardizedFileURL == folder.inboxURL.standardizedFileURL else { return nil }
      let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
      guard name != "Processed" else { return nil }
      let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
      let isCurrent = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
      if !isCurrent {
        do {
          try FileManager.default.startDownloadingUbiquitousItem(at: url)
          rowErrors[url.path] = nil
        } catch {
          rowErrors[url.path] = error.localizedDescription
        }
      }
      return ChatAccessInbox.MetadataSnapshot(
        url: url,
        name: name,
        isCurrent: isCurrent,
        recipeName: recipeNamesByID[url.path]
      )
    }
    updateRows(from: snapshots)
    loadNames(for: snapshots)
  }

  func updateRows(from snapshots: [ChatAccessInbox.MetadataSnapshot]) {
    rows = ChatAccessInbox.rows(from: snapshots)
    let visibleIDs = Set(rows.map(\.id))
    rowErrors = rowErrors.filter { visibleIDs.contains($0.key) }
  }

  private func loadNames(for snapshots: [ChatAccessInbox.MetadataSnapshot]) {
    for snapshot in snapshots where snapshot.isCurrent {
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
      metadataQueryDidChange()
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

  private func startQueryIfNeeded(for folder: ChatAccessFolder) {
    guard query == nil else { return }
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(
      format: "%K BEGINSWITH %@",
      NSMetadataItemPathKey,
      folder.inboxURL.path + "/"
    )
    query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: false)]
    self.query = query
    let center = NotificationCenter.default
    for name in [Notification.Name.NSMetadataQueryDidFinishGathering, Notification.Name.NSMetadataQueryDidUpdate] {
      observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.metadataQueryDidChange()
        }
      })
    }
    query.start()
  }
}
