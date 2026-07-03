import SwiftUI
import SwiftUINavigation
import UIKit
import YesChefCore

struct RecipeDetailView: View {
  @State private var model: RecipeDetailModel
  let libraryModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel

  init(
    recipeID: Recipe.ID,
    libraryModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel
  ) {
    _model = State(wrappedValue: RecipeDetailModel(recipeID: recipeID))
    self.libraryModel = libraryModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
  }

  var body: some View {
    @Bindable var model = model

    ScrollView {
      if let recipe = model.recipe {
        VStack(alignment: .leading, spacing: 24) {
          header(recipe)
          if !model.displayablePhotos.isEmpty {
            RecipePhotoGallery(photos: model.displayablePhotos)
          }
          metadata(recipe)
          if !model.ingredientLines.isEmpty {
            ingredients
          }
          if let makeAhead = model.makeAhead {
            makeAheadSection(makeAhead)
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
          model.chatButtonTapped()
        } label: {
          Label("Chat", systemImage: "sparkles")
        }
        Button {
          mealCalendarModel.addRecipeToPlanButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Plan", systemImage: "calendar.badge.plus")
        }
        Button {
          groceryModel.addRecipeButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Groceries", systemImage: "cart.badge.plus")
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Button {
          libraryModel.editButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Edit", systemImage: "square.and.pencil")
        }
        Menu {
          Button(role: .destructive) {
            libraryModel.deleteButtonTapped(recipeID: model.recipeID)
          } label: {
            Label("Archive", systemImage: "archivebox")
          }
        } label: {
          Label("More", systemImage: "ellipsis.circle")
        }
      }
    }
    .sheet(item: $model.destination.chat) { chatModel in
      NavigationStack {
        RecipeChatPanel(
          chatModel: chatModel,
          applyActions: model.applyActionCatalog(for: chatModel)
        )
      }
    }
    .alert("Recipe Update Failed", isPresented: $model.isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "Something went wrong.")
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
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: 12) {
          recipeStats(recipe)
          Spacer(minLength: 12)
          startCookingButton(recipe)
        }

        VStack(alignment: .leading, spacing: 10) {
          recipeStats(recipe)
          startCookingButton(recipe)
        }
      }

      if recipe.libraryPlacement == .reference {
        Label(recipe.libraryPlacement.title, systemImage: "books.vertical")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if let source = model.detail?.source {
        SourceMetadataView(source: source)
      }

      if let tags = model.detail?.tags, !tags.isEmpty {
        WrappingLabels(labels: tags.map(\.name), systemImage: "tag")
      }
      if let categoryDisplayNames = model.detail?.categoryDisplayNames, !categoryDisplayNames.isEmpty {
        WrappingLabels(labels: categoryDisplayNames, systemImage: "folder")
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

  private func recipeStats(_ recipe: Recipe) -> some View {
    HStack(spacing: 12) {
      if let servingsText = recipe.servingsText {
        Label(servingsText, systemImage: "person.2")
      }
      if let totalTime = recipe.totalTimeMinutes {
        Label("\(totalTime) min", systemImage: "clock")
      }
      if let rating = recipe.rating, rating > 0 {
        Label("\(rating)", systemImage: "star.fill")
          .accessibilityLabel(Text("Rating \(rating) out of 5"))
      }
      if let difficulty = recipe.difficulty {
        Label(difficulty.rawValue.capitalized, systemImage: "gauge.with.dots.needle.33percent")
          .accessibilityLabel(Text("Difficulty \(difficulty.rawValue)"))
      }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }

  private func startCookingButton(_ recipe: Recipe) -> some View {
    Button {
      libraryModel.cookButtonTapped(recipeID: recipe.id)
    } label: {
      Label("Start Cooking", systemImage: "flame")
    }
    .buttonStyle(.borderedProminent)
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
      let groups = model.ingredientGroups
      VStack(alignment: .leading, spacing: 12) {
        if groups.isEmpty {
          ingredientLineList(model.ingredientLines)
        } else {
          ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 8) {
              if let name = group.name, !name.isEmpty {
                Text(name)
                  .font(.subheadline.bold())
                  .foregroundStyle(.secondary)
              }
              ingredientLineList(group.lines)
            }
          }
        }
      }
    }
  }

  private func ingredientLineList(_ lines: [IngredientLine]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(lines) { line in
        Text("• \(IngredientScaler.scaledText(for: line, factor: model.scaleFactor))")
          .font(.body)
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

  private func makeAheadSection(_ makeAhead: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Make-ahead")
          .font(.title2.bold())
        Spacer()
        Button(role: .destructive) {
          model.clearMakeAheadButtonTapped()
        } label: {
          Label("Clear", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
      }
      Text(makeAhead)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct RecipeChatPanel: View {
  let chatModel: RecipeChatModel
  let applyActions: [AnyChatApplyAction]

  @State private var draft = ""
  @State private var applyingActionID: AnyChatApplyAction.ID?
  @State private var actionSummary: String?
  @State private var actionError: String?

  var body: some View {
    @Bindable var chatModel = chatModel

    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ChatContextHeader(chatModel: chatModel)
            ForEach(chatModel.messages) { message in
              ChatMessageBubble(message: message)
                .id(message.id)
            }
            if let actionSummary {
              ChatActionSummary(text: actionSummary)
            }
            if let error = chatModel.errorText ?? actionError {
              Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding()
        }
        .onChange(of: chatModel.messages.count) { _, _ in
          guard let lastID = chatModel.messages.last?.id else { return }
          withAnimation {
            proxy.scrollTo(lastID, anchor: .bottom)
          }
        }
      }

      Divider()

      VStack(alignment: .leading, spacing: 12) {
        ForEach(applyActions) { action in
          Button {
            Task { await run(action) }
          } label: {
            Label(
              applyingActionID == action.id ? "Saving make-ahead..." : action.title,
              systemImage: applyingActionID == action.id ? "hourglass" : "text.badge.checkmark"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.bordered)
          .disabled(chatModel.isResponding || applyingActionID != nil)
        }

        HStack(alignment: .bottom, spacing: 8) {
          TextField("Ask about this recipe", text: $draft, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .onSubmit {
              Task { await sendDraft() }
            }

          Button {
            Task { await sendDraft() }
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.title2)
          }
          .buttonStyle(.plain)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatModel.isResponding)
          .accessibilityLabel(Text("Send"))
        }
      }
      .padding()
      .background(.background)
    }
    .navigationTitle(chatModel.context.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if chatModel.frontierAvailable {
          Toggle(isOn: $chatModel.useFrontier) {
            Label("Use frontier model", systemImage: "network")
          }
          .toggleStyle(.button)
          .accessibilityHint(Text("When enabled, recipe context leaves the device."))
        }
      }
    }
  }

  private func sendDraft() async {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    actionSummary = nil
    actionError = nil
    await chatModel.send(text)
  }

  @MainActor
  private func run(_ action: AnyChatApplyAction) async {
    applyingActionID = action.id
    actionSummary = nil
    actionError = nil
    defer { applyingActionID = nil }

    do {
      if let summary = try await action.run(chatModel.messages) {
        actionSummary = summary
      }
    } catch {
      actionError = RecipeChatErrorText.describe(error)
    }
  }
}

private struct ChatContextHeader: View {
  let chatModel: RecipeChatModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(chatModel.sendsToProvider ? "Frontier model" : "On-device", systemImage: chatModel.sendsToProvider ? "network" : "iphone")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      Text(chatModel.sendsToProvider ? "Recipe context leaves the device for this conversation." : "Seeded with the recipe on screen.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ChatMessageBubble: View {
  let message: RecipeChatMessage

  var body: some View {
    HStack {
      if message.role == .user {
        Spacer(minLength: 48)
      }
      Text(LocalizedStringKey(message.text))
        .padding(10)
        .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      if message.role == .assistant {
        Spacer(minLength: 48)
      }
    }
  }
}

private struct ChatActionSummary: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Saved to Make-ahead", systemImage: "checkmark.circle")
        .font(.caption.bold())
        .foregroundStyle(.green)
      Text(text)
        .font(.callout)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct SourceMetadataView: View {
  let source: RecipeSource

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "book")
          .foregroundStyle(.secondary)
        if let urlString = source.url, let url = URL(string: urlString) {
          Link(source.displayName, destination: url)
        } else {
          Text(source.displayName)
        }
      }

      ForEach(source.detailLines, id: \.self) { line in
        Text(line)
          .foregroundStyle(.secondary)
          .padding(.leading, 28)
      }
    }
    .font(.subheadline)
  }
}

