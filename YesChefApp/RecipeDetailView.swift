import SwiftUI
import SwiftUINavigation
import UIKit
import YesChefCore

struct RecipeDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(ChatWorkspaceDetent.storageKey) private var chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
  @State private var model: RecipeDetailModel
  let libraryModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let isFocusActive: Bool
  let focusButtonTapped: (() -> Void)?

  init(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil,
    libraryModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil
  ) {
    _model = State(wrappedValue: RecipeDetailModel(recipeID: recipeID, scaleContext: scaleContext))
    self.libraryModel = libraryModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.isFocusActive = isFocusActive
    self.focusButtonTapped = focusButtonTapped
  }

  var body: some View {
    @Bindable var model = model

    detailContent
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      model.persistedScaleChanged(model.persistedScale)
    }
    .onChange(of: model.persistedScale) { _, persistedScale in
      model.persistedScaleChanged(persistedScale)
    }
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        if isSplitEnabled, let focusButtonTapped {
          Button {
            focusButtonTapped()
          } label: {
            Label(
              "Focus",
              systemImage: isFocusActive ? "rectangle.expand" : "arrow.up.left.and.arrow.down.right"
            )
          }
        }
        if !model.ingredientLines.isEmpty {
          Button {
            model.scaleButtonTapped()
          } label: {
            Label(model.scaleSummary, systemImage: "slider.horizontal.3")
          }
          .popover(
            isPresented: $model.destination.scaling,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
          ) {
            ScalePanel(model: model)
              .presentationCompactAdaptation(.popover)
          }
        }
        Button {
          chatButtonTapped()
        } label: {
          Label("Chat", systemImage: "sparkles")
        }
        .disabled(model.detail == nil)
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

  @ViewBuilder
  private var detailContent: some View {
    if isSplitEnabled, let detail = model.detail {
      ChatWorkspaceSplit(
        context: .recipe(RecipeChatRecipeContext(detail: detail)),
        detentRaw: $chatWorkspaceDetentRaw,
        applyActions: { chatModel in
          model.applyActionCatalog(for: chatModel)
        }
      ) {
        RecipeReaderView(model: model, libraryModel: libraryModel)
      }
    } else {
      RecipeReaderView(model: model, libraryModel: libraryModel)
    }
  }

  private var isSplitEnabled: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }

  private func chatButtonTapped() {
    if isSplitEnabled {
      chatWorkspaceDetentRaw = ChatWorkspaceDetent.balanced.rawValue
    } else {
      model.chatButtonTapped()
    }
  }
}

private struct RecipeReaderView: View {
  private enum CompactSection: String, CaseIterable, Identifiable {
    case ingredients
    case directions

    var id: Self { self }

    var title: String {
      switch self {
      case .ingredients: "Ingredients"
      case .directions: "Directions"
      }
    }
  }

  private let twoColumnThreshold: CGFloat = 640

  let model: RecipeDetailModel
  let libraryModel: RecipeLibraryModel

  @State private var compactSection: CompactSection = .ingredients
  @State private var isPhotoGalleryPresented = false

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        if let recipe = model.recipe {
          VStack(alignment: .leading, spacing: 16) {
            header(recipe)
            metadata(recipe)
            recipeBody(isTwoColumn: proxy.size.width >= twoColumnThreshold)
          }
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
      }
    }
    .sheet(isPresented: $isPhotoGalleryPresented) {
      NavigationStack {
        ScrollView {
          RecipePhotoGallery(photos: model.displayablePhotos)
            .padding()
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              isPhotoGalleryPresented = false
            }
          }
        }
      }
    }
  }

  private func header(_ recipe: Recipe) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(recipe.title)
              .font(.title.bold())
            if recipe.favorite {
              Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            }
          }
          if let subtitle = recipe.subtitle {
            Text(subtitle)
              .font(.headline)
              .foregroundStyle(.secondary)
          }
          if let summary = recipe.summary {
            Text(summary)
              .font(.callout)
          }
        }
        Spacer(minLength: 12)
        if !model.displayablePhotos.isEmpty, let photo = model.primaryDisplayPhoto {
          RecipeReaderThumbnail(photo: photo) {
            isPhotoGalleryPresented = true
          }
        }
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

  @ViewBuilder
  private func recipeBody(isTwoColumn: Bool) -> some View {
    if isTwoColumn {
      HStack(alignment: .top, spacing: 24) {
        ingredients
          .frame(maxWidth: .infinity, alignment: .topLeading)
        VStack(alignment: .leading, spacing: 18) {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else {
      Picker("Recipe section", selection: $compactSection) {
        ForEach(CompactSection.allCases) { section in
          Text(section.title).tag(section)
        }
      }
      .pickerStyle(.segmented)

      switch compactSection {
      case .ingredients:
        ingredients
      case .directions:
        VStack(alignment: .leading, spacing: 18) {
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
        Text(model.scaleSummary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
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

private extension RecipeDetailModel {
  var primaryDisplayPhoto: RecipePhoto? {
    displayablePhotos.min { lhs, rhs in lhs.displaySortKey < rhs.displaySortKey }
  }
}

private struct RecipeReaderThumbnail: View {
  let photo: RecipePhoto
  let action: () -> Void

  var body: some View {
    if let data = photo.thumbnailData ?? photo.displayData {
      Button(action: action) {
        RecipePhotoFrame(data: data, aspectRatio: 1)
          .frame(width: 112, height: 112)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
      .accessibilityHint(Text("Opens photo gallery."))
    }
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
  @State private var enlargedPhoto: RecipePhoto?

  private var selectedPhoto: RecipePhoto? {
    if let selectedPhotoID, let photo = photos.first(where: { $0.id == selectedPhotoID }) {
      return photo
    }
    return photos.min { lhs, rhs in lhs.displaySortKey < rhs.displaySortKey }
  }

  var body: some View {
    if let selectedPhoto, let data = selectedPhoto.displayData ?? selectedPhoto.thumbnailData {
      VStack(alignment: .leading, spacing: 10) {
        Button {
          enlargedPhoto = selectedPhoto
        } label: {
          RecipePhotoFrame(data: data, aspectRatio: selectedPhoto.displayAspectRatio)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(selectedPhoto.caption ?? "Recipe photo"))
        .accessibilityHint(Text("Opens enlarged photo."))

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
      .fullScreenCover(item: $enlargedPhoto) { photo in
        RecipePhotoFullScreenView(photo: photo)
      }
    }
  }
}

private struct RecipePhotoFullScreenView: View {
  @Environment(\.dismiss) private var dismiss
  let photo: RecipePhoto

  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      if let data = photo.displayData ?? photo.thumbnailData {
        RecipePhotoImage(data: data)
          .aspectRatio(photo.displayAspectRatio, contentMode: .fit)
          .padding()
          .accessibilityLabel(Text(photo.caption ?? "Recipe photo"))
      }
    }
    .overlay(alignment: .topTrailing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.largeTitle)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.white)
      }
      .buttonStyle(.plain)
      .padding()
      .accessibilityLabel(Text("Close"))
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

        HStack(spacing: 0) {
          Picker("Whole multiplier", selection: $model.scaleWholePart) {
            ForEach(0...10, id: \.self) { whole in
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

      LabeledContent("Multiplier", value: ScaleText.factor(model.scaleFactor))
        .font(.subheadline)
      if let scaledServingsSummary = model.scaledServingsSummary {
        LabeledContent("Makes", value: "~\(scaledServingsSummary)")
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
