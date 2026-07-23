import SwiftUI
import YesChefCore

struct SettingsView: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  private let selectedPane: Binding<SettingsPane?>?
  @State private var syncHealth = SyncHealthModel()
  @Environment(\.scenePhase) private var scenePhase

  init(
    model: RecipeLibraryModel,
    groceryModel: GroceryLibraryModel,
    selectedPane: Binding<SettingsPane?>? = nil
  ) {
    self.model = model
    self.groceryModel = groceryModel
    self.selectedPane = selectedPane
  }

  var body: some View {
    Form {
      // Above Library so "am I actually syncing?" is the first thing Settings answers
      // — silent degradation is fine for dev, not for cross-device use (ADR-0003).
      SyncStatusSection(model: syncHealth)

      Section("Library") {
        categoryRow
        pantryRow
        archivedRecipesRow
      }

      Section("AI") {
        aiRow
      }

      Section("Import & Export") {
        Button {
          model.importPaprikaExportButtonTapped()
        } label: {
          Label("Import Paprika HTML Export", systemImage: "square.and.arrow.down")
        }
        .disabled(model.isImporting)

        Button {
          model.supplementPaprikaBackupButtonTapped()
        } label: {
          Label("Supplement Paprika Backup", systemImage: "calendar.badge.clock")
        }
        .disabled(model.isImporting)
      }

      Section("Developer") {
        seedCoverageRow
      }
    }
    .navigationTitle("Settings")
    // Refresh the sync signals on appear, on scene activation (the same hook that
    // drives the pending-change redrain), and on cross-process DB changes.
    .task { await syncHealth.refresh() }
    .task {
      for await _ in NotificationCenter.default.notifications(named: DatabaseChangeBeacon.didChange) {
        await syncHealth.refresh()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await syncHealth.refresh() }
    }
    // When a sync cycle finishes (the engine's observable activity flips), re-read the
    // pending count so "Syncing…" clears to "Up to date" as changes drain.
    .onChange(of: syncHealth.isSynchronizing) { _, _ in
      Task { await syncHealth.refresh() }
    }
  }

  @ViewBuilder private var categoryRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .categories
      } label: {
        SettingsPane.categories.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        CategoryManagementView()
      } label: {
        SettingsPane.categories.label
      }
    }
  }

  @ViewBuilder private var pantryRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .pantry
      } label: {
        SettingsPane.pantry.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        PantrySettingsView(model: groceryModel)
      } label: {
        SettingsPane.pantry.label
      }
    }
  }

  @ViewBuilder private var aiRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .ai
      } label: {
        SettingsPane.ai.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        AISettingsView()
      } label: {
        SettingsPane.ai.label
      }
    }
  }

  @ViewBuilder private var archivedRecipesRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .archivedRecipes
      } label: {
        SettingsPane.archivedRecipes.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        ArchivedRecipesView(model: model)
      } label: {
        SettingsPane.archivedRecipes.label
      }
    }
  }

  @ViewBuilder private var seedCoverageRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .seedCoverage
      } label: {
        SettingsPane.seedCoverage.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        SeedCoverageView()
      } label: {
        SettingsPane.seedCoverage.label
      }
    }
  }
}

struct SettingsDetailPane: View {
  let selectedPane: SettingsPane?
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel

  var body: some View {
    switch selectedPane {
    case .ai:
      NavigationStack {
        AISettingsView()
      }
    case .categories:
      NavigationStack {
        CategoryManagementView()
      }
    case .pantry:
      NavigationStack {
        PantrySettingsView(model: groceryModel)
      }
    case .archivedRecipes:
      NavigationStack {
        ArchivedRecipesView(model: model)
      }
    case .seedCoverage:
      SeedCoverageView()
    case nil:
      ContentUnavailableView("Settings", systemImage: AppSection.settings.systemImage)
    }
  }
}
