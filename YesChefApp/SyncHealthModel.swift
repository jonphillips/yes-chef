import CloudKit
import CloudSyncKit
import Dependencies
import Foundation
import GRDB
import Observation
import SQLiteData
import UIKit
import YesChefCore

/// The thin observable shell that feeds the pure `SyncHealth` reducer live signals
/// (jon-platform ADR-0003, closing the silent-degradation gap Yes Chef still carried).
/// It reads the gate, the iCloud account status, the `SyncEngine`'s observable running
/// state, and the pending-change count, folds them into a `SyncHealth`, and exposes the
/// folded `displayStatus` for the Settings row. All the decision logic lives in the
/// tested value type; this only gathers and orchestrates.
@MainActor
@Observable
final class SyncHealthModel {
  private(set) var health: SyncHealth
  /// True while a start attempt (Try again / Enable) is in flight — drives the
  /// button's progress affordance.
  private(set) var isStarting = false
  private var isRefreshing = false
  private var refreshRequestedWhileRefreshing = false

  /// Local row counts per synced table — the dogfood diagnostic that answers
  /// "did this table's rows actually reach this device?" at a glance. Populated on
  /// demand from the Sync detail sheet; compare the two devices side by side.
  private(set) var recordCounts: [RecordCount] = []

  /// Rows that CloudSyncKit can name as not uploaded, grouped into user-readable
  /// retry actions for the Sync detail sheet.
  private(set) var notUploadedRows: [NotUploadedDisplayRow] = []
  private(set) var isRetryingRows: Set<String> = []
  private(set) var retryError: String?
  private var syncFailureVerdictCache = SyncFailureVerdictCache()

  private(set) var isCheckingLeftovers = false
  private(set) var isDeletingLeftovers = false
  private(set) var leftoverReport: CloudSyncLeftoverReport?
  private(set) var leftoverDisplayGroups: [LeftoverDisplayGroup] = []
  private(set) var leftoverCheckError: String?
  private(set) var leftoverDeleteSummary: String?

  var leftoverCount: Int { leftoverReport?.leftovers.count ?? 0 }

  #if DEBUG
  private(set) var isDiagnosingSyncFailure = false
  private(set) var syncFailureDiagnosisReadout: String?
  private(set) var syncFailureDiagnosisError: String?
  #endif

  /// The last error from a *start attempt* (launch is discarded; Try again / Enable
  /// capture theirs). Held separately so a routine `refresh()` — which only reads
  /// live account/pending signals — never clobbers it, and so it survives until the
  /// next start attempt supersedes it.
  private var lastStartError: String?

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var syncEngine

  init() {
    health = SyncHealth(
      isManuallyEnabled: YesChefCloudSync.isManuallyEnabled(),
      account: .couldNotDetermine,
      isEngineRunning: false,
      pendingChangeCount: 0
    )
  }

  var displayStatus: SyncDisplayStatus { health.displayStatus }

  /// Live-observed sync activity. Reading the `SyncEngine`'s observable getter from
  /// the view lets a `.onChange` drive a `refresh()` the moment a sync cycle finishes,
  /// so the row flips from "Syncing…" to "Up to date" as the pending count drains.
  var isSynchronizing: Bool { syncEngine.isSynchronizing }

