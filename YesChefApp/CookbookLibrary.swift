import CloudKit
import Dependencies
import Foundation
import Observation
import SwiftUI
import YesChefCore

enum CookbookLibrarySurface: String, CaseIterable, Identifiable {
  case lenses = "Lenses"
  case recipes = "Recipes"
  case powerBrowser = "Power Browser"

  var id: Self { self }
}

@Observable
@MainActor
final class CookbookLibraryModel {
  struct Entry: Codable, Identifiable {
    var id: UUID
    var ownerName: String
    var loadedAt: Date
    var zoneOwnerName: String?
  }

  private(set) var entries: [Entry] = []
  private(set) var contexts: [CookbookContext] = []
  private(set) var isFetching = false
  private(set) var progress: [String: String] = [:]
  private(set) var errorMessage: String?
  var acceptanceErrorMessage: String?
  var selectedZoneOwnerName: String?
  private var selectedSurfaceByOwnerName: [String: CookbookLibrarySurface] = [:]
  var pendingPowerBrowserQuery: RecipeBrowserQuery?
  private(set) var acceptedZoneOwnerName: String?
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored let fetchClient: CookbookFetchClient
  @ObservationIgnored private var fetchTask: Task<Void, Never>?
  @ObservationIgnored private var needsFollowUp = false
  @ObservationIgnored private var notificationTask: Task<Void, Never>?
  /// Keyed by mirror file, not owner: an owner who stops sharing and shares again gets a new mirror, and models
  /// built over the deleted one would read nothing.
  @ObservationIgnored private var modelsByMirror: [URL: CookbookLibraryModels] = [:]
  private let directory: URL
  private let indexURL: URL

  func surface(for context: CookbookContext) -> CookbookLibrarySurface {
    selectedSurfaceByOwnerName[context.zoneOwnerName] ?? .recipes
  }

  func setSurface(_ surface: CookbookLibrarySurface, for context: CookbookContext) {
    selectedSurfaceByOwnerName[context.zoneOwnerName] = surface
  }

  func libraryModels(for context: CookbookContext) -> CookbookLibraryModels {
    if let models = modelsByMirror[context.mirror.fileURL] { return models }
    let models = CookbookLibraryModels(context: context)
    modelsByMirror[context.mirror.fileURL] = models
    return models
  }

  func resolveInitialSurface(for context: CookbookContext, lensCount: Int) {
    guard selectedSurfaceByOwnerName[context.zoneOwnerName] == nil else { return }
    selectedSurfaceByOwnerName[context.zoneOwnerName] = lensCount > 0 ? .lenses : .recipes
  }

