import SwiftUI
import YesChefCore

struct TodayPrepFullScreenCover: View {
  @Environment(\.dismiss) private var dismiss
  let presentation: TodayPrepPresentation
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let toastCenter: AppToastCenter

  var body: some View {
    NavigationStack {
      TodayPrepView(
        presentation: presentation,
        recipeModel: recipeModel,
        mealCalendarModel: mealCalendarModel,
        groceryModel: groceryModel,
        toastCenter: toastCenter
      )
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .overlay(alignment: .top) { AppToastOverlay(toastCenter: toastCenter).ignoresSafeArea(.keyboard) }
    .sensoryFeedback(.success, trigger: toastCenter.feedbackTrigger)
    .mealCalendarItemEditorDestination(mealCalendarModel: mealCalendarModel)
    .groceryDestinations(groceryModel: groceryModel, mealCalendarModel: mealCalendarModel)
    .recipeDetailDestinations(recipeModel: recipeModel)
    .handoffReviewDestinations()
  }
}

struct TodayPrepView: View {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var detailModel: MenuDetailModel
  @State private var selectedReaderID: String?
  @State private var selectedBandID: String?
  @State private var expandedSectionIDs: Set<String> = ["still-open", "today"]
  @State private var editor: PrepPlanStepEditorDraft?
  @State private var isUncheckConfirmationPresented = false
  @State private var feedbackTrigger = 0

  let presentation: TodayPrepPresentation
  let recipeModel: RecipeLibraryModel
  let mealCalendarModel: MealCalendarModel
  let groceryModel: GroceryLibraryModel
  let toastCenter: AppToastCenter

  init(
    presentation: TodayPrepPresentation,
    recipeModel: RecipeLibraryModel,
    mealCalendarModel: MealCalendarModel,
    groceryModel: GroceryLibraryModel,
    toastCenter: AppToastCenter
  ) {
    self.presentation = presentation
    self.recipeModel = recipeModel
    self.mealCalendarModel = mealCalendarModel
    self.groceryModel = groceryModel
    self.toastCenter = toastCenter
    _detailModel = State(wrappedValue: MenuDetailModel(menuID: presentation.menuID, toastCenter: toastCenter))
  }

  private var detail: MenuDetailData? { detailModel.detail }

  private var layout: TodayPrepLayout? {
    guard let detail else { return nil }
    return TodayPrepLayout.make(
      steps: detail.prepPlanSteps,
      dayCount: detail.menu.dayCount,
      placements: detail.placements,
      today: detailModel.now
    )
  }

  private var cookItems: [CookSessionItem] {
    detail?.itemRows.compactMap { row in
      guard row.item.kind == .recipe, let recipe = row.recipe, !recipe.archived else { return nil }
      return CookSessionItem(recipeID: recipe.id, scaleContext: .menuItem(row.item.id), title: row.displayTitle)
    } ?? []
  }

  private var selectedReader: CookSessionItem? {
    cookItems.first { $0.id == selectedReaderID } ?? cookItems.first
  }

  private var manualBand: MenuPrepPlanBand? {
    guard let layout else { return nil }
    let id = selectedBandID ?? layout.firstOpenBandID
    return layout.bands.first { $0.id == id } ?? layout.bands.first
  }

  private var visibleSections: [TodayPrepSection] {
    guard let layout else { return [] }
    if case .manual = layout.mode, let manualBand {
      return [TodayPrepSection(id: manualBand.id, title: manualBand.title, kind: .manual, steps: manualBand.steps)]
    }
    return layout.sections
  }

  var body: some View {
    Group {
      if let detail, let layout {
        content(detail: detail, layout: layout)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Uncheck All", systemImage: "arrow.counterclockwise") { isUncheckConfirmationPresented = true }
        } label: {
          Label("Prep Actions", systemImage: "ellipsis.circle")
        }
      }
    }
    .confirmationDialog("Uncheck all prep steps?", isPresented: $isUncheckConfirmationPresented) {
      Button("Uncheck All", role: .destructive) { detailModel.uncheckAllPrepPlanSteps() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This clears the completion checks for every step in this menu.")
    }
    .sheet(item: $editor) { draft in
      PrepPlanStepEditorSheet(
        draft: draft,
        itemRows: detail?.itemRows ?? [],
        dayCount: detail?.menu.dayCount ?? 1,
        placementStartDate: detail?.placements.count == 1 ? detail?.placements.first?.startDate : nil
      ) { saved in
        if let id = saved.stepID { detailModel.updatePrepPlanStep(saved.step, id: id) }
        else { detailModel.createPrepPlanStep(saved.step) }
      }
    }
    .alert("Prep Error", isPresented: $detailModel.isShowingError) {
      Button("OK") {}
    } message: {
      Text(detailModel.errorMessage ?? "")
    }
    .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
    .keepsScreenAwakeWhilePresented()
    .onAppear {
      if selectedReaderID == nil { selectedReaderID = cookItems.first?.id }
    }
  }

