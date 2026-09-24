import SwiftUI
import SwiftUINavigation
import UIKit
import YesChefCore

struct RecipeDetailView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var model: RecipeDetailModel
  @State private var handoffTransport: HandoffInAppTransport
  /// Own toast host: this view is presented from four places (full-screen cover, both iPad split
  /// layouts, and the cook session) and only one of them mounts an overlay.
  @State private var toastCenter: AppToastCenter
  @State private var isConfirmingBaseRecipeHandoff = false
  @State private var isPlaybookJumpAvailable = false
  @State private var playbookJumpRequest = UUID()
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
    includingArchivedRecipe: Bool = false,
    libraryModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    isFocusActive: Bool = false,
    focusButtonTapped: (() -> Void)? = nil,
    onRecipeSelected: @escaping (RecipeDetailPresentation) -> Void = { _ in }
  ) {
    let toastCenter = AppToastCenter()
    let model = RecipeDetailModel(
      recipeID: recipeID,
      scaleContext: scaleContext,
      workbenchID: workbenchID,
      includingArchivedRecipe: includingArchivedRecipe,
      toastCenter: toastCenter
    )
    _model = State(
      wrappedValue: model
    )
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
      model.serveWithDidLoadOrAppear()
    }
    .onChange(of: model.persistedScale) { _, persistedScale in
      model.persistedScaleChanged(persistedScale)
    }
    .onChange(of: model.detail) { _, _ in
      model.serveWithDidLoadOrAppear()
    }
    .toolbar {
      recipeToolbar
    }
    .recipeAskPresentation(model: model, isSplitEnabled: isSplitEnabled)
    .sheet(isPresented: $model.destination.labelSuggestions) {
      RecipeSuggestedLabelsSheet(model: model)
    }
    .sheet(item: $model.destination.workbench) { presentation in
      NavigationStack {
        WorkbenchDetailView(
          workbenchID: presentation.workbenchID,
          onRecipeSelected: onRecipeSelected
        )
      }
    }
    .sheet(item: $model.destination.repairServeWith) { presentation in
      ServeWithRepairSheet(presentation: presentation, save: model.repairServeWith)
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
      isPlaybookJumpAvailable: $isPlaybookJumpAvailable,
      playbookJumpRequest: playbookJumpRequest,
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
        FocusToolbarButton(isActive: isFocusActive, action: focusButtonTapped)
      }
    }
    ToolbarItemGroup(placement: .primaryAction) {
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

        Button {
          model.askButtonTapped()
        } label: {
          Label("Ask now", systemImage: "sparkles")
        }
      } label: {
        Label("Hand off", systemImage: "sparkles.square.filled.on.square")
      }
      if isPlaybookJumpAvailable {
        Button {
          playbookJumpRequest = UUID()
        } label: {
          Label("Playbook", systemImage: "text.book.closed")
        }
        .accessibilityHint("Jumps to the recipe Playbook after the instructions.")
      }
      Button {
        libraryModel.editButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Edit", systemImage: "square.and.pencil")
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
      Button {
        libraryModel.deleteButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Archive", systemImage: "archivebox")
      }
      Button(role: .destructive) {
        libraryModel.deleteArchivedRecipeButtonTapped(recipeID: model.recipeID)
      } label: {
        Label("Delete…", systemImage: "trash")
      }
    }
  }
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
            surface: .recipeAskSheet(
              content: .init(
                applyActions: model.applyActionCatalog(for: chatModel),
                finalization: model.seededAskSection.map {
                  ChatFinalizeConfiguration.recipe(recipeID: model.recipeID, section: $0)
                },
                focusesInputOnAppear: model.seededAskSection == nil
              ),
              selectSection: model.askSection,
              activeSection: model.seededAskSection,
              onDismiss: { model.destination = nil }
            )
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
      surface: .recipeAskInspector(
        content: .init(
          applyActions: model.applyActionCatalog(for: chatModel),
          finalization: model.seededAskSection.map {
            ChatFinalizeConfiguration.recipe(recipeID: model.recipeID, section: $0)
          },
          focusesInputOnAppear: model.seededAskSection == nil
        ),
        selectSection: model.askSection,
        activeSection: model.seededAskSection,
        onDismiss: { model.destination = nil }
      )
    )
    .inspectorColumnWidth(
      min: ChatInspectorMetrics.minimumWidth,
      ideal: ChatInspectorMetrics.idealWidth,
      max: ChatInspectorMetrics.maximumWidth
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
    static let compactThumbnailSideLength: CGFloat = 288
    static let wideHeroWidth: CGFloat = 360
  }

  private let twoColumnThreshold: CGFloat = 640
  private let directionsContentMaximumWidth: CGFloat = 920

  let model: RecipeDetailModel
  let handoffTransport: HandoffInAppTransport
  let libraryModel: RecipeLibraryModel
  @Binding var isPlaybookJumpAvailable: Bool
  let playbookJumpRequest: UUID
  let onRecipeSelected: (RecipeDetailPresentation) -> Void

  @State private var compactSection: CompactSection = .ingredients
  @State private var isPhotoGalleryPresented = false
  @State private var isVariationManagerPresented = false
  @State private var isSummaryExpanded = false
  @State private var promotingVariation: RecipeVariation?
  @State private var splittingOffVariation: RecipeVariation?
  @State private var splitOffTitleDraft = ""
  @State private var pendingVariationRemoval: PendingVariationRemoval?

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
                if !model.activeVariationUnresolvedAnchors.isEmpty {
                  RecipeVariationRepairNotice(anchors: model.activeVariationUnresolvedAnchors, blocksSaving: false)
                }
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
      .onAppear {
        isPlaybookJumpAvailable = model.recipe != nil
      }
      .onChange(of: playbookJumpRequest) { _, _ in
        if proxy.size.width < twoColumnThreshold {
          compactSection = .playbook
        }
      }
      .onChange(of: model.recipe?.id) { _, _ in
        isPlaybookJumpAvailable = model.recipe != nil
      }
      .onDisappear {
        isPlaybookJumpAvailable = false
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
    .sheet(isPresented: $isVariationManagerPresented) {
      NavigationStack {
        ScrollView {
          RecipeVariationChoices(
            variations: model.variations,
            model: model,
            handoffTransport: handoffTransport,
            promotingVariation: $promotingVariation,
            splittingOffVariation: $splittingOffVariation,
            splitOffTitleDraft: $splitOffTitleDraft
          )
          .padding()
        }
        .navigationTitle("Manage Variations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { isVariationManagerPresented = false }
          }
        }
      }
      .presentationDetents([.medium, .large])
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
      pendingVariationRemoval: $pendingVariationRemoval
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
        RecipeMarkdownText(summary)
          .font(.callout)
          .lineLimit(isSummaryExpanded ? nil : 2)
        Button(isSummaryExpanded ? "Less" : "More") {
          isSummaryExpanded.toggle()
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.plain)
        .accessibilityHint(isSummaryExpanded ? "Shows less recipe summary." : "Shows the full recipe summary.")
      }
      RecipeVariationSelector(
        variations: model.variations,
        activeVariationID: model.detail?.activeVariationID,
        select: model.activeVariationSelectionChanged,
        manage: { isVariationManagerPresented = true }
      )
    }
  }

  private func wideColumnHeader(_ recipe: Recipe) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
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
            RecipeMarkdownText(summary)
              .font(.callout)
              .lineLimit(isSummaryExpanded ? nil : 2)
            Button(isSummaryExpanded ? "Less" : "More") {
              isSummaryExpanded.toggle()
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .accessibilityHint(isSummaryExpanded ? "Shows less recipe summary." : "Shows the full recipe summary.")
          }
        }

        wideMetadata(recipe)

        RecipeVariationSelector(
          variations: model.variations,
          activeVariationID: model.detail?.activeVariationID,
          select: model.activeVariationSelectionChanged,
          manage: { isVariationManagerPresented = true }
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let photo = model.primaryDisplayPhoto {
        RecipeReaderHero(photo: photo, width: HeaderMetrics.wideHeroWidth) {
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

      if let notes = model.detail?.source?.sourceNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
        RecipeMarkdownText(notes)
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

      if let categoryDisplayNames = model.detail?.categoryDisplayNames, !categoryDisplayNames.isEmpty {
        WrappingLabels(labels: categoryDisplayNames, systemImage: "folder")
      }

      Button {
        model.suggestLabelsButtonTapped()
      } label: {
        Label("Edit Tags", systemImage: "tag")
      }
      .buttonStyle(.bordered)

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

  private func wideMetadata(_ recipe: Recipe) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      recipeStats(recipe)

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          if recipe.libraryPlacement == .reference {
            Label(recipe.libraryPlacement.title, systemImage: "books.vertical")
              .font(.caption)
              .recipeChip()
          }
          ForEach(Array((model.detail?.categoryDisplayNames ?? []).enumerated()), id: \.offset) { _, name in
            Text(name)
              .font(.caption)
              .recipeChip()
          }
          Button {
            model.suggestLabelsButtonTapped()
          } label: {
            Label("Edit Tags", systemImage: "tag")
              .font(.caption.weight(.medium))
              .frame(minHeight: 36)
          }
          .buttonStyle(.plain)

          if model.adjustmentRestorePoint != nil {
            Button {
              model.undoLastAdjustmentButtonTapped()
            } label: {
              Label("Undo", systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.medium))
                .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)

      if let source = model.detail?.source {
        SourceMetadataView(source: source)
      }
      if let notes = model.detail?.source?.sourceNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
        Text(notes)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
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
      Label(RecipeDurationText.readable(totalTime), systemImage: "clock")
        .recipeChip()
    }
    if let lastCookedAt = model.derivedLastCookedAt {
      Label(
        "Last cooked \(lastCookedAt.formatted(date: .abbreviated, time: .omitted))",
        systemImage: "clock.arrow.circlepath"
      )
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
        onRecipeSelected: onRecipeSelected
      )
    }
  }

  private func wideRecipeColumns(_ recipe: Recipe, in size: CGSize) -> some View {
    let ingredientsWidth = size.width * 0.27
    let directionsWidth = size.width - ingredientsWidth - PlaybookColumnMetrics.separatorWidth
    return HStack(alignment: .top, spacing: 0) {
      ScrollView {
        ingredients
          .padding()
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(width: ingredientsWidth)

      RecipeWideColumnSeparator()

      ScrollViewReader { scrollProxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
              wideColumnHeader(recipe)
                .id("recipe-directions-top")
              directionsColumn
            }

            Divider()

            HStack {
              Text("Playbook")
                .font(.title2.bold())
              Spacer()
              Button {
                withAnimation(.snappy) {
                  scrollProxy.scrollTo("recipe-directions-top", anchor: .top)
                }
              } label: {
                Label("Directions", systemImage: "arrow.up")
                  .font(.caption.weight(.semibold))
              }
              .buttonStyle(.plain)
              .accessibilityHint("Returns to the top of the recipe directions.")
            }
            .id("recipe-playbook")

            RecipePlaybookView(
              model: model,
              handoffTransport: handoffTransport,
              onRecipeSelected: onRecipeSelected
            )
          }
          .padding()
          .frame(maxWidth: directionsContentMaximumWidth, alignment: .topLeading)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onChange(of: playbookJumpRequest) { _, _ in
          withAnimation(.snappy) {
            scrollProxy.scrollTo("recipe-playbook", anchor: .top)
          }
        }
        .frame(width: directionsWidth)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  @ViewBuilder
  private var directionsColumn: some View {
    VStack(alignment: .leading, spacing: 18) {
      if !model.activeVariationUnresolvedAnchors.isEmpty {
        RecipeVariationRepairNotice(
          anchors: model.activeVariationUnresolvedAnchors,
          blocksSaving: false
        )
      }
      if let note = model.activeVariationNote {
        variationMethodNote(note)
      }
      if !model.instructionGroups.isEmpty {
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
      VStack(alignment: .leading, spacing: 20) {
        ForEach(model.instructionStepDisplayGroups) { group in
          VStack(alignment: .leading, spacing: 8) {
            if let name = group.name {
              Text(name)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 14) {
              ForEach(group.steps) { display in
                InstructionStepRow(display: display)
              }
            }
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
    .attentionCard()
  }
}
