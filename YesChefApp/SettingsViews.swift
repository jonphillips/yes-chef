import SwiftUI
import UniformTypeIdentifiers
import YesChefCore

struct SettingsView: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  private let selectedPane: Binding<SettingsPane?>?
  @State private var syncHealth = SyncHealthModel()
  @State private var backupExport = YesChefDatabaseBackupExportModel()
  @State private var backupExportDocument: BackupExportDocument?
  @State private var backupExportFilename = "YesChef-Backup.sqlite"
  @State private var isPresentingBackupExporter = false
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
          Task {
            guard let snapshot = await backupExport.prepareBackupForExport() else { return }
            backupExportDocument = BackupExportDocument(snapshot: snapshot)
            backupExportFilename = backupExport.defaultFilename()
            isPresentingBackupExporter = true
          }
        } label: {
          Label("Export a Backup", systemImage: "externaldrive.badge.checkmark")
        }
        .disabled(backupExport.isPreparing)

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
#if DEBUG
        modelCallInventoryRow
#endif
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
    .fileExporter(
      isPresented: $isPresentingBackupExporter,
      document: backupExportDocument,
      contentType: .yesChefSQLiteBackup,
      defaultFilename: backupExportFilename,
      onCompletion: backupExportCompleted,
      onCancellation: backupExportCancelled
    )
    .alert("Could Not Export Backup", isPresented: backupExportErrorPresented) {
      Button("OK") {
        backupExport.dismissError()
      }
    } message: {
      Text(backupExport.errorMessage ?? "")
    }
  }

  private var backupExportErrorPresented: Binding<Bool> {
    Binding(
      get: { backupExport.errorMessage != nil },
      set: { isPresented in
        guard !isPresented else { return }
        backupExport.dismissError()
      }
    )
  }

  private func backupExportCompleted(_ result: Result<URL, any Error>) {
    defer { clearPreparedBackup() }
    guard case let .failure(error) = result else { return }
    backupExport.recordExportFailure(error)
  }

  private func backupExportCancelled() {
    clearPreparedBackup()
  }

  private func clearPreparedBackup() {
    if let backupExportDocument {
      backupExport.discard(backupExportDocument.snapshot)
    }
    backupExportDocument = nil
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

#if DEBUG
  @ViewBuilder private var modelCallInventoryRow: some View {
    if let selectedPane {
      Button {
        selectedPane.wrappedValue = .modelCallInventory
      } label: {
        SettingsPane.modelCallInventory.label
      }
      .foregroundStyle(.primary)
    } else {
      NavigationLink {
        ModelCallInventoryView()
      } label: {
        SettingsPane.modelCallInventory.label
      }
    }
  }
#endif
}

private final class BackupExportDocument: WritableDocument {
  typealias Writer = BackupExportDocumentWriter

  static let writableContentTypes: [UTType] = [.yesChefSQLiteBackup]

  let snapshot: YesChefDatabaseBackup.Snapshot

  init(snapshot: YesChefDatabaseBackup.Snapshot) {
    self.snapshot = snapshot
  }

  func writer(configuration: sending DocumentWriteConfiguration) -> sending BackupExportDocumentWriter {
    BackupExportDocumentWriter()
  }

  func snapshot(contentType: UTType) async throws -> sending URL {
    snapshot.fileURL
  }
}

private struct BackupExportDocumentWriter: DocumentWriter {
  typealias Snapshot = URL

  func write(
    snapshot: sending URL,
    to destination: sending URL,
    previous: sending URL?,
    progress: consuming Subprogress
  ) async throws {
    try FileManager.default.copyItem(at: snapshot, to: destination)
  }
}

private extension UTType {
  static let yesChefSQLiteBackup = UTType(
    exportedAs: "com.jonphillips.yeschef.database-backup",
    conformingTo: .data
  )
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
#if DEBUG
    case .modelCallInventory:
      NavigationStack {
        ModelCallInventoryView()
      }
#endif
    case nil:
      ContentUnavailableView("Settings", systemImage: AppSection.settings.systemImage)
    }
  }
}
