import SwiftUI

struct RecipeActiveFilterFacet: Identifiable, Equatable {
  let kind: RecipeFilterFacetKind
  let detail: String?
  let selectionCount: Int

  init(kind: RecipeFilterFacetKind, detail: String? = nil, selectionCount: Int) {
    self.kind = kind
    self.detail = detail
    self.selectionCount = selectionCount
  }

  var id: RecipeFilterFacetKind { kind }
}

enum RecipeFilterFacetKind: Hashable, Identifiable, Sendable {
  case library
  case favorites
  case photos
  case categories
  case tags
  case cuisine
  case course
  case sources
  case authors

  var id: Self { self }

  var title: String {
    switch self {
    case .library: "Library"
    case .favorites: "Favorites"
    case .photos: "Photos"
    case .categories: "Categories"
    case .tags: "Tags"
    case .cuisine: "Cuisine"
    case .course: "Course"
    case .sources: "Sources"
    case .authors: "Authors"
    }
  }

  var systemImage: String {
    switch self {
    case .library: "books.vertical"
    case .favorites: "star.fill"
    case .photos: "photo"
    case .categories: "folder"
    case .tags: "tag"
    case .cuisine: "globe.americas"
    case .course: "fork.knife"
    case .sources: "book"
    case .authors: "person.text.rectangle"
    }
  }
}

struct RecipeActiveFilterBar: View {
  let model: RecipeLibraryModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RecipeActiveFilterSummaryHeader(
        resultSummary: model.filteredRecipeCountSummary,
        activeSelectionCount: model.activeFilterSelectionCount
      ) {
        model.clearFiltersButtonTapped()
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.activeFilterFacets) { facet in
            RecipeActiveFilterFacetChip(facet: facet) {
              model.clearFilterFacetButtonTapped(facet.kind)
            }
          }
        }
        .padding(.horizontal)
      }
    }
    .padding(.vertical, 8)
    .background(.bar)
  }
}

private struct RecipeActiveFilterSummaryHeader: View {
  let resultSummary: String
  let activeSelectionCount: Int
  let clearAction: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(resultSummary)
        .font(.caption.weight(.semibold))
      Text("\(activeSelectionCount) \(activeSelectionCount == 1 ? "filter" : "filters")")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Button("Clear") {
        clearAction()
      }
      .font(.caption.weight(.semibold))
    }
    .padding(.horizontal)
  }
}

private struct RecipeActiveFilterFacetChip: View {
  let facet: RecipeActiveFilterFacet
  let clearAction: () -> Void

  var body: some View {
    Button(action: clearAction) {
      HStack(spacing: 7) {
        Image(systemName: facet.kind.systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 18)

        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 4) {
            Text(facet.kind.title)
              .font(.caption.weight(.semibold))
            if facet.selectionCount > 1 {
              Text("\(facet.selectionCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.tertiary.opacity(0.35), in: Capsule())
            }
          }

          if let detail = facet.detail {
            Text(detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Image(systemName: "xmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(maxWidth: 230, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    if let detail = facet.detail {
      "Clear \(facet.kind.title) filter: \(detail)"
    } else {
      "Clear \(facet.kind.title) filter"
    }
  }
}
