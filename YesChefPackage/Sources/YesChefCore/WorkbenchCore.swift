import Foundation
import SQLiteData

@Table("workbenches")
public struct Workbench: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var notes: String?
  public var draftRecipeID: Recipe.ID?
  public var sortOrder: Int
  public var dateCreated: Date
  public var dateModified: Date

  public init(
    id: UUID,
    title: String,
    notes: String? = nil,
    draftRecipeID: Recipe.ID? = nil,
    sortOrder: Int,
    dateCreated: Date,
    dateModified: Date
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.draftRecipeID = draftRecipeID
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
    self.dateModified = dateModified
  }
}

@Table("workbenchCandidates")
public struct WorkbenchCandidate: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var workbenchID: Workbench.ID
  public var recipeID: Recipe.ID?
  public var recipeTitleSnapshot: String
  public var annotation: String?
  public var sortOrder: Int
  public var dateCreated: Date

  public init(
    id: UUID,
    workbenchID: Workbench.ID,
    recipeID: Recipe.ID? = nil,
    recipeTitleSnapshot: String,
    annotation: String? = nil,
    sortOrder: Int,
    dateCreated: Date
  ) {
    self.id = id
    self.workbenchID = workbenchID
    self.recipeID = recipeID
    self.recipeTitleSnapshot = recipeTitleSnapshot
    self.annotation = annotation
    self.sortOrder = sortOrder
    self.dateCreated = dateCreated
  }
}

public struct WorkbenchRowData: Identifiable, Equatable, Sendable {
  public var workbench: Workbench
  public var candidateCount: Int

  public init(workbench: Workbench, candidateCount: Int = 0) {
    self.workbench = workbench
    self.candidateCount = candidateCount
  }

  public var id: Workbench.ID { workbench.id }
}

public struct WorkbenchDetailData: Equatable, Sendable {
  public var workbench: Workbench
  public var candidateRows: [WorkbenchCandidateRowData]
  public var draftRecipeDetail: RecipeDetailData?

  public init(
    workbench: Workbench,
    candidateRows: [WorkbenchCandidateRowData] = [],
    draftRecipeDetail: RecipeDetailData? = nil
  ) {
    self.workbench = workbench
    self.candidateRows = candidateRows
    self.draftRecipeDetail = draftRecipeDetail
  }
}

public struct WorkbenchCandidateRowData: Identifiable, Equatable, Sendable {
  public var candidate: WorkbenchCandidate
  public var recipeDetail: RecipeDetailData?

  public init(
    candidate: WorkbenchCandidate,
    recipeDetail: RecipeDetailData? = nil
  ) {
    self.candidate = candidate
    self.recipeDetail = recipeDetail
  }

  public var id: WorkbenchCandidate.ID { candidate.id }

  public var displayTitle: String {
    recipeDetail?.recipe.title ?? candidate.recipeTitleSnapshot
  }
}

public struct WorkbenchListRequest: FetchKeyRequest {
  public init() {}

  public func fetch(_ db: Database) throws -> [WorkbenchRowData] {
    let candidatesByWorkbenchID = Dictionary(grouping: try WorkbenchCandidate.fetchAll(db), by: \.workbenchID)
    return try Workbench.fetchAll(db)
      .map { workbench in
        WorkbenchRowData(
          workbench: workbench,
          candidateCount: deduplicatedCandidates(candidatesByWorkbenchID[workbench.id] ?? []).count
        )
      }
      .sorted(by: areWorkbenchRowsInIncreasingOrder)
  }
}

public struct WorkbenchDetailRequest: FetchKeyRequest {
  public var workbenchID: Workbench.ID

  public init(workbenchID: Workbench.ID) {
    self.workbenchID = workbenchID
  }

  public func fetch(_ db: Database) throws -> WorkbenchDetailData? {
    guard let workbench = try Workbench.find(workbenchID).fetchOne(db) else { return nil }
    let candidates = deduplicatedCandidates(
      try WorkbenchCandidate
        .where { $0.workbenchID.eq(workbenchID) }
        .fetchAll(db)
    )

    let candidateRows = try candidates.map { candidate in
      WorkbenchCandidateRowData(
        candidate: candidate,
        recipeDetail: try candidate.recipeID.flatMap { try RecipeRepository.fetchDetail(recipeID: $0, in: db) }
      )
    }

    return WorkbenchDetailData(workbench: workbench, candidateRows: candidateRows)
      .withDraftRecipeDetail(try workbench.draftRecipeID.flatMap { try RecipeRepository.fetchDetail(recipeID: $0, in: db) })
  }
}

