import SwiftUI
import YesChefCore

struct WorkbenchCandidatePickerView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchDetailModel
  @State private var selection: Set<Recipe.ID> = []
  @State private var searchText = ""

  var body: some View {
    List(selection: $selection) {
      ForEach(filteredRecipeRows) { row in
        RecipeListRow(
          row: row,
          options: RecipeListViewOptions(
            density: .compact,
            showsSourceMetadata: true,
            showsCategoryMetadata: false
          )
        )
        .tag(row.recipe.id)
        .disabled(model.existingCandidateRecipeIDs.contains(row.recipe.id))
      }
    }
    .environment(\.editMode, .constant(.active))
    .navigationTitle("Add Candidates")
    .searchable(
      text: $searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search recipes"
    )
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Add") {
          if model.addCandidatesButtonTapped(recipeIDs: selection) {
            dismiss()
          }
        }
        .disabled(selection.isEmpty)
      }
    }
  }

  private var filteredRecipeRows: [RecipeListRowData] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return model.availableRecipeRows }
    return model.availableRecipeRows.filter { row in
      RecipeSearchMatcher.matches(query: query, in: row.recipe.title, row.recipe.subtitle)
    }
  }
}

struct WorkbenchCandidatePhotoPickerView: View {
  @Environment(\.dismiss) private var dismiss
  let model: WorkbenchDetailModel

  var body: some View {
    List(model.candidatePhotoChoices) { choice in
      Button {
        model.selectCandidatePhotoButtonTapped(photoID: choice.photo.id)
      } label: {
        HStack(spacing: 12) {
          RecipePhotoImage(
            photoID: choice.photo.id,
            checksum: choice.photo.checksum,
            variant: .thumbnail,
            thumbnailData: choice.photo.thumbnailData
          )
          .frame(width: 72, height: 72)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading, spacing: 4) {
            Text(choice.candidateTitle)
              .font(.headline)
            Text("Use this candidate photo")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
      }
      .buttonStyle(.plain)
    }
    .navigationTitle("Choose Candidate Photo")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }
}
