import CasePaths
import Dependencies
import Observation
import SQLiteData
import YesChefCore

@Observable
@MainActor
final class WorkbenchLibraryModel {
  @CasePathable
  enum Destination {
    case addWorkbench
    case deleteWorkbench(WorkbenchDeletionContext)
  }

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch(WorkbenchListRequest(), animation: .default) var workbenchRows: [WorkbenchRowData] = []

  var destination: Destination?
  var navigationPath: [Workbench.ID] = []
  var selectedWorkbenchID: Workbench.ID?
  var errorMessage: String?
  var isShowingError = false

  func reloadAfterExternalChange() async {
    try? await $workbenchRows.load()
  }

  func addWorkbenchButtonTapped() {
    destination = .addWorkbench
  }

  func selectWorkbench(_ workbenchID: Workbench.ID) {
    selectedWorkbenchID = workbenchID
    navigationPath = [workbenchID]
  }

  func saveWorkbenchButtonTapped(title: String, notes: String) -> Bool {
    do {
      let workbenchID = try database.write { db in
        try WorkbenchRepository.addWorkbench(
          title: title,
          notes: notes,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      selectWorkbench(workbenchID)
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func deleteWorkbenchButtonTapped(_ row: WorkbenchRowData) {
    destination = .deleteWorkbench(
      WorkbenchDeletionContext(
        workbenchID: row.id,
        title: row.workbench.title,
        candidateCount: row.candidateCount
      )
    )
  }

  func confirmDeleteWorkbenchButtonTapped(_ context: WorkbenchDeletionContext) {
    destination = nil
    do {
      try database.write { db in
        try WorkbenchRepository.deleteWorkbench(workbenchID: context.workbenchID, in: db)
      }
      if selectedWorkbenchID == context.workbenchID {
        selectedWorkbenchID = nil
      }
      navigationPath.removeAll { $0 == context.workbenchID }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

@Observable
@MainActor
final class WorkbenchDetailModel {
  @CasePathable
  enum Destination {
    case addCandidates
    case chat(RecipeChatModel)
  }

  let workbenchID: Workbench.ID

  @ObservationIgnored
  @Dependency(\.date.now) private var now
  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored
  @Dependency(\.uuid) private var uuid
  @ObservationIgnored
  @Fetch var detail: WorkbenchDetailData?
  @ObservationIgnored
  @Fetch(RecipeListRequest(), animation: .default) var recipeRows: [RecipeListRowData] = []

  var destination: Destination?
  var errorMessage: String?
  var isShowingError = false

  init(workbenchID: Workbench.ID) {
    self.workbenchID = workbenchID
    _detail = Fetch(wrappedValue: nil, WorkbenchDetailRequest(workbenchID: workbenchID), animation: .default)
  }

  var availableRecipeRows: [RecipeListRowData] {
    recipeRows
      .filter { !$0.recipe.archived }
      .sorted {
        $0.recipe.title.localizedStandardCompare($1.recipe.title) == .orderedAscending
      }
  }

  var existingCandidateRecipeIDs: Set<Recipe.ID> {
    Set(detail?.candidateRows.compactMap(\.candidate.recipeID) ?? [])
  }

  func addCandidatesButtonTapped() {
    destination = .addCandidates
  }

  func chatButtonTapped() {
    guard let detail else { return }
    destination = .chat(RecipeChatModel(context: .workbench(WorkbenchChatContext(detail: detail))))
  }

  func saveNotesButtonTapped(_ notes: String) {
    do {
      try database.write { db in
        try WorkbenchRepository.updateWorkbenchNotes(
          workbenchID: workbenchID,
          notes: notes,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func saveTitleButtonTapped(_ title: String) {
    do {
      try database.write { db in
        try WorkbenchRepository.updateWorkbenchTitle(
          workbenchID: workbenchID,
          title: title,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func addCandidatesButtonTapped(recipeIDs: Set<Recipe.ID>) -> Bool {
    do {
      try database.write { db in
        try WorkbenchRepository.addCandidates(
          Array(recipeIDs),
          to: workbenchID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func updateAnnotation(candidateID: WorkbenchCandidate.ID, annotation: String) {
    do {
      try database.write { db in
        try WorkbenchRepository.updateCandidateAnnotation(
          candidateID: candidateID,
          annotation: annotation,
          in: db,
          now: now
        )
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func deleteCandidateButtonTapped(candidateID: WorkbenchCandidate.ID) {
    do {
      try database.write { db in
        try WorkbenchRepository.deleteCandidate(candidateID: candidateID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}

struct WorkbenchDeletionContext: Identifiable, Hashable, Sendable {
  var workbenchID: Workbench.ID
  var title: String
  var candidateCount: Int

  var id: Workbench.ID { workbenchID }
}
