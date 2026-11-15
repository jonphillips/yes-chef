import CloudKit
import Foundation
import SQLiteData

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

public struct CookbookLensBundle: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var lenses: [RecipeLens]
  public var shelves: [RecipeLensShelf]
  public var categories: [Category]
  public var facets: [Facet]

  public init(lenses: [RecipeLens], shelves: [RecipeLensShelf], categories: [Category], facets: [Facet]) {
    self.lenses = lenses
    self.shelves = shelves
    self.categories = categories
    self.facets = facets
  }

  public static func read(from db: Database) throws -> Self {
    let lenses = try RecipeLens.order { $0.sortOrder }.fetchAll(db)
    let shelves = try RecipeLensShelf.order { $0.sortOrder }.fetchAll(db)
    let queries = lenses.flatMap { [$0.baseQuery] } + shelves.map(\.query)
    let categoryIDs: Set<Category.ID>
    var facetIDs = Set<Facet.ID>()
    var referencedCategoryIDs = Set<Category.ID>()
    for encoded in queries {
      guard let query = try? RecipeLensQueryCodec.decode(encoded) else { continue }
      facetIDs.formUnion(query.facetSelections.map(\.facetID))
      referencedCategoryIDs.formUnion(query.facetSelections.flatMap(\.categoryIDs))
      referencedCategoryIDs.formUnion(query.looseLabelIDs)
    }
    categoryIDs = referencedCategoryIDs
    var categories: [Category] = []
    var pendingCategoryIDs = categoryIDs
    var visitedCategoryIDs = Set<Category.ID>()
    while let categoryID = pendingCategoryIDs.popFirst() {
      guard visitedCategoryIDs.insert(categoryID).inserted else { continue }
      guard let category = try Category.find(categoryID).fetchOne(db) else { continue }
      categories.append(category)
      if let parentID = category.parentCategoryID { pendingCategoryIDs.insert(parentID) }
      if let facetID = category.facetID { facetIDs.insert(facetID) }
    }
    let facets = try facetIDs.sorted { $0.uuidString < $1.uuidString }.compactMap { try Facet.find($0).fetchOne(db) }
    return Self(lenses: lenses, shelves: shelves, categories: categories, facets: facets)
  }

  public func encodedPayload() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    func sorted<T: Encodable>(_ values: [T]) throws -> [T] {
      try values.map { (try encoder.encode($0), $0) }
        .sorted { $0.0.lexicographicallyPrecedes($1.0) }.map(\.1)
    }
    var value = self
    value.lenses = try sorted(lenses)
    value.shelves = try sorted(shelves)
    value.categories = try sorted(categories)
    value.facets = try sorted(facets)
    return try encoder.encode(value)
  }
}

public struct CookbookPublishLenses: Equatable, Sendable {
  public var payload: Data
  public var contentHash: String
  public var payloadVersion: Int

  public init(payload: Data, contentHash: String, payloadVersion: Int = CookbookLensBundle.currentVersion) {
    self.payload = payload
    self.contentHash = contentHash
    self.payloadVersion = payloadVersion
  }
}

public struct CookbookPublishPlan: Equatable, Sendable {
  public var recipesToSave: [CookbookPublishRecipe]
  public var recordNamesToDelete: [String]
  public var lensesToSave: CookbookPublishLenses?

