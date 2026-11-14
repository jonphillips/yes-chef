import CloudKit
import CryptoKit
import Foundation

public struct CookbookPublishRecipe: Equatable, Sendable {
  public var recordName: String
  public var payload: Data
  public var contentHash: String
  public var payloadVersion: Int
  public var displayImage: Data?

  public init(recordName: String, payload: Data, contentHash: String, payloadVersion: Int, displayImage: Data?) {
    self.recordName = recordName
    self.payload = payload
    self.contentHash = contentHash
    self.payloadVersion = payloadVersion
    self.displayImage = displayImage
  }
}

public struct CookbookPublishProfile: Equatable, Sendable {
  public var displayName: String
  public var recipeCount: Int
  public var payloadVersion: Int
  public var publishedAt: Date

  public init(displayName: String, recipeCount: Int, payloadVersion: Int, publishedAt: Date) {
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
    existingHashes: [String: String],
    displayImages: [RecipePhoto.ID: Data] = [:]
  ) throws -> Self {
    let recipes = try bundles.map { bundle in
      let payload = try CookbookPayload.encodedPayload(bundle)
      let displayPhoto = bundle.recipe.coverPhotoID.flatMap { coverID in
        bundle.photos.first { $0.id == coverID }
      } ?? bundle.photos.sorted { $0.sortOrder < $1.sortOrder }.first
      return CookbookPublishRecipe(
        recordName: bundle.recipe.id.uuidString,
        payload: payload,
        contentHash: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
        payloadVersion: bundle.version,
        displayImage: displayPhoto.flatMap { displayImages[$0.id] }
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
      let status: String
      switch participant.acceptanceStatus {
      case .accepted: status = "accepted"
      case .pending: status = "invited"
      case .removed: status = "removed"
      default: status = "unknown"
      }
      let permission: String
      switch participant.permission {
      case .readOnly: permission = "read-only"
      case .readWrite: permission = "read-write"
      case .none: permission = "no access"
      default: permission = "unknown access"
      }
      let participantID = participant.userIdentity.lookupInfo?.userRecordID?.recordName
        ?? "\(participant.role)-\(name)-\(index)"
      return Self(id: participantID,
        name: name, invitationStatus: status, permission: permission)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

public struct CookbookPublishClient: Sendable {
  public var fetchRecipeHashes: @Sendable () async throws -> [String: String]
  public var saveRecipes: @Sendable ([CookbookPublishRecipe], @Sendable (Int) -> Void) async throws -> Void
  public var deleteRecipes: @Sendable ([String]) async throws -> Void
  public var fetchProfile: @Sendable () async throws -> CookbookPublishProfile?
  public var saveProfile: @Sendable (CookbookPublishProfile) async throws -> Void
  public var fetchShare: @Sendable () async throws -> CKShare?
  public var createOrFetchShare: @Sendable (String) async throws -> CKShare
  public var deleteCookbook: @Sendable () async throws -> Void

  public init(
    fetchRecipeHashes: @escaping @Sendable () async throws -> [String: String],
    saveRecipes: @escaping @Sendable ([CookbookPublishRecipe], @Sendable (Int) -> Void) async throws -> Void,
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
    displayImages: [RecipePhoto.ID: Data] = [:],
    displayName: String,
    publishedAt: Date = .now,
    client: CookbookPublishClient,
    progress: @escaping @Sendable (Int, Int) -> Void
  ) async throws {
    let existing: [String: String]
    do { existing = try await client.fetchRecipeHashes() }
    catch let error as CKError where error.code == .zoneNotFound { return }
    let plan = try await Task.detached(priority: .utility) {
      try CookbookPublishPlan.make(bundles: bundles, existingHashes: existing, displayImages: displayImages)
    }.value
    try await client.saveRecipes(plan.recipesToSave) { saved in
      progress(saved, plan.recipesToSave.count)
    }
    try await client.deleteRecipes(plan.recordNamesToDelete)
    try await client.saveProfile(CookbookPublishProfile(
      displayName: displayName, recipeCount: bundles.count,
      payloadVersion: RecipeBundleCoding.currentVersion, publishedAt: publishedAt
    ))
  }
}