  @ViewBuilder
  private func content(detail: MenuDetailData, layout: TodayPrepLayout) -> some View {
    if horizontalSizeClass == .regular {
      HStack(spacing: 0) {
        checklist(detail: detail, layout: layout)
          .frame(minWidth: 360, idealWidth: 460, maxWidth: 540)
        Divider()
        readerPane
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    } else {
      checklist(detail: detail, layout: layout)
    }
  }

  private func checklist(detail: MenuDetailData, layout: TodayPrepLayout) -> some View {
    List {
      if case .manual = layout.mode, !layout.bands.isEmpty {
        Picker("Prep band", selection: Binding(
          get: { selectedBandID ?? layout.firstOpenBandID ?? layout.bands[0].id },
          set: { selectedBandID = $0 }
        )) {
          ForEach(layout.bands) { band in Text(band.title).tag(band.id) }
        }
      }
      if case let .dated(dayTitle, _) = layout.mode {
        Text(dayTitle).font(.subheadline).foregroundStyle(.secondary).listRowSeparator(.hidden)
      }
      ForEach(visibleSections) { section in
        if section.kind == .getAhead || section.kind == .tomorrow {
          DisclosureGroup(isExpanded: disclosureBinding(section.id)) {
            sectionRows(section, detail: detail, layout: layout)
          } label: {
            Text("\(section.title) · \(section.steps.filter { !layout.doneStepIDs.contains($0.step.id) }.count) left")
          }
        } else {
          Section(section.title) {
            sectionRows(section, detail: detail, layout: layout)
            if section.kind == .today || section.kind == .manual {
              addStepButton(section, layout: layout)
            }
          }
        }
      }
    }
    .listStyle(.plain)
  }

  @ViewBuilder
  private func sectionRows(_ section: TodayPrepSection, detail: MenuDetailData, layout: TodayPrepLayout) -> some View {
    ForEach(section.steps, id: \.step.id) { row in
      let isDone = layout.doneStepIDs.contains(row.step.id)
      VStack(alignment: .leading, spacing: 5) {
        if let session = row.sessionLabel { Text(session).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
        HStack(alignment: .top, spacing: 12) {
          Button {
            detailModel.setPrepPlanStepCompleted(row.step.id, at: isDone ? nil : detailModel.now)
            feedbackTrigger += 1
          } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
              .font(.title2)
              .contentTransition(.symbolEffect(.replace))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(isDone ? "Mark \(row.step.task) as not done" : "Mark \(row.step.task) done")
          stepBody(row.step, isDone: isDone, detail: detail)
        }
        let serves = row.step.serves
          ?? detail.itemRows.first(where: { $0.id == row.step.sourceDish })?.displayTitle
        if serves != nil || row.step.makeAheadWindow != nil {
          HStack(spacing: 8) {
            if let serves { Text(serves) }
            if let window = row.step.makeAheadWindow { Text(window) }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.leading, 42)
        }
      }
      .padding(.vertical, 4)
      .listRowSeparator(.hidden)
      .swipeActions(edge: .trailing) {
        if !isDone, canMoveTomorrow(row.step, layout: layout) {
          Button(moveActionTitle(layout), systemImage: "arrow.right") { moveTomorrow(row.step, layout: layout) }
            .tint(.indigo)
        }
      }
      .contextMenu {
        if !isDone, canMoveTomorrow(row.step, layout: layout) {
          Button(moveActionTitle(layout), systemImage: "arrow.right") { moveTomorrow(row.step, layout: layout) }
        }
        Button { editor = PrepPlanStepEditorDraft(step: row.step) } label: {
          Label("Edit Step…", symbol: .editRow)
        }
      }
      .accessibilityElement(children: .contain)
    }
    let count = section.steps.filter { layout.doneStepIDs.contains($0.step.id) }.count
    Text("\(count) of \(section.steps.count) done")
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .listRowSeparator(.hidden)
  }

  @ViewBuilder
  private func stepBody(
    _ step: PrepPlanStepRecord,
    isDone: Bool,
    detail: MenuDetailData
  ) -> some View {
    let recipe = detail.itemRows.first(where: { $0.id == step.sourceDish })?.recipe
    if horizontalSizeClass == .compact, let recipe, !recipe.archived,
       let item = detail.itemRows.first(where: { $0.id == step.sourceDish }) {
      NavigationLink {
        RecipeDetailView(
          recipeID: recipe.id,
          scaleContext: .menuItem(item.id),
          libraryModel: recipeModel,
          mealCalendarModel: mealCalendarModel,
          groceryModel: groceryModel
        )
      } label: {
        Text(step.task).foregroundStyle(isDone ? .secondary : .primary)
      }
      .simultaneousGesture(TapGesture().onEnded {
        selectReader(for: step)
      })
    } else {
      Button {
        if horizontalSizeClass == .regular { selectReader(for: step) }
      } label: {
        Text(step.task)
          .foregroundStyle(isDone ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private var readerPane: some View {
    Group {
      if selectedReader != nil {
        TabView(selection: $selectedReaderID) {
          ForEach(cookItems) { dish in
            RecipeDetailView(
              recipeID: dish.recipeID,
              scaleContext: dish.scaleContext,
              libraryModel: recipeModel,
              mealCalendarModel: mealCalendarModel,
              groceryModel: groceryModel
            )
            .tag(Optional(dish.id))
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
      } else {
        ContentUnavailableView {
          Label("No Recipe", symbol: .source)
        } description: {
          Text("This menu has no active recipe dishes.")
        }
      }
    }
  }

  private var navigationTitle: String {
    guard let layout else { return presentation.title }
    if case .dated = layout.mode { return "Today's Prep" }
    return "Prep"
  }

  private func disclosureBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { expandedSectionIDs.contains(id) },
      set: { if $0 { expandedSectionIDs.insert(id) } else { expandedSectionIDs.remove(id) } }
    )
  }

  private func addStepButton(_ section: TodayPrepSection, layout: TodayPrepLayout) -> some View {
    Button {
      var draft = PrepPlanStepEditorDraft()
      if case let .dated(_, dayOffset) = layout.mode { draft.workDayOffset = dayOffset }
      else { draft.workDayOffset = manualBand?.steps.first?.step.workDayOffset }
      editor = draft
    } label: {
      Label("Add Step", systemImage: "plus")
    }
    .listRowSeparator(.hidden)
    .accessibilityHint("Add a step to \(section.title)")
  }

  private func moveActionTitle(_ layout: TodayPrepLayout) -> String {
    if case .dated = layout.mode { return "Tomorrow" }
    return "Next Day"
  }

  private func canMoveTomorrow(_ step: PrepPlanStepRecord, layout: TodayPrepLayout) -> Bool {
    guard let detail, detail.menu.dayCount > 1, let stepOffset = step.workDayOffset,
          let targetOffset = targetTomorrowOffset(layout), targetOffset < detail.menu.dayCount else { return false }
    return stepOffset != targetOffset
  }

  private func targetTomorrowOffset(_ layout: TodayPrepLayout) -> Int? {
    switch layout.mode {
    case let .dated(_, dayOffset): dayOffset + 1
    case .manual: manualBand?.steps.first?.step.workDayOffset.map { $0 + 1 }
    }
  }

  private func moveTomorrow(_ step: PrepPlanStepRecord, layout: TodayPrepLayout) {
    guard let targetOffset = targetTomorrowOffset(layout) else { return }
    detailModel.updatePrepPlanStep(
      PrepPlanStep(
        session: step.session,
        task: step.task,
        serves: step.serves,
        makeAheadWindow: step.makeAheadWindow,
        timeOfDay: step.timeOfDay,
        sourceDish: step.sourceDish,
        workDayOffset: targetOffset
      ),
      id: step.id
    )
  }

  private func selectReader(for step: PrepPlanStepRecord) {
    guard let dish = step.sourceDish else { return }
    let readerID = ScaleContext.menuItem(dish).id
    guard cookItems.contains(where: { $0.id == readerID }) else { return }
    selectedReaderID = readerID
  }
}
