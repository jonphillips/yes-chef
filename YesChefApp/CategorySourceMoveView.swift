import SwiftUI
import YesChefCore

struct CategorySourceMoveView: View {
  @State private var model = CategorySourceMoveModel()

  var body: some View {
    @Bindable var model = model

    List {
      if let report = model.report {
        summarySection(report)
        cleanupSection
        if !report.problems.isEmpty {
          Section {
            ForEach(report.problems) { entry in
              Button {
                model.problemTapped(entry)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(entry.recipeTitle)
                    .foregroundStyle(.primary)
                  Text("\(entry.field.group.name): \(entry.categoryNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  Text(entry.outcome.problemDescription(entry.field))
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
              }
            }
          } header: {
            Text("Won't Move (\(report.problems.count))")
          } footer: {
            Text("These keep their tag. Tap one to fix it in the editor.")
          }
        }
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Cookbook & Chef")
    .toolbar {
      if let report = model.report, !report.problems.isEmpty {
        ShareLink(item: report.problemSummary) {
          Label("Share Report", systemImage: "square.and.arrow.up")
        }
      }
    }
    .task { model.task() }
    .confirmationDialog(
      "Move \(model.report?.changeCount ?? 0) values?",
      isPresented: $model.isConfirmingApply,
      titleVisibility: .visible
    ) {
      Button("Move and Remove Tags") {
        model.confirmApplyButtonTapped()
      }
    } message: {
      Text("Fills empty Book title, Publication, and Author fields and removes the Cookbook and Chef tags they came from. Recipes in the Won't Move list are left alone.")
    }
    .confirmationDialog(
      "Delete Unused Categories?",
      isPresented: $model.isConfirmingCleanup,
      titleVisibility: .visible
    ) {
      Button("Delete Unused Categories", role: .destructive) {
        model.confirmCleanupButtonTapped()
      }
    } message: {
      Text("Deletes every Cookbook and Chef category no recipe is tagged with, then each group left empty. Categories still on a recipe stay.")
    }
    .sheet(item: $model.editingRecipeID, id: \.self, onDismiss: model.editorDismissed) { recipeID in
      NavigationStack {
        RecipeEditorView(recipeID: recipeID)
      }
    }
    .alert("Couldn't Move", isPresented: Binding(
      get: { model.errorMessage != nil },
      set: { if !$0 { model.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  @ViewBuilder private var cleanupSection: some View {
    Section {
      if let cleanup = model.cleanupReport {
        LabeledContent("Categories deleted", value: "\(cleanup.deletedCategoryCount)")
        ForEach(cleanup.deletedGroups, id: \.self) { group in
          Label("\(group.name) group deleted", systemImage: "checkmark.circle")
        }
        ForEach(cleanup.remaining) { remaining in
          LabeledContent(
            "\(remaining.group.name): \(remaining.categoryName)",
            value: remaining.recipeCount == 1 ? "1 recipe" : "\(remaining.recipeCount) recipes"
          )
        }
      }
      Button("Delete Unused Cookbook & Chef Categories", role: .destructive) {
        model.cleanupButtonTapped()
      }
    } header: {
      Text("Clean Up")
    } footer: {
      Text(model.cleanupReport.map { $0.remaining.isEmpty ? "Nothing left to clean up." : "These are still tagged on recipes, so they stay." }
        ?? "Run this after the move to remove the empty categories and groups.")
    }
  }

  @ViewBuilder private func summarySection(_ report: CategorySourceMoveReport) -> some View {
    Section {
      ForEach(report.missingGroups, id: \.self) { group in
        Label("No \"\(group.name)\" category group found", systemImage: "exclamationmark.triangle")
          .foregroundStyle(.secondary)
      }
      if !model.hasApplied, !report.cookbookValues.isEmpty {
        NavigationLink {
          CategorySourcePublicationsView(model: model)
        } label: {
          LabeledContent(
            "Publications",
            value: "\(report.cookbookValues.filter(model.isPublication).count) of \(report.cookbookValues.count)"
          )
        }
      }
      LabeledContent(model.hasApplied ? "Moved" : "Will move", value: "\(report.moveCount)")
      LabeledContent(
        model.hasApplied ? "Already set; tag removed" : "Already set; tag will be removed",
        value: "\(report.alreadySetCount)"
      )
      LabeledContent("Won't move", value: "\(report.problems.count)")
      if !model.hasApplied {
        Button("Move \(report.changeCount) Values") {
          model.applyButtonTapped()
        }
        .disabled(report.changeCount == 0)
      }
    } footer: {
      Text("Cookbook → Book title (or Publication, for the values you mark) and Chef → Author, only where the field is empty. The categories themselves stay until you run Clean Up below.")
    }
  }
}

private struct CategorySourcePublicationsView: View {
  let model: CategorySourceMoveModel

  var body: some View {
    List {
      Section {
        ForEach(model.report?.cookbookValues ?? [], id: \.self) { value in
          Toggle(value, isOn: Binding(
            get: { model.isPublication(value) },
            set: { model.publicationToggled(value, isPublication: $0) }
          ))
        }
      } footer: {
        Text("On moves the Cookbook value to Publication; off moves it to Book title.")
      }
    }
    .navigationTitle("Publications")
  }
}
