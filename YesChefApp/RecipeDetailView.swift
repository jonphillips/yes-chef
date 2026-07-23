import SwiftUI
import SwiftUINavigation
import UIKit
import YesChefCore

struct RecipeDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @AppStorage(RecipePlaybookColumnPreferences.visibilityStorageKey)
  private var isPlaybookColumnVisible = true
  @State private var model: RecipeDetailModel
  @State private var handoffTransport: HandoffInAppTransport
  /// Own toast host: this view is presented from four places (full-screen cover, both iPad split
  /// layouts, and the cook session) and only one of them mounts an overlay.
  @State private var toastCenter: AppToastCenter
  @State private var isConfirmingBaseRecipeHandoff = false
  let libraryModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let isFocusActive: Bool
  let focusButtonTapped: (() -> Void)?
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  init(
    recipeID: Recipe.ID,
    scaleContext: ScaleContext? = nil,
    workbenchID: Workbench.ID? = nil,
    libraryModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void = { _ in }
  ) {
    _model = State(
      wrappedValue: RecipeDetailModel(
        recipeID: recipeID,
        scaleContext: scaleContext,
        workbenchID: workbenchID
      )
    )
    let toastCenter = AppToastCenter()
    _toastCenter = State(wrappedValue: toastCenter)
    _handoffTransport = State(wrappedValue: HandoffInAppTransport(toastCenter: toastCenter))
    self.libraryModel = libraryModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.isFocusActive = isFocusActive
    self.focusButtonTapped = focusButtonTapped
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
      recipeToolbar
    }
    .recipeAskPresentation(model: model, isSplitEnabled: isSplitEnabled)
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
    .sheet(item: $model.destination.variationEditor, id: \.self) { variationID in
      NavigationStack {
        RecipeVariationEditorView(recipeID: model.recipeID, variationID: variationID)
      }
    }
    .alert("Recipe Update Failed", isPresented: $model.isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "Something went wrong.")
    }
    .handoffTransportAlert(handoffTransport)
    .overlay(alignment: .top) {
      AppToastOverlay(toastCenter: toastCenter)
        .ignoresSafeArea(.keyboard)
    }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
    .confirmationDialog(
      RecipeVariationBaseWriteGuard.handoffConfirmationTitle,
      isPresented: $isConfirmingBaseRecipeHandoff,
      titleVisibility: .visible
    ) {
      Button("Hand Off Base Recipe") {
        copyAdjustmentPrompt()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      if let variationName = model.activeVariation?.name {
        Text(RecipeVariationBaseWriteGuard.handoffConfirmation(variationName: variationName))
      }
    }
  }

  private func copyAdjustmentPrompt() {
    Task {
      await handoffTransport.copyPrompt(for: .recipeAdjustment(model.recipeID))
    }
  }

  @ViewBuilder
  private var detailContent: some View {
    RecipeReaderView(
      model: model,
      handoffTransport: handoffTransport,
      libraryModel: libraryModel,
      isPlaybookColumnVisible: $isPlaybookColumnVisible,
      onRecipeSelected: onRecipeSelected
    )
  }

  private var isSplitEnabled: Bool {
    WideLayout.isEnabled(horizontalSizeClass: horizontalSizeClass)
  }

  @ToolbarContentBuilder
  private var recipeToolbar: some ToolbarContent {
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
    }
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        libraryModel.editButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Edit", systemImage: "square.and.pencil")
      }
      Button {
        groceryModel.addRecipeButtonTapped(
          recipeID: model.recipeID,
          scaleContext: model.scaleContext
        )
      } label: {
        Label("Groceries", systemImage: "cart.badge.plus")
      }
      Button {
        mealCalendarModel.addRecipeToPlanButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Plan", systemImage: "calendar.badge.plus")
      }
      Menu {
        // `PasteButton` does not render inside a `Menu`, so this stays a plain button that reads the
        // pasteboard directly, matching the scoped Playbook hand-off menu (ADR-0041 Amd 1).
        Button {
          // The hand-off exports the base recipe even when a variation is displayed, so confirm rather
          // than let the cook argue for an hour about text the return cannot apply to (Amd1-OQ3).
          if model.activeVariation == nil {
            copyAdjustmentPrompt()
          } else {
            isConfirmingBaseRecipeHandoff = true
          }
        } label: {
          Label("Hand off", systemImage: "sparkles.square.filled.on.square")
        }

        Button {
          // A declined paste alert (or a non-string clipboard) yields nil. Hand the empty case to the
          // transport rather than returning silently, so the tap always produces visible feedback.
          let results = UIPasteboard.general.string.map { [$0] } ?? []
          Task {
            await handoffTransport.pastedResultsReceived(
              results,
              source: .recipeAdjustment(model.recipeID)
            )
          }
        } label: {
          Label("Paste", systemImage: "doc.on.clipboard")
        }
        .disabled(!UIPasteboard.general.hasStrings)
      } label: {
        Label("Hand off", systemImage: "sparkles.square.filled.on.square")
      }
    }
    ToolbarItemGroup(placement: .secondaryAction) {
      Button {
        model.openWorkbenchButtonTapped()
      } label: {
        Label("Workbench", systemImage: "hammer")
      }

      if model.recipe?.originalSnapshot != nil {
        Button {
          libraryModel.originalSnapshotButtonTapped(recipeID: model.recipeID)
        } label: {
          Label("View Original", systemImage: "doc.text.magnifyingglass")
        }
      }
      Button(role: .destructive) {
        libraryModel.deleteButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Archive", systemImage: "archivebox")
      }
    }
  }
}

