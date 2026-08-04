import SwiftUI
import YesChefCore

struct CategoryManagementView: View {
  @State private var model = CategoryManagementModel()

  var body: some View {
    @Bindable var model = model

    CategoryManagementListView(model: model)
      .sheet(item: $model.categoryEditor) { editor in
        NavigationStack {
          CategoryEditorSheet(model: model, editor: editor)
        }
        .presentationDetents([.medium, .large])
      }
      .sheet(item: $model.facetEditor) { editor in
        NavigationStack {
          CategoryGroupEditorSheet(model: model, editor: editor)
        }
        .presentationDetents([.medium])
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
      .confirmationDialog(
        "Delete Category Group?",
        item: $model.destination.deleteCategoryGroup,
        titleVisibility: .visible
      ) { facetID in
        Button("Delete Category Group", role: .destructive) {
          model.confirmDeleteCategoryGroupButtonTapped(facetID: facetID)
        }
        Button("Cancel", role: .cancel) {}
      } message: { facetID in
        Text("Delete \(model.categoryGroupTitle(for: facetID))?")
      }
      .alert("Could Not Save Category", isPresented: $model.isShowingError) {
        Button("OK") {}
      } message: {
        Text(model.errorMessage ?? "")
      }
  }
}

private struct CategoryManagementListView: View {
  let model: CategoryManagementModel

  var body: some View {
    List {
      Section("Category Groups") {
        ForEach(model.facets) { facet in
          CategoryGroupRow(model: model, facet: facet)
        }
      }

      Section("Other Categories") {
        ForEach(model.looseCategories) { category in
          CategoryRow(model: model, category: category, facetID: nil)
        }
      }
    }
    .overlay {
      if model.facets.isEmpty && model.looseCategories.isEmpty {
        ContentUnavailableView {
          Label("No Categories", systemImage: "folder")
        } actions: {
          Button {
            model.addCategoryGroupButtonTapped()
          } label: {
            Label("New Category Group", systemImage: "folder.badge.plus")
          }
        }
      }
    }
    .navigationTitle("Categories")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button {
            model.addCategoryGroupButtonTapped()
          } label: {
            Label("New Category Group", systemImage: "folder.badge.plus")
          }
          Button {
            model.addLooseCategoryButtonTapped()
          } label: {
            Label("New Category", systemImage: "tag")
          }
        } label: {
          Label("Add Category", systemImage: "plus")
        }
      }
    }
  }
}

private struct CategoryGroupRow: View {
  let model: CategoryManagementModel
  let facet: Facet

