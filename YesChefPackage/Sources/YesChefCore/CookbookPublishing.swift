import CloudKit
import Foundation

public struct CookbookPublishRecipe: Equatable, Sendable {
  public var recordName: String
  public var payload: Data
  public var contentHash: String
  public var payloadVersion: Int
  public var displayPhotoID: RecipePhoto.ID?
  public var displayImage: Data?

  public init(
    recordName: String,
    payload: Data,
    contentHash: String,
    payloadVersion: Int,
    displayPhotoID: RecipePhoto.ID? = nil,
    displayImage: Data? = nil
  ) {
    self.recordName = recordName
    self.payload = payload
    self.contentHash = contentHash
    self.payloadVersion = payloadVersion
    self.displayPhotoID = displayPhotoID
    self.displayImage = displayImage
  }
}

public struct CookbookPublishProfile: Equatable, Sendable {
  public var displayName: String
  public var recipeCount: Int
  public var payloadVersion: Int
  public var publishedAt: Date?

  public init(displayName: String, recipeCount: Int, payloadVersion: Int, publishedAt: Date?) {
    self.displayName = displayName
    self.recipeCount = recipeCount
    self.payloadVersion = payloadVersion
    self.publishedAt = publishedAt
  }
}

public struct CookbookPublishPlan: Equatable, Sendable {
  public var recipesToSave: [CookbookPublishRecipe]
  public var recordNamesToDelete: [String]

  public static func make(
    bundles: [RecipeBundleCoding.RecipeBundle],
    existingHashes: [String: String]
  ) throws -> Self {
    let recipes = try bundles.map { bundle in
      let payload = try CookbookPayload.encodedPayload(bundle)
      let displayPhoto = bundle.recipe.coverPhotoID.flatMap { coverID in
        bundle.photos.first { $0.id == coverID }
      } ?? bundle.photos.sorted { $0.sortOrder < $1.sortOrder }.first
      return CookbookPublishRecipe(
        recordName: bundle.recipe.id.uuidString,
        payload: payload,
        contentHash: CookbookPayload.contentHash(payload),
        payloadVersion: bundle.version,
        displayPhotoID: displayPhoto?.id
      )
    }.sorted { $0.recordName < $1.recordName }
    let currentNames = Set(recipes.map(\.recordName))
    return Self(
      recipesToSave: recipes.filter { existingHashes[$0.recordName] != $0.contentHash },
      recordNamesToDelete: existingHashes.keys.filter { !currentNames.contains($0) }.sorted()
    )
  }
}