  /// Gather the live signals and fold them into `health`. Overlapping calls coalesce
  /// into one follow-up refresh so status events don't decode the library concurrently.
  func refresh() async {
    if isRefreshing {
      refreshRequestedWhileRefreshing = true
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    repeat {
      refreshRequestedWhileRefreshing = false
      await refreshOnce()
    } while refreshRequestedWhileRefreshing
  }

  private func refreshOnce() async {
    let isManuallyEnabled = YesChefCloudSync.isManuallyEnabled()
    let isEngineRunning = syncEngine.isRunning
    // The download counterpart to the pending (upload) count: true while the engine is
    // pulling changes down. Without it a fresh device pulling a large library reads
    // "Up to date" the instant the first batch lands (ADR-0028). Only meaningful while
    // running.
    let isFetchingChanges = isEngineRunning && syncEngine.isFetchingChanges
    let account = await currentAccountStatus()
    // The pending-changes table only exists once sync has run; querying it while the
    // gate is off can throw "no such table", so skip it — the status is `.disabled`
    // regardless.
    let pending = isManuallyEnabled ? await currentPendingCount() : 0

    let failureReport: SyncFailureReport?
    if isManuallyEnabled, isEngineRunning {
      failureReport = await currentSyncFailureReport(isEngineRunning: true)
    } else {
      failureReport = nil
      syncFailureReportError = nil
    }
    if let failureReport {
      notUploadedRows = (try? await database.read { db in
        try Self.makeNotUploadedRows(from: failureReport, in: db)
      }) ?? Self.fallbackNotUploadedRows(from: failureReport)
    } else {
      notUploadedRows = []
    }

    health = SyncHealth(
      isManuallyEnabled: isManuallyEnabled,
      account: account,
      isEngineRunning: isEngineRunning,
      pendingChangeCount: pending,
      isFetchingChanges: isFetchingChanges,
      notUploadedCount: failureReport?.notUploadedCount ?? 0,
      notAppliedCount: failureReport?.notAppliedCount ?? 0,
      lastError: lastStartError ?? syncFailureReportError
    )
  }

  private var syncFailureReportError: String?

  /// Retry only the selected row or group. CloudSyncKit re-queues it through
  /// SQLiteData's metadata triggers; the engine handles the next send normally.
  func retry(_ row: NotUploadedDisplayRow) async {
    guard !row.primaryKeys.isEmpty else { return }
    guard isRetryingRows.insert(row.id).inserted else { return }
    retryError = nil
    defer { isRetryingRows.remove(row.id) }

    do {
      let result = try await YesChefCloudSync.requeue(
        recordType: row.recordType,
        primaryKeys: row.primaryKeys,
        in: database,
        verdictCache: syncFailureVerdictCache
      )
      syncFailureVerdictCache = result.verdictCache
      await refresh()
    } catch {
      retryError = "Couldn’t retry \(row.title): \(error.localizedDescription)"
    }
  }

  func isRetrying(_ row: NotUploadedDisplayRow) -> Bool {
    isRetryingRows.contains(row.id)
  }

  /// Fetch remote changes first, then compare the private zones with this device's
  /// rows. This is intentionally an on-demand network operation; zone scans are large.
  func checkForLeftovers() async {
    guard !isCheckingLeftovers, !isDeletingLeftovers else { return }
    isCheckingLeftovers = true
    leftoverCheckError = nil
    leftoverDeleteSummary = nil
    leftoverReport = nil
    leftoverDisplayGroups = []
    defer { isCheckingLeftovers = false }

    let fetchStartedAt = Date.now
    do {
      try await syncEngine.fetchChanges()
      let engineRunning = syncEngine.isRunning
      let pending = await currentPendingCount()
      let client = CloudKitLeftoverClient(
        database: CKContainer(identifier: YesChefCloudSync.containerIdentifier).privateCloudDatabase
      )
      switch try await YesChefCloudSync.leftoverCheck(
        in: database,
        client: client,
        isEngineRunning: engineRunning,
        pendingChangeCount: pending,
        isSendingChanges: engineRunning && syncEngine.isSendingChanges,
        fetchStartedAt: fetchStartedAt
      ) {
      case .notIdle:
        leftoverCheckError = "Sync has pending changes. Wait for it to finish, then check again."
      case let .completed(report):
        let groups = try await database.read { db in
          try Self.makeLeftoverDisplayGroups(from: report, in: db)
        }
        leftoverReport = report
        leftoverDisplayGroups = groups
      }
    } catch {
      leftoverCheckError = "Couldn’t check iCloud for leftovers: \(error.localizedDescription)"
    }
  }

  /// Delete only the record IDs present in the report the user reviewed and confirmed.
  func deleteConfirmedLeftovers() async {
    guard !isDeletingLeftovers, let report = leftoverReport else { return }
    isDeletingLeftovers = true
    leftoverCheckError = nil
    defer { isDeletingLeftovers = false }

    let recordIDs = report.leftovers.map { $0.record.recordID }
    let client = CloudKitLeftoverClient(
      database: CKContainer(identifier: YesChefCloudSync.containerIdentifier).privateCloudDatabase
    )
    do {
      let result = try await YesChefCloudSync.deleteLeftovers(recordIDs, using: client)
      let failedIDs = Set(result.failures.keys)
      var remainingReport = report
      remainingReport.leftovers = report.leftovers.filter { failedIDs.contains($0.record.recordID) }
      remainingReport.countsByTable = Dictionary(
        remainingReport.leftovers.map { ($0.tableName, 1) },
        uniquingKeysWith: +
      )
      let reportAfterDelete = remainingReport
      leftoverReport = reportAfterDelete
      let displayGroups = try await database.read { db in
        try Self.makeLeftoverDisplayGroups(from: reportAfterDelete, in: db)
      }
      leftoverDisplayGroups = displayGroups

      var lines = ["Deleted \(result.deletedCount) of \(recordIDs.count) records from iCloud."]
      if !result.failures.isEmpty {
        lines.append("\(result.failures.count) failed:")
        lines += result.failures.keys.sorted { $0.recordName < $1.recordName }.map { recordID in
          "\(recordID.recordName): \(result.failures[recordID] ?? "Unknown error")"
        }
      }
      leftoverDeleteSummary = lines.joined(separator: "\n")
    } catch {
      leftoverCheckError = "Couldn’t delete confirmed records from iCloud: \(error.localizedDescription)"
    }
  }

  nonisolated static func makeLeftoverDisplayGroups(
    from report: CloudSyncLeftoverReport,
    in db: Database
  ) throws -> [LeftoverDisplayGroup] {
    var recipeTitles: [String: String] = [:]
    for leftover in report.leftovers where leftover.tableName == "recipes" {
      if let title = leftover.record["title"] as? String {
        recipeTitles[leftover.primaryKey] = title
      }
    }
    let recipeIDs = Set(report.leftovers.compactMap { leftover in
      leftover.tableName == "recipes" ? nil : Self.stringValue(leftover.record["recipeID"])
    })
    for recipeID in recipeIDs where recipeTitles[recipeID] == nil {
      if let title = try String.fetchOne(
        db,
        sql: "SELECT \"title\" FROM \"recipes\" WHERE \"id\" = ?",
        arguments: [recipeID]
      ) {
        recipeTitles[recipeID] = title
      }
    }

    var rowsByTitle: [String: [LeftoverDisplayRow]] = [:]
    for leftover in report.leftovers {
      let recipeID = Self.stringValue(leftover.record["recipeID"])
      let recipeTitle = leftover.tableName == "recipes"
        ? (recipeTitles[leftover.primaryKey] ?? "Recipe")
        : recipeID.flatMap { recipeTitles[$0] }
      let title = recipeTitle ?? Self.readableTableName(leftover.tableName)
      rowsByTitle[title, default: []].append(LeftoverDisplayRow(
        id: leftover.record.recordID.recordName,
        kind: Self.leftoverKind(for: leftover.tableName),
        detail: Self.leftoverContent(for: leftover),
        tableName: leftover.tableName
      ))
    }
    return rowsByTitle.keys.sorted().map { title in
      LeftoverDisplayGroup(
        title: title,
        rows: (rowsByTitle[title] ?? []).sorted {
          $0.tableName == $1.tableName ? $0.id < $1.id : $0.tableName < $1.tableName
        }
      )
    }
  }

  nonisolated private static func stringValue(_ value: CKRecordValue?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? UUID { return value.uuidString.lowercased() }
    return nil
  }

  nonisolated private static func leftoverKind(for tableName: String) -> String {
    switch tableName {
    case "recipes": "Recipe"
    case "instructionSteps": "Step"
    case "instructionSections": "Instruction section"
    case "ingredientLines": "Ingredient"
    case "ingredientSections": "Ingredient section"
    case "recipeNotes": "Note"
    default: readableTableName(tableName)
    }
  }

  nonisolated private static func leftoverContent(for leftover: CloudSyncLeftover) -> String {
    let record = leftover.record
    let keys: [String]
    switch leftover.tableName {
    case "recipes": keys = ["title"]
    case "instructionSteps": keys = ["text"]
    case "instructionSections", "ingredientSections": keys = ["name"]
    case "ingredientLines": keys = ["originalText"]
    case "recipeNotes": keys = ["text"]
    default: keys = ["title", "name", "text", "originalText", "item", "label", "url"]
    }
    for key in keys {
      if let value = record[key] as? String, !value.isEmpty { return value }
    }
    return leftover.primaryKey
  }

  #if DEBUG
  /// Decode the metadatabase and bounded CloudKit samples away from the main actor.
  func diagnoseSyncFailure() async {
    guard !isDiagnosingSyncFailure else { return }
    isDiagnosingSyncFailure = true
    syncFailureDiagnosisError = nil
    syncFailureDiagnosisReadout = nil
    defer { isDiagnosingSyncFailure = false }

    let database = database
    let engineRunning = syncEngine.isRunning
    let sending = engineRunning && syncEngine.isSendingChanges
    let fetching = engineRunning && syncEngine.isFetchingChanges
    let capturedAt = Date.now
    let deviceModel = UIDevice.current.model
    let verdictCache = syncFailureVerdictCache
    let result: Result<SyncFailureDiagnosis, Error> = await Task.detached(priority: .utility) {
      do {
        return .success(try await YesChefCloudSync.syncFailureDiagnosis(
          in: database,
          isEngineRunning: engineRunning,
          isSendingChanges: sending,
          isFetchingChanges: fetching,
          now: capturedAt,
          verdictCache: verdictCache
        ))
      } catch {
        return .failure(error)
      }
    }.value
    switch result {
    case let .success(diagnosis):
      syncFailureVerdictCache = diagnosis.verdictCache
      syncFailureDiagnosisReadout = Self.format(
        diagnosis,
        capturedAt: capturedAt,
        deviceModel: deviceModel,
        isEngineRunning: engineRunning,
        isSendingChanges: sending,
        isFetchingChanges: fetching
      )
    case let .failure(error):
      syncFailureDiagnosisError = "Couldn’t diagnose sync status: \(error.localizedDescription)"
    }
  }

  nonisolated private static func format(
    _ diagnosis: SyncFailureDiagnosis,
    capturedAt: Date,
    deviceModel: String,
    isEngineRunning: Bool,
    isSendingChanges: Bool,
    isFetchingChanges: Bool
  ) -> String {
    let counts = diagnosis.reasons
    let formatter = ISO8601DateFormatter()
    var lines = [
      "Sync failure diagnosis",
      "Device model: \(deviceModel)",
      "Captured at: \(formatter.string(from: capturedAt))",
      "Engine state: running=\(isEngineRunning), sending=\(isSendingChanges), fetching=\(isFetchingChanges)",
      "Rows considered: \(diagnosis.consideredCount)",
      "Confirmed: \(counts.confirmed)",
      "No server record: \(counts.noServerRecord)",
      "Undecodable: \(counts.undecodable)",
      "No change tag: \(counts.noChangeTag)",
      "Unsent edits: \(counts.unsentEdit)",
      "Stamp-only rows: \(counts.stampOnly)",
      "Elapsed: \(diagnosis.elapsed) seconds",
      "All-fields decoded: \(diagnosis.decodedRowCount)",
      "Verdicts cached: \(diagnosis.cachedRowCount)",
    ]
    if let delta = diagnosis.localEditDelta {
      lines += [
        "Local edit delta seconds (min / median / max): \(delta.minimum) / \(delta.median) / \(delta.maximum)",
        "Delta histogram: under 1 h \(delta.underOneHour), 1 h–1 d \(delta.oneHourToOneDay), 1–7 d \(delta.oneToSevenDays), over 7 d \(delta.overSevenDays)",
      ]
    }
    lines.append("By record type:")
    for type in diagnosis.byRecordType {
      let reason = type.reasons
      lines.append("  \(type.recordType): confirmed \(reason.confirmed), no record \(reason.noServerRecord), undecodable \(reason.undecodable), no tag \(reason.noChangeTag), unsent edit \(reason.unsentEdit), stamp-only \(reason.stampOnly)")
    }
    lines.append("Samples:")
    for sample in diagnosis.samples {
      let serverModified = sample.serverModificationDate.map(formatter.string(from:)) ?? "none"
      let serverCreated = sample.serverCreationDate.map(formatter.string(from:)) ?? "none"
      let sentStamp = sample.serverUserModificationTime.map(formatter.string(from:)) ?? "none"
      lines.append("  \(sample.recordType)/\(sample.primaryKey): reason=\(reasonDescription(sample.reason)), local=\(formatter.string(from: sample.userModificationTime)), serverModified=\(serverModified), serverCreated=\(serverCreated), changeTag=\(sample.hasChangeTag), sentUserModificationTime=\(sentStamp), differingColumns=\(sample.differingColumns.joined(separator: ","))")
    }
    return lines.joined(separator: "\n")
  }

  nonisolated private static func reasonDescription(_ reason: SyncFailureReason) -> String {
    switch reason {
    case .confirmed: "confirmed"
    case .noServerRecord: "no server record"
    case .undecodable: "undecodable"
    case .noChangeTag: "no change tag"
    case let .unsentEdit(delta): "unsent edit by \(delta) seconds"
    case let .stampOnly(delta): "stamp-only by \(delta) seconds"
    }
  }
  #endif

  /// Turn the gate on (the row is the enable affordance when sync is off), start the
  /// engine, then refresh.
  func enableSyncButtonTapped() async {
    YesChefCloudSync.setManuallyEnabled(true)
    await start()
  }

  /// Re-run the same start the app runs at launch, capturing its error, then refresh.
  func tryAgainButtonTapped() async {
    await start()
  }

  private func start() async {
    isStarting = true
    defer { isStarting = false }
    switch await YesChefCloudSync.startIfManuallyEnabled() {
    case let .failed(message):
      lastStartError = message
    case .started, .disabled, .unavailable:
      // A clean start (or a still-unavailable account, which the reducer surfaces as
      // local-only) clears any stale start error.
      lastStartError = nil
    }
    await refresh()
  }

  /// Read per-table row counts from the local store. Cheap `COUNT(*)`s; failures
  /// collapse to an empty list rather than disturbing the sync detail sheet.
  func loadRecordCounts() async {
    recordCounts = (try? await database.read { db in
      [
        RecordCount(name: "recipes", count: try Recipe.fetchCount(db)),
        RecordCount(name: "recipeSources", count: try RecipeSource.fetchCount(db)),
        RecordCount(name: "ingredientSections", count: try IngredientSection.fetchCount(db)),
        RecordCount(name: "ingredientLines", count: try IngredientLine.fetchCount(db)),
        RecordCount(name: "instructionSections", count: try InstructionSection.fetchCount(db)),
        RecordCount(name: "instructionSteps", count: try InstructionStep.fetchCount(db)),
        RecordCount(name: "recipePhotos", count: try RecipePhoto.fetchCount(db)),
        RecordCount(name: "recipeNotes", count: try RecipeNote.fetchCount(db)),
        RecordCount(name: "menus", count: try Menu.fetchCount(db)),
        RecordCount(name: "menuItems", count: try MenuItem.fetchCount(db)),
        RecordCount(name: "mealPlanItems", count: try MealPlanItem.fetchCount(db)),
      ]
    }) ?? []
  }

  private func currentSyncFailureReport(isEngineRunning: Bool) async -> SyncFailureReport? {
    do {
      let result = try await YesChefCloudSync.syncFailureReport(
        in: database,
        isEngineRunning: isEngineRunning,
        isSendingChanges: isEngineRunning && syncEngine.isSendingChanges,
        isFetchingChanges: isEngineRunning && syncEngine.isFetchingChanges,
        verdictCache: syncFailureVerdictCache
      )
      syncFailureVerdictCache = result.verdictCache
      syncFailureReportError = nil
      return result.report
    } catch {
      // A failed signal read must not make the Settings row claim “Up to date.”
      syncFailureReportError = "Couldn’t check which records have synced."
      return nil
    }
  }

  nonisolated static func makeNotUploadedRows(
    from report: SyncFailureReport,
    in db: Database
  ) throws -> [NotUploadedDisplayRow] {
    var rows: [NotUploadedDisplayRow] = []
    for group in report.notUploaded {
      let keys = group.primaryKeys
      if group.recordType == "recipes" {
        for key in keys {
          let title = try String.fetchOne(
            db,
            sql: "SELECT \"title\" FROM \"recipes\" WHERE \"id\" = ?",
            arguments: [key]
          )
          rows.append(NotUploadedDisplayRow(
            recordType: group.recordType,
            primaryKeys: [key],
            title: title ?? "Recipe on this device",
            detail: title == nil ? "Couldn’t read its title" : "Recipe"
          ))
        }
      } else if isRecipeChildRecordType(group.recordType) {
        var keysByRecipeID: [String: [String]] = [:]
        var titlesByRecipeID: [String: String] = [:]
        for key in keys {
          let row = try Row.fetchOne(
            db,
            sql: """
              SELECT child.\"recipeID\" AS recipeID, recipe.\"title\" AS title
              FROM \"\(group.recordType)\" AS child
              LEFT JOIN \"recipes\" AS recipe ON recipe.\"id\" = child.\"recipeID\"
              WHERE child.\"id\" = ?
              """,
            arguments: [key]
          )
          guard let row,
                let recipeID = row["recipeID"] as String?,
                let title = row["title"] as String?
          else { continue }
          keysByRecipeID[recipeID, default: []].append(key)
          titlesByRecipeID[recipeID] = title
        }
        let recipeIDs = keysByRecipeID.keys.sorted {
          let leftTitle = titlesByRecipeID[$0, default: ""]
          let rightTitle = titlesByRecipeID[$1, default: ""]
          return leftTitle == rightTitle ? $0 < $1 : leftTitle < rightTitle
        }
        for recipeID in recipeIDs {
          let recipeKeys = keysByRecipeID[recipeID] ?? []
          rows.append(NotUploadedDisplayRow(
            recordType: group.recordType,
            primaryKeys: recipeKeys,
            title: titlesByRecipeID[recipeID] ?? "Recipe on this device",
            detail: "\(recipeKeys.count) \(pluralizedTableName(group.recordType))"
          ))
        }
        let resolvedKeys = Set(keysByRecipeID.values.flatMap { $0 })
        let missingKeys = keys.filter { !resolvedKeys.contains($0) }
        if !missingKeys.isEmpty {
          rows.append(aggregateRow(for: group, keys: missingKeys))
        }
      } else {
        rows.append(aggregateRow(for: group, keys: keys))
      }

      let unlistedCount = group.count - keys.count
      if unlistedCount > 0 {
        rows.append(NotUploadedDisplayRow(
          recordType: group.recordType,
          primaryKeys: [],
          title: "\(unlistedCount) more \(pluralizedTableName(group.recordType)) not listed",
          detail: "Retry the listed rows and reopen Sync to see the rest."
        ))
      }
    }
    return rows
  }

  nonisolated private static func fallbackNotUploadedRows(
    from report: SyncFailureReport
  ) -> [NotUploadedDisplayRow] {
    report.notUploaded.flatMap { group in
      var rows = [aggregateRow(for: group, keys: group.primaryKeys)]
      let unlistedCount = group.count - group.primaryKeys.count
      if unlistedCount > 0 {
        rows.append(NotUploadedDisplayRow(
          recordType: group.recordType,
          primaryKeys: [],
          title: "\(unlistedCount) more \(pluralizedTableName(group.recordType)) not listed",
          detail: "Retry the listed rows and reopen Sync to see the rest."
        ))
      }
      return rows
    }
  }

  nonisolated static func aggregateRow(
    for group: NotUploadedRecordGroup,
    keys: [String]
  ) -> NotUploadedDisplayRow {
    let count = keys.count == group.primaryKeys.count ? group.count : keys.count
    let tableName = readableTableName(group.recordType)
    return NotUploadedDisplayRow(
      recordType: group.recordType,
      primaryKeys: keys,
      title: "\(count) \(count == 1 ? "row" : "rows")",
      detail: tableName
    )
  }

  nonisolated private static func readableTableName(_ name: String) -> String {
    let spaced = name.replacingOccurrences(
      of: "([a-z0-9])([A-Z])",
      with: "$1 $2",
      options: .regularExpression
    )
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }

  nonisolated private static func pluralizedTableName(_ name: String) -> String {
    let label = readableTableName(name).lowercased()
    return label.hasSuffix("s") ? label : "\(label) rows"
  }

  nonisolated private static func isRecipeChildRecordType(_ recordType: String) -> Bool {
    recipeChildRecordTypes.contains(recordType)
  }

  nonisolated private static let recipeChildRecordTypes: Set<String> = [
    "recipeSources", "recipeImportRef", "ingredientSections", "ingredientLines",
    "instructionSections", "instructionSteps", "recipeNotes", "recipePhotos",
    "recipeServeWith", "recipeTags", "recipeCategories", "recipeEquipment",
    "recipeVariations", "recipeActiveVariations", "recipeRelatedRecipes",
    "recipeDeliberationLog",
  ]

  private func currentAccountStatus() async -> SyncAccountStatus {
    do {
      let status = try await CKContainer(identifier: YesChefCloudSync.containerIdentifier)
        .accountStatus()
      return SyncAccountStatus(status)
    } catch {
      // A thrown status read is itself "couldn't determine" — the reducer shows it as
      // local-only, which is the honest thing to say.
      return .couldNotDetermine
    }
  }

  private func currentPendingCount() async -> Int {
    (try? await YesChefCloudSync.pendingRecordZoneChangeCount(in: database)) ?? 0
  }
}

/// One synced table's local row count, for the Sync detail diagnostics list.
struct RecordCount: Identifiable, Sendable {
  let name: String
  let count: Int
  var id: String { name }
}

struct NotUploadedDisplayRow: Identifiable, Equatable, Sendable {
  let recordType: String
  let primaryKeys: [String]
  let title: String
  let detail: String

  var id: String { "\(recordType):\(primaryKeys.joined(separator: ","))" }
}

struct LeftoverDisplayGroup: Identifiable, Sendable {
  let title: String
  let rows: [LeftoverDisplayRow]
  var id: String { title }
}

struct LeftoverDisplayRow: Identifiable, Sendable {
  let id: String
  let kind: String
  let detail: String
  let tableName: String
}