  var body: some View {
    HStack(spacing: 8) {
      NavigationLink {
        CategoryGroupBrowserView(model: model, facetID: facet.id)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "folder.fill")
            .foregroundStyle(.secondary)
            .frame(width: 22)
          Text(facet.name)
          Spacer()
          if facet.hidden {
            Image(systemName: "eye.slash")
              .foregroundStyle(.secondary)
          }
          Text(model.categories(in: facet.id).count, format: .number)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Menu {
        Button {
          model.editCategoryGroupButtonTapped(facetID: facet.id)
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        Button {
          model.toggleCategoryGroupVisibilityButtonTapped(facetID: facet.id)
        } label: {
          Label(facet.hidden ? "Show Category Group" : "Hide Category Group", systemImage: facet.hidden ? "eye" : "eye.slash")
        }
        if model.canDeleteCategoryGroup(facetID: facet.id) {
          Button(role: .destructive) {
            model.deleteCategoryGroupButtonTapped(facetID: facet.id)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      } label: {
        Label("Category Group Actions", systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .font(.title3)
      .frame(width: 44, height: 44)
    }
  }
}

private struct CategoryGroupBrowserView: View {
  let model: CategoryManagementModel
  let facetID: Facet.ID
  let parentCategoryID: YesChefCore.Category.ID?

  init(model: CategoryManagementModel, facetID: Facet.ID, parentCategoryID: YesChefCore.Category.ID? = nil) {
    self.model = model
    self.facetID = facetID
    self.parentCategoryID = parentCategoryID
  }

  var body: some View {
    let categories = model.children(of: parentCategoryID, in: facetID)

    List {
      ForEach(categories) { category in
        CategoryRow(model: model, category: category, facetID: facetID)
      }
    }
    .overlay {
      if categories.isEmpty {
        ContentUnavailableView {
          Label("No Categories", systemImage: "folder")
        } actions: {
          if parentCategoryID == nil {
            Button {
              model.addCategoryButtonTapped(facetID: facetID)
            } label: {
              Label("New Category", systemImage: "plus")
            }
          }
        }
      }
    }
    .navigationTitle(title)
    .toolbar {
      if parentCategoryID == nil {
        ToolbarItem(placement: .primaryAction) {
          Button {
            model.addCategoryButtonTapped(facetID: facetID)
          } label: {
            Label("New Category", systemImage: "plus")
          }
        }
      }
    }
  }

  private var title: String {
    parentCategoryID.map { model.title(for: $0) } ?? model.categoryGroupTitle(for: facetID)
  }
}

private struct CategoryRow: View {
  let model: CategoryManagementModel
  let category: YesChefCore.Category
  let facetID: Facet.ID?

  var body: some View {
    HStack(spacing: 8) {
      if let facetID, model.childCount(for: category.id) > 0 {
        NavigationLink {
          CategoryGroupBrowserView(model: model, facetID: facetID, parentCategoryID: category.id)
        } label: {
          label
        }
      } else {
        label
      }

      Menu {
        Button {
          model.editCategoryButtonTapped(categoryID: category.id)
        } label: {
          Label("Edit", systemImage: "pencil")
        }
        Button {
          model.toggleCategoryVisibilityButtonTapped(categoryID: category.id)
        } label: {
          Label(category.hidden ? "Show Category" : "Hide Category", systemImage: category.hidden ? "eye" : "eye.slash")
        }
        if model.canDelete(categoryID: category.id) {
          Button(role: .destructive) {
            model.deleteCategoryButtonTapped(categoryID: category.id)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      } label: {
        Label("Category Actions", systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .font(.title3)
      .frame(width: 44, height: 44)
    }
  }

  private var label: some View {
    HStack(spacing: 12) {
      Image(systemName: model.childCount(for: category.id) > 0 ? "folder.fill" : "tag")
        .foregroundStyle(.secondary)
        .frame(width: 22)
      Text(category.name)
        .lineLimit(1)
      Spacer()
      if category.hidden {
        Image(systemName: "eye.slash")
          .foregroundStyle(.secondary)
      }
      if model.childCount(for: category.id) > 0 {
        Text(model.childCount(for: category.id), format: .number)
          .font(.subheadline)
          .foregroundStyle(.secondary)
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

      Section("Group") {
        Picker("Group", selection: $editor.facetID) {
          Text("No Group").tag(Facet.ID?.none)
          ForEach(model.visibleFacets) { facet in
            Text(facet.name).tag(Optional(facet.id))
          }
        }
      }

      if editor.facetID != nil {
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
      }

      if let categoryID = editor.categoryID, model.canDelete(categoryID: categoryID) {
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
    .onChange(of: editor.facetID) { oldFacetID, newFacetID in
      guard oldFacetID != newFacetID else { return }
      editor.parentCategoryID = nil
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          model.cancelCategoryEditingButtonTapped()
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveCategoryButtonTapped() {
            dismiss()
          }
        }
        .disabled(model.isCategorySaveDisabled)
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
    if !name.isEmpty { return name }
    return editor.categoryID == nil ? "New Category" : "Category"
  }
}

private struct CategoryGroupEditorSheet: View {
  @Environment(\.dismiss) private var dismiss

  let model: CategoryManagementModel
  let editor: FacetEditorModel

  var body: some View {
    @Bindable var editor = editor

    Form {
      Section("Category Group") {
        StackedTextField(title: "Name", text: $editor.name)
      }

      if let facetID = editor.facetID, model.canDeleteCategoryGroup(facetID: facetID) {
        Section {
          Button(role: .destructive) {
            model.deleteCategoryGroupButtonTapped(facetID: facetID)
            dismiss()
          } label: {
            Label("Delete Category Group", systemImage: "trash")
          }
        }
      }
    }
    .navigationTitle(editorTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          model.cancelCategoryGroupEditingButtonTapped()
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveCategoryGroupButtonTapped() {
            dismiss()
          }
        }
        .disabled(model.isCategoryGroupSaveDisabled)
      }
    }
  }

  private var editorTitle: String {
    let name = editor.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !name.isEmpty { return name }
    return editor.facetID == nil ? "New Category Group" : "Category Group"
  }
}

private struct CategoryParentPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  let model: CategoryManagementModel
  let editor: CategoryEditorModel

  var body: some View {
    List {
      CategoryParentPickerRow(title: "None", isSelected: editor.parentCategoryID == nil) {
        editor.parentCategoryID = nil
        dismiss()
      }

      ForEach(model.parentOptions(in: editor.facetID, excluding: editor.categoryID)) { option in
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
      ForEach(model.categorySections) { section in
        Section(section.title) {
          ForEach(section.rows) { row in
            RecipeCategorySelectionRow(
              row: row,
              isSelected: model.selectedCategoryIDs.contains(row.category.id)
            ) {
              model.categorySelectionButtonTapped(row.category.id)
            }
          }
        }
      }
    }
    .overlay {
      if model.categorySections.allSatisfy({ $0.rows.isEmpty }) {
        ContentUnavailableView("No Categories", systemImage: "folder")
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
    }
    .buttonStyle(.plain)
  }
}
