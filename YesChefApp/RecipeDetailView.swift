import SwiftUI
import SwiftUINavigation
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
            ingredients
          }
          if !model.instructionSteps.isEmpty {
            instructions
          }
          if !model.visibleNotes.isEmpty {
            notesView(model.visibleNotes)
          }
        }
        .padding()
        .frame(maxWidth: 860, alignment: .leading)
      } else {
        ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
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
        Menu {
          Button(role: .destructive) {
            libraryModel.deleteButtonTapped(recipeID: model.recipeID)
          } label: {
            Label("Delete Recipe", systemImage: "trash")
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
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

  private var ingredients: some View {
    @Bindable var model = model

    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Ingredients")
          .font(.title2.bold())
        Spacer()
        Button {
          model.scaleButtonTapped()
        } label: {
          Label(model.scaleSummary, systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .popover(
          isPresented: $model.destination.scaling,
          attachmentAnchor: .rect(.bounds),
          arrowEdge: .top
        ) {
          ScalePanel(model: model)
            .presentationCompactAdaptation(.popover)
        }
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

private struct ScalePanel: View {
  let model: RecipeDetailModel

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 16) {
      Label("Scale Ingredients", systemImage: "slider.horizontal.3")
        .font(.headline)

      if let recipe = model.recipe {
        LabeledContent("Original", value: recipe.servingsText ?? recipe.yieldText ?? "Unknown")
          .font(.subheadline)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(model.baseServings == nil ? "Scale" : "Servings")
          .font(.subheadline.bold())

        HStack(spacing: 0) {
          Picker("Whole", selection: $model.scaleWholePart) {
            ForEach(1...10, id: \.self) { whole in
              Text("\(whole)")
                .tag(whole)
            }
          }
          .pickerStyle(.wheel)
          .frame(width: 96, height: 128)
          .clipped()

          Picker("Fraction", selection: $model.scaleFraction) {
            ForEach(ScaleFraction.allCases) { fraction in
              Text(fraction.label)
                .tag(fraction)
            }
          }
          .pickerStyle(.wheel)
          .frame(width: 112, height: 128)
          .clipped()
        }
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .onChange(of: model.scaleWholePart) { _, _ in
        model.scalePickerChanged()
      }
      .onChange(of: model.scaleFraction) { _, _ in
        model.scalePickerChanged()
      }

      LabeledContent("Scale", value: ScaleText.factor(model.scaleFactor))
        .font(.subheadline)

      HStack {
        LabeledContent("Units", value: "Default")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Reset") {
          model.resetScaleButtonTapped()
        }
        .disabled(model.scaleFactor == 1)
      }
    }
    .padding()
    .frame(width: 300)
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
