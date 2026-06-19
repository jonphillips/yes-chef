import SwiftUI
import YesChefCore

struct RecipeListPreset: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var state: RecipeListPresetState
  var dateCreated: Date
  var dateModified: Date
}

struct RecipeListPresetState: Codable, Equatable {
  var searchText: String
  var sortOrder: RecipeListSort
  var libraryScope: RecipeLibraryScope
  var showsFavoritesOnly: Bool
  var showsPhotosOnly: Bool
  var selectedCategoryNames: [String]
  var selectedTagNames: [String]
  var selectedCuisine: String?
  var selectedCourse: String?
  var selectedSourceNames: [String]
  var selectedAuthorNames: [String]

  var isDefault: Bool {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && sortOrder == .title
      && libraryScope == .main
      && !showsFavoritesOnly
      && !showsPhotosOnly
      && selectedCategoryNames.isEmpty
      && selectedTagNames.isEmpty
      && selectedCuisine == nil
      && selectedCourse == nil
      && selectedSourceNames.isEmpty
      && selectedAuthorNames.isEmpty
  }

  var summaryLines: [RecipeListPresetSummaryLine] {
    var lines: [RecipeListPresetSummaryLine] = [
      RecipeListPresetSummaryLine(title: "Sort", detail: sortOrder.title, systemImage: "arrow.up.arrow.down"),
      RecipeListPresetSummaryLine(title: "Library", detail: libraryScope.title, systemImage: "books.vertical"),
    ]

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      lines.append(RecipeListPresetSummaryLine(title: "Search", detail: query, systemImage: "magnifyingglass"))
    }
    if showsFavoritesOnly {
      lines.append(RecipeListPresetSummaryLine(title: "Favorites", detail: "Only favorites", systemImage: "star.fill"))
    }
    if showsPhotosOnly {
      lines.append(RecipeListPresetSummaryLine(title: "Photos", detail: "Only recipes with photos", systemImage: "photo"))
    }
    if !selectedCategoryNames.isEmpty {
      lines.append(
        RecipeListPresetSummaryLine(
          title: "Categories",
          detail: selectedCategoryNames.formattedForPresetSummary(),
          systemImage: "folder"
        )
      )
    }
    if !selectedTagNames.isEmpty {
      lines.append(
        RecipeListPresetSummaryLine(
          title: "Tags",
          detail: selectedTagNames.formattedForPresetSummary(),
          systemImage: "tag"
        )
      )
    }
    if let selectedCuisine {
      lines.append(RecipeListPresetSummaryLine(title: "Cuisine", detail: selectedCuisine, systemImage: "globe.americas"))
    }
    if let selectedCourse {
      lines.append(RecipeListPresetSummaryLine(title: "Course", detail: selectedCourse, systemImage: "fork.knife"))
    }
    if !selectedSourceNames.isEmpty {
      lines.append(
        RecipeListPresetSummaryLine(
          title: "Sources",
          detail: selectedSourceNames.formattedForPresetSummary(),
          systemImage: "book"
        )
      )
    }
    if !selectedAuthorNames.isEmpty {
      lines.append(
        RecipeListPresetSummaryLine(
          title: "Authors",
          detail: selectedAuthorNames.formattedForPresetSummary(),
          systemImage: "person.text.rectangle"
        )
      )
    }

    return lines
  }

  var menuSummary: String {
    if isDefault {
      return "Default list"
    }

    let filterCount = [
      !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      libraryScope != .main,
      showsFavoritesOnly,
      showsPhotosOnly,
      !selectedCategoryNames.isEmpty,
      !selectedTagNames.isEmpty,
      selectedCuisine != nil,
      selectedCourse != nil,
      !selectedSourceNames.isEmpty,
      !selectedAuthorNames.isEmpty,
    ].filter { $0 }.count

    if filterCount == 0 {
      return "Sorted by \(sortOrder.title)"
    }

    let filterText = filterCount == 1 ? "1 filter" : "\(filterCount) filters"
    return "\(filterText) · \(sortOrder.title)"
  }
}

struct RecipeListPresetSummaryLine: Equatable, Identifiable {
  var title: String
  var detail: String
  var systemImage: String

  var id: String { "\(title)-\(detail)-\(systemImage)" }
}

