import SwiftUI
import YesChefCore

struct CategoryManagementView: View {
  @State private var model = CategoryManagementModel()

  var body: some View {
    @Bindable var model = model

    CategoryBrowserView(model: model, parentCategoryID: nil)
    .sheet(item: $model.editor) { editor in
      NavigationStack {
        CategoryEditorSheet(model: model, editor: editor)
      }
      .presentationDetents([.medium, .large])
    }
    .confirmationDialog(
      "Delete Category?",
      item: $model.destination.deleteCategory,
      titleVisibility: .visible
    ) { categoryID in
      Button("Delete Category", role: .destructive) {
        model.confirmDeleteCategoryButtonTapped(categoryID: categoryID)
      }
      Button("Cancel", role: .cancel) {}
    } message: { categoryID in
      Text("Delete \(model.title(for: categoryID))?")
    }
    .alert("Could Not Save Category", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct CategoryBrowserView: View {
  let model: CategoryManagementModel
  let parentCategoryID: YesChefCore.Category.ID?

  var body: some View {
    List {
      if categories.isEmpty {
        CategoryEmptyListContent(model: model, parentCategoryID: parentCategoryID)
      } else {
        Section {
          ForEach(categories) { category in
            CategoryBrowserRow(
              model: model,
              category: category,
              childCount: model.childCount(for: category.id),
              isRootLevel: parentCategoryID == nil
            )
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(title)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          if let parentCategoryID {
            model.addChildCategoryButtonTapped(parentCategoryID: parentCategoryID)
          } else {
            model.addRootCategoryButtonTapped()
          }
        } label: {
          Label(parentCategoryID == nil ? "Add Category" : "Add Child Category", systemImage: "plus")
        }
      }
    }
  }

  private var categories: [YesChefCore.Category] {
    model.children(of: parentCategoryID)
  }

  private var title: String {
    parentCategoryID.map { model.title(for: $0) } ?? "Categories"
  }
}

private struct CategoryBrowserRow: View {
  let model: CategoryManagementModel
  let category: YesChefCore.Category
  let childCount: Int
  let isRootLevel: Bool

  var body: some View {
    HStack(spacing: 8) {
      if isRootLevel {
        NavigationLink {
          CategoryBrowserView(model: model, parentCategoryID: category.id)
        } label: {
          rowContent(showsFolder: true)
        }
      } else {
        rowContent(showsFolder: false)
      }
    }
  }

  private func rowContent(showsFolder: Bool) -> some View {
    HStack(spacing: 8) {
      CategoryBrowserRowLabel(
        name: category.name,
        childCount: childCount,
        showsFolder: showsFolder
      )

      Menu {
        Button {
          model.editCategoryButtonTapped(categoryID: category.id)
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        if isRootLevel {
          Button {
            model.addChildCategoryButtonTapped(parentCategoryID: category.id)
          } label: {
            Label("Add Child", systemImage: "plus")
          }
        }
        Button(role: .destructive) {
          model.deleteCategoryButtonTapped(categoryID: category.id)
        } label: {
          Label("Delete", systemImage: "trash")
        }
      } label: {
        Label("Category Actions", systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .font(.title3)
      .frame(width: 44, height: 44)
      .contentShape(.rect)
    }
  }
}

private struct CategoryBrowserRowLabel: View {
  let name: String
  let childCount: Int
  let showsFolder: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(name)
        .lineLimit(1)
      Spacer()
      if childCount > 0 {
        Text(childCount, format: .number)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
  }

  private var iconName: String {
    if !showsFolder {
      return "tag"
    }
    return childCount > 0 ? "folder.fill" : "folder"
  }
}

private struct CategoryEmptyListContent: View {
  let model: CategoryManagementModel
  let parentCategoryID: YesChefCore.Category.ID?

  var body: some View {
    ContentUnavailableView {
      Label(parentCategoryID == nil ? "No Categories" : "No Child Categories", systemImage: "folder")
    } actions: {
      Button {
        if let parentCategoryID {
          model.addChildCategoryButtonTapped(parentCategoryID: parentCategoryID)
        } else {
          model.addRootCategoryButtonTapped()
        }
      } label: {
        Label(parentCategoryID == nil ? "Add Category" : "Add Child Category", systemImage: "plus")
      }
    }
  }
}

private struct CategoryEditorSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var isShowingParentPicker = false

  let model: CategoryManagementModel
  let editor: CategoryEditorModel

  var body: some View {
    @Bindable var editor = editor

    Form {
      Section("Category") {
        StackedTextField(title: "Name", text: $editor.name)
      }

      Section("Parent") {
        Button {
          isShowingParentPicker = true
        } label: {
          StackedFormField(title: "Parent") {
            HStack {
              Text(model.parentTitle(for: editor.parentCategoryID))
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            }
          }
        }
        .buttonStyle(.plain)
      }

      if let categoryID = editor.categoryID {
        Section {
          Button(role: .destructive) {
            model.deleteCategoryButtonTapped(categoryID: categoryID)
            dismiss()
          } label: {
            Label("Delete Category", systemImage: "trash")
          }
        }
      }
    }
    .navigationTitle(editorTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          model.cancelEditingButtonTapped()
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveCategoryButtonTapped() {
            dismiss()
          }
        }
        .disabled(model.isSaveDisabled)
      }
    }
    .sheet(isPresented: $isShowingParentPicker) {
      NavigationStack {
        CategoryParentPickerSheet(model: model, editor: editor)
      }
      .presentationDetents([.medium, .large])
    }
  }

  private var editorTitle: String {
    let name = editor.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty {
      return name
    }
    return editor.categoryID == nil ? "New Category" : "Category"
  }
}

private struct CategoryParentPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  let model: CategoryManagementModel
  let editor: CategoryEditorModel

  var body: some View {
    List {
      CategoryParentPickerRow(
        title: "None",
        isSelected: editor.parentCategoryID == nil
      ) {
        editor.parentCategoryID = nil
        dismiss()
      }

      ForEach(model.parentOptions(excluding: editor.categoryID)) { option in
        CategoryParentPickerRow(
          title: option.title,
          isSelected: editor.parentCategoryID == option.categoryID
        ) {
          editor.parentCategoryID = option.categoryID
          dismiss()
        }
      }
    }
    .navigationTitle("Parent")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }
}

private struct CategoryParentPickerRow: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct RecipeCategorySelectionField: View {
  let model: RecipeEditorModel

  var body: some View {
    NavigationLink {
      RecipeCategorySelectionView(model: model)
    } label: {
      StackedFormField(title: "Categories") {
        Text(model.selectedCategorySummary)
          .foregroundStyle(model.selectedCategoryIDs.isEmpty ? .secondary : .primary)
          .lineLimit(3)
      }
    }
  }
}

private struct RecipeCategorySelectionView: View {
  let model: RecipeEditorModel

  var body: some View {
    List {
      if model.categoryRows.isEmpty {
        ContentUnavailableView("No Categories", systemImage: "folder")
      } else {
        ForEach(model.categoryRows) { row in
          RecipeCategorySelectionRow(
            row: row,
            isSelected: model.selectedCategoryIDs.contains(row.category.id)
          ) {
            model.categorySelectionButtonTapped(row.category.id)
          }
        }
      }
    }
    .navigationTitle("Categories")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct RecipeCategorySelectionRow: View {
  let row: CategoryHierarchy.DisplayRow
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: row.hasChildren ? "folder.fill" : "folder")
          .foregroundStyle(.secondary)
          .frame(width: 22)
        Text(row.category.name)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
        }
      }
      .padding(.leading, CGFloat(row.depth) * 18)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
