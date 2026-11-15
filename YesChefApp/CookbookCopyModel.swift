import CloudKit
import Dependencies
import Observation
import YesChefCore

@Observable
@MainActor
final class CookbookCopyModel {
  enum Prompt: Identifiable {
    case existingCopies(context: CookbookContext, sourceID: Recipe.ID, ids: [Recipe.ID])
    case copyResult(CookbookCopyResult)
    case missingTargets(CookbookCopyResult)
    case failure(String)

    var id: String {
      switch self {
      case let .existingCopies(_, sourceID, _): "existing-\(sourceID.uuidString)"
      case let .copyResult(result): "copied-\(result.recipeID.uuidString)"
      case let .missingTargets(result): "missing-\(result.recipeID.uuidString)"
      case let .failure(message): "failure-\(message)"
      }
    }
  }

  private struct PendingCopy {
    var context: CookbookContext
    var bundle: RecipeBundleCoding.RecipeBundle
  }

  @ObservationIgnored @Dependency(\.defaultDatabase) private var libraryDatabase
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored let fetchClient: CookbookFetchClient

  private(set) var copiedSourceIDsByCookbook: [String: Set<Recipe.ID>] = [:]
  var prompt: Prompt?
  private var pendingCopy: PendingCopy?
  var toastCenter: AppToastCenter?

  init(fetchClient: CookbookFetchClient = CookbookCloudKitClientFactory.fetchClient()) {
    self.fetchClient = fetchClient
  }

