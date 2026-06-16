import SwiftUI
import YesChefCore

struct RecipeDetailView: View {
  @State private var model: RecipeDetailModel
  let libraryModel: RecipeLibraryModel

  init(recipeID: Recipe.ID, libraryModel: RecipeLibraryModel) {
    _model = State(wrappedValue: RecipeDetailModel(recipeID: recipeID))
    self.libraryModel = libraryModel
  }

  var body: some View {
    @Bindable var model = model

    ScrollView {
      if let recipe = model.recipe {
        VStack(alignment: .leading, spacing: 24) {
          header(recipe)
          metadata(recipe)
          if !model.ingredientLines.isEmpty {
            ingredients(scaleFactor: $model.scaleFactor)
          }
          if !model.instructionSteps.isEmpty {
            instructions
          }
          if let notes = model.detail?.notes, !notes.isEmpty {
            notesView(notes)
          }
        }
        .padding()
        .frame(maxWidth: 860, alignment: .leading)
      } else {
        ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
      }
    }
    .navigationTitle(model.recipe?.title ?? "Recipe")
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          libraryModel.markCookedButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Mark Cooked", systemImage: "checkmark.circle")
        }
        Button {
          libraryModel.cookButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Cook", systemImage: "flame")
        }
        Button {
          libraryModel.editButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Edit", systemImage: "square.and.pencil")
        }
      }
    }
  }

  private func header(_ recipe: Recipe) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(recipe.title)
          .font(.largeTitle.bold())
        if recipe.favorite {
          Image(systemName: "star.fill")
            .foregroundStyle(.yellow)
        }
      }
      if let subtitle = recipe.subtitle {
        Text(subtitle)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      if let summary = recipe.summary {
        Text(summary)
      }
    }
  }

  private func metadata(_ recipe: Recipe) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        if let servingsText = recipe.servingsText {
          Label(servingsText, systemImage: "person.2")
        }
        if let totalTime = recipe.totalTimeMinutes {
          Label("\(totalTime) min", systemImage: "clock")
        }
        if recipe.timesCooked > 0 {
          Label("Cooked \(recipe.timesCooked)x", systemImage: "checkmark")
        }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)

      if let source = model.detail?.source {
        HStack {
          Image(systemName: "book")
          if let urlString = source.url, let url = URL(string: urlString) {
            Link(source.name ?? urlString, destination: url)
          } else {
            Text(source.name ?? "Source")
          }
        }
        .font(.subheadline)
      }

      if let tags = model.detail?.tags, !tags.isEmpty {
        WrappingLabels(labels: tags.map(\.name), systemImage: "tag")
      }
      if let categories = model.detail?.categories, !categories.isEmpty {
        WrappingLabels(labels: categories.map(\.name), systemImage: "folder")
      }

      if recipe.originalSnapshot != nil {
        Button {
          libraryModel.originalSnapshotButtonTapped(recipeID: recipe.id)
        } label: {
          Label("View Original", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func ingredients(scaleFactor: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Ingredients")
          .font(.title2.bold())
        Spacer()
        Picker("Scale", selection: scaleFactor) {
          Text("1x").tag(1.0)
          Text("1.5x").tag(1.5)
          Text("2x").tag(2.0)
          Text("3x").tag(3.0)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
      }
      VStack(alignment: .leading, spacing: 8) {
        ForEach(model.ingredientLines) { line in
          Text("• \(IngredientScaler.scaledText(for: line, factor: model.scaleFactor))")
            .font(.body)
        }
      }
    }
  }

  private var instructions: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Instructions")
        .font(.title2.bold())
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(model.instructionSteps.enumerated()), id: \.element.id) { index, step in
          HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
              .font(.caption.bold())
              .foregroundStyle(.white)
              .frame(width: 26, height: 26)
              .background(Circle().fill(Color.accentColor))
            Text(step.text)
          }
        }
      }
    }
  }

  private func notesView(_ notes: [RecipeNote]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Notes")
        .font(.title2.bold())
      ForEach(notes) { note in
        VStack(alignment: .leading, spacing: 4) {
          Text(note.noteType.rawValue.capitalized)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(note.text)
        }
        .padding(.vertical, 4)
      }
    }
  }

}

private struct WrappingLabels: View {
  let labels: [String]
  let systemImage: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
      ForEach(labels, id: \.self) { label in
        Text(label)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.quaternary, in: Capsule())
      }
    }
  }
}