public enum WorkbenchRepository {
  @discardableResult
  public static func addWorkbench(
    title: String,
    notes: String? = nil,
    candidateRecipeIDs: [Recipe.ID] = [],
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Workbench.ID {
    guard let title = title.nonEmptyWorkbenchText else {
      throw WorkbenchRepositoryError.emptyTitle
    }
    let workbenchID = uuid()
    let workbench = Workbench(
      id: workbenchID,
      title: title,
      notes: notes?.nonEmptyWorkbenchText,
      sortOrder: try nextWorkbenchSortOrder(in: db),
      dateCreated: now,
      dateModified: now
    )
    try Workbench.insert { workbench }.execute(db)
    try addCandidates(
      candidateRecipeIDs,
      to: workbenchID,
      in: db,
      now: now,
      uuid: uuid
    )
    return workbenchID
  }

  public static func addCandidates(
    _ recipeIDs: [Recipe.ID],
    to workbenchID: Workbench.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws {
    guard !recipeIDs.isEmpty else { return }
    var workbench = try requireWorkbench(workbenchID, in: db)
    var existingRecipeIDs = Set(
      try WorkbenchCandidate
        .where { $0.workbenchID.eq(workbenchID) }
        .fetchAll(db)
        .compactMap(\.recipeID)
    )
    var nextSortOrder = try nextCandidateSortOrder(workbenchID: workbenchID, in: db)
    var inserted = false
    for recipeID in recipeIDs where !existingRecipeIDs.contains(recipeID) {
      guard let recipe = try Recipe.find(recipeID).fetchOne(db), !recipe.archived else {
        throw WorkbenchRepositoryError.recipeNotFound(recipeID)
      }
      let candidate = WorkbenchCandidate(
        id: uuid(),
        workbenchID: workbenchID,
        recipeID: recipeID,
        recipeTitleSnapshot: recipe.title,
        sortOrder: nextSortOrder,
        dateCreated: now
      )
      try WorkbenchCandidate.insert { candidate }.execute(db)
      existingRecipeIDs.insert(recipeID)
      nextSortOrder += 1
      inserted = true
    }
    if inserted {
      workbench.dateModified = now
      try Workbench.upsert { workbench }.execute(db)
    }
  }

  public static func updateCandidateAnnotation(
    candidateID: WorkbenchCandidate.ID,
    annotation: String?,
    in db: Database,
    now: Date
  ) throws {
    var candidate = try requireCandidate(candidateID, in: db)
    candidate.annotation = annotation?.nonEmptyWorkbenchText
    try WorkbenchCandidate.upsert { candidate }.execute(db)

    var workbench = try requireWorkbench(candidate.workbenchID, in: db)
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func deleteCandidate(
    candidateID: WorkbenchCandidate.ID,
    in db: Database,
    now: Date
  ) throws {
    let candidate = try requireCandidate(candidateID, in: db)
    try WorkbenchCandidate.find(candidateID).delete().execute(db)
    var workbench = try requireWorkbench(candidate.workbenchID, in: db)
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func updateWorkbenchNotes(
    workbenchID: Workbench.ID,
    notes: String?,
    in db: Database,
    now: Date
  ) throws {
    var workbench = try requireWorkbench(workbenchID, in: db)
    workbench.notes = notes?.nonEmptyWorkbenchText
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func updateWorkbenchTitle(
    workbenchID: Workbench.ID,
    title: String,
    in db: Database,
    now: Date
  ) throws {
    guard let title = title.nonEmptyWorkbenchText else {
      throw WorkbenchRepositoryError.emptyTitle
    }
    var workbench = try requireWorkbench(workbenchID, in: db)
    workbench.title = title
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
  }

  public static func deleteWorkbench(
    workbenchID: Workbench.ID,
    in db: Database
  ) throws {
    _ = try requireWorkbench(workbenchID, in: db)
    try Workbench.find(workbenchID).delete().execute(db)
  }

  @discardableResult
  public static func createDraftRecipe(
    _ draftRecipe: WorkbenchDraftRecipe,
    for workbenchID: Workbench.ID,
    in db: Database,
    now: Date,
    uuid: () -> UUID
  ) throws -> Recipe.ID {
    var workbench = try requireWorkbench(workbenchID, in: db)
    if let draftRecipeID = workbench.draftRecipeID {
      throw WorkbenchRepositoryError.draftRecipeAlreadyExists(draftRecipeID)
    }

    let recipeID = try RecipeRepository.save(
      draft: draftRecipe.editorDraft(libraryPlacement: .reference),
      in: db,
      now: now,
      uuid: uuid
    )
    workbench.draftRecipeID = recipeID
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
    return recipeID
  }

  @discardableResult
  public static func promoteDraftRecipe(
    workbenchID: Workbench.ID,
    in db: Database,
    now: Date
  ) throws -> Recipe.ID {
    var workbench = try requireWorkbench(workbenchID, in: db)
    guard let recipeID = workbench.draftRecipeID else {
      throw WorkbenchRepositoryError.missingDraftRecipe(workbenchID)
    }
    guard try Recipe.find(recipeID).fetchOne(db) != nil else {
      throw WorkbenchRepositoryError.draftRecipeNotFound(recipeID)
    }
    try RecipeRepository.setLibraryPlacement(.main, recipeID: recipeID, in: db, now: now)
    workbench.dateModified = now
    try Workbench.upsert { workbench }.execute(db)
    return recipeID
  }

  private static func requireWorkbench(_ workbenchID: Workbench.ID, in db: Database) throws -> Workbench {
    guard let workbench = try Workbench.find(workbenchID).fetchOne(db) else {
      throw WorkbenchRepositoryError.workbenchNotFound(workbenchID)
    }
    return workbench
  }

  private static func requireCandidate(
    _ candidateID: WorkbenchCandidate.ID,
    in db: Database
  ) throws -> WorkbenchCandidate {
    guard let candidate = try WorkbenchCandidate.find(candidateID).fetchOne(db) else {
      throw WorkbenchRepositoryError.candidateNotFound(candidateID)
    }
    return candidate
  }

  private static func nextWorkbenchSortOrder(in db: Database) throws -> Int {
    (try Workbench.fetchAll(db).map(\.sortOrder).max() ?? -1) + 1
  }

  private static func nextCandidateSortOrder(workbenchID: Workbench.ID, in db: Database) throws -> Int {
    (try WorkbenchCandidate
      .where { $0.workbenchID.eq(workbenchID) }
      .fetchAll(db)
      .map(\.sortOrder)
      .max() ?? -1) + 1
  }
}

public enum WorkbenchRepositoryError: Error, Equatable, Sendable {
  case emptyTitle
  case workbenchNotFound(Workbench.ID)
  case candidateNotFound(WorkbenchCandidate.ID)
  case recipeNotFound(Recipe.ID)
  case draftRecipeAlreadyExists(Recipe.ID)
  case missingDraftRecipe(Workbench.ID)
  case draftRecipeNotFound(Recipe.ID)
}

private extension WorkbenchDetailData {
  func withDraftRecipeDetail(_ draftRecipeDetail: RecipeDetailData?) -> WorkbenchDetailData {
    WorkbenchDetailData(
      workbench: workbench,
      candidateRows: candidateRows,
      draftRecipeDetail: draftRecipeDetail
    )
  }
}

private func areWorkbenchRowsInIncreasingOrder(_ lhs: WorkbenchRowData, _ rhs: WorkbenchRowData) -> Bool {
  if lhs.workbench.sortOrder != rhs.workbench.sortOrder {
    return lhs.workbench.sortOrder < rhs.workbench.sortOrder
  }
  if lhs.workbench.dateCreated != rhs.workbench.dateCreated {
    return lhs.workbench.dateCreated < rhs.workbench.dateCreated
  }
  return lhs.workbench.title.localizedStandardCompare(rhs.workbench.title) == .orderedAscending
}

private func areWorkbenchCandidatesInIncreasingOrder(
  _ lhs: WorkbenchCandidate,
  _ rhs: WorkbenchCandidate
) -> Bool {
  if lhs.sortOrder != rhs.sortOrder {
    return lhs.sortOrder < rhs.sortOrder
  }
  if lhs.dateCreated != rhs.dateCreated {
    return lhs.dateCreated < rhs.dateCreated
  }
  return lhs.id.uuidString < rhs.id.uuidString
}

private func deduplicatedCandidates(_ candidates: [WorkbenchCandidate]) -> [WorkbenchCandidate] {
  let sortedCandidates = candidates.sorted(by: areWorkbenchCandidatesInIncreasingOrder)
  var seenRecipeIDs: Set<Recipe.ID> = []
  var result: [WorkbenchCandidate] = []
  for candidate in sortedCandidates {
    if let recipeID = candidate.recipeID {
      guard !seenRecipeIDs.contains(recipeID) else { continue }
      seenRecipeIDs.insert(recipeID)
    }
    result.append(candidate)
  }
  return result
}

private extension String {
  var nonEmptyWorkbenchText: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