enum RecipeListPresetPersistence {
  static func decode(_ data: Data) -> [RecipeListPreset] {
    guard !data.isEmpty else { return [] }

    do {
      return try JSONDecoder()
        .decode([RecipeListPreset].self, from: data)
        .sortedByName()
    } catch {
      return []
    }
  }

  static func encode(_ presets: [RecipeListPreset]) -> Data {
    do {
      return try JSONEncoder().encode(presets.sortedByName())
    } catch {
      return Data()
    }
  }
}

struct RecipeListPresetMenu: View {
  let presets: [RecipeListPreset]
  let activePresetID: RecipeListPreset.ID?
  let applyPreset: (RecipeListPreset) -> Void
  let saveCurrentView: () -> Void
  let managePresets: () -> Void

  var body: some View {
    Menu {
      Button {
        saveCurrentView()
      } label: {
        Label("Save Current View", systemImage: "plus")
      }

      if !presets.isEmpty {
        Divider()

        ForEach(presets) { preset in
          Button {
            applyPreset(preset)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text(preset.name)
                Text(preset.state.menuSummary)
              }
            } icon: {
              Image(systemName: activePresetID == preset.id ? "checkmark" : "bookmark")
            }
          }
        }

        Divider()

        Button {
          managePresets()
        } label: {
          Label("Manage Saved Views", systemImage: "slider.horizontal.3")
        }
      }
    } label: {
      Label("Saved Views", systemImage: activePresetID == nil ? "bookmark" : "bookmark.fill")
    }
  }
}

struct RecipeListPresetSaveView: View {
  let state: RecipeListPresetState
  let recipeCount: Int
  let existingNames: [String]
  let save: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  var body: some View {
    Form {
      Section {
        StackedTextField(title: "Name", text: $name, prompt: "Favorites for dinner")
          .submitLabel(.done)
      } footer: {
        if isDuplicateName {
          Text("A saved view already uses this name.")
            .foregroundStyle(.red)
        }
      }

      Section("Captured View") {
        RecipeListPresetSummaryView(state: state, recipeCount: recipeCount)
      }
    }
    .navigationTitle("Save View")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          save(trimmedName)
          dismiss()
        }
        .disabled(trimmedName.isEmpty || isDuplicateName)
      }
    }
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isDuplicateName: Bool {
    existingNames.contains { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }
  }
}

struct RecipeListPresetManagementView: View {
  let presets: [RecipeListPreset]
  let activePresetID: RecipeListPreset.ID?
  let recipeCount: (RecipeListPreset) -> Int
  let applyPreset: (RecipeListPreset) -> Void
  let deletePreset: (RecipeListPreset) -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      if presets.isEmpty {
        ContentUnavailableView("No Saved Views", systemImage: "bookmark")
      } else {
        ForEach(presets) { preset in
          RecipeListPresetManagementRow(
            preset: preset,
            isActive: preset.id == activePresetID,
            recipeCount: recipeCount(preset)
          ) {
            applyPreset(preset)
            dismiss()
          }
          .swipeActions {
            Button(role: .destructive) {
              deletePreset(preset)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
    .navigationTitle("Saved Views")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") {
          dismiss()
        }
      }
    }
  }
}

private struct RecipeListPresetManagementRow: View {
  let preset: RecipeListPreset
  let isActive: Bool
  let recipeCount: Int
  let apply: () -> Void

  var body: some View {
    Button(action: apply) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isActive ? "bookmark.fill" : "bookmark")
          .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
          .frame(width: 22)

        VStack(alignment: .leading, spacing: 5) {
          Text(preset.name)
            .font(.headline)
          Text(preset.state.menuSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("\(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct RecipeListPresetSummaryView: View {
  let state: RecipeListPresetState
  let recipeCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label {
        Text("\(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
      } icon: {
        Image(systemName: "fork.knife")
      }

      ForEach(state.summaryLines) { line in
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(line.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(line.detail)
              .lineLimit(2)
          }
        } icon: {
          Image(systemName: line.systemImage)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private extension Array where Element == RecipeListPreset {
  func sortedByName() -> Self {
    sorted { lhs, rhs in
      lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }
}

private extension Array where Element == String {
  func formattedForPresetSummary() -> String {
    prefix(3).joined(separator: ", ") + remainingSummary
  }

  var remainingSummary: String {
    let remainingCount = count - 3
    guard remainingCount > 0 else { return "" }
    return " + \(remainingCount) more"
  }
}
