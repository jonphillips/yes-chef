import SwiftUI

struct SettingsStack: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel

  var body: some View {
    NavigationStack {
      SettingsView(model: model, groceryModel: groceryModel)
    }
  }
}

struct SettingsView: View {
  let model: RecipeLibraryModel
  let groceryModel: GroceryLibraryModel
  private let selectedPane: Binding<SettingsPane?>?

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
      Section("Library") {
        categoryRow
        pantryRow
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
    }
    .navigationTitle("Settings")
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
}

struct SettingsDetailPane: View {
  let selectedPane: SettingsPane?
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
    case nil:
      ContentUnavailableView("Settings", systemImage: AppSection.settings.systemImage)
    }
  }
}
