import CloudKit
import Foundation

private typealias CookbookModifyResult = (
  saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
  deleteResults: [CKRecord.ID: Result<Void, any Error>]
)

public enum CookbookCloudKitClientFactory {
  public static let containerIdentifier = "iCloud.com.jonphillips.yeschef.cookbook"
  public static let zoneID = CKRecordZone.ID(zoneName: "Cookbook", ownerName: CKCurrentUserDefaultName)

  public static func fetchClient(container: CKContainer = CKContainer(identifier: containerIdentifier)) -> CookbookFetchClient {
    let database = container.sharedCloudDatabase
    return CookbookFetchClient(
      sharedZones: {
        try await retrying {
          try await database.allRecordZones().map(\.zoneID)
            .filter { $0.zoneName == "Cookbook" }
        }
      },
      fetchPage: { zoneID, tokenData in
        let token = try tokenData.flatMap {
          try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        let page = try await database.recordZoneChanges(
          inZoneWith: zoneID, since: token,
          desiredKeys: ["payload", "contentHash", "payloadVersion", "displayName", "recipeCount", "publishedAt"],
          resultsLimit: 400
        )
        let records = try page.modificationResultsByID.values.map { result -> CookbookFetchedRecord in
          let record = try result.get().record
          switch record.recordType {
          case "CookbookRecipe":
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
              throw CookbookFetchError.missingPayload(record.recordID.recordName)
            }
            return .recipe(
              name: record.recordID.recordName, payload: try Data(contentsOf: url),
              version: record["payloadVersion"] as? Int ?? 0
            )
          case "CookbookProfile":
            guard let displayName = record["displayName"] as? String else { return .ignored }
            return .profile(CookbookPublishProfile(
              displayName: displayName, recipeCount: record["recipeCount"] as? Int ?? 0,
              payloadVersion: record["payloadVersion"] as? Int ?? 0, publishedAt: record["publishedAt"] as? Date
            ))
          case "CookbookLenses":
            guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
              throw CookbookFetchError.missingPayload(record.recordID.recordName)
            }
            return .lenses(
              name: record.recordID.recordName, payload: try Data(contentsOf: url),
              version: record["payloadVersion"] as? Int ?? 0
            )
          default: return .ignored
          }
        }
        let deletions = page.deletions.map { CookbookFetchedDeletion(recordName: $0.recordID.recordName, recordType: $0.recordType) }
        let data = try NSKeyedArchiver.archivedData(withRootObject: page.changeToken, requiringSecureCoding: true)
        return CookbookFetchedPage(records: records, deletions: deletions, changeToken: data, moreComing: page.moreComing)
      },
      fetchDisplayImage: { zoneID, recordName in
        let record = try await retrying {
          try await database.record(for: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        }
        guard let asset = record["displayImage"] as? CKAsset, let url = asset.fileURL else {
          throw CookbookFetchError.missingDisplayImage(recordName)
        }
        return try Data(contentsOf: url)
      }
    )
  }

