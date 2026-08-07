import SwiftUI
import YesChefCore

// Split out of GroceryViews.swift to keep that file under the SwiftLint file-length budget.
// Uses the internal `String.nonEmptyGroceryViewText` helper that stays in GroceryViews.swift.

struct GroceryIngredientChoiceSection: View {
  let title: String
  let choices: [GroceryIngredientChoice]
  @Binding var selectedIngredientLineIDs: Set<IngredientLine.ID>
  var showsRecipeTitle: Bool
  var scale: Double

  var body: some View {
    Section(title) {
      ForEach(choices) { choice in
        Button {
          toggle(choice.line.id)
        } label: {
          GroceryIngredientChoiceRow(
            choice: choice,
            isSelected: selectedIngredientLineIDs.contains(choice.line.id),
            showsRecipeTitle: showsRecipeTitle,
            scale: scale
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func toggle(_ lineID: IngredientLine.ID) {
    if selectedIngredientLineIDs.contains(lineID) {
      selectedIngredientLineIDs.remove(lineID)
    } else {
      selectedIngredientLineIDs.insert(lineID)
    }
  }
}

private struct GroceryIngredientChoiceRow: View {
  let choice: GroceryIngredientChoice
  var isSelected: Bool
  var showsRecipeTitle: Bool
  var scale: Double

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(IngredientScaler.scaledText(for: choice.line, factor: scale))
          .foregroundStyle(.primary)

        if let detailText {
          Text(detailText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var detailText: String? {
    var parts: [String] = []
    if showsRecipeTitle {
      parts.append(choice.recipe.title)
    }
    if let sectionName = choice.section.name?.nonEmptyGroceryViewText {
      parts.append(sectionName)
    }
    if let item = choice.line.item?.nonEmptyGroceryViewText,
       item != choice.line.originalText {
      parts.append(item)
    }
    return parts.joined(separator: " · ").nonEmptyGroceryViewText
  }
}