private enum RecipeAskSlideOverMetrics {
  // Matches the established Menu recipe-browser inspector range so companion panels
  // keep a readable, non-dominating width across regular iPad layouts.
  static let minimumWidth: CGFloat = 320
  static let idealWidth: CGFloat = 380
  static let maximumWidth: CGFloat = 480
}

private struct RecipeAskPresentationModifier: ViewModifier {
  let model: RecipeDetailModel
  let isSplitEnabled: Bool

  func body(content: Content) -> some View {
    @Bindable var model = model

    content
      .inspector(isPresented: isSplitEnabled ? askInspectorPresented : .constant(false)) {
        if let destination = model.destination, case let .chat(chatModel) = destination {
          askSlideOver(chatModel)
        }
      }
      .sheet(item: isSplitEnabled ? .constant(nil) : $model.destination.chat) { chatModel in
        NavigationStack {
          RecipeChatPanel(
            chatModel: chatModel,
            applyActions: model.applyActionCatalog(for: chatModel)
          )
        }
      }
  }

  private var askInspectorPresented: Binding<Bool> {
    Binding(
      get: { model.destination.chat != nil },
      set: { isPresented in
        guard !isPresented, model.destination.chat != nil else { return }
        model.destination = nil
      }
    )
  }

  private func askSlideOver(_ chatModel: RecipeChatModel) -> some View {
    RecipeChatPanel(
      chatModel: chatModel,
      applyActions: model.applyActionCatalog(for: chatModel)
    )
    .inspectorColumnWidth(
      min: RecipeAskSlideOverMetrics.minimumWidth,
      ideal: RecipeAskSlideOverMetrics.idealWidth,
      max: RecipeAskSlideOverMetrics.maximumWidth
    )
  }
}

private extension View {
  func recipeAskPresentation(model: RecipeDetailModel, isSplitEnabled: Bool) -> some View {
    modifier(RecipeAskPresentationModifier(model: model, isSplitEnabled: isSplitEnabled))
  }
}

private struct RecipeReaderView: View {
  private enum CompactSection: String, CaseIterable, Identifiable {
    case ingredients
    case directions
    case playbook

    var id: Self { self }

    var title: String {
      switch self {
      case .ingredients: "Ingredients"
      case .directions: "Directions"
      case .playbook: "Playbook"
      }
    }
  }

