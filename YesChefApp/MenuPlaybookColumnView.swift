import SwiftUI
import YesChefCore

struct MenuDetailReader: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let detail: MenuDetailData
  let handoffTransport: HandoffInAppTransport
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var regeneratePrepPlan: () -> Void

  @AppStorage(MenuPlaybookColumnPreferences.detentsStorageKey)
  private var persistedPlaybookDetentsData = Data()
  @GestureState private var playbookDragTranslation: CGFloat = 0

  init(
    model: MenuLibraryModel,
    detailModel: MenuDetailModel,
    detail: MenuDetailData,
    handoffTransport: HandoffInAppTransport,
    onRecipeSelected: ((RecipeDetailPresentation) -> Void)? = nil,
    regeneratePrepPlan: @escaping () -> Void
  ) {
    self.model = model
    self.detailModel = detailModel
    self.detail = detail
    self.handoffTransport = handoffTransport
    self.onRecipeSelected = onRecipeSelected
    self.regeneratePrepPlan = regeneratePrepPlan
  }

  private var isServiceDateTodayOrPast: Bool {
    MenuServiceDate.hasArrived(placements: detail.placements, now: detailModel.now)
  }

  var body: some View {
    GeometryReader { proxy in
      Group {
        if proxy.size.width >= MenuPlaybookColumnMetrics.twoColumnThreshold {
          wideMenuColumns(in: proxy.size)
        } else {
          compactMenuReader
        }
      }
    }
    .swipeActionsContainer()
  }

  private var compactMenuReader: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        menuBody
        menuPlaybook
      }
      .padding()
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func wideMenuColumns(in size: CGSize) -> some View {
    let layout = MenuWideColumnLayout(
      width: size.width,
      isPlaybookVisible: true
    )
    let detent = currentPlaybookDetent
    let basePlaybookWidth = layout.playbookWidth(for: detent)
    let livePlaybookWidth = layout.proposedPlaybookWidth(
      base: basePlaybookWidth,
      translation: playbookDragTranslation
    )

    return HStack(alignment: .top, spacing: 0) {
      ScrollView {
        menuBody
          .padding()
          .frame(maxWidth: 900, alignment: .leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(width: layout.bodyWidth(playbookWidth: livePlaybookWidth))

      RecipePlaybookResizeHandle(
        detent: detent,
        splitAccessibilityLabel: "Dishes and Playbook split",
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
        menuPlaybook
          .padding()
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .frame(width: livePlaybookWidth, alignment: .topLeading)
    }
    .animation(.snappy(duration: 0.22), value: currentPlaybookDetent)
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  private var currentPlaybookDetent: RecipePlaybookColumnDetent {
    get {
      persistedPlaybookDetents[detail.menu.id.uuidString]
        ?? (isServiceDateTodayOrPast ? .comfortable : .wide)
    }
    nonmutating set {
      var detents = persistedPlaybookDetents
      detents[detail.menu.id.uuidString] = newValue
      persistedPlaybookDetents = detents
    }
  }

  private var persistedPlaybookDetents: [String: RecipePlaybookColumnDetent] {
    get {
      MenuPlaybookColumnPreferences.detents(from: persistedPlaybookDetentsData)
    }
    nonmutating set {
      persistedPlaybookDetentsData = MenuPlaybookColumnPreferences.encodedDetents(newValue)
    }
  }

  private var menuBody: some View {
    VStack(alignment: .leading, spacing: 24) {
      MenuDetailHeader(detail: detail)
      MenuExternalProjectField(
        externalProjectName: detail.menu.externalProjectName,
        save: detailModel.updateExternalProjectName
      )
      MenuDishList(
        model: model,
        detailModel: detailModel,
        menu: detail.menu,
        detail: detail,
        isInitiallyExpanded: !isServiceDateTodayOrPast,
        onRecipeSelected: onRecipeSelected
      )
      MenuPlacementList(
        model: model,
        menu: detail.menu,
        minimumDayCount: max((detail.itemRows.map(\.item.dayOffset).max() ?? 0) + 1, 1),
        placements: detail.placements
      )
    }
  }

  private var menuPlaybook: some View {
    VStack(alignment: .leading, spacing: 24) {
      MenuPrepPlanSection(
        steps: detail.prepPlanSteps,
        itemRows: detail.itemRows,
        handoffSource: .menu(detailModel.menuID),
        complementHandoffSource: .menuComplement(detailModel.menuID),
        handoffTransport: handoffTransport,
        onRecipeSelected: onRecipeSelected,
        clearPrepPlan: {
          model.clearPrepPlanButtonTapped(menuID: detailModel.menuID)
        },
        regeneratePrepPlan: regeneratePrepPlan,
        createStep: detailModel.createPrepPlanStep,
        updateStep: detailModel.updatePrepPlanStep,
        deleteStep: detailModel.deletePrepPlanStep,
        reorderStep: detailModel.reorderPrepPlanStep,
        isInitiallyExpanded: true
      )
      LearningsSection(
        learnings: detail.learnings,
        updateLearning: detailModel.updateLearning,
        deleteLearning: detailModel.deleteLearning,
        reorderLearnings: detailModel.reorderLearnings
      )
    }
  }
}
