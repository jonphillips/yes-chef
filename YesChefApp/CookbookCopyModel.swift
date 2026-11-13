import Dependencies
import Observation
import YesChefCore

@Observable
@MainActor
final class CookbookCopyModel {
  enum Prompt: Identifiable {
    case existingCopies(context: CookbookContext, sourceID: Recipe.ID, ids: [Recipe.ID])
    case copyResult(CookbookCopyResult)
    case failure(String)

    var id: String {
      switch self {
      case let .existingCopies(_, sourceID, _): "existing-\(sourceID.uuidString)"
      case let .copyResult(result): "copied-\(result.recipeID.uuidString)"
      case let .failure(message): "failure-\(message)"
      }
    }
  }

  @ObservationIgnored @Dependency(\.defaultDatabase) private var libraryDatabase
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  private(set) var copyIDsBySource: [Recipe.ID: [Recipe.ID]] = [:]
  var prompt: Prompt?
  private var pendingCopy: (context: CookbookContext, sourceID: Recipe.ID, bundle: RecipeBundleCoding.RecipeBundle)?
  var toastCenter: AppToastCenter?

  func refreshCopyStatus(context: CookbookContext, sourceID: Recipe.ID) async {
    do {
      guard let bundle = try await context.mirror.database.read({
        try CookbookPayload.bundle(for: sourceID, in: $0)
      }) else { return }
      copyIDsBySource[sourceID] = try await libraryDatabase.read {
        try RecipeRepository.existingCopies(of: bundle, in: $0)
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
      copyIDsBySource[sourceID] = copies
      if !copies.isEmpty {
        pendingCopy = (context, sourceID, bundle)
        prompt = .existingCopies(context: context, sourceID: sourceID, ids: copies)
      } else {
        try await copy(bundle, context: context, sourceID: sourceID)
      }
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func copyAnywayButtonTapped() async {
    guard let pendingCopy else { return }
    do {
      try await copy(pendingCopy.bundle, context: pendingCopy.context, sourceID: pendingCopy.sourceID)
      self.pendingCopy = nil
    } catch {
      prompt = .failure(String(describing: error))
    }
  }

  func newestCopy(of ids: [Recipe.ID]) async -> Recipe.ID? {
    guard !ids.isEmpty else { return nil }
    return try? await libraryDatabase.read { db in
      try Recipe.fetchAll(db)
        .filter { ids.contains($0.id) }
        .max { $0.dateCreated < $1.dateCreated }?.id
    }
  }

  func clearPrompt() {
    prompt = nil
  }

  private func copy(
    _ bundle: RecipeBundleCoding.RecipeBundle,
    context: CookbookContext,
    sourceID: Recipe.ID
  ) async throws {
    let copyDate = now
    let makeUUID = uuid
    let result = try await libraryDatabase.write { db in
      try RecipeRepository.copyCookbookRecipe(
        bundle,
        ownerName: context.ownerName,
        displayImages: [:],
        in: db,
        now: copyDate,
        uuid: { makeUUID() }
      )
    }
    copyIDsBySource[sourceID, default: []].append(result.recipeID)
    if result.textOnlyServeWith.isEmpty && result.unlinkedRelated.isEmpty && result.warnings.isEmpty {
      prompt = nil
    } else {
      prompt = .copyResult(result)
    }
    toastCenter?.postSuccess("Copied to My Recipes")
  }
}
