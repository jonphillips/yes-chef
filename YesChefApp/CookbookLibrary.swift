import Dependencies
import Foundation
import Observation
import SwiftUI
import UIKit
import YesChefCore

@Observable
@MainActor
final class CookbookLibraryModel {
  struct Entry: Codable, Identifiable {
    var id: UUID
    var ownerName: String
    var loadedAt: Date
  }

  private(set) var entries: [Entry] = []
  private(set) var contexts: [CookbookContext] = []
  @ObservationIgnored @Dependency(\.defaultDatabase) private var libraryDatabase
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  private let directory: URL
  private let indexURL: URL

  struct LoadResult {
    var appliedCount: Int
    var newerVersionSkippedCount: Int
    var elapsedSeconds: Double
  }

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    directory = support.appendingPathComponent("Cookbooks", isDirectory: true)
    indexURL = directory.appendingPathComponent("index.json")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var folder = directory
      try folder.setResourceValues(values)
      if let data = try? Data(contentsOf: indexURL) {
        entries = try JSONDecoder().decode([Entry].self, from: data)
      }
      contexts = entries.compactMap { entry in
        guard let mirror = try? CookbookMirror(id: entry.id, directory: directory) else { return nil }
        return CookbookContext(ownerName: entry.ownerName, mirror: mirror, loadedAt: entry.loadedAt)
      }
    } catch {
      entries = []
      contexts = []
    }
  }

  func register(id: UUID, ownerName: String, loadedAt: Date) throws -> CookbookContext {
    let mirror = try CookbookMirror(id: id, directory: directory)
    let context = CookbookContext(ownerName: ownerName, mirror: mirror, loadedAt: loadedAt)
    try store(context)
    return context
  }

  func exportCookbookFile() async throws -> URL {
    let bundles = try await libraryDatabase.read { try CookbookPayload.bundles(in: $0) }
    let payloads = try bundles.map(CookbookPayload.encodedPayload)
    let file = CookbookFile(ownerName: Self.deviceOwnerName, generatedAt: now, payloads: payloads)
    let data = try JSONEncoder().encode(file)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChef-\(Self.deviceOwnerName)-Cookbook")
      .appendingPathExtension("json")
    try data.write(to: url, options: .atomic)
    return url
  }

  func loadCookbookFile(at url: URL) async throws -> LoadResult {
    let startedAt = Date()
    let didAccess = url.startAccessingSecurityScopedResource()
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
    let file = try JSONDecoder().decode(CookbookFile.self, from: Data(contentsOf: url))
    let decoded = try file.decodedPayloads()
    let existingEntry = entries.first { $0.ownerName.caseInsensitiveCompare(file.ownerName) == .orderedSame }
    let id = existingEntry?.id ?? uuid()
    if let existing = contexts.first(where: { $0.ownerName.caseInsensitiveCompare(file.ownerName) == .orderedSame }) {
      let currentIDs = try await existing.mirror.database.read { try Recipe.fetchAll($0).map(\.id) }
      let incomingIDs = Set(decoded.bundles.map { $0.recipe.id })
      try existing.mirror.apply(
        upserting: decoded.bundles,
        deleting: currentIDs.filter { !incomingIDs.contains($0) }
      )
      let context = CookbookContext(ownerName: file.ownerName, mirror: existing.mirror, loadedAt: file.generatedAt)
      try store(context)
    } else {
      if existingEntry != nil {
      let stale = try CookbookMirror(id: id, directory: directory)
      try stale.deleteMirror()
      }
      entries.removeAll { $0.id == id || $0.ownerName.caseInsensitiveCompare(file.ownerName) == .orderedSame }
      contexts.removeAll { $0.ownerName.caseInsensitiveCompare(file.ownerName) == .orderedSame }
      let mirror = try CookbookMirror(id: id, directory: directory)
      try mirror.apply(upserting: decoded.bundles, deleting: [])
      try store(CookbookContext(ownerName: file.ownerName, mirror: mirror, loadedAt: file.generatedAt))
    }
    return LoadResult(
      appliedCount: decoded.bundles.count,
      newerVersionSkippedCount: decoded.newerVersionCount,
      elapsedSeconds: Date().timeIntervalSince(startedAt)
    )
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
    entries.removeAll { $0.id == id || $0.ownerName.caseInsensitiveCompare(context.ownerName) == .orderedSame }
    entries.append(Entry(id: id, ownerName: context.ownerName, loadedAt: context.loadedAt))
    try persist()
    contexts.removeAll { $0.mirror.fileURL == context.mirror.fileURL || $0.ownerName.caseInsensitiveCompare(context.ownerName) == .orderedSame }
    contexts.append(context)
    contexts.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
  }

  private static var deviceOwnerName: String {
    var name = UIDevice.current.name
    for suffix in ["'s iPhone", "'s iPad", "'s Mac"] where name.hasSuffix(suffix) {
      name.removeLast(suffix.count)
      break
    }
    return name.isEmpty ? "My" : name
  }

}

struct CookbookShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct FamilyCookbooksView: View {
  let model: CookbookLibraryModel
  let copyModel: CookbookCopyModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    NavigationStack {
      List(model.contexts, id: \.self) { context in
        NavigationLink(value: context) {
          Label("\(context.ownerName)'s Recipes", symbol: .libraryShelf)
        }
      }
      .overlay {
        if model.contexts.isEmpty {
          ContentUnavailableView {
            Label("No Family Cookbooks", symbol: .libraryShelf)
          }
        }
      }
      .navigationTitle("Family Cookbooks")
      .navigationDestination(for: CookbookContext.self) { context in
        let currentContext = model.contexts.first(where: { $0.ownerName.caseInsensitiveCompare(context.ownerName) == .orderedSame }) ?? context
        CookbookRecipesView(
          context: currentContext,
          copyModel: copyModel,
          mealCalendarModel: mealCalendarModel,
          groceryModel: groceryModel,
          onRecipeSelected: onRecipeSelected
        )
      }
    }
  }
}

private struct CookbookRecipesView: View {
  private enum Surface: String, CaseIterable, Identifiable {
    case recipes = "Recipes"
    case powerBrowser = "Power Browser"

    var id: Self { self }
  }

  let context: CookbookContext
  let copyModel: CookbookCopyModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let onRecipeSelected: (RecipeDetailPresentation) -> Void
  @State private var models: CookbookLibraryModels
  @State private var surface = Surface.recipes
  @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

  init(
    context: CookbookContext,
    copyModel: CookbookCopyModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void
  ) {
    self.context = context
    self.copyModel = copyModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.onRecipeSelected = onRecipeSelected
    _models = State(initialValue: CookbookLibraryModels(context: context))
  }

  var body: some View {
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
    .safeAreaInset(edge: .top, spacing: 0) {
      Text("\(context.ownerName)'s Recipes · read-only · loaded \(context.loadedAt.formatted(date: .abbreviated, time: .shortened))")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Cookbook screen", selection: $surface) {
          ForEach(Surface.allCases) { surface in Text(surface.rawValue).tag(surface) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
      }
    }
  }
}