  init(
    fetchClient: CookbookFetchClient = CookbookCloudKitClientFactory.fetchClient(),
    directory: URL? = nil
  ) {
    self.fetchClient = fetchClient
    let support = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let cookbookDirectory = support.appendingPathComponent("Cookbooks", isDirectory: true)
    self.directory = cookbookDirectory
    self.indexURL = cookbookDirectory.appendingPathComponent("index.json")
    do {
      try FileManager.default.createDirectory(at: cookbookDirectory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var folder = cookbookDirectory
      try folder.setResourceValues(values)
      if let data = try? Data(contentsOf: indexURL) {
        entries = try JSONDecoder().decode([Entry].self, from: data)
      }
      if entries.contains(where: { $0.zoneOwnerName == nil }) {
        for entry in entries {
          try? CookbookMirror(id: entry.id, directory: cookbookDirectory).deleteMirror()
        }
        entries = []
        contexts = []
        try persist()
      }
      contexts = entries.compactMap { entry in
        guard let mirror = try? CookbookMirror(id: entry.id, directory: cookbookDirectory) else { return nil }
        return CookbookContext(ownerName: entry.ownerName, mirror: mirror, loadedAt: entry.loadedAt,
          zoneOwnerName: entry.zoneOwnerName ?? "")
      }
    } catch {
      entries = []
      contexts = []
    }
  }

  func start() {
    guard notificationTask == nil else { return }
    notificationTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: .cookbookShareAccepted) {
        guard let self else { return }
        if let message = notification.userInfo?["error"] as? String { self.shareAcceptanceFailed(message) }
        else if let ownerName = notification.userInfo?["zoneOwnerName"] as? String { self.shareWasAccepted(in: ownerName) }
        await self.fetchCookbooks()
      }
    }
    Task { await fetchCookbooks() }
  }

  func shareWasAccepted(in zoneOwnerName: String) {
    acceptedZoneOwnerName = zoneOwnerName
  }

  func shareAcceptanceFailed(_ message: String) {
    acceptedZoneOwnerName = nil
    acceptanceErrorMessage = message
  }

  func selectAcceptedCookbookIfReady() -> Bool {
    guard let acceptedZoneOwnerName,
      contexts.contains(where: { $0.zoneOwnerName == acceptedZoneOwnerName })
    else { return false }
    selectedZoneOwnerName = acceptedZoneOwnerName
    self.acceptedZoneOwnerName = nil
    return true
  }

  func sceneBecameActive() { Task { await fetchCookbooks() } }

  func fetchCookbooks() async {
    guard fetchTask == nil else { needsFollowUp = true; return }
    fetchTask = Task { [weak self] in await self?.runFetches() }
    await fetchTask?.value
    fetchTask = nil
    if needsFollowUp { needsFollowUp = false; await fetchCookbooks() }
  }

  private func runFetches() async {
    isFetching = true
    defer { isFetching = false }
    do {
      let zones = try await fetchClient.sharedZones()
      var zoneOwners = Set(zones.map(\.ownerName))
      for zone in zones {
        let ownerID = zone.ownerName
        let entry = entries.first { $0.zoneOwnerName == ownerID }
        let id = entry?.id ?? uuid()
        let existingContext = contexts.first { $0.zoneOwnerName == ownerID }
        let mirror: CookbookMirror
        if let existingContext {
          mirror = existingContext.mirror
        } else {
          mirror = try CookbookMirror(id: id, directory: directory)
        }
        if existingContext == nil {
          try store(CookbookContext(ownerName: "Family cookbook", mirror: mirror, loadedAt: now, zoneOwnerName: ownerID))
        }
        let mirrorState = try mirror.fetchState()
        let expectsFullFetch = mirrorState.changeToken == nil
          || mirrorState.payloadVersion < RecipeBundleCoding.currentVersion
          || mirrorState.fullFetchActive
        progress[ownerID] = expectsFullFetch ? "Fetching" : "Updating…"
        do {
          try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: fetchClient) { [weak self] update in
            await MainActor.run {
              guard let self else { return }
              if update.isFullFetch {
                self.progress[ownerID] = update.total.map { "Fetching \(update.fetched) of \($0)" }
                  ?? "Fetching \(update.fetched)"
              } else {
                self.progress[ownerID] = "Updating…"
              }
              if let displayName = update.displayName { self.updateOwnerName(displayName, zoneOwnerName: ownerID) }
            }
          }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
          try mirror.deleteMirror()
          zoneOwners.remove(ownerID)
          progress.removeValue(forKey: ownerID)
          continue
        }
        let state = try mirror.fetchState()
        let context = CookbookContext(
          ownerName: state.displayName ?? existingContext?.ownerName ?? ownerID,
          mirror: mirror, loadedAt: state.fetchedAt ?? now, zoneOwnerName: ownerID,
          recipeCount: state.recipeCount, skippedCount: try mirror.skippedRecordCount()
        )
        try store(context)
        progress.removeValue(forKey: ownerID)
      }
      let removed = entries.filter { !zoneOwners.contains($0.zoneOwnerName ?? "") }
      for entry in removed {
        if let context = contexts.first(where: { $0.zoneOwnerName == entry.zoneOwnerName }) { try context.mirror.deleteMirror() }
      }
      entries.removeAll { !zoneOwners.contains($0.zoneOwnerName ?? "") }
      contexts.removeAll { !zoneOwners.contains($0.zoneOwnerName) }
      let mirrorURLs = Set(contexts.map(\.mirror.fileURL))
      modelsByMirror = modelsByMirror.filter { mirrorURLs.contains($0.key) }
      try persist()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func persist() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(entries).write(to: indexURL, options: .atomic)
  }

  private func updateOwnerName(_ ownerName: String, zoneOwnerName: String) {
    guard var context = contexts.first(where: { $0.zoneOwnerName == zoneOwnerName }), context.ownerName != ownerName else {
      return
    }
    context.ownerName = ownerName
    do { try store(context) }
    catch { errorMessage = error.localizedDescription }
  }

  private func store(_ context: CookbookContext) throws {
    guard let id = UUID(uuidString: context.mirror.fileURL.deletingPathExtension().lastPathComponent) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    entries.removeAll { $0.id == id || $0.zoneOwnerName == context.zoneOwnerName }
    entries.append(Entry(id: id, ownerName: context.ownerName, loadedAt: context.loadedAt, zoneOwnerName: context.zoneOwnerName))
    try persist()
    contexts.removeAll { $0.mirror.fileURL == context.mirror.fileURL || $0.zoneOwnerName == context.zoneOwnerName }
    contexts.append(context)
    contexts.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
  }

}

