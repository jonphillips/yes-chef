import SwiftUI
import YesChefCore

struct RecipeCategoryFilterAvailability: Equatable {
  let categoryName: String
  let matchingRecipeCount: Int
  let isSelected: Bool

  var isEnabled: Bool {
    isSelected || matchingRecipeCount > 0
  }

  var countText: String {
    "\(matchingRecipeCount)"
  }

  static func empty(categoryName: String) -> Self {
    Self(categoryName: categoryName, matchingRecipeCount: 0, isSelected: false)
  }
}

struct RecipeStringFilterNavigationRow<Destination: View>: View {
  let title: LocalizedStringKey
  let emptyTitle: LocalizedStringKey
  let summary: String
  let symbol: AppSymbol
  let isDefaultSelection: Bool
  let options: [String]
  let destination: Destination

  init(
    title: LocalizedStringKey,
    emptyTitle: LocalizedStringKey,
    summary: String,
    symbol: AppSymbol,
    isDefaultSelection: Bool,
    options: [String],
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.emptyTitle = emptyTitle
    self.summary = summary
    self.symbol = symbol
    self.isDefaultSelection = isDefaultSelection
    self.options = options
    self.destination = destination()
  }

  var body: some View {
    if options.isEmpty {
      Label(emptyTitle, symbol: symbol)
        .foregroundStyle(.secondary)
    } else {
      NavigationLink {
        destination
      } label: {
        StackedFormField(title: title) {
          Label {
            Text(summary)
              .foregroundStyle(isDefaultSelection ? .secondary : .primary)
              .lineLimit(3)
          } icon: {
            Image(symbol: symbol)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

struct RecipeStringFilterPickerView: View {
  let title: String
  let options: [String]
  let popularOptions: [String]
  let remainingOptions: [String]
  let countsByOption: [String: Int]
  let selectedValues: Set<String>
  let symbol: AppSymbol
  let toggle: (String) -> Void
  @State private var searchText = ""

  private var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var filteredOptions: [String] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return options }
    return options.filter { RecipeSearchMatcher.matches(query: query, in: $0) }
  }

  var body: some View {
    List {
      if isSearching {
        RecipeStringFilterSearchSection(
          title: title,
          options: filteredOptions,
          countsByOption: countsByOption,
          selectedValues: selectedValues,
          symbol: symbol,
          toggle: toggle
        )
      } else if options.isEmpty {
        ContentUnavailableView { Label("No \(title)", symbol: symbol) }
      } else {
        if !popularOptions.isEmpty {
          RecipeStringFilterPickerSection(
            title: "Top \(title)",
            options: popularOptions,
            countsByOption: countsByOption,
            selectedValues: selectedValues,
            symbol: symbol,
            toggle: toggle
          )
        }
        if !remainingOptions.isEmpty {
          RecipeStringFilterPickerSection(
            title: popularOptions.isEmpty ? title : "All Other \(title)",
            options: remainingOptions,
            countsByOption: countsByOption,
            selectedValues: selectedValues,
            symbol: symbol,
            toggle: toggle
          )
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $searchText, prompt: "Search \(title.lowercased())")
  }
}

struct RecipeOptionalStringPicker: View {
  let title: String
  @Binding var selection: String?
  let options: [String]

  var body: some View {
    if !options.isEmpty {
      Picker(title, selection: $selection) {
        Text("All")
          .tag(nil as String?)
        ForEach(options, id: \.self) { option in
          Text(option)
            .tag(option as String?)
        }
      }
    }
  }
}

struct RecipeFilterSelectionRow: View {
  let title: String
  let symbol: AppSymbol
  let detail: String?
  let isSelected: Bool
  let isEnabled: Bool
  let action: () -> Void

  init(
    title: String,
    symbol: AppSymbol,
    detail: String? = nil,
    isSelected: Bool,
    isEnabled: Bool = true,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.symbol = symbol
    self.detail = detail
    self.isSelected = isSelected
    self.isEnabled = isEnabled
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(symbol: symbol)
          .foregroundStyle(.secondary)
          .frame(width: 22)
        Text(title)
          .foregroundStyle(isEnabled ? .primary : .secondary)
        Spacer()
        if let detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
        }
      }
      .contentShape(Rectangle())
    }
    .disabled(!isEnabled)
    .buttonStyle(.plain)
  }
}

private struct RecipeStringFilterSearchSection: View {
  let title: String
  let options: [String]
  let countsByOption: [String: Int]
  let selectedValues: Set<String>
  let symbol: AppSymbol
  let toggle: (String) -> Void

  var body: some View {
    if options.isEmpty {
      ContentUnavailableView { Label("No Matching \(title)", symbol: symbol) }
    } else {
      RecipeStringFilterPickerSection(
        title: "Matches",
        options: options,
        countsByOption: countsByOption,
        selectedValues: selectedValues,
        symbol: symbol,
        toggle: toggle
      )
    }
  }
}

private struct RecipeStringFilterPickerSection: View {
  let title: String
  let options: [String]
  let countsByOption: [String: Int]
  let selectedValues: Set<String>
  let symbol: AppSymbol
  let toggle: (String) -> Void

  var body: some View {
    Section(title) {
      ForEach(options, id: \.self) { option in
        RecipeFilterSelectionRow(
          title: option,
          symbol: symbol,
          detail: countsByOption[option].map { String($0) },
          isSelected: selectedValues.contains(option)
        ) {
          toggle(option)
        }
      }
    }
  }
}
