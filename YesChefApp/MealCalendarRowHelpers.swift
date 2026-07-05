import SwiftUI
import UIKit
import YesChefCore

struct MealPlanRecipeSelectionRow: View {
  let row: RecipeListRowData
  let isSelected: Bool
  var allowsMultipleSelection = false

  var body: some View {
    HStack(spacing: 12) {
      RecipeThumbnail(data: row.thumbnailData)
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 4) {
        Text(row.recipe.title)
          .font(.headline)
        if let subtitle = row.recipe.subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } else if !row.categoryNames.isEmpty {
          Text(row.categoryNames.joined(separator: ", "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer()

      Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
        .foregroundStyle(.tint)
        .accessibilityLabel(isSelected ? "Selected" : selectionAccessibilityLabel)
    }
    .padding(.vertical, 4)
  }

  private var selectionAccessibilityLabel: String {
    allowsMultipleSelection ? "Add recipe to selection" : "Select recipe"
  }
}

struct MealPlanItemImage: View {
  let row: MealPlanItemRowData

  var body: some View {
    if row.item.kind == .recipe {
      RecipeThumbnail(data: row.thumbnailData)
    } else {
      Image(systemName: row.item.kind.systemImage)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quinary)
        .clipShape(.rect(cornerRadius: 8))
    }
  }
}

struct RecipeThumbnail: View {
  let data: Data?

  var body: some View {
    Group {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: "fork.knife")
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.quinary)
      }
    }
    .clipShape(.rect(cornerRadius: 8))
  }
}