  private enum HeaderMetrics {
    static let compactThumbnailSideLength: CGFloat = 72
    // The nested wide-column header can use its reclaimed vertical space for a
    // more legible cover photo without changing the compact reader's density.
    static let wideColumnPhotoSideLength: CGFloat = 96
  }

  private let twoColumnThreshold: CGFloat = 640

  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  let libraryModel: RecipeLibraryModel
  @Binding var isPlaybookColumnVisible: Bool
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  @AppStorage(RecipePlaybookColumnPreferences.detentStorageKey)
  private var playbookDetentRaw = RecipePlaybookColumnDetent.comfortable.rawValue
  @State private var compactSection: CompactSection = .ingredients
  @GestureState private var playbookDragTranslation: CGFloat = 0
  @State private var isPhotoGalleryPresented = false
  @State private var promotingVariation: RecipeVariation?
  @State private var splittingOffVariation: RecipeVariation?
  @State private var splitOffTitleDraft = ""
  @State private var unrepresentablePromotionNames: [String] = []

  var body: some View {
    GeometryReader { proxy in
      Group {
        if let recipe = model.recipe {
          let isTwoColumn = proxy.size.width >= twoColumnThreshold
          if isTwoColumn {
            wideRecipeColumns(recipe, in: proxy.size)
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
            .swipeActionsContainer()
          }
        } else {
          ContentUnavailableView("Recipe Not Found", systemImage: "fork.knife")
            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
      }
      .toolbar {
        if model.recipe != nil, proxy.size.width >= twoColumnThreshold {
          ToolbarItem(placement: .primaryAction) {
            Button {
              isPlaybookColumnVisible.toggle()
            } label: {
              Label(
                isPlaybookColumnVisible ? "Hide Playbook" : "Show Playbook",
                systemImage: "sidebar.trailing"
              )
            }
          }
        }
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
    .recipeVariationPromotionPresentation(
      model: model,
      promotingVariation: $promotingVariation,
      unrepresentablePromotionNames: $unrepresentablePromotionNames
    )
  }

  private func header(_ recipe: Recipe) -> some View {
    VStack(alignment: .leading, spacing: 4) {
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
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
      }
      if let summary = recipe.summary {
        Text(summary)
          .font(.callout)
          .lineLimit(2)
      }
    }
  }

  private func wideColumnHeader(_ recipe: Recipe) -> some View {
    HStack(alignment: .top, spacing: 12) {
      header(recipe)
        .frame(maxWidth: .infinity, alignment: .leading)
      if let photo = model.primaryDisplayPhoto {
        RecipeReaderThumbnail(photo: photo, sideLength: HeaderMetrics.wideColumnPhotoSideLength) {
          isPhotoGalleryPresented = true
        }
      }
    }
  }

  private func metadata(
    _ recipe: Recipe,
    showsPhoto: Bool = true
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            recipeStats(recipe)
            if let source = model.detail?.source {
              SourceMetadataView(source: source)
            }
          }
          Spacer(minLength: 12)
          if showsPhoto, let photo = model.primaryDisplayPhoto {
            RecipeReaderThumbnail(photo: photo, sideLength: HeaderMetrics.compactThumbnailSideLength) {
              isPhotoGalleryPresented = true
            }
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          if showsPhoto, let photo = model.primaryDisplayPhoto {
            RecipeReaderThumbnail(photo: photo, sideLength: HeaderMetrics.compactThumbnailSideLength) {
              isPhotoGalleryPresented = true
            }
          }
          recipeStats(recipe)
          if let source = model.detail?.source {
            SourceMetadataView(source: source)
          }
        }
      }

      if let notes = model.detail?.source?.sourceNotes?.nonEmpty {
        Text(notes)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if recipe.libraryPlacement == .reference {
        Label(recipe.libraryPlacement.title, systemImage: "books.vertical")
          .font(.caption)
          .foregroundStyle(.secondary)
          .recipeChip()
      }

      if let tags = model.detail?.tags, !tags.isEmpty {
        WrappingLabels(labels: tags.map(\.name), systemImage: "tag")
      }
      if let categoryDisplayNames = model.detail?.categoryDisplayNames, !categoryDisplayNames.isEmpty {
        WrappingLabels(labels: categoryDisplayNames, systemImage: "folder")
      }

      if let detail = model.detail, !detail.variations.isEmpty {
        RecipeVariationPicker(
          variations: detail.variations,
          activeVariationID: detail.activeVariationID,
          model: model,
          promotingVariation: $promotingVariation,
          splittingOffVariation: $splittingOffVariation,
          splitOffTitleDraft: $splitOffTitleDraft
        )
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

  private func recipeStats(_ recipe: Recipe) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        recipeStatChips(recipe)
      }
      .fixedSize(horizontal: true, vertical: false)

      VStack(alignment: .leading, spacing: 8) {
        recipeStatChips(recipe)
      }
    }
    .font(.subheadline)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private func recipeStatChips(_ recipe: Recipe) -> some View {
    if let servingsText = recipe.servingsText ?? recipe.yieldText {
      if model.ingredientLines.isEmpty {
        Label(servingsText, systemImage: "person.2")
          .recipeChip()
      } else {
        let scaled = model.scaleFactor != 1
        scaleButton(
          scaled ? (model.scaledServingsSummary ?? servingsText) : servingsText,
          systemImage: scaled ? "slider.horizontal.3" : "person.2"
        )
      }
    } else if !model.ingredientLines.isEmpty {
      scaleButton("Scale \(model.scaleSummary)")
    }
    if let totalTime = recipe.totalTimeMinutes {
      Label("\(totalTime) min", systemImage: "clock")
        .recipeChip()
    }
    if let rating = recipe.rating, rating > 0 {
      Label("\(rating)", systemImage: "star.fill")
        .accessibilityLabel(Text("Rating \(rating) out of 5"))
        .recipeChip()
    }
    if let difficulty = recipe.difficulty {
      Label(difficulty.rawValue.capitalized, systemImage: "gauge.with.dots.needle.33percent")
        .accessibilityLabel(Text("Difficulty \(difficulty.rawValue)"))
        .recipeChip()
    }
  }

  private func scaleButton(
    _ title: String,
    systemImage: String = "slider.horizontal.3"
  ) -> some View {
    @Bindable var model = model

    return Button {
      model.scaleButtonTapped()
    } label: {
      Label(title, systemImage: systemImage)
        .recipeChip()
        .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
    .popover(
      isPresented: $model.destination.scaling,
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .top
    ) {
      ScalePanel(model: model)
        .presentationCompactAdaptation(.popover)
    }
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
    case .playbook:
      RecipePlaybookView(
        model: model,
        handoffTransport: handoffTransport,
        ask: model.chatButtonTapped
      )
    }
  }

  private func wideRecipeColumns(_ recipe: Recipe, in size: CGSize) -> some View {
    let layout = RecipeWideColumnLayout(width: size.width, isPlaybookVisible: isPlaybookColumnVisible)
    let detent = currentPlaybookDetent
    let basePlaybookWidth = layout.playbookWidth(for: detent)
    let livePlaybookWidth = layout.proposedPlaybookWidth(
      base: basePlaybookWidth,
      translation: playbookDragTranslation
    )

    return HStack(alignment: .top, spacing: 0) {
      ScrollView {
        ingredients
          .padding()
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(width: layout.ingredientsWidth)

      RecipeWideColumnSeparator()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          wideColumnHeader(recipe)
          metadata(recipe, showsPhoto: false)
          directionsColumn
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(width: layout.directionsWidth(playbookWidth: livePlaybookWidth))

      if isPlaybookColumnVisible {
        RecipePlaybookResizeHandle(
          detent: detent,
          cycle: { currentPlaybookDetent = detent.next },
          decrement: { currentPlaybookDetent = detent.previous },
          increment: { currentPlaybookDetent = detent.next }
        )
        .simultaneousGesture(
          DragGesture(minimumDistance: 2)
            .updating($playbookDragTranslation) { value, state, _ in
              state = value.translation.width
            }
            .onEnded { value in
              let proposedWidth = layout.proposedPlaybookWidth(
                base: basePlaybookWidth,
                translation: value.translation.width
              )
              currentPlaybookDetent = layout.nearestDetent(to: proposedWidth)
            }
        )

        ScrollView {
          RecipePlaybookView(
            model: model,
            handoffTransport: handoffTransport,
            ask: model.chatButtonTapped
          )
          .padding()
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .swipeActionsContainer()
        .frame(width: livePlaybookWidth, alignment: .topLeading)
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.22), value: isPlaybookColumnVisible)
    .animation(.snappy(duration: 0.22), value: playbookDetentRaw)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  private var currentPlaybookDetent: RecipePlaybookColumnDetent {
    get {
      RecipePlaybookColumnDetent(rawValue: playbookDetentRaw) ?? .comfortable
    }
    nonmutating set {
      playbookDetentRaw = newValue.rawValue
    }
  }

  @ViewBuilder
  private var directionsColumn: some View {
    VStack(alignment: .leading, spacing: 18) {
      if let note = model.activeVariationNote {
        variationMethodNote(note)
      }
      if !model.instructionSteps.isEmpty {
        instructions
      }
      if !model.workbenchCandidateLinks.isEmpty {
        WorkbenchCandidateLinksView(links: model.workbenchCandidateLinks, onRecipeSelected: onRecipeSelected)
      }
    }
  }

  private var ingredients: some View {
    @Bindable var model = model

    return VStack(alignment: .leading, spacing: 12) {
      Text("Ingredients")
        .font(.title2.bold())
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
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "book")
        .foregroundStyle(.secondary)
      if let urlString = source.url, let url = URL(string: urlString) {
        Link(source.displayName, destination: url)
      } else {
        Text(source.displayName)
      }
      if let detail = source.compactDetail {
        Text(detail)
          .foregroundStyle(.secondary)
      }
    }
    .lineLimit(1)
    .font(.caption)
  }
}

private extension RecipeSource {
  var displayName: String {
    name?.nonEmpty ?? publicationName?.nonEmpty ?? bookTitle?.nonEmpty ?? url?.nonEmpty ?? "Source"
  }

  var compactDetail: String? {
    author.nonEmpty ?? publicationName.nonEmpty ?? bookTitle.nonEmpty ?? pageNumber.nonEmpty
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

private struct WorkbenchCandidateLinksView: View {
  let links: [WorkbenchCandidateLink]
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Drafted From", systemImage: "arrow.triangle.branch")
        .font(.subheadline.weight(.semibold))
      ForEach(links) { link in
        if let recipeID = link.recipeID {
          Button {
            onRecipeSelected(RecipeDetailPresentation(recipeID: recipeID))
          } label: {
            linkLabel(link)
          }
          .buttonStyle(.plain)
        } else {
          linkLabel(link)
            .foregroundStyle(.secondary)
        }
      }
    }
    .font(.subheadline)
  }

  private func linkLabel(_ link: WorkbenchCandidateLink) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: link.recipeID == nil ? "book.closed" : "arrow.up.right.square")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(link.title)
        if let sourceName = link.sourceName {
          Text(sourceName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}


extension View {
  func recipeChip() -> some View {
    modifier(RecipeChip())
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

private struct RecipeChip: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .overlay {
        Capsule()
          .stroke(.quaternary, lineWidth: 1)
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
            ForEach(0...ScaleFraction.maximumWholeMultiplier, id: \.self) { whole in
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
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        chips
      }
      .fixedSize(horizontal: true, vertical: false)

      VStack(alignment: .leading, spacing: 8) {
        chips
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private var chips: some View {
    ForEach(labels, id: \.self) { label in
      Label(label, systemImage: systemImage)
        .recipeChip()
    }
  }
}
