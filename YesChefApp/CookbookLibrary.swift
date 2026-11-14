import CloudKit
import Dependencies
import Foundation
import Observation
import SwiftUI
import YesChefCore

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
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored private let fetchClient: CookbookFetchClient
  @ObservationIgnored private var fetchTask: Task<Void, Never>?
  @ObservationIgnored private var needsFollowUp = false
  @ObservationIgnored private var notificationTask: Task<Void, Never>?
  private let directory: URL
  private let indexURL: URL

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
        await self.fetchCookbooks()
        if let message = notification.userInfo?["error"] as? String { self.acceptanceErrorMessage = message }
      }
    }
    Task { await fetchCookbooks() }
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
        let mirror = try CookbookMirror(id: id, directory: directory)
        let existingContext = contexts.first { $0.zoneOwnerName == ownerID }
        if existingContext == nil {
          try store(CookbookContext(ownerName: ownerID, mirror: mirror, loadedAt: now, zoneOwnerName: ownerID))
        }
        progress[ownerID] = "Fetching"
        do {
          try await CookbookFetcher.fetch(zoneID: zone, mirror: mirror, client: fetchClient) { [weak self] fetched, total in
            await MainActor.run {
              self?.progress[ownerID] = total.map { "Fetching \(fetched) of \($0)" } ?? "Fetching \(fetched)"
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
  @State private var selectedOwnerName: String?

  private var selectedContext: CookbookContext? {
    model.contexts.first { $0.zoneOwnerName == (selectedOwnerName ?? "") }
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
            get: { selectedOwnerName ?? context.zoneOwnerName },
            set: { selectedOwnerName = $0 }
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
      guard let selectedOwnerName,
        !ownerNames.contains(selectedOwnerName)
      else { return }
      self.selectedOwnerName = ownerNames.first
    }
  }
}

private enum CookbookLibrarySurface: String, CaseIterable, Identifiable {
  case recipes = "Recipes"
  case powerBrowser = "Power Browser"

  var id: Self { self }
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
  @State private var surface = CookbookLibrarySurface.recipes
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
    _models = State(initialValue: CookbookLibraryModels(context: context))
  }

  var body: some View {
    @Bindable var recipes = models.recipes
    let mirror = context.mirror
    VStack(spacing: 0) {
      CookbookLibraryHeader(
        context: context,
        contexts: contexts,
        errorMessage: libraryModel.errorMessage,
        progressMessage: libraryModel.progress[context.zoneOwnerName],
        selectedOwnerName: $selectedOwnerName,
        surface: $surface
      )
      Group {
        switch surface {
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
    .environment(\.cookbookDisplayImageLoader, cookbookDisplayImageLoader(mirror: mirror, zoneOwnerName: context.zoneOwnerName))
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
    let updated = context.loadedAt.formatted(date: .abbreviated, time: .shortened)
    let skipped = context.skippedCount == 0 ? "" : " · \(context.skippedCount) need a newer Yes Chef"
    return "\(context.ownerName)'s Recipes · read-only · updated \(updated)\(skipped)"
  }
}