  public static func make(
    bundles: [RecipeBundleCoding.RecipeBundle],
    existingHashes: [String: String],
    lenses: CookbookLensBundle? = nil
  ) throws -> Self {
    let recipes = try bundles.map { bundle in
      let payload = try CookbookPayload.encodedPayload(bundle)
      return CookbookPublishRecipe(
        recordName: bundle.recipe.id.uuidString,
        payload: payload,
        contentHash: CookbookPayload.contentHash(payload),
        payloadVersion: bundle.version,
        displayPhotoID: CookbookPayload.displayPhotoID(for: bundle.recipe, photos: bundle.photos)
      )
    }.sorted { $0.recordName < $1.recordName }
    let currentNames = Set(recipes.map(\.recordName))
    let lensPayload = try lenses?.encodedPayload()
    let lensRecord = lensPayload.map {
      CookbookPublishLenses(payload: $0, contentHash: CookbookPayload.contentHash($0))
    }
    return Self(
      recipesToSave: recipes.filter { existingHashes[$0.recordName] != $0.contentHash },
      recordNamesToDelete: existingHashes.keys.filter { $0 != "lenses" && !currentNames.contains($0) }.sorted(),
      lensesToSave: lensRecord.flatMap { existingHashes["lenses"] == $0.contentHash ? nil : $0 }
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
    // The owner is you, not family, and CloudKit gives your own identity no name.
    share.participants.filter { $0.role != .owner }.enumerated().map { index, participant in
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
  public var saveLenses: @Sendable (CookbookPublishLenses) async throws -> Void
  public var fetchShare: @Sendable () async throws -> CKShare?
  public var createOrFetchShare: @Sendable (String) async throws -> CKShare
  public var deleteCookbook: @Sendable () async throws -> Void

  public init(
    fetchRecipeHashes: @escaping @Sendable () async throws -> [String: String],
    saveRecipes: @escaping @Sendable ([CookbookPublishRecipe], @Sendable (Int) async -> Void) async throws -> Void,
    deleteRecipes: @escaping @Sendable ([String]) async throws -> Void,
    fetchProfile: @escaping @Sendable () async throws -> CookbookPublishProfile?,
    saveProfile: @escaping @Sendable (CookbookPublishProfile) async throws -> Void,
    saveLenses: @escaping @Sendable (CookbookPublishLenses) async throws -> Void = { _ in },
    fetchShare: @escaping @Sendable () async throws -> CKShare?,
    createOrFetchShare: @escaping @Sendable (String) async throws -> CKShare,
    deleteCookbook: @escaping @Sendable () async throws -> Void
  ) {
    self.fetchRecipeHashes = fetchRecipeHashes
    self.saveRecipes = saveRecipes
    self.deleteRecipes = deleteRecipes
    self.fetchProfile = fetchProfile
    self.saveProfile = saveProfile
    self.saveLenses = saveLenses
    self.fetchShare = fetchShare
    self.createOrFetchShare = createOrFetchShare
    self.deleteCookbook = deleteCookbook
  }
}

public enum CookbookFetchedRecord: Sendable {
  case recipe(name: String, payload: Data, version: Int)
  case profile(CookbookPublishProfile)
  case lenses(name: String, payload: Data, version: Int)
  case ignored
}

public struct CookbookFetchedDeletion: Sendable {
  public var recordName: String
  public var recordType: String

  public init(recordName: String, recordType: String) {
    self.recordName = recordName
    self.recordType = recordType
  }
}

public struct CookbookFetchedPage: Sendable {
  public var records: [CookbookFetchedRecord]
  public var deletions: [CookbookFetchedDeletion]
  public var changeToken: Data?
  public var moreComing: Bool

  public init(records: [CookbookFetchedRecord], deletions: [CookbookFetchedDeletion], changeToken: Data?, moreComing: Bool) {
    self.records = records
    self.deletions = deletions
    self.changeToken = changeToken
    self.moreComing = moreComing
  }
}

public struct CookbookFetchProgress: Sendable {
  public var fetched: Int
  public var total: Int?
  public var displayName: String?
  public var isFullFetch: Bool

  public init(fetched: Int, total: Int?, displayName: String?, isFullFetch: Bool) {
    self.fetched = fetched
    self.total = total
    self.displayName = displayName
    self.isFullFetch = isFullFetch
  }
}

public struct CookbookFetchClient: Sendable {
  public var sharedZones: @Sendable () async throws -> [CKRecordZone.ID]
  public var fetchPage: @Sendable (CKRecordZone.ID, Data?) async throws -> CookbookFetchedPage
  public var fetchDisplayImage: @Sendable (CKRecordZone.ID, String) async throws -> Data
  public var fetchProfile: @Sendable (CKRecordZone.ID) async throws -> CookbookPublishProfile?

  public init(
    sharedZones: @escaping @Sendable () async throws -> [CKRecordZone.ID],
    fetchPage: @escaping @Sendable (CKRecordZone.ID, Data?) async throws -> CookbookFetchedPage,
    fetchDisplayImage: @escaping @Sendable (CKRecordZone.ID, String) async throws -> Data,
    fetchProfile: @escaping @Sendable (CKRecordZone.ID) async throws -> CookbookPublishProfile? = { _ in nil }
  ) {
    self.sharedZones = sharedZones
    self.fetchPage = fetchPage
    self.fetchDisplayImage = fetchDisplayImage
    self.fetchProfile = fetchProfile
  }
}

public enum CookbookFetcher {
  public static func fetch(
    zoneID: CKRecordZone.ID, mirror: CookbookMirror, client: CookbookFetchClient,
    progress: @escaping @Sendable (CookbookFetchProgress) async -> Void = { _ in }
  ) async throws {
    do {
      try await fetchPages(zoneID: zoneID, mirror: mirror, client: client, progress: progress)
    } catch let error as CKError where error.code == .changeTokenExpired {
      try mirror.resetChangeTokenForFullFetch()
      try await fetchPages(zoneID: zoneID, mirror: mirror, client: client, progress: progress)
    }
  }

  private static func fetchPages(
    zoneID: CKRecordZone.ID, mirror: CookbookMirror, client: CookbookFetchClient,
    progress: @escaping @Sendable (CookbookFetchProgress) async -> Void
  ) async throws {
    var state = try mirror.fetchState()
    let fullFetch = state.changeToken == nil || state.payloadVersion < RecipeBundleCoding.currentVersion || state.fullFetchActive
    if state.payloadVersion < RecipeBundleCoding.currentVersion { state.changeToken = nil }
    var token = fullFetch ? nil : state.changeToken
    if state.fullFetchActive { token = state.changeToken }
    var startsFullFetch = fullFetch && !state.fullFetchActive
    var fetched = 0
    var total = state.recipeCount
    // The publisher saves the profile last, so a full fetch would otherwise learn the name and total on its last page.
    if fullFetch, let profile = try await retrying({ try await client.fetchProfile(zoneID) }) {
      total = profile.recipeCount
      await progress(CookbookFetchProgress(
        fetched: 0, total: total, displayName: profile.displayName, isFullFetch: true
      ))
    }
    var moreComing = true
    while moreComing {
      let pageToken = token
      let page = try await retrying { try await client.fetchPage(zoneID, pageToken) }
      var bundles: [RecipeBundleCoding.RecipeBundle] = []
      var deleted: [Recipe.ID] = []
      var seen: [String] = []
      var skipped: [String: Int] = [:]
      var profile: CookbookPublishProfile?
      var lenses: CookbookLensBundle?
      let deletesLenses: Bool
      for record in page.records {
        switch record {
        case let .recipe(name, payload, version):
          seen.append(name)
          do { bundles.append(try RecipeBundleCoding.decodePayload(payload)) }
          catch RecipeBundleCoding.PayloadError.newerVersion(let newer) { skipped[name] = newer }
          catch { throw error }
          if version > RecipeBundleCoding.currentVersion { skipped[name] = version }
        case let .profile(value):
          profile = value
          total = value.recipeCount
        case let .lenses(name, payload, version):
          seen.append(name)
          do {
            guard version <= CookbookLensBundle.currentVersion else { skipped[name] = version; continue }
            lenses = try JSONDecoder().decode(CookbookLensBundle.self, from: payload)
          }
          catch { throw error }
        case .ignored: break
        }
      }
      for deletion in page.deletions where deletion.recordType == "CookbookRecipe" {
        if let id = UUID(uuidString: deletion.recordName) { deleted.append(id) }
      }
      deletesLenses = page.deletions.contains { $0.recordType == "CookbookLenses" }
      token = page.changeToken
      fetched += bundles.count
      try mirror.apply(page: CookbookMirrorPage(
        bundles: bundles, deletedRecipeIDs: deleted, seenRecordNames: seen, profile: profile,
        lensBundle: lenses, deletesLensRecord: deletesLenses, skippedRecords: skipped, changeToken: token,
        startsFullFetch: startsFullFetch, finishesFullFetch: fullFetch && !page.moreComing
      ))
      await progress(CookbookFetchProgress(
        fetched: fetched, total: total, displayName: profile?.displayName, isFullFetch: fullFetch
      ))
      startsFullFetch = false
      moreComing = page.moreComing
    }
  }

  private static func retrying<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
    var attempt = 1
    while true {
      do { return try await operation() }
      catch {
        guard attempt < CookbookRetry.attempts, let delay = CookbookRetry.delay(for: error) else { throw error }
        attempt += 1
        try await Task.sleep(for: .seconds(delay))
      }
    }
  }
}

public enum CookbookPublisher {
  public static func publish(
    bundles: [RecipeBundleCoding.RecipeBundle],
    displayName: String,
    currentProfile: CookbookPublishProfile? = nil,
    lenses: CookbookLensBundle? = nil,
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
        try CookbookPublishPlan.make(bundles: bundles, existingHashes: existing, lenses: lenses)
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
      // A run that changed nothing leaves the profile alone, so `publishedAt` stays the last real publish and viewers
      // don't fetch a profile change on every check.
      if let lensesToSave = plan.lensesToSave { try await client.saveLenses(lensesToSave) }
      if plan.recipesToSave.isEmpty, plan.recordNamesToDelete.isEmpty, plan.lensesToSave == nil, let currentProfile,
        currentProfile.publishedAt != nil, currentProfile.displayName == displayName,
        currentProfile.recipeCount == bundles.count, currentProfile.payloadVersion == RecipeBundleCoding.currentVersion
      {
        return .unchanged
      }
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
  case unchanged
  case zoneMissing
}