  public static func live(container: CKContainer = CKContainer(identifier: containerIdentifier)) -> CookbookPublishClient {
    let database = container.privateCloudDatabase
    return CookbookPublishClient(
      fetchRecipeHashes: {
        var hashes: [String: String] = [:]
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
          let pageToken = token
          let page = try await retrying {
            try await database.recordZoneChanges(
              inZoneWith: zoneID, since: pageToken, desiredKeys: ["contentHash"], resultsLimit: 400
            )
          }
          for result in page.modificationResultsByID.values {
            let record = try result.get().record
            guard record.recordType == "CookbookRecipe" || record.recordType == "CookbookLenses" else { continue }
            hashes[record.recordID.recordName] = record["contentHash"] as? String ?? ""
          }
          token = page.changeToken
          moreComing = page.moreComing
        }
        return hashes
      },
      saveRecipes: { recipes, progress in
        var saved = 0
        for start in stride(from: 0, to: recipes.count, by: 400) {
          let batch = Array(recipes[start..<min(start + 400, recipes.count)])
          saved = try await save(batch, in: database, savedBefore: saved, progress: progress)
        }
      },
      deleteRecipes: { names in
        for start in stride(from: 0, to: names.count, by: 400) {
          let batch = names[start..<min(start + 400, names.count)].map {
            CKRecord.ID(recordName: $0, zoneID: zoneID)
          }
          let failures = try await modify(in: database, saving: [], deleting: batch)
          guard failures.isEmpty else {
            if failures.allSatisfy({ ($0 as? CKError)?.code == .zoneNotFound }), let first = failures.first {
              throw first
            }
            throw CookbookPublishFailure.records(failures, fallbackCount: batch.count)
          }
        }
      },
      fetchProfile: {
        do {
          let record = try await retrying {
            try await database.record(for: CKRecord.ID(recordName: "profile", zoneID: zoneID))
          }
          guard let displayName = record["displayName"] as? String else { return nil }
          return CookbookPublishProfile(
            displayName: displayName,
            recipeCount: record["recipeCount"] as? Int ?? 0,
            payloadVersion: record["payloadVersion"] as? Int ?? 0,
            publishedAt: record["publishedAt"] as? Date
          )
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
          return nil
        }
      },
      saveProfile: { profile in
        let record = CKRecord(recordType: "CookbookProfile", recordID: CKRecord.ID(recordName: "profile", zoneID: zoneID))
        record["displayName"] = profile.displayName as CKRecordValue
        record["recipeCount"] = profile.recipeCount as CKRecordValue
        record["payloadVersion"] = profile.payloadVersion as CKRecordValue
        record["publishedAt"] = profile.publishedAt as CKRecordValue?
        let failures = try await modify(in: database, saving: [record], deleting: [])
        guard failures.isEmpty else {
          if failures.allSatisfy({ ($0 as? CKError)?.code == .zoneNotFound }), let first = failures.first {
            throw first
          }
          throw CookbookPublishFailure.records(failures, fallbackCount: 1)
        }
      },
      saveLenses: { lenses in
        let url = try writeAsset(lenses.payload)
        defer { try? FileManager.default.removeItem(at: url) }
        let record = CKRecord(recordType: "CookbookLenses", recordID: CKRecord.ID(recordName: "lenses", zoneID: zoneID))
        record["payload"] = CKAsset(fileURL: url)
        record["contentHash"] = lenses.contentHash as CKRecordValue
        record["payloadVersion"] = lenses.payloadVersion as CKRecordValue
        let failures = try await modify(in: database, saving: [record], deleting: [])
        guard failures.isEmpty else {
          if failures.allSatisfy({ ($0 as? CKError)?.code == .zoneNotFound }), let first = failures.first { throw first }
          throw CookbookPublishFailure.records(failures, fallbackCount: 1)
        }
      },
      fetchShare: { try await Self.fetchShare(in: database) },
      createOrFetchShare: { displayName in
        do {
          _ = try await database.recordZone(for: zoneID)
        } catch let error as CKError where error.code == .zoneNotFound {
          _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }
        if let share = try await Self.fetchShare(in: database) {
          let title = "\(displayName)'s Recipes"
          if share[CKShare.SystemFieldKey.title] as? String != title {
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            share.publicPermission = .none
            guard let saved = try await database.save(share) as? CKShare else { throw CookbookCloudKitError.unexpectedShareRecord }
            return saved
          }
          return share
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "\(displayName)'s Recipes" as CKRecordValue
        share.publicPermission = .none
        guard let saved = try await database.save(share) as? CKShare else { throw CookbookCloudKitError.unexpectedShareRecord }
        return saved
      },
      deleteCookbook: {
        do { _ = try await database.deleteRecordZone(withID: zoneID) }
        catch let error as CKError where error.code == .zoneNotFound { return }
      }
    )
  }

