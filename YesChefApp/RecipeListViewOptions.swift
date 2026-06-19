import SwiftUI

struct RecipeListViewOptions: Equatable {
  var density: RecipeListRowDensity
  var showsSourceMetadata: Bool
  var showsCategoryMetadata: Bool
}

enum RecipeListRowDensity: String, CaseIterable, Identifiable {
  case compact
  case rich

  var id: Self { self }

  var title: String {
    switch self {
    case .compact: "Compact"
    case .rich: "Rich"
    }
  }
}

struct RecipeListViewOptionsMenu: View {
  @Binding var rowDensityRawValue: String
  @Binding var showsSourceMetadata: Bool
  @Binding var showsCategoryMetadata: Bool

  var body: some View {
    Menu {
      Picker("Density", selection: $rowDensityRawValue) {
        ForEach(RecipeListRowDensity.allCases) { density in
          Text(density.title)
            .tag(density.rawValue)
        }
      }

      Divider()

      Toggle("Show Source and Author", isOn: $showsSourceMetadata)
      Toggle("Show Categories", isOn: $showsCategoryMetadata)

      Divider()

      Button("Reset View Options") {
        rowDensityRawValue = RecipeListRowDensity.rich.rawValue
        showsSourceMetadata = true
        showsCategoryMetadata = true
      }
      .disabled(isDefaultSelection)
    } label: {
      Label("View Options", systemImage: "rectangle.grid.1x2")
    }
  }

  private var isDefaultSelection: Bool {
    rowDensityRawValue == RecipeListRowDensity.rich.rawValue
      && showsSourceMetadata
      && showsCategoryMetadata
  }
}