struct FamilyCookbooksView: View {
  let model: CookbookLibraryModel
  let copyModel: CookbookCopyModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  private var selectedContext: CookbookContext? {
    model.contexts.first { $0.zoneOwnerName == (model.selectedZoneOwnerName ?? "") }
      ?? model.contexts.first
  }

  var body: some View {
    Group {
      if let context = selectedContext {
        CookbookRecipesView(
          context: context,
          contexts: model.contexts,
          libraryModel: model,
          selectedOwnerName: Binding(
            get: { model.selectedZoneOwnerName ?? context.zoneOwnerName },
            set: { model.selectedZoneOwnerName = $0 }
          ),
          copyModel: copyModel,
          mealCalendarModel: mealCalendarModel,
          groceryModel: groceryModel,
          onRecipeSelected: onRecipeSelected
        )
        .id(context.zoneOwnerName)
      } else {
        ContentUnavailableView {
          Label("No Family Cookbooks", symbol: .libraryShelf)
        }
        .navigationTitle("Family Cookbooks")
      }
    }
    .task { await model.fetchCookbooks() }
    .onChange(of: model.contexts.map(\.zoneOwnerName)) { _, ownerNames in
      if let selected = model.selectedZoneOwnerName, ownerNames.contains(selected) { return }
      model.selectedZoneOwnerName = ownerNames.first
    }
  }
}

private struct CookbookRecipesView: View {

  let context: CookbookContext
  let contexts: [CookbookContext]
  let libraryModel: CookbookLibraryModel
  @Binding var selectedOwnerName: String
  let copyModel: CookbookCopyModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  @State private var models: CookbookLibraryModels
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  init(
    context: CookbookContext,
    contexts: [CookbookContext],
    libraryModel: CookbookLibraryModel,
    selectedOwnerName: Binding<String>,
    copyModel: CookbookCopyModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void
  ) {
    self.context = context
    self.contexts = contexts
    self.libraryModel = libraryModel
    _selectedOwnerName = selectedOwnerName
    self.copyModel = copyModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.onRecipeSelected = onRecipeSelected
    _models = State(initialValue: libraryModel.libraryModels(for: context))
  }