  /// Saves one batch. When every failure is `batchRequestFailed`, no record named a cause: the request failed as a
  /// whole. Split it and save each half, so a request that was too large goes through in pieces and a record that
  /// can't be saved is isolated with its own error. Depth-first, so a failure that hits every record costs about
  /// log2(batch) requests before it's reported, not one per record.
  private static func save(
    _ recipes: [CookbookPublishRecipe],
    in database: CKDatabase,
    savedBefore: Int,
    progress: @Sendable (Int) async -> Void
  ) async throws -> Int {
    let failures = try await attemptSave(recipes, in: database)
    if failures.isEmpty {
      await progress(savedBefore + recipes.count)
      return savedBefore + recipes.count
    }
    if failures.allSatisfy({ ($0 as? CKError)?.code == .zoneNotFound }), let first = failures.first {
      throw first
    }
    if recipes.count > 1, failures.allSatisfy({ ($0 as? CKError)?.code == .batchRequestFailed }) {
      let middle = recipes.count / 2
      let afterFirstHalf = try await save(
        Array(recipes[..<middle]), in: database, savedBefore: savedBefore, progress: progress
      )
      return try await save(Array(recipes[middle...]), in: database, savedBefore: afterFirstHalf, progress: progress)
    }
    throw CookbookPublishFailure.records(failures, fallbackCount: recipes.count)
  }

  /// One modify request. Returns the per-record failures; the asset files are removed before it returns.
  private static func attemptSave(_ recipes: [CookbookPublishRecipe], in database: CKDatabase) async throws -> [any Error] {
    var temporaryFiles: [URL] = []
    defer { temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
    let records = try recipes.map { recipe -> CKRecord in
      let id = CKRecord.ID(recordName: recipe.recordName, zoneID: zoneID)
      let record = CKRecord(recordType: "CookbookRecipe", recordID: id)
      let payloadURL = try writeAsset(recipe.payload)
      temporaryFiles.append(payloadURL)
      record["payload"] = CKAsset(fileURL: payloadURL)
      record["contentHash"] = recipe.contentHash as CKRecordValue
      record["payloadVersion"] = recipe.payloadVersion as CKRecordValue
      if let image = recipe.displayImage {
        let imageURL = try writeAsset(image)
        temporaryFiles.append(imageURL)
        record["displayImage"] = CKAsset(fileURL: imageURL)
      } else {
        record["displayImage"] = nil
      }
      return record
    }
    return try await modify(in: database, saving: records, deleting: [])
  }

  /// One modify request, sent again while CloudKit asks us to wait (rate limits, a busy zone). Returns the per-record
  /// failures left after that.
  private static func modify(in database: CKDatabase, saving: [CKRecord], deleting: [CKRecord.ID]) async throws -> [any Error] {
    var attempt = 1
    while true {
      let failures: [any Error]
      do {
        let result: CookbookModifyResult = try await database.modifyRecords(
          saving: saving, deleting: deleting, savePolicy: .changedKeys, atomically: false
        )
        failures = result.saveResults.values.compactMap(\.failure) + result.deleteResults.values.compactMap(\.failure)
      } catch let error as CKError where error.code == .partialFailure {
        if isZoneNotFound(error) { throw error }
        failures = error.partialErrorsByItemID.map { Array($0.values) } ?? [error]
      } catch {
        guard attempt < CookbookRetry.attempts, let delay = CookbookRetry.delay(for: error) else { throw error }
        attempt += 1
        try await Task.sleep(for: .seconds(delay))
        continue
      }
      guard !failures.isEmpty, attempt < CookbookRetry.attempts,
        let delay = CookbookRetry.delay(forRecordFailures: failures)
      else { return failures }
      attempt += 1
      try await Task.sleep(for: .seconds(delay))
    }
  }

  /// Runs a CloudKit call, again while CloudKit asks us to wait.
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

  private static func fetchShare(in database: CKDatabase) async throws -> CKShare? {
    do {
      let record = try await retrying {
        try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID))
      }
      return record as? CKShare
    } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
      return nil
    }
  }

  private static func writeAsset(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cookbook-\(UUID().uuidString).asset")
    try data.write(to: url, options: .atomic)
    return url
  }


  private static func isZoneNotFound(_ error: CKError) -> Bool {
    guard error.code == .partialFailure,
      let errors = error.partialErrorsByItemID?.values,
      !errors.isEmpty
    else { return false }
    return errors.allSatisfy { ($0 as? CKError)?.code == .zoneNotFound }
  }
}

private enum CookbookFetchError: LocalizedError {
  case missingPayload(String)
  case missingDisplayImage(String)

