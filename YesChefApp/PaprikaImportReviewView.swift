import SwiftUI
import YesChefCore

struct PaprikaImportReviewView: View {
  @Environment(\.dismiss) private var dismiss
  let libraryModel: RecipeLibraryModel
  let model: RecipeImportModel

  var body: some View {
    @Bindable var model = model

    Form {
      if let draft = model.draft {
        PaprikaImportOverviewSection(draft: draft)
        PaprikaImportRecipeRows(preview: draft.preview)
        PaprikaImportWarningSections(draft: draft)
      }
    }
    .navigationTitle("Review Import")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
        .disabled(model.isCommitting)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button {
          Task {
            if let commit = await model.commitButtonTapped() {
              libraryModel.paprikaImportCommitted(commit)
              dismiss()
            }
          }
        } label: {
          if model.isCommitting {
            ProgressView()
          } else {
            Text("Commit")
          }
        }
        .disabled(!model.canCommit)
      }
    }
    .alert("Import Error", isPresented: $model.isShowingError) {
      Button("OK") {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct PaprikaImportOverviewSection: View {
  let draft: PaprikaRecipeImportDraft

  var body: some View {
    Section("Summary") {
      LabeledContent("Recipes", value: "\(draft.preview.results.count)")
      LabeledContent("New", value: "\(draft.preview.newCount + draft.preview.titleOnlyCollisionCount)")
      LabeledContent("Already Imported", value: "\(draft.preview.alreadyImportedCount)")
      if draft.preview.titleOnlyCollisionCount > 0 {
        LabeledContent("Title Collisions", value: "\(draft.preview.titleOnlyCollisionCount)")
      }
      if totalWarningCount > 0 {
        LabeledContent("Warnings", value: "\(totalWarningCount)")
      }
    }
  }

  private var totalWarningCount: Int {
    draft.parseResult.warnings.count + draft.preview.warnings.count
  }
}

private struct PaprikaImportRecipeRows: View {
  let preview: RecipeImportBatchPreview

  var body: some View {
    Section("Recipes") {
      ForEach(preview.results) { result in
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline) {
            Text(result.title)
            Spacer()
            Text(result.status.reviewTitle)
              .font(.caption)
              .foregroundStyle(result.status.reviewColor)
          }
          ForEach(result.warnings, id: \.message) { warning in
            Text(warning.message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

private struct PaprikaImportWarningSections: View {
  let draft: PaprikaRecipeImportDraft

  var body: some View {
    if !draft.parseResult.warnings.isEmpty {
      Section("Parse Warnings") {
        ForEach(draft.parseResult.warnings, id: \.reviewTitle) { warning in
          Text(warning.reviewTitle)
            .foregroundStyle(.secondary)
        }
      }
    }

    if !draft.preview.warnings.isEmpty {
      Section("Identity Warnings") {
        ForEach(draft.preview.warnings, id: \.message) { warning in
          Text(warning.message)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private extension RecipeImportPreviewStatus {
  var reviewTitle: String {
    switch self {
    case .new:
      "New"
    case .alreadyImported:
      "Skip"
    case .titleOnlyCollision:
      "New"
    }
  }

  var reviewColor: Color {
    switch self {
    case .new:
      .green
    case .alreadyImported:
      .secondary
    case .titleOnlyCollision:
      .orange
    }
  }
}

private extension PaprikaHTMLImportWarning {
  var reviewTitle: String {
    var title = message
    if let affectedCount {
      title += " (\(affectedCount))"
    }
    if !examples.isEmpty {
      title += ": \(examples.prefix(3).joined(separator: ", "))"
    }
    return title
  }
}