private extension RecipeSource {
  var displayName: String {
    name?.nonEmpty ?? publicationName?.nonEmpty ?? bookTitle?.nonEmpty ?? url?.nonEmpty ?? "Source"
  }

  var detailLines: [String] {
    [
      author.nonEmpty.map { "Author: \($0)" },
      publicationName.nonEmpty.map { "Publication: \($0)" },
      bookTitle.nonEmpty.map { "Book: \($0)" },
      pageNumber.nonEmpty.map { "Page: \($0)" },
      sourceNotes.nonEmpty,
    ].compactMap(\.self)
  }
}

private extension String {
  var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    flatMap(\.nonEmpty)
  }
}

private struct RecipePhotoGallery: View {
  let photos: [RecipePhoto]
  @State private var selectedPhotoID: RecipePhoto.ID?

  private var selectedPhoto: RecipePhoto? {
    if let selectedPhotoID, let photo = photos.first(where: { $0.id == selectedPhotoID }) {
      return photo
    }
    return photos.min { lhs, rhs in lhs.displaySortKey < rhs.displaySortKey }
  }

  var body: some View {
    if let selectedPhoto, let data = selectedPhoto.displayData ?? selectedPhoto.thumbnailData {
      VStack(alignment: .leading, spacing: 10) {
        RecipePhotoFrame(data: data, aspectRatio: selectedPhoto.displayAspectRatio)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel(Text(selectedPhoto.caption ?? "Recipe photo"))

        if let caption = selectedPhoto.caption {
          Text(caption)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }

        if photos.count > 1 {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(photos) { photo in
                if let thumbnailData = photo.thumbnailData ?? photo.displayData {
                  Button {
                    selectedPhotoID = photo.id
                  } label: {
                    RecipePhotoFrame(data: thumbnailData, aspectRatio: 1)
                      .frame(width: 76, height: 76)
                      .overlay {
                        RoundedRectangle(cornerRadius: 8)
                          .stroke(
                            photo.id == selectedPhoto.id ? Color.accentColor : Color.clear,
                            lineWidth: 3
                          )
                      }
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
                }
              }
            }
            .padding(.vertical, 2)
          }
          .scrollIndicators(.hidden)
        }
      }
    }
  }
}