  var errorDescription: String? {
    switch self {
    case let .missingPayload(name): "Cookbook record \(name) has no payload asset."
    case let .missingDisplayImage(name): "Cookbook recipe \(name) has no full-size photo asset."
    }
  }
}

private enum CookbookCloudKitError: Error {
  case unexpectedShareRecord
}

public enum CookbookPublishFailure: LocalizedError, Equatable {
  case failedRecords(count: Int, firstError: String)

  public var errorDescription: String? {
    switch self {
    case let .failedRecords(count, firstError): "\(count) CloudKit record(s) failed; cause: \(firstError)"
    }
  }

  /// When one record in a batch fails, CloudKit rejects the rest of its batch with `batchRequestFailed`, so the
  /// cause is the first error that isn't that one. The count still covers every record that didn't save.
  public static func records(_ errors: [any Error], fallbackCount: Int) -> Self {
    let cause = errors.first { ($0 as? CKError)?.code != .batchRequestFailed } ?? errors.first
    let rejectedWithIt = errors.count - 1
    let detail = cause.map(describe) ?? "Unknown CloudKit error"
    return .failedRecords(
      count: errors.isEmpty ? fallbackCount : errors.count,
      firstError: rejectedWithIt > 0 && (cause as? CKError)?.code != .batchRequestFailed
        ? "\(detail); the other \(rejectedWithIt) were rejected with it"
        : detail
    )
  }

  public static func describe(_ error: any Error) -> String {
    guard let error = error as? CKError else { return error.localizedDescription }
    return "CKError \(name(error.code)) (\(error.localizedDescription))"
  }

  public static func name(_ code: CKError.Code) -> String {
    switch code {
    case .internalError: "internalError"
    case .partialFailure: "partialFailure"
    case .networkUnavailable: "networkUnavailable"
    case .networkFailure: "networkFailure"
    case .serviceUnavailable: "serviceUnavailable"
    case .requestRateLimited: "requestRateLimited"
    case .notAuthenticated: "notAuthenticated"
    case .permissionFailure: "permissionFailure"
    case .unknownItem: "unknownItem"
    case .invalidArguments: "invalidArguments"
    case .serverRecordChanged: "serverRecordChanged"
    case .serverRejectedRequest: "serverRejectedRequest"
    case .assetFileNotFound: "assetFileNotFound"
    case .assetFileModified: "assetFileModified"
    case .constraintViolation: "constraintViolation"
    case .batchRequestFailed: "batchRequestFailed"
    case .zoneBusy: "zoneBusy"
    case .quotaExceeded: "quotaExceeded"
    case .zoneNotFound: "zoneNotFound"
    case .limitExceeded: "limitExceeded"
    case .userDeletedZone: "userDeletedZone"
    case .serverResponseLost: "serverResponseLost"
    case .assetNotAvailable: "assetNotAvailable"
    default: "code \(code.rawValue)"
    }
  }
}

/// CloudKit errors that clear on their own if you wait: it says how long in `retryAfterSeconds`.
public enum CookbookRetry {
  public static let attempts = 5

  public static func delay(for error: any Error) -> TimeInterval? {
    guard let error = error as? CKError else { return nil }
    switch error.code {
    case .requestRateLimited, .zoneBusy, .serviceUnavailable, .networkFailure, .networkUnavailable:
      return error.retryAfterSeconds ?? 5
    case .partialFailure:
      return delay(forRecordFailures: error.partialErrorsByItemID.map { Array($0.values) } ?? [])
    default:
      return nil
    }
  }

  /// A batch is worth sending again when at least one record was told to wait and every other failure is only the
  /// batch rejection that came with it.
  public static func delay(forRecordFailures errors: [any Error]) -> TimeInterval? {
    var delays: [TimeInterval] = []
    for error in errors {
      if (error as? CKError)?.code == .batchRequestFailed { continue }
      guard let delay = delay(for: error) else { return nil }
      delays.append(delay)
    }
    return delays.max()
  }
}

private extension Result {
  var failure: Failure? {
    if case let .failure(error) = self { return error }
    return nil
  }
}
