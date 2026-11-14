import CloudKit
import Dependencies
import GRDB
import Observation
import SQLiteData
import SwiftUI
import YesChefCore

@Observable
@MainActor
final class CookbookPublishModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var libraryDatabase
  @ObservationIgnored private let client: CookbookPublishClient
  @ObservationIgnored private var observation: AnyDatabaseCancellable?
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  @ObservationIgnored private var isCheckingZone = false
  @ObservationIgnored private var didCheckZone = false
  @ObservationIgnored private var needsFollowUp = false
  @ObservationIgnored private var lastRunFailed = false

  var displayName = ""
  private(set) var share: CKShare?
  private(set) var participants: [CookbookParticipantRow] = []
  private(set) var isPublishing = false
  private(set) var progressText: String?
  private(set) var errorMessage: String?
  private(set) var publishedProfile: CookbookPublishProfile?
  private(set) var sharePresentationRequest = 0
  private(set) var isSharing = false
  private(set) var lastCheckedAt: Date?

  init(client: CookbookPublishClient = CookbookCloudKitClientFactory.live()) {
    self.client = client
  }

  var shareContainer: CKContainer { CKContainer(identifier: CookbookCloudKitClientFactory.containerIdentifier) }
  var hasShare: Bool { share != nil }

  func start() {
    guard observation == nil else { return }
    let tables: [any DatabaseRegionConvertible] = [
      Table(Recipe.tableName), Table(RecipeSource.tableName), Table(IngredientSection.tableName),
      Table(IngredientLine.tableName), Table(InstructionSection.tableName), Table(InstructionStep.tableName),
      Table(RecipeNote.tableName), Table(RecipePhoto.tableName), Table(Category.tableName), Table(Facet.tableName),
      Table(RecipeCategory.tableName), Table(RecipeServeWith.tableName), Table(RecipeRelatedRecipe.tableName),
      Table(RecipeVariation.tableName),
    ]
    observation = DatabaseRegionObservation(tracking: tables).start(in: libraryDatabase) { [weak self] error in
      Task { @MainActor [weak self] in self?.errorMessage = "Cookbook library observation failed: \(error.localizedDescription)" }
    } onChange: { [weak self] _ in
      Task { @MainActor [weak self] in self?.schedulePublish()
      }
    }
    Task { await checkZoneAndPublishIfNeeded() }
  }

  func sceneBecameActive() {
    Task { await foregrounded() }
  }

  /// Foreground publishes only to retry a failed run. Edits made here or synced in reach the library observation,
  /// whose debounced publish survives a trip to the background; launch covers what synced while the app was closed.
  func foregrounded() async {
    if !didCheckZone {
      await checkZoneAndPublishIfNeeded()
    } else if lastRunFailed {
      await publishIfShared()
    }
  }

  func shareButtonTapped() {
    Task { await shareMyRecipes() }
  }

  func shareMyRecipes() async {
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      errorMessage = "Enter the name your family will see before sharing."
      return
    }
    isSharing = true
    defer { isSharing = false }
    do {
      share = try await client.createOrFetchShare(name)
      if let share { participants = CookbookParticipantRow.rows(from: share) }
      sharePresentationRequest += 1
      await publishNow()
    } catch { errorMessage = error.localizedDescription }
  }

  func publishNowTapped() { Task { await publishNow() } }

  func stopSharingTapped() {
    Task { await stopSharing() }
  }

  func stopSharing() async {
    do {
      try await client.deleteCookbook()
      share = nil
      participants = []
      publishedProfile = nil
      progressText = nil
      errorMessage = nil
    } catch { errorMessage = error.localizedDescription }
  }

  func checkZoneAndPublishIfNeeded() async {
    guard !didCheckZone, !isCheckingZone else {
      if didCheckZone { await publishIfShared() }
      return
    }
    isCheckingZone = true
    defer { isCheckingZone = false }
    do {
      share = try await client.fetchShare()
      didCheckZone = true
      participants = share.map(CookbookParticipantRow.rows(from:)) ?? []
      guard share != nil else { return }
      publishedProfile = try await client.fetchProfile()
      if let name = publishedProfile?.displayName { displayName = name }
      await publishNow()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func refreshShareStatus() async {
    do {
      share = try await client.fetchShare()
      participants = share.map(CookbookParticipantRow.rows(from:)) ?? []
      publishedProfile = try await client.fetchProfile()
      if let name = publishedProfile?.displayName { displayName = name }
    } catch { errorMessage = error.localizedDescription }
  }

  private func schedulePublish() {
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(120)) } catch { return }
      await self?.publishIfShared()
    }
  }

  private func publishIfShared() async {
    guard share != nil else { return }
    await publishNow()
  }

  func publishNow() async {
    guard !isPublishing else { needsFollowUp = true; return }
    guard share != nil else { return }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      errorMessage = "Enter the name your family will see before sharing."
      return
    }
    isPublishing = true
    defer { isPublishing = false }
    repeat {
      needsFollowUp = false
      await publishCurrentSnapshot()
    } while needsFollowUp
  }

  private func publishCurrentSnapshot() async {
    do {
      let bundles = try await libraryDatabase.read { try CookbookPayload.bundles(in: $0) }
      progressText = "Preparing \(bundles.count) recipes"
      let database = libraryDatabase
      let outcome = try await CookbookPublisher.publish(
        bundles: bundles,
        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        currentProfile: publishedProfile,
        client: client,
        loadDisplayImages: { photoIDs in
          guard !photoIDs.isEmpty else { return [:] }
          let rows = try await database.read { db in
            try RecipePhoto.where { $0.id.in(photoIDs) }
              .select { CookbookDisplayImageRow.Columns(id: $0.id, displayData: $0.displayData) }
              .fetchAll(db)
          }
          return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.displayData.map { (row.id, $0) }
          })
        }
      ) { saved, total in
        await MainActor.run { self.progressText = "Publishing \(saved) of \(total)" }
      }
      switch outcome {
      case .zoneMissing:
        share = nil
        participants = []
        publishedProfile = nil
        progressText = nil
        return
      case .published:
        publishedProfile = try await client.fetchProfile()
        if let name = publishedProfile?.displayName { displayName = name }
      case .unchanged:
        break
      }
      lastCheckedAt = .now
      lastRunFailed = false
      progressText = nil
      errorMessage = nil
    } catch {
      lastRunFailed = true
      progressText = nil
      errorMessage = error.localizedDescription
    }
  }
}

@Selection
private struct CookbookDisplayImageRow: Sendable {
  let id: RecipePhoto.ID
  let displayData: Data?
}