private extension RecipePhoto {
  var displaySortKey: PhotoDisplaySortKey {
    PhotoDisplaySortKey(
      isLowResolution: isLowResolution,
      kindRank: kind == .hero ? 0 : 1,
      sortOrder: sortOrder
    )
  }

  var displayAspectRatio: CGFloat {
    guard kind == .referenceDocument else { return 16.0 / 10.0 }
    guard
      let pixelWidth,
      let pixelHeight,
      pixelWidth > 0,
      pixelHeight > 0
    else {
      return 3.0 / 4.0
    }
    return Swift.min(Swift.max(CGFloat(pixelWidth) / CGFloat(pixelHeight), 0.65), 1.4)
  }

  var isLowResolution: Bool {
    Swift.max(pixelWidth ?? 0, pixelHeight ?? 0) < 700
  }
}

private struct PhotoDisplaySortKey: Comparable {
  var isLowResolution: Bool
  var kindRank: Int
  var sortOrder: Int

  static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.isLowResolution != rhs.isLowResolution {
      return !lhs.isLowResolution
    }
    if lhs.kindRank != rhs.kindRank {
      return lhs.kindRank < rhs.kindRank
    }
    return lhs.sortOrder < rhs.sortOrder
  }
}

private struct RecipePhotoFrame: View {
  let data: Data
  let aspectRatio: CGFloat

  var body: some View {
    Color.clear
      .aspectRatio(aspectRatio, contentMode: .fit)
      .overlay {
        RecipePhotoImage(data: data)
          .padding(1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct RecipePhotoImage: View {
  let data: Data

  var body: some View {
    if let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Image(systemName: "photo")
        .font(.title)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Text("Multiplier")
          .font(.subheadline.bold())

        HStack(spacing: 8) {
          ForEach([1.0, 2.0, 3.0], id: \.self) { multiplier in
            Button {
              model.multiplierButtonTapped(multiplier)
            } label: {
              Text(ScaleText.factor(multiplier))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(model.scaleFactor == multiplier ? .accentColor : nil)
            .accessibilityAddTraits(model.scaleFactor == multiplier ? .isSelected : [])
          }
        }
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
      if let scaledServingsSummary = model.scaledServingsSummary {
        LabeledContent("Resulting servings", value: scaledServingsSummary)
          .font(.subheadline)
      }

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
