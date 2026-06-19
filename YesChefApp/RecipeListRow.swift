import SwiftUI
import YesChefCore

struct RecipeListRow: View {
  let row: RecipeListRowData
  let options: RecipeListViewOptions

  private var recipe: Recipe { row.recipe }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RecipeListThumbnail(data: row.thumbnailData)

      switch options.density {
      case .compact:
        RecipeListCompactContent(
          title: recipe.title,
          subtitleText: recipe.listSubtitleText,
          libraryPlacement: recipe.libraryPlacement,
          isFavorite: recipe.favorite,
          sourceSummary: row.listSourceSummary,
          categorySummary: row.listCategorySummary,
          options: options
        )
      case .rich:
        RecipeListRichContent(
          title: recipe.title,
          subtitleText: recipe.listSubtitleText,
          libraryPlacement: recipe.libraryPlacement,
          isFavorite: recipe.favorite,
          sourceSummary: row.listSourceSummary,
          categorySummary: row.listCategorySummary,
          options: options
        )
      }
    }
    .padding(.vertical, options.rowVerticalPadding)
  }
}

private extension RecipeListViewOptions {
  var rowVerticalPadding: CGFloat {
    switch density {
    case .compact: 2
    case .rich: 4
    }
  }
}

private struct RecipeListCompactContent: View {
  let title: String
  let subtitleText: String?
  let libraryPlacement: RecipeLibraryPlacement
  let isFavorite: Bool
  let sourceSummary: String?
  let categorySummary: String?
  let options: RecipeListViewOptions

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      RecipeListTitleLine(
        title: title,
        libraryPlacement: libraryPlacement,
        isFavorite: isFavorite,
        titleLineLimit: 1
      )

      if let secondarySummary {
        Text(secondarySummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private var secondarySummary: String? {
    let metadataSummary = options.showsSourceMetadata ? sourceSummary : nil
    let fallbackMetadataSummary = options.showsCategoryMetadata ? categorySummary : nil
    return distinctDisplayValues(
      [
        subtitleText,
        metadataSummary ?? fallbackMetadataSummary,
      ]
    )
    .joinedForListRow()
  }
}

private struct RecipeListRichContent: View {
  let title: String
  let subtitleText: String?
  let libraryPlacement: RecipeLibraryPlacement
  let isFavorite: Bool
  let sourceSummary: String?
  let categorySummary: String?
  let options: RecipeListViewOptions

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      RecipeListTitleLine(
        title: title,
        libraryPlacement: libraryPlacement,
        isFavorite: isFavorite,
        titleLineLimit: 2
      )

      if let subtitleText {
        Text(subtitleText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if displayedSourceSummary != nil || displayedCategorySummary != nil {
        RecipeListMetadataStack(
          sourceSummary: displayedSourceSummary,
          categorySummary: displayedCategorySummary
        )
      }
    }
  }

  private var displayedSourceSummary: String? {
    options.showsSourceMetadata ? sourceSummary : nil
  }

  private var displayedCategorySummary: String? {
    options.showsCategoryMetadata ? categorySummary : nil
  }
}

private struct RecipeListTitleLine: View {
  let title: String
  let libraryPlacement: RecipeLibraryPlacement
  let isFavorite: Bool
  let titleLineLimit: Int

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(title)
        .font(.headline)
        .lineLimit(titleLineLimit)
        .layoutPriority(1)

      if libraryPlacement == .reference {
        Text(libraryPlacement.badgeTitle)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary, in: Capsule())
      }

      if isFavorite {
        Image(systemName: "star.fill")
          .font(.caption)
          .foregroundStyle(.yellow)
      }
    }
  }
}

private struct RecipeListMetadataStack: View {
  let sourceSummary: String?
  let categorySummary: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let sourceSummary {
        RecipeListMetadataLine(systemImage: "book", text: sourceSummary)
      }

      if let categorySummary {
        RecipeListMetadataLine(systemImage: "folder", text: categorySummary)
      }
    }
  }
}

private struct RecipeListMetadataLine: View {
  let systemImage: String
  let text: String

  var body: some View {
    Label {
      Text(text)
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .frame(width: 14)
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }
}

private struct RecipeListThumbnail: View {
  let data: Data?

  var body: some View {
    ZStack {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "photo")
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 52, height: 52)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityHidden(true)
  }
}

private extension Recipe {
  var listSubtitleText: String? {
    subtitle.nonEmpty ?? summary.nonEmpty
  }
}

private extension RecipeListRowData {
  var listSourceSummary: String? {
    guard let source else { return nil }
    return distinctDisplayValues(
      [
        source.listDisplayName,
        source.author.nonEmpty,
      ]
    )
    .joinedForListRow()
  }

  var listCategorySummary: String? {
    categoryNames.summarizedForListRow(limit: 2)
  }
}

private extension RecipeSource {
  var listDisplayName: String? {
    name.nonEmpty
      ?? publicationName.nonEmpty
      ?? bookTitle.nonEmpty
      ?? url.nonEmpty
  }
}

private extension Array where Element == String {
  func joinedForListRow() -> String? {
    guard !isEmpty else { return nil }
    return joined(separator: " · ")
  }

  func summarizedForListRow(limit: Int) -> String? {
    guard !isEmpty else { return nil }
    let visibleValues = prefix(limit)
    let remainingCount = count - visibleValues.count
    let visibleSummary = visibleValues.joined(separator: " · ")
    guard remainingCount > 0 else { return visibleSummary }
    return "\(visibleSummary) + \(remainingCount) more"
  }
}

private func distinctDisplayValues(_ values: [String?]) -> [String] {
  var seenValues: Set<String> = []
  return values.compactMap { value in
    guard let value else { return nil }
    let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    guard !seenValues.contains(key) else { return nil }
    seenValues.insert(key)
    return value
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    flatMap(\.nonEmpty)
  }
}
