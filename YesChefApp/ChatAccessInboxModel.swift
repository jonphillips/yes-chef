import ChatAccessKit
import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import SQLiteData
import UIKit
import YesChefCore

@Observable
@MainActor
final class ChatAccessInboxModel {
  static let probeCleanupDefaultsKey = "chatAccessProbeCleanupCompleted"
  static let legacyDevExportCleanupDefaultsKey = "chatAccessLegacyDevExportCleanupCompleted"

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessFolderClient) private var folderClient
  @ObservationIgnored @Dependency(\.chatAccessInboxFileClient) private var fileClient
  @ObservationIgnored @Dependency(\.createRecipeCoordinator) private var createRecipeCoordinator
  @ObservationIgnored @Dependency(\.handoffReviewCoordinator) private var handoffReviewCoordinator
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored weak var toastCenter: AppToastCenter?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private(set) var watcher: ChatInboxWatcher?
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var latestSnapshots: [ChatInboxSnapshot] = []
  @ObservationIgnored private var claimedIDs: Set<String> = []
  @ObservationIgnored private var isPreparing = false
  @ObservationIgnored private var recipeNamesByID: [String: String] = [:]
  @ObservationIgnored private var menuTitlesByID: [String: String] = [:]
  @ObservationIgnored private var nameReadIDs: Set<String> = []
  @ObservationIgnored private var nameReadsInProgress: Set<String> = []
  @ObservationIgnored private var metadataGeneration = 0

  private(set) var folder: ChatAccessFolder?
  private(set) var rows: [ChatAccessInbox.Row] = []
  private(set) var returnRows: [ChatAccessInbox.ReturnRow] = []
  private(set) var recipeReturnRows: [ChatAccessInbox.RecipeReturnRow] = []
  private(set) var menuRows: [ChatAccessInbox.MenuRow] = []
  var menuReview: ChatMenuReviewModel?
  var onMenuSelected: ((Menu.ID) -> Void)?
  private(set) var rowErrors: [String: String] = [:]
  private(set) var workingIDs: Set<String> = []
  private(set) var message: String?

  var inboxCount: Int {
    rows.count + menuRows.count
      + returnRows.filter { if case .openable = $0.destination { true } else { false } }.count
      + recipeReturnRows.filter { if case .openable = $0.destination { true } else { false } }.count
  }

  init(folder: ChatAccessFolder? = nil, defaults: UserDefaults = .standard) {
    self.folder = folder
    self.defaults = defaults
  }

  isolated deinit {
    watcher?.stop()
    watcherTask?.cancel()
  }

  func prepare() async {
    guard !isPreparing else { return }
    isPreparing = true
    defer { isPreparing = false }
    do {
      let folder = try await resolveFolderIfNeeded()
      startWatcher(for: folder)
      message = nil
      let shouldRemoveProbe = !defaults.bool(forKey: Self.probeCleanupDefaultsKey)
      do {
        try await fileClient.maintain(folder, now, shouldRemoveProbe)
        if shouldRemoveProbe { defaults.set(true, forKey: Self.probeCleanupDefaultsKey) }
      } catch {
        message = error.localizedDescription
      }
      #if DEBUG
      if !defaults.bool(forKey: Self.legacyDevExportCleanupDefaultsKey) {
        do {
          if let id = defaults.string(forKey: ChatAccessExportWriter.installationIDKey) {
            try await fileClient.cleanupLegacyDevExport(folder, id)
          }
          defaults.set(true, forKey: Self.legacyDevExportCleanupDefaultsKey)
        } catch {
          message = error.localizedDescription
        }
      }
      #endif
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
      forget([row.url])
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
      await createRecipeCoordinator.stage(text: text)
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([row.url])
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
      forget([row.url])
      rows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([row.url])
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
      forget([row.url] + row.superseded)
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
      forget([row.url] + row.superseded)
      returnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch {
      rowErrors[row.id] = error.localizedDescription
    }
  }

  func open(_ row: ChatAccessInbox.RecipeReturnRow) async {
    guard case .openable = row.destination, row.downloadState == .current,
      let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      let text = try await fileClient.read(row.url)
      guard let data = text.data(using: .utf8) else { throw ChatInboxOpenError.invalidEncoding }
      let envelope = try JSONDecoder().decode(ChatAccessStagedRecipeReturn.self, from: data)
      let currentNow = now
      let generator = uuid
      let makeUUID: @Sendable () -> UUID = { generator() }
      let result = try await database.write { db -> AIHandoffReviewResult in
        let review = try ChatRecipeReturnImport.stageReview(envelope, in: db, now: currentNow, uuid: makeUUID)
        guard case .recipeItems = review else { throw ChatInboxOpenError.unexpectedRecipeReturn }
        return AIHandoffReviewResult(review: review, warning: nil)
      }
      await handoffReviewCoordinator.presentStaged(result, toastCenter: toastCenter)
      try await fileClient.claim(folder, row.url)
      forget([row.url])
      recipeReturnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([row.url])
      recipeReturnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch { rowErrors[row.id] = error.localizedDescription }
  }

  func discard(_ row: ChatAccessInbox.RecipeReturnRow) async {
    guard case .missing = row.destination, let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      try await fileClient.claim(folder, row.url)
      forget([row.url])
      recipeReturnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([row.url])
      recipeReturnRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch { rowErrors[row.id] = error.localizedDescription }
  }

  func open(_ row: ChatAccessInbox.MenuRow) async {
    guard row.downloadState == .current, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      let text = try await fileClient.read(row.url)
      guard let data = text.data(using: .utf8) else { throw ChatInboxOpenError.invalidEncoding }
      let envelope = try JSONDecoder().decode(ChatAccessStagedMenu.self, from: data)
      let items = try await database.read { db in try ChatMenuImport.resolve(envelope, in: db) }
      menuReview = ChatMenuReviewModel(row: row, title: envelope.title, dayCount: envelope.dayCount, items: items)
    } catch { rowErrors[row.id] = error.localizedDescription }
  }

  func discard(_ row: ChatAccessInbox.MenuRow) async {
    guard let folder, !workingIDs.contains(row.id) else { return }
    workingIDs.insert(row.id)
    defer { workingIDs.remove(row.id) }
    do {
      try await fileClient.claim(folder, row.url)
      forget([row.url])
      menuRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([row.url])
      menuRows.removeAll { $0.id == row.id }
      rowErrors[row.id] = nil
    } catch { rowErrors[row.id] = error.localizedDescription }
  }

  func createMenu(from review: ChatMenuReviewModel) async {
    guard let folder, !review.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      review.items.contains(where: \.isKept), !workingIDs.contains(review.row.id) else { return }
    workingIDs.insert(review.row.id)
    defer { workingIDs.remove(review.row.id) }
    do {
      let title = review.title
      let items = review.items
      let dayCount = review.dayCount
      let currentNow = now
      let generator = uuid
      let makeUUID: @Sendable () -> UUID = { generator() }
      let menuID = try await database.write { db in
        try ChatMenuImport.create(title: title, dayCount: dayCount, items: items, in: db, now: currentNow, uuid: makeUUID)
      }
      try await fileClient.claim(folder, review.row.url)
      forget([review.row.url])
      menuRows.removeAll { $0.id == review.row.id }
      rowErrors[review.row.id] = nil
      menuReview = nil
      toastCenter?.postSuccess("Menu created.")
      onMenuSelected?(menuID)
    } catch let error as HandoffInboxError where error == .alreadyClaimed {
      forget([review.row.url])
      menuRows.removeAll { $0.id == review.row.id }
      menuReview = nil
    } catch { rowErrors[review.row.id] = error.localizedDescription }
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
      catch HandoffInboxError.alreadyClaimed { }
      forget([url])
    }
    metadataGeneration += 1
    returnRows.removeAll { $0.id == row.id }
    rowErrors[row.id] = nil
  }

  private func forget(_ urls: [URL]) {
    let ids = Set(urls.map(\.path))
    claimedIDs.formUnion(ids)
    latestSnapshots.removeAll { ids.contains($0.url.path) }
    metadataGeneration += 1
  }

  func receiveSnapshots(_ snapshots: [ChatInboxSnapshot]) {
    claimedIDs.formIntersection(Set(snapshots.map { $0.url.path }))
    latestSnapshots = snapshots.filter { !claimedIDs.contains($0.url.path) }
    rebuildRows()
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
    let visibleIDs = Set(snapshots.map { $0.url.path } + returnRows.map(\.id) + recipeReturnRows.map(\.id) + menuRows.map(\.id))
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
      let recipeIDs = Set(snapshots.compactMap { snapshot -> UUID? in
        guard snapshot.url.pathExtension == "ycrecipereturn", let staged = StagedHandoff(url: snapshot.url) else { return nil }
        return UUID(uuidString: staged.slug)
      })
      let recipes = try await database.read { db in try recipeIDs.compactMap { try Recipe.find($0).fetchOne(db) } }
      let recipeLookup = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
      recipeReturnRows = ChatAccessInbox.recipeReturnRows(from: snapshots) { recipeLookup[$0] }
      menuRows = ChatAccessInbox.menuRows(from: snapshots.map {
        ChatAccessInbox.MetadataSnapshot(url: $0.url, name: $0.name, isCurrent: $0.isCurrent,
          recipeName: $0.recipeName, menuTitle: menuTitlesByID[$0.url.path])
      })
      updateRows(from: snapshots)
    } catch {
      message = error.localizedDescription
    }
  }

  private func loadNames(for snapshots: [ChatAccessInbox.MetadataSnapshot]) {
    for snapshot in snapshots where snapshot.isCurrent && ["json", "ycmenu"].contains(snapshot.url.pathExtension) {
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
      if url.pathExtension == "ycmenu" {
        if let name = ChatAccessInbox.menuTitle(from: text) { menuTitlesByID[id] = name }
      } else if let name = ChatAccessInbox.recipeName(from: text) {
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
          self.receiveSnapshots(snapshots)
        }
      }
    }
    watcher?.start()
  }
}

private enum ChatInboxOpenError: LocalizedError {
  case invalidEncoding
  case unexpectedRecipeReturn

  var errorDescription: String? {
    switch self {
    case .invalidEncoding: "The staged item is not valid UTF-8."
    case .unexpectedRecipeReturn: "The recipe return produced an unsupported review."
    }
  }
}
