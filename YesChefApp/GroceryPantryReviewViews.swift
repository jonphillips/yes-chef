import SwiftUI
import YesChefCore

struct GroceryPantryReviewSection: View {
  let rows: [GroceryItemRowData]
  let model: GroceryLibraryModel

  var body: some View {
    if !rows.isEmpty {
      Section("You may need more") {
        ForEach(rows) { row in
          GroceryItemRowView(
            row: row,
            headline: reviewHeadline(for: row),
            includesQuantityInDetail: false,
            togglePurchased: {
              model.togglePurchasedButtonTapped(itemID: row.id)
            },
            deleteItem: {
              model.deleteButtonTapped(itemID: row.id)
            },
            editItem: {
              model.editItemButtonTapped(itemID: row.id)
            },
            deleteSource: { sourceID in
              model.deleteSourceButtonTapped(sourceID: sourceID)
            },
            deleteContribution: { sourceID in
              model.deleteContributionButtonTapped(sourceID: sourceID)
            },
            addToPantry: {
              model.addToPantryButtonTapped(itemID: row.id)
            }
          )
          .swipeActions(edge: .leading) {
            Button {
              model.togglePurchasedButtonTapped(itemID: row.id)
            } label: {
              Label("Mark Purchased", systemImage: "checkmark.circle")
            }
            .tint(.green)
          }
          .swipeActions {
            Button {
              model.editItemButtonTapped(itemID: row.id)
            } label: {
              Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
              model.deleteButtonTapped(itemID: row.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
  }

  private func reviewHeadline(for row: GroceryItemRowData) -> String {
    "You may need more - \(row.item.title) (\(reviewTotalText(for: row.item)))"
  }

  private func reviewTotalText(for item: GroceryItem) -> String {
    if let quantityText = groceryQuantityText(for: item) {
      return "\(quantityText) total"
    }
    return "total needs review"
  }
}

struct GroceryAssumedPantrySection: View {
  let rows: [GroceryItemRowData]
  let model: GroceryLibraryModel

  var body: some View {
    if !rows.isEmpty {
      Section {
        DisclosureGroup {
          ForEach(rows) { row in
            AssumedPantryRowView(
              row: row,
              addBack: {
                model.addBackAssumedPantryItemButtonTapped(itemID: row.id)
              }
            )
          }
        } label: {
          Label("Assumed in pantry", systemImage: "archivebox")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct AssumedPantryRowView: View {
  let row: GroceryItemRowData
  var addBack: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "archivebox")
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 6) {
        Text(row.item.title)
          .font(.headline)
          .foregroundStyle(.secondary)

        if let detailText {
          Text(detailText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        addBack()
      } label: {
        Label("Add Back", systemImage: "cart.badge.plus")
          .labelStyle(.iconOnly)
          .frame(width: 32, height: 32)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Add \(row.item.title) back to list")
    }
    .padding(.vertical, 4)
  }

  private var detailText: String? {
    [
      groceryQuantityText(for: row.item),
      row.item.aisle.map { "· \($0)" },
      row.item.notes.map { "· \($0)" },
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .nonEmptyGroceryPantryReviewText
  }
}

private func groceryQuantityText(for item: GroceryItem) -> String? {
  [
    item.quantityText,
    item.unit,
  ]
  .compactMap { $0?.nonEmptyGroceryPantryReviewText }
  .joined(separator: " ")
  .nonEmptyGroceryPantryReviewText
}

private extension String {
  var nonEmptyGroceryPantryReviewText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