  func refreshCopyStatus(context: CookbookContext) async {
    do {
      let keys = try await context.mirror.database.read { try CookbookPayload.identityKeys(in: $0) }
      copiedSourceIDsByCookbook[context.zoneOwnerName] = try await libraryDatabase.read {
        try RecipeRepository.copiedSourceIDs(keys, in: $0)
      }
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func copyButtonTapped(context: CookbookContext, sourceID: Recipe.ID) async {
    do {
      guard let bundle = try await context.mirror.database.read({
        try CookbookPayload.bundle(for: sourceID, in: $0)
      }) else { throw CookbookCopyError.missingParent(sourceID) }
      let copies = try await libraryDatabase.read {
        try RecipeRepository.existingCopies(of: bundle, in: $0)
      }
      if !copies.isEmpty {
        pendingCopy = PendingCopy(context: context, bundle: bundle)
        prompt = .existingCopies(context: context, sourceID: sourceID, ids: copies)
      } else {
        pendingCopy = PendingCopy(context: context, bundle: bundle)
        try await copy(bundle, context: context)
      }
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func copyAnywayButtonTapped() async {
    guard let pendingCopy else { return }
    do {
      try await copy(pendingCopy.bundle, context: pendingCopy.context)
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func copyThemTooButtonTapped(_ initialResult: CookbookCopyResult) async {
    guard let pendingCopy else { return }
    do {
      let targets = try await pendingCopy.context.mirror.database.read { db in
        try initialResult.uncopiedTargets.compactMap { id in
          try CookbookPayload.bundle(for: id, in: db)
        }
      }
      let foundIDs = Set(targets.map { $0.recipe.id })
      let missingIDs = initialResult.uncopiedTargets.filter { !foundIDs.contains($0) }
      let copies = await withPhotoData(for: targets, context: pendingCopy.context)
      let copyDate = now
      let makeUUID = uuid
      let copyWarnings = try await libraryDatabase.write { db -> [String] in
        var warnings: [String] = []
        for (bundle, images, _) in copies {
          let copyResult = try RecipeRepository.copyCookbookRecipe(bundle, ownerName: pendingCopy.context.ownerName,
            displayImages: images, in: db, now: copyDate, uuid: { makeUUID() })
          warnings.append(contentsOf: copyResult.warnings)
        }
        try RecipeRepository.relinkCookbookCopy(initialResult.recipeID, from: pendingCopy.bundle,
          in: db, now: copyDate, uuid: { makeUUID() })
        return warnings
      }
      await refreshCopyStatus(context: pendingCopy.context)
      let count = copies.count + 1
      let firstCopyID = initialResult.recipeID
      var result = initialResult
      result.warnings.append(contentsOf: copyWarnings)
      result.warnings.append(contentsOf: copies.compactMap(\.2))
      if !missingIDs.isEmpty {
        let names = missingIDs.map { id in
          pendingCopy.bundle.linkTargets.first { $0.recipeID == id }?.title
            ?? pendingCopy.bundle.serveWith.first { $0.linkedRecipeID == id }?.title
            ?? id.uuidString
        }
        result.warnings.append("Not available in this cookbook: \(names.joined(separator: ", ")).")
        prompt = .missingTargets(result)
      } else if result.warnings.isEmpty {
        prompt = nil
      } else {
        prompt = .copyResult(result)
      }
      let recipeNoun = count == 1 ? "recipe" : "recipes"
      toastCenter?.postSuccess("Copied \(count) \(recipeNoun)", actionTitle: "Open", action: .openRecipe(firstCopyID))
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func newestCopy(of ids: [Recipe.ID]) async -> Recipe.ID? {
    guard !ids.isEmpty else { return nil }
    return try? await libraryDatabase.read { db in
      try Recipe.fetchAll(db).filter { ids.contains($0.id) }.max { $0.dateCreated < $1.dateCreated }?.id
    }
  }

  func clearPrompt() {
    prompt = nil
    pendingCopy = nil
  }

  /// SwiftUI writes `false` to an alert's binding before the tapped button's action runs, so dismissal
  /// clears only the prompt. The pending copy survives for Copy Anyway and Copy Them Too.
  func promptDismissed() {
    prompt = nil
  }

  private func copy(
    _ bundle: RecipeBundleCoding.RecipeBundle, context: CookbookContext
  ) async throws {
    let (displayImages, photoWarning) = await displayImageData(for: bundle, context: context)
    let copyDate = now
    let makeUUID = uuid
    var result = try await libraryDatabase.write { db in
      try RecipeRepository.copyCookbookRecipe(bundle, ownerName: context.ownerName,
        displayImages: displayImages, in: db, now: copyDate, uuid: { makeUUID() })
    }
    if let photoWarning { result.warnings.append(photoWarning) }
    await refreshCopyStatus(context: context)
    if result.textOnlyServeWith.isEmpty && result.unlinkedRelated.isEmpty
      && result.uncopiedTargets.isEmpty && result.warnings.isEmpty
    {
      prompt = nil
      pendingCopy = nil
    } else {
      prompt = .copyResult(result)
    }
    toastCenter?.postSuccess("Copied to My Recipes", actionTitle: "Open", action: .openRecipe(result.recipeID))
  }

  private func withPhotoData(
    for bundles: [RecipeBundleCoding.RecipeBundle], context: CookbookContext
  ) async -> [(RecipeBundleCoding.RecipeBundle, [RecipePhoto.ID: Data], String?)] {
    var result: [(RecipeBundleCoding.RecipeBundle, [RecipePhoto.ID: Data], String?)] = []
    for bundle in bundles {
      let image = await Self.displayImageData(for: bundle, context: context, fetchClient: fetchClient)
      result.append((bundle, image.data, image.warning))
    }
    return result
  }

  private func displayImageData(
    for bundle: RecipeBundleCoding.RecipeBundle, context: CookbookContext
  ) async -> ([RecipePhoto.ID: Data], String?) {
    let result = await Self.displayImageData(for: bundle, context: context, fetchClient: fetchClient)
    return (result.data, result.warning)
  }

  private static func displayImageData(
    for bundle: RecipeBundleCoding.RecipeBundle, context: CookbookContext,
    fetchClient: CookbookFetchClient
  ) async -> (data: [RecipePhoto.ID: Data], warning: String?) {
    guard let photoID = CookbookPayload.displayPhotoID(for: bundle.recipe, photos: bundle.photos) else {
      return ([:], nil)
    }
    let cached = try? await context.mirror.database.read({
      try RecipePhoto.find(photoID).select(\.displayData).fetchOne($0)
    })
    if let cached = cached ?? nil {
      return ([photoID: cached], nil)
    }
    do {
      let zoneID = CKRecordZone.ID(zoneName: "Cookbook", ownerName: context.zoneOwnerName)
      let data = try await fetchClient.fetchDisplayImage(zoneID, bundle.recipe.id.uuidString)
      try context.mirror.cacheDisplayImage(data, photoID: photoID)
      return ([photoID: data], nil)
    } catch CookbookFetchError.missingDisplayImage {
      return ([:], nil)
    } catch {
      return ([:], "The full photo couldn’t load; the copy has the thumbnail.")
    }
  }
}