  var body: some View {
    @Bindable var libraryModel = libraryModel
    @Bindable var recipes = models.recipes
    let mirror = context.mirror
    let surface = Binding(
      get: { libraryModel.surface(for: context) },
      set: { libraryModel.setSurface($0, for: context) }
    )
    VStack(spacing: 0) {
      CookbookLibraryHeader(
        context: context,
        contexts: contexts,
        errorMessage: libraryModel.errorMessage,
        progressMessage: libraryModel.progress[context.zoneOwnerName],
        selectedOwnerName: $selectedOwnerName,
        surface: surface
      )
      Group {
        switch libraryModel.surface(for: context) {
        case .lenses:
          CookbookLensesView(context: context, model: models.lenses,
            copyModel: copyModel,
            onRecipeSelected: onRecipeSelected, onBrowseAll: { query in
              models.powerBrowser.query = query
              libraryModel.setSurface(.powerBrowser, for: context)
            })
        case .recipes:
          NavigationSplitView(columnVisibility: $columnVisibility) {
            RecipeListView(model: models.recipes, onArchivedRecipesRequested: {})
          } detail: {
            if let recipe = models.recipes.selectedRecipe {
              withDependencies {
                $0.defaultDatabase = context.mirror.database
              } operation: {
                RecipeDetailView(
                  recipeID: recipe.id,
                  scope: .cookbook(context),
                  libraryModel: models.recipes,
                  mealCalendarModel: mealCalendarModel,
                  groceryModel: groceryModel,
                  cookbookCopyModel: copyModel,
                  isFocusActive: columnVisibility == .detailOnly,
                  focusButtonTapped: focusButtonTapped,
                  onRecipeSelected: onRecipeSelected
                )
              }
              .id(recipe.id)
            } else {
              ContentUnavailableView {
                Label("Select a Recipe", symbol: .source)
              }
            }
          }
        case .powerBrowser:
          PowerBrowserView(model: models.powerBrowser, onRecipeSelected: onRecipeSelected)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // The library's filter sheet is hosted at the app root on the library's own model.
    .sheet(isPresented: $recipes.destination.filterRecipes) {
      NavigationStack {
        RecipeFilterView(model: recipes)
      }
    }
    .environment(\.recipeImageDatabase, context.mirror.database)
    .environment(\.cookbookCopiedSourceIDs, copyModel.copiedSourceIDsByCookbook[context.zoneOwnerName] ?? [])
    .environment(\.cookbookDisplayImageLoader, cookbookDisplayImageLoader(
      fetchClient: libraryModel.fetchClient, mirror: mirror, zoneOwnerName: context.zoneOwnerName
    ))
    .task(id: context.loadedAt) { await copyModel.refreshCopyStatus(context: context) }
    .onChange(of: models.lenses.lensLibrary.lenses.count) { oldCount, newCount in
      libraryModel.resolveInitialSurface(for: context, lensCount: newCount)
    }
    .onAppear {
      libraryModel.resolveInitialSurface(for: context, lensCount: models.lenses.lensLibrary.lenses.count)
      if let query = libraryModel.pendingPowerBrowserQuery {
        models.powerBrowser.query = query
        libraryModel.pendingPowerBrowserQuery = nil
      }
    }
  }

  private func focusButtonTapped() {
    columnVisibility = columnVisibility == .detailOnly ? .doubleColumn : .detailOnly
  }
}

private struct CookbookLibraryHeader: View {
  let context: CookbookContext
  let contexts: [CookbookContext]
  let errorMessage: String?
  let progressMessage: String?
  @Binding var selectedOwnerName: String
  @Binding var surface: CookbookLibrarySurface

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(headerText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      HStack {
        Picker("Cookbook screen", selection: $surface) {
          ForEach(CookbookLibrarySurface.allCases) { surface in Text(surface.rawValue).tag(surface) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        if contexts.count > 1 {
          Menu {
            ForEach(contexts, id: \.zoneOwnerName) { cookbook in
              Button {
                selectedOwnerName = cookbook.zoneOwnerName
              } label: {
                if cookbook.zoneOwnerName == context.zoneOwnerName {
                  Label(cookbook.ownerName, systemImage: "checkmark")
                } else {
                  Text(cookbook.ownerName)
                }
              }
            }
          } label: {
            Label(context.ownerName, systemImage: "chevron.up.chevron.down")
              .labelStyle(.titleAndIcon)
              .font(.caption.weight(.medium))
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private var headerText: String {
    if let error = errorMessage { return error }
    if let progress = progressMessage { return "\(context.ownerName)'s Recipes · \(progress)" }
    let updated = context.loadedAt.formatted(.relative(presentation: .named))
    let skipped = context.skippedCount == 0 ? "" : " · \(context.skippedCount) need a newer Yes Chef"
    return "\(context.ownerName)'s Recipes · read-only · updated \(updated)\(skipped)"
  }
}
