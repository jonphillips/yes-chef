import SwiftUI
import YesChefCore

struct MenuDetailReader: View {
  let model: MenuLibraryModel
  let detailModel: MenuDetailModel
  let detail: MenuDetailData
  let handoffTransport: HandoffInAppTransport
  var onRecipeSelected: ((RecipeDetailPresentation) -> Void)?
  var isAskActive: Bool
  var askPrepPlan: () -> Void
  var askComplement: () -> Void
  var regeneratePrepPlan: () -> Void

  @AppStorage(MenuPlaybookColumnPreferences.visibilityStorageKey)
  private var isPlaybookColumnVisible = true
  @AppStorage(MenuPlaybookColumnPreferences.detentsStorageKey)
  private var persistedPlaybookDetentsData = Data()
  @GestureState private var playbookDragTranslation: CGFloat = 0

  init(
    model: MenuLibraryModel,
    detailModel: MenuDetailModel,
    detail: MenuDetailData,
    handoffTransport: HandoffInAppTransport,
    onRecipeSelected: ((RecipeDetailPresentation) -> Void)? = nil,
    isAskActive: Bool,
    askPrepPlan: @escaping () -> Void,
    askComplement: @escaping () -> Void,
    regeneratePrepPlan: @escaping () -> Void
  ) {
    self.model = model
    self.detailModel = detailModel
    self.detail = detail
    self.handoffTransport = handoffTransport
    self.onRecipeSelected = onRecipeSelected
    self.isAskActive = isAskActive
    self.askPrepPlan = askPrepPlan
    self.askComplement = askComplement
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
      .swipeActionsContainer()
      .toolbar {
        if proxy.size.width >= MenuPlaybookColumnMetrics.twoColumnThreshold {
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
      isPlaybookVisible: isPlaybookColumnVisible
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

      if isPlaybookColumnVisible {
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
        handoffTransport: handoffTransport,
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
      menuPlaybookHeader
      MenuPrepPlanSection(
        steps: detail.prepPlanSteps,
        itemRows: detail.itemRows,
        handoffSource: .menu(detailModel.menuID),
        handoffTransport: handoffTransport,
        onRecipeSelected: onRecipeSelected,
        clearPrepPlan: {
          model.clearPrepPlanButtonTapped(menuID: detailModel.menuID)
        },
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

  private var menuPlaybookHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Spacer()
      Menu {
        Button("Prep Plan", action: askPrepPlan)
        Button("Complement", action: askComplement)
        Divider()
        Button("Regenerate whole plan", action: regeneratePrepPlan)
          .disabled(detail.prepPlanSteps.isEmpty)
      } label: {
        Label("Ask", systemImage: "sparkles")
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.roundedRectangle(radius: 8))
      .tint(isAskActive ? .accentColor : nil)
      .overlay {
        if isAskActive {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.tint, lineWidth: 3)
        }
      }
      .accessibilityValue(isAskActive ? "Panel open" : "Panel closed")
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Playbook actions")
  }
}