public struct CookbookParticipantRow: Equatable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var invitationStatus: String
  public var permission: String

  public var description: String { "\(name) · \(invitationStatus) · \(permission)" }

  public static func rows(from share: CKShare) -> [Self] {
    share.participants.enumerated().map { index, participant in
      let name = participant.userIdentity.nameComponents.map {
        PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
      }.flatMap { $0.isEmpty ? nil : $0 } ?? "Family member"
      let participantID = participant.userIdentity.lookupInfo?.userRecordID?.recordName
        ?? "\(participant.role)-\(name)-\(index)"
      return Self(id: participantID,
        name: name,
        invitationStatus: invitationStatus(participant.acceptanceStatus),
        permission: permission(participant.permission))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  public static func invitationStatus(_ status: CKShare.ParticipantAcceptanceStatus) -> String {
    switch status {
    case .accepted: "accepted"
    case .pending: "invited"
    case .removed: "removed"
    default: "unknown"
    }
  }

  public static func permission(_ permission: CKShare.ParticipantPermission) -> String {
    switch permission {
    case .readOnly: "read-only"
    case .readWrite: "read-write"
    case .none: "no access"
    default: "unknown access"
    }
  }
}

public struct CookbookPublishClient: Sendable {
  public var fetchRecipeHashes: @Sendable () async throws -> [String: String]
  public var saveRecipes: @Sendable ([CookbookPublishRecipe], @Sendable (Int) async -> Void) async throws -> Void
  public var deleteRecipes: @Sendable ([String]) async throws -> Void
  public var fetchProfile: @Sendable () async throws -> CookbookPublishProfile?
  public var saveProfile: @Sendable (CookbookPublishProfile) async throws -> Void
  public var fetchShare: @Sendable () async throws -> CKShare?
  public var createOrFetchShare: @Sendable (String) async throws -> CKShare
  public var deleteCookbook: @Sendable () async throws -> Void

  public init(
    fetchRecipeHashes: @escaping @Sendable () async throws -> [String: String],
    saveRecipes: @escaping @Sendable ([CookbookPublishRecipe], @Sendable (Int) async -> Void) async throws -> Void,
    deleteRecipes: @escaping @Sendable ([String]) async throws -> Void,
    fetchProfile: @escaping @Sendable () async throws -> CookbookPublishProfile?,
    saveProfile: @escaping @Sendable (CookbookPublishProfile) async throws -> Void,
    fetchShare: @escaping @Sendable () async throws -> CKShare?,
    createOrFetchShare: @escaping @Sendable (String) async throws -> CKShare,
    deleteCookbook: @escaping @Sendable () async throws -> Void
  ) {
    self.fetchRecipeHashes = fetchRecipeHashes
    self.saveRecipes = saveRecipes
    self.deleteRecipes = deleteRecipes
    self.fetchProfile = fetchProfile
    self.saveProfile = saveProfile
    self.fetchShare = fetchShare
    self.createOrFetchShare = createOrFetchShare
    self.deleteCookbook = deleteCookbook
  }
}

public enum CookbookPublisher {
  public static func publish(
    bundles: [RecipeBundleCoding.RecipeBundle],
    displayName: String,
    publishedAt: Date = .now,
    client: CookbookPublishClient,
    loadDisplayImages: @escaping @Sendable ([RecipePhoto.ID]) async throws -> [RecipePhoto.ID: Data] = { _ in [:] },
    progress: @escaping @Sendable (Int, Int) async -> Void
  ) async throws -> CookbookPublishOutcome {
    let existing: [String: String]
    do { existing = try await client.fetchRecipeHashes() }
    catch {
      if isZoneNotFound(error) { return .zoneMissing }
      throw error
    }
    do {
      let plan = try await Task.detached(priority: .utility) {
        try CookbookPublishPlan.make(bundles: bundles, existingHashes: existing)
      }.value
      let total = plan.recipesToSave.count
      for start in stride(from: 0, to: total, by: 400) {
        let end = min(start + 400, total)
        var batch = Array(plan.recipesToSave[start..<end])
        let photoIDs = batch.compactMap(\.displayPhotoID)
        if !photoIDs.isEmpty {
          let images = try await loadDisplayImages(photoIDs)
          for index in batch.indices {
            if let photoID = batch[index].displayPhotoID {
              batch[index].displayImage = images[photoID]
            }
          }
        }
        try await client.saveRecipes(batch) { saved in
          await progress(start + saved, total)
        }
      }
      try await client.deleteRecipes(plan.recordNamesToDelete)
      try await client.saveProfile(CookbookPublishProfile(
        displayName: displayName, recipeCount: bundles.count,
        payloadVersion: RecipeBundleCoding.currentVersion, publishedAt: publishedAt
      ))
      return .published
    } catch {
      if isZoneNotFound(error) { return .zoneMissing }
      throw error
    }
  }

  private static func isZoneNotFound(_ error: Error) -> Bool {
    guard let cloudError = error as? CKError else { return false }
    if cloudError.code == .zoneNotFound { return true }
    guard cloudError.code == .partialFailure,
      let partialErrors = cloudError.partialErrorsByItemID?.values,
      !partialErrors.isEmpty
    else { return false }
    return partialErrors.allSatisfy { ($0 as? CKError)?.code == .zoneNotFound }
  }
}

public enum CookbookPublishOutcome: Equatable, Sendable {
  case published
  case zoneMissing
}
