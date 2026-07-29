import SwiftUI

/// A row-grain editor for sections whose items can be addressed independently.
struct EditableRowsSection<Item: Identifiable, EmptyState: View, ItemContent: View, Badge: View>: View {
  let title: String
  let titleFont: Font
  let editorLabel: String
  let items: [Item]
  let itemText: KeyPath<Item, String>
  var addItem: ((String) -> Bool)? = nil
  var addButtonLabel: String? = nil
  let updateItem: (Item, String) -> Void
  let deleteItem: (Item) -> Void
  var reorderItems: (([Item.ID], Item.ID?) -> Void)? = nil
  let emptyState: () -> EmptyState
  let itemContent: (Item) -> ItemContent
  let badge: ((Item) -> Badge)?

  @State private var isAdding = false
  @State private var newItemText = ""
  @FocusState private var isNewItemFocused: Bool

  init(
    title: String,
    titleFont: Font,
    editorLabel: String,
    items: [Item],
    itemText: KeyPath<Item, String>,
    addItem: ((String) -> Bool)? = nil,
    addButtonLabel: String? = nil,
    updateItem: @escaping (Item, String) -> Void,
    deleteItem: @escaping (Item) -> Void,
    reorderItems: (([Item.ID], Item.ID?) -> Void)? = nil,
    @ViewBuilder emptyState: @escaping () -> EmptyState,
    @ViewBuilder itemContent: @escaping (Item) -> ItemContent,
    @ViewBuilder badge: @escaping (Item) -> Badge
  ) {
    self.title = title
    self.titleFont = titleFont
    self.editorLabel = editorLabel
    self.items = items
    self.itemText = itemText
    self.addItem = addItem
    self.addButtonLabel = addButtonLabel
    self.updateItem = updateItem
    self.deleteItem = deleteItem
    self.reorderItems = reorderItems
    self.emptyState = emptyState
    self.itemContent = itemContent
    self.badge = badge
  }

  init(
    title: String,
    titleFont: Font,
    editorLabel: String,
    items: [Item],
    itemText: KeyPath<Item, String>,
    addItem: ((String) -> Bool)? = nil,
    addButtonLabel: String? = nil,
    updateItem: @escaping (Item, String) -> Void,
    deleteItem: @escaping (Item) -> Void,
    reorderItems: (([Item.ID], Item.ID?) -> Void)? = nil,
    @ViewBuilder emptyState: @escaping () -> EmptyState,
    @ViewBuilder itemContent: @escaping (Item) -> ItemContent
  ) where Badge == EmptyView {
    self.init(
      title: title,
      titleFont: titleFont,
      editorLabel: editorLabel,
      items: items,
      itemText: itemText,
      addItem: addItem,
      addButtonLabel: addButtonLabel,
      updateItem: updateItem,
      deleteItem: deleteItem,
      reorderItems: reorderItems,
      emptyState: emptyState,
      itemContent: itemContent,
      badge: { _ in EmptyView() }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if isAdding {
        addEditor
      }
      if items.isEmpty && !isAdding {
        emptyState()
      } else if !items.isEmpty {
        rows
      }
    }
    .onChange(of: isAdding) { _, isAdding in
      isNewItemFocused = isAdding
    }
  }

  private var header: some View {
    HStack {
      Text(title)
        .font(titleFont)
      Spacer()
      if addItem != nil {
        Button {
          isAdding = true
        } label: {
          Label(addButtonLabel ?? "Add \(title)", systemImage: "plus")
        }
      }
    }
  }

  private var addEditor: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField(editorLabel, text: $newItemText, axis: .vertical)
        .lineLimit(2...6)
        .focused($isNewItemFocused)
      HStack {
        Button("Cancel") {
          newItemText = ""
          isAdding = false
        }
        Spacer()
        Button("Add") {
          guard addItem?(newItemText) == true else { return }
          newItemText = ""
          isAdding = false
        }
        .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .attentionCard()
  }

  @ViewBuilder
  private var rows: some View {
    if let reorderItems {
      reorderableRows(reorderItems)
    } else {
      staticRows
    }
  }

  private var staticRows: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(items) { item in
        row(for: item)
      }
    }
  }

  private func reorderableRows(_ reorderItems: @escaping ([Item.ID], Item.ID?) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(items) { item in
        row(for: item)
      }
      .reorderable()
    }
    .reorderContainer(for: Item.self, itemID: \.id) { difference in
      let destinationID: Item.ID? = switch difference.destination.position {
      case let .before(id): id
      case .end: nil
      }
      reorderItems(difference.sources, destinationID)
    }
  }

  private func row(for item: Item) -> some View {
    VStack(spacing: 0) {
      EditableRow(
        item: item,
        editorLabel: editorLabel,
        itemText: item[keyPath: itemText],
        updateItem: updateItem,
        deleteItem: deleteItem,
        content: itemContent,
        badge: badge
      )
      if item.id != items.last?.id {
        Divider()
      }
    }
  }
}

private struct EditableRow<Item: Identifiable, Content: View, Badge: View>: View {
  let item: Item
  let editorLabel: String
  let itemText: String
  let updateItem: (Item, String) -> Void
  let deleteItem: (Item) -> Void
  let content: (Item) -> Content
  let badge: ((Item) -> Badge)?

  @State private var isEditing = false
  @State private var draft = ""

  var body: some View {
    Group {
      if isEditing {
        VStack(alignment: .leading, spacing: 8) {
          TextField(editorLabel, text: $draft, axis: .vertical)
            .lineLimit(2...6)
          HStack {
            Button("Cancel") {
              draft = itemText
              isEditing = false
            }
            Spacer()
            Button("Save") {
              updateItem(item, draft)
              isEditing = false
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
      } else {
        Button {
          draft = itemText
          isEditing = true
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            content(item)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let badge {
              badge(item)
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(editorLabel.lowercased()): \(itemText)")
      }
    }
    .padding(.vertical, 12)
    .swipeActions {
      Button(role: .destructive) {
        deleteItem(item)
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }
}
