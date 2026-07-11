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
  let showsStartCookingButton: Bool
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  init(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil,
    libraryModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil,
    showsStartCookingButton: Bool = true,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void = { _ in }
  ) {
    _model = State(wrappedValue: RecipeDetailModel(recipeID: recipeID, scaleContext: scaleContext))
    self.libraryModel = libraryModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.isFocusActive = isFocusActive
    self.focusButtonTapped = focusButtonTapped
    self.showsStartCookingButton = showsStartCookingButton
    self.onRecipeSelected = onRecipeSelected
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
      ToolbarItemGroup(placement: .topBarLeading) {
        if isSplitEnabled, let focusButtonTapped {
          Button {
            focusButtonTapped()
          } label: {
            Label(
              isFocusActive ? "Exit Focus" : "Focus",
              systemImage: isFocusActive
                ? "arrow.up.left.and.arrow.down.right.circle.fill"
                : "arrow.up.left.and.arrow.down.right"
            )
          }
          .tint(isFocusActive ? .accentColor : .primary)
          .accessibilityValue(Text(isFocusActive ? "Focused" : "Split view"))
        }
        Button {
          libraryModel.editButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("Edit", systemImage: "square.and.pencil")
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
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
        Menu {
          Button {
            model.openWorkbenchButtonTapped()
          } label: {
            Label("Open a Workbench", systemImage: "hammer")
          }
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
    .sheet(item: $model.destination.workbench) { presentation in
      NavigationStack {
        WorkbenchDetailView(
          workbenchID: presentation.workbenchID,
          onRecipeSelected: onRecipeSelected
        )
      }
    }
    .adjustmentReviewPresentation(
      item: $model.destination.adjustmentReview,
      usesFullScreenCover: isSplitEnabled
    ) { review in
      RecipeAdjustmentReviewView(
        review: review,
        overwrite: { model.overwriteAdjustmentButtonTapped($0) },
        keepAsVariation: { model.keepAdjustmentAsVariationButtonTapped($0, name: $1) }
      )
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
        context: .recipe(RecipeChatRecipeContext(detail: model.displayDetail ?? detail)),
        detentRaw: $chatWorkspaceDetentRaw,
        applyActions: { chatModel in
          model.applyActionCatalog(for: chatModel)
        }
      ) {
        RecipeReaderView(
          model: model,
          libraryModel: libraryModel,
          showsStartCookingButton: showsStartCookingButton
        )
      }
    } else {
      RecipeReaderView(
        model: model,
        libraryModel: libraryModel,
        showsStartCookingButton: showsStartCookingButton
      )
    }
  }

  private var isSplitEnabled: Bool {
    UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
  }

  private func chatButtonTapped() {
    if isSplitEnabled {
      chatWorkspaceDetentRaw = chatWorkspaceDetentRaw == ChatWorkspaceDetent.readerOnly.rawValue
        ? ChatWorkspaceDetent.balanced.rawValue
        : ChatWorkspaceDetent.readerOnly.rawValue
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
  let showsStartCookingButton: Bool

  @State private var compactSection: CompactSection = .ingredients
  @State private var isPhotoGalleryPresented = false
  @State private var isEditingReaderFeedback = false
  @State private var readerFeedbackDrafts: [RecipeNote.ID: String] = [:]
  @State private var renamingVariation: RecipeVariation?
  @State private var variationNameDraft = ""

  var body: some View {
    GeometryReader { proxy in
      if let recipe = model.recipe {
        let isTwoColumn = proxy.size.width >= twoColumnThreshold
        if isTwoColumn {
          VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
              header(recipe)
              metadata(recipe)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack(alignment: .top, spacing: 0) {
              ScrollView {
                ingredients
                  .padding()
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
              .frame(maxWidth: .infinity)

              Divider()

              ScrollView {
                directionsColumn
                  .padding()
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
              .frame(maxWidth: .infinity)
            }
          }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              header(recipe)
              metadata(recipe)
              compactRecipeBody
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      } else {
        ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
      }
    }
    .sheet(isPresented: $isPhotoGalleryPresented) {
      NavigationStack {
        ScrollView {
          RecipePhotoGallery(
            photos: model.displayablePhotos,
            coverPhotoID: model.recipe?.coverPhotoID,
            setCoverPhoto: { model.coverPhotoButtonTapped($0) }
          )
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
    .keepsScreenAwakeWhilePresented()
    .onChange(of: model.detail?.activeVariationID) {
      #if DEBUG
        let selection = model.detail?.activeVariationID?.uuidString ?? "base"
        AppLog.performance.log(
          "recipe-detail-view active-variation-delivered selection=\(selection, privacy: .public)"
        )
      #endif
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
          if showsStartCookingButton {
            startCookingButton(recipe)
          }
        }

        VStack(alignment: .leading, spacing: 10) {
          recipeStats(recipe)
          if showsStartCookingButton {
            startCookingButton(recipe)
          }
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
      if let detail = model.detail, !detail.variations.isEmpty {
        variationPicker(detail.variations, activeVariationID: detail.activeVariationID)
      }
      if model.adjustmentRestorePoint != nil {
        Button {
          model.undoLastAdjustmentButtonTapped()
        } label: {
          Label("Undo Adjustment", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func variationPicker(
    _ variations: [RecipeVariation],
    activeVariationID: RecipeVariation.ID?
  ) -> some View {
    let activeVariation = activeVariationID.flatMap { id in variations.first { $0.id == id } }
    return HStack(spacing: 8) {
      Picker(
        "Variation",
        selection: Binding(
          get: { activeVariationID },
          set: { model.activeVariationSelectionChanged($0) }
        )
      ) {
        Label("Base Recipe", systemImage: "book.closed")
          .tag(nil as RecipeVariation.ID?)
        ForEach(variations) { variation in
          Text(variation.name)
            .tag(variation.id as RecipeVariation.ID?)
        }
      }
      .pickerStyle(.menu)

      if let activeVariation {
        Button {
          variationNameDraft = activeVariation.name
          renamingVariation = activeVariation
        } label: {
          Label("Rename Variation", systemImage: "pencil")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Rename Variation"))
      }
    }
    .alert(
      "Rename Variation",
      isPresented: Binding(
        get: { renamingVariation != nil },
        set: { if !$0 { renamingVariation = nil } }
      )
    ) {
      TextField("Name", text: $variationNameDraft)
      Button("Save") {
        if let variation = renamingVariation {
          model.renameVariation(variation.id, to: variationNameDraft)
        }
        renamingVariation = nil
      }
      Button("Cancel", role: .cancel) {
        renamingVariation = nil
      }
    } message: {
      Text("Give this variation a new name.")
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
  private var compactRecipeBody: some View {
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
      directionsColumn
    }
  }

  @ViewBuilder
  private var directionsColumn: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let makeAhead = model.makeAhead {
        makeAheadSection(makeAhead)
      }
      if !model.serveWithItems.isEmpty {
        serveWithSection(model.serveWithItems)
      }
      if let note = model.activeVariationNote {
        variationMethodNote(note)
      }
      if !model.instructionSteps.isEmpty {
        instructions
      }
      let visibleNotes = model.visibleNotes
      let readerFeedbackNotes = visibleNotes.filter { $0.noteType == .readerFeedback }
      let otherNotes = visibleNotes.filter { $0.noteType != .readerFeedback }
      if !readerFeedbackNotes.isEmpty {
        readerFeedbackView(readerFeedbackNotes)
      }
      if !otherNotes.isEmpty {
        notesView(otherNotes)
      }
      if let chefItUp = model.chefItUp {
        chefItUpSection(chefItUp)
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
          ingredientLineList(model.ingredientLineDisplays)
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

  private func ingredientLineList(_ lines: [IngredientLineDisplay]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(lines) { display in
        IngredientLineRow(
          display: display,
          scaledText: IngredientScaler.scaledText(for: display.line, factor: model.scaleFactor)
        )
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

  private func variationMethodNote(_ note: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(model.activeVariation?.name ?? "Variation", systemImage: "square.stack.3d.up")
        .font(.title3.bold())
      Text(note)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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

  private func chefItUpSection(_ chefItUp: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Chef It Up")
          .font(.title2.bold())
        Spacer()
        Button(role: .destructive) {
          model.clearChefItUpButtonTapped()
        } label: {
          Label("Clear", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
      }
      Text(chefItUp)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func serveWithSection(_ items: [ServeWithItem]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Serve With")
        .font(.title2.bold())
      VStack(alignment: .leading, spacing: 10) {
        ForEach(items) { item in
          HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
              Text(item.title)
                .font(.headline)
              if let note = item.note {
                Text(note)
                  .font(.callout)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
              model.removeServeWithButtonTapped(item.id)
            } label: {
              Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove \(item.title)"))
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
          Text(note.noteType.displayTitle)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
          Text(note.text)
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func readerFeedbackView(_ notes: [RecipeNote]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Reader Feedback")
          .font(.title2.bold())
        Spacer()
        Button(isEditingReaderFeedback ? "Done" : "Edit") {
          if isEditingReaderFeedback {
            commitReaderFeedbackEdits(notes)
          } else {
            readerFeedbackDrafts = Dictionary(
              uniqueKeysWithValues: notes.map { ($0.id, $0.text) }
            )
          }
          isEditingReaderFeedback.toggle()
        }
        .font(.callout)
      }
      ForEach(notes) { note in
        if isEditingReaderFeedback {
          VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: readerFeedbackDraftBinding(for: note))
              .frame(minHeight: 72)
              .padding(6)
              .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            Button(role: .destructive) {
              readerFeedbackDrafts[note.id] = nil
              model.deleteReaderFeedbackNote(note)
            } label: {
              Label("Delete", systemImage: "trash")
            }
            .font(.callout)
          }
          .padding(.vertical, 4)
        } else {
          Text(note.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
      }
    }
  }

  private func readerFeedbackDraftBinding(for note: RecipeNote) -> Binding<String> {
    Binding(
      get: { readerFeedbackDrafts[note.id] ?? note.text },
      set: { readerFeedbackDrafts[note.id] = $0 }
    )
  }

  private func commitReaderFeedbackEdits(_ notes: [RecipeNote]) {
    for note in notes {
      guard let draft = readerFeedbackDrafts[note.id] else { continue }
      model.updateReaderFeedbackNote(note, text: draft)
    }
    readerFeedbackDrafts = [:]
  }
}

private struct IngredientLineRow: View {
  let display: IngredientLineDisplay
  let scaledText: String

  private var line: IngredientLine { display.line }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if line.isHeader {
        Text(line.originalText.trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines)))
          .font(.headline)
      } else {
        Text("•")
          .foregroundStyle(.secondary)
        Text(scaledText)
          .font(.body)
          .strikethrough(display.highlight == .removed)
      }
    }
    .foregroundStyle(display.highlight == .removed ? .secondary : .primary)
    .padding(.horizontal, display.highlight == nil ? 0 : 8)
    .padding(.vertical, display.highlight == nil ? 0 : 4)
    .background(highlightColor, in: RoundedRectangle(cornerRadius: 6))
  }

  private var highlightColor: Color {
    switch display.highlight {
    case .added:
      Color.green.opacity(0.14)
    case .changed:
      Color.accentColor.opacity(0.12)
    case .removed:
      Color.secondary.opacity(0.10)
    case nil:
      Color.clear
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

private extension View {
  @ViewBuilder
  func adjustmentReviewPresentation<Item: Identifiable, Content: View>(
    item: Binding<Item?>,
    usesFullScreenCover: Bool,
    @ViewBuilder content: @escaping (Item) -> Content
  ) -> some View {
    if usesFullScreenCover {
      fullScreenCover(item: item, content: content)
    } else {
      sheet(item: item, content: content)
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
