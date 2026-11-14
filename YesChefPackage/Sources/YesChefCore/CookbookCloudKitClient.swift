import CloudKit
import Foundation

private typealias CookbookModifyResult = (
  saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
  deleteResults: [CKRecord.ID: Result<Void, any Error>]
)

public enum CookbookCloudKitClientFactory {
  public static let containerIdentifier = "iCloud.com.jonphillips.yeschef.cookbook"
  public static let zoneID = CKRecordZone.ID(zoneName: "Cookbook", ownerName: CKCurrentUserDefaultName)

  public static func live(container: CKContainer = CKContainer(identifier: containerIdentifier)) -> CookbookPublishClient {
    let database = container.privateCloudDatabase
    return CookbookPublishClient(
      fetchRecipeHashes: {
        var hashes: [String: String] = [:]
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
          let page = try await database.recordZoneChanges(
            inZoneWith: zoneID, since: token, desiredKeys: ["contentHash"], resultsLimit: 400
          )
          for result in page.modificationResultsByID.values {
            let record = try result.get().record
            guard record.recordType == "CookbookRecipe" else { continue }
            hashes[record.recordID.recordName] = record["contentHash"] as? String ?? ""
          }
          token = page.changeToken
          moreComing = page.moreComing
        }
        return hashes
      },
      saveRecipes: { recipes, progress in
        for start in stride(from: 0, to: recipes.count, by: 400) {
          let batch = Array(recipes[start..<min(start + 400, recipes.count)])
          var temporaryFiles: [URL] = []
          defer { temporaryFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
          let records = try batch.map { recipe -> CKRecord in
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
          let result: CookbookModifyResult
          do {
            result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
          } catch let error as CKError where error.code == .partialFailure || error.code == .quotaExceeded {
            throw Self.publishFailure(error, fallbackCount: batch.count)
          }
          let failures = result.saveResults.values.compactMap { result -> Error? in
            if case let .failure(error) = result { return error }
            return nil
          }
          guard failures.isEmpty else {
            let detail = failures.first.map(describe) ?? "Unknown CloudKit error"
            throw CookbookPublishFailure.failedRecords(count: failures.count, firstError: detail)
          }
          progress(min(start + batch.count, recipes.count))
        }
      },
      deleteRecipes: { names in
        for start in stride(from: 0, to: names.count, by: 400) {
          let batch = names[start..<min(start + 400, names.count)].map {
            CKRecord.ID(recordName: $0, zoneID: zoneID)
          }
          let result: CookbookModifyResult
          do {
            result = try await database.modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
          } catch let error as CKError where error.code == .partialFailure || error.code == .quotaExceeded {
            throw Self.publishFailure(error, fallbackCount: batch.count)
          }
          let failures = result.deleteResults.values.compactMap { result -> Error? in
            if case let .failure(error) = result { return error }
            return nil
          }
          guard failures.isEmpty else {
            throw CookbookPublishFailure.failedRecords(count: failures.count, firstError: failures.first.map(describe) ?? "Unknown CloudKit error")
          }
        }
      },
      fetchProfile: {
        do {
          let record = try await database.record(for: CKRecord.ID(recordName: "profile", zoneID: zoneID))
          guard let displayName = record["displayName"] as? String,
            let recipeCount = record["recipeCount"] as? Int,
            let payloadVersion = record["payloadVersion"] as? Int,
            let publishedAt = record["publishedAt"] as? Date
          else { return nil }
          return CookbookPublishProfile(displayName: displayName, recipeCount: recipeCount, payloadVersion: payloadVersion, publishedAt: publishedAt)
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
          return nil
        }
      },
      saveProfile: { profile in
        let record = CKRecord(recordType: "CookbookProfile", recordID: CKRecord.ID(recordName: "profile", zoneID: zoneID))
        record["displayName"] = profile.displayName as CKRecordValue
        record["recipeCount"] = profile.recipeCount as CKRecordValue
        record["payloadVersion"] = profile.payloadVersion as CKRecordValue
        record["publishedAt"] = profile.publishedAt as CKRecordValue
        _ = try await database.save(record)
      },
      fetchShare: {
        do {
          let record = try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID))
          return record as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
          return nil
        }
      },
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

  private static func fetchShare(in database: CKDatabase) async throws -> CKShare? {
    do {
      let record = try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID))
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

  private static func describe(_ error: Error) -> String {
    guard let error = error as? CKError else { return error.localizedDescription }
    return "CKError \(error.code) (\(error.localizedDescription))"
  }

  private static func publishFailure(_ error: CKError, fallbackCount: Int) -> CookbookPublishFailure {
    let itemErrors = error.partialErrorsByItemID?.values.map { $0 } ?? []
    return .failedRecords(
      count: itemErrors.isEmpty ? fallbackCount : itemErrors.count,
      firstError: itemErrors.first.map(Self.describe) ?? Self.describe(error)
    )
  }
}

private enum CookbookCloudKitError: Error {
  case unexpectedShareRecord
}

public enum CookbookPublishFailure: LocalizedError, Equatable {
  case failedRecords(count: Int, firstError: String)

  public var errorDescription: String? {
    switch self {
    case let .failedRecords(count, firstError): "\(count) CloudKit record(s) failed; first error: \(firstError)"
    }
  }
}
