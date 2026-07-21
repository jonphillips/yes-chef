import CasePaths
import Dependencies
import Foundation
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
    case moveCandidatesToReference
    case candidatePhotoPicker
    case chat(RecipeChatModel)
    case logEntryEditor(WorkbenchLogEntryEditorState)
  }

  let workbenchID: Workbench.ID
  @ObservationIgnored private let openRecipe: (Recipe.ID) -> Void
  @ObservationIgnored private let toastCenter: AppToastCenter?

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
  var isConfirmingRemoveWorkingRecipe = false
  var isShowingCompare = false
  let compareAlignmentModel = WorkbenchCompareAlignmentModel()

  init(
    workbenchID: Workbench.ID,
    openRecipe: @escaping (Recipe.ID) -> Void = { _ in },
    toastCenter: AppToastCenter? = nil
  ) {
    self.workbenchID = workbenchID
    self.openRecipe = openRecipe
    self.toastCenter = toastCenter
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

  func moveAllCandidatesToReferenceButtonTapped() {
    guard detail?.candidateRows.isEmpty == false else { return }
    destination = .moveCandidatesToReference
  }

  func confirmMoveAllCandidatesToReferenceButtonTapped() {
    destination = nil
    do {
      try database.write { db in
        try WorkbenchRepository.moveAllCandidatesToReference(for: workbenchID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  /// Recipes with loaded ingredient data available to compare — the working recipe (if any) plus
  /// every candidate whose recipe still resolves. Compare needs at least two.
  var comparableColumnCount: Int {
    guard let detail else { return 0 }
    return (detail.draftRecipeDetail != nil ? 1 : 0)
      + detail.candidateRows.filter { $0.recipeDetail != nil }.count
  }

  var canCompare: Bool {
    comparableColumnCount >= 2
  }

  func compareButtonTapped() {
    guard canCompare else { return }
    isShowingCompare = true
  }

  func chatButtonTapped() {
    guard let detail else { return }
    destination = .chat(RecipeChatModel(context: .workbench(WorkbenchChatContext(detail: detail))))
  }

  func openWorkingRecipeButtonTapped() {
    guard let recipeID = detail?.workbench.draftRecipeID else { return }
    openRecipe(recipeID)
  }

  func openCandidateButtonTapped(recipeID: Recipe.ID) {
    openRecipe(recipeID)
  }

  func promoteWorkingRecipeButtonTapped() {
    do {
      let recipeID = try database.write { db in
        try WorkbenchRepository.promoteDraftRecipe(
          workbenchID: workbenchID,
          in: db,
          now: now
        )
      }
      openRecipe(recipeID)
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  /// Whether the current working recipe has been promoted to the main library. Drives the
  /// remove-confirmation wording: a promoted recipe is only unlinked (it stays in the library),
  /// an unpromoted `.reference` draft is deleted outright.
  var workingRecipeIsPromoted: Bool {
    detail?.draftRecipeDetail?.recipe.libraryPlacement == .main
  }

  func removeWorkingRecipeButtonTapped() {
    guard detail?.workbench.draftRecipeID != nil else { return }
    isConfirmingRemoveWorkingRecipe = true
  }

  var candidatePhotoChoices: [WorkbenchCandidatePhoto] {
    detail?.candidateRows.flatMap { row in
      (row.recipeDetail?.photos.filter(\.isDisplayable) ?? []).map {
        WorkbenchCandidatePhoto(photo: $0, candidateTitle: row.displayTitle)
      }
    } ?? []
  }

  func candidatePhotoPickerButtonTapped() {
    guard detail?.draftRecipeDetail != nil, !candidatePhotoChoices.isEmpty else { return }
    destination = .candidatePhotoPicker
  }

  func selectCandidatePhotoButtonTapped(photoID: RecipePhoto.ID) {
    do {
      try database.write { db in
        try WorkbenchRepository.copyCandidatePhotoToDraft(
          photoID: photoID,
          for: workbenchID,
          in: db,
          now: now,
          uuid: { uuid() }
        )
      }
      destination = nil
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func confirmRemoveWorkingRecipe() {
    isConfirmingRemoveWorkingRecipe = false
    do {
      try database.write { db in
        try WorkbenchRepository.removeDraftRecipe(workbenchID: workbenchID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  func applyActionCatalog(for chatModel: RecipeChatModel) -> [AnyChatApplyAction] {
    @Dependency(\.workbenchDraftRecipeClient) var workbenchDraftRecipeClient

    let logAction = ChatApplyAction<WorkbenchLogEntryDraft>(
      title: "Save to Workbench Log",
      extractingTitle: "Preparing log entry...",
      reviewTitle: "Review workbench log entry",
      commitTitle: "Save to Log",
      committingTitle: "Saving to log...",
      committedTitle: "Saved to Workbench Log",
      extract: { selection, _ in
        WorkbenchLogEntryDraft(kind: .note, body: selection)
      },
      commit: { [weak self] draft in
        try self?.commitLogEntry(draft)
      }
    )
    var actions = [
      AnyChatApplyAction(logAction) { draft in
        draft.renderedReview()
      }
    ]

    if detail?.workbench.draftRecipeID == nil, detail?.candidateRows.isEmpty == false {
      let context = chatModel.context.serialized(for: chatModel.activeTier)
      let draftAction = ChatApplyAction<WorkbenchDraftRecipe>(
        title: "Draft working recipe -> Working recipe",
        extractingTitle: "Drafting working recipe...",
        reviewTitle: "Review working recipe",
        commitTitle: "Create Working Recipe",
        committingTitle: "Creating working recipe...",
        committedTitle: "Created Working Recipe",
        extract: { selection, messages in
          try await workbenchDraftRecipeClient(
            selection: selection,
            messages: messages,
            context: context,
            tier: chatModel.activeTier
          )
        },
        commit: { [weak self] draftRecipe in
          try self?.commitDraftRecipe(draftRecipe)
        }
      )

      actions.append(
        AnyChatApplyAction(draftAction, requiresSubject: false) { [weak self] draftRecipe in
          guard !draftRecipe.isEmpty else { return [] }
          let originalEditableText = draftRecipe.editableProseReviewText()
          return [
            ChatApplyReviewItem(
              title: draftAction.reviewTitle,
              summary: draftRecipe.renderedReview(),
              editableTitle: "Draft prose fields",
              editableText: originalEditableText,
              commitTitle: draftAction.commitTitle,
              committingTitle: draftAction.committingTitle,
              committedTitle: draftAction.committedTitle,
              commit: { editedText in
                let approved = editedText == originalEditableText
                  ? draftRecipe
                  : draftRecipe.applyingEditableProseReviewText(editedText)
                try self?.commitDraftRecipe(approved)
              }
            )
          ]
        }
      )
    }

    return actions
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
      toastCenter?.postSuccess("Annotation saved.")
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

  func addLogEntryButtonTapped() {
    destination = .logEntryEditor(WorkbenchLogEntryEditorState())
  }

  func editLogEntryButtonTapped(_ entry: WorkbenchLogEntry) {
    destination = .logEntryEditor(WorkbenchLogEntryEditorState(entry: entry))
  }

  func saveLogEntryButtonTapped(_ editorState: WorkbenchLogEntryEditorState) -> Bool {
    let draft = WorkbenchLogEntryDraft(
      kind: editorState.kind,
      body: editorState.body,
      hypothesis: editorState.hypothesis,
      change: editorState.change,
      rationale: editorState.rationale,
      outcome: editorState.outcome,
      relatedRecipeID: editorState.relatedRecipeID
    )
    do {
      try database.write { db in
        if let entryID = editorState.entryID {
          try WorkbenchRepository.updateLogEntry(
            entryID: entryID,
            draft: draft,
            in: db,
            now: now
          )
        } else {
          try WorkbenchRepository.addLogEntry(
            draft,
            to: workbenchID,
            in: db,
            now: now,
            uuid: { uuid() }
          )
        }
      }
      destination = nil
      toastCenter?.postSuccess(
        editorState.entryID == nil ? "Log entry added." : "Log entry saved."
      )
      return true
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
      return false
    }
  }

  func deleteLogEntryButtonTapped(entryID: WorkbenchLogEntry.ID) {
    do {
      try database.write { db in
        try WorkbenchRepository.deleteLogEntry(entryID: entryID, in: db, now: now)
      }
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }

  private func commitDraftRecipe(_ draftRecipe: WorkbenchDraftRecipe) throws {
    guard !draftRecipe.isEmpty else {
      throw WorkbenchDetailError.emptyDraftRecipe
    }
    let recipeID = try database.write { db in
      try WorkbenchRepository.createDraftRecipe(
        draftRecipe,
        for: workbenchID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
    openRecipe(recipeID)
  }

  private func commitLogEntry(_ draft: WorkbenchLogEntryDraft) throws {
    try database.write { db in
      try WorkbenchRepository.addLogEntry(
        draft,
        to: workbenchID,
        in: db,
        now: now,
        uuid: { uuid() }
      )
    }
  }
}

private enum WorkbenchDetailError: Error, CustomStringConvertible, LocalizedError {
  case emptyDraftRecipe

  var description: String {
    switch self {
    case .emptyDraftRecipe:
      "The assistant did not find a working recipe to save."
    }
  }

  var errorDescription: String? { description }
}

struct WorkbenchCandidatePhoto: Identifiable, Equatable {
  let photo: RecipeDetailPhoto
  let candidateTitle: String

  var id: RecipePhoto.ID { photo.id }
}

struct WorkbenchDeletionContext: Identifiable, Hashable, Sendable {
  var workbenchID: Workbench.ID
  var title: String
  var candidateCount: Int

  var id: Workbench.ID { workbenchID }
}

struct WorkbenchLogEntryEditorState: Identifiable, Hashable, Sendable {
  var entryID: WorkbenchLogEntry.ID?
  var kind: WorkbenchLogEntryKind = .note
  var body = ""
  var hypothesis = ""
  var change = ""
  var rationale = ""
  var outcome = ""
  var relatedRecipeID: Recipe.ID?

  var id: String {
    entryID?.uuidString ?? "new"
  }

  init() {}

  init(entry: WorkbenchLogEntry) {
    entryID = entry.id
    kind = entry.kind
    body = entry.body
    hypothesis = entry.hypothesis ?? ""
    change = entry.change ?? ""
    rationale = entry.rationale ?? ""
    outcome = entry.outcome ?? ""
    relatedRecipeID = entry.relatedRecipeID
  }
}

private extension WorkbenchLogEntryDraft {
  func renderedReview() -> String? {
    let body = self.body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return nil }
    var lines = ["\(kind.title): \(body)"]
    if let outcome = outcome?.trimmingCharacters(in: .whitespacesAndNewlines), !outcome.isEmpty {
      lines.append("Outcome: \(outcome)")
    }
    return lines.joined(separator: "\n\n")
  }
}
