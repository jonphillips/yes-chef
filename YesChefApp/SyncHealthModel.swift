import CloudKit
import CloudSyncKit
import Dependencies
import Foundation
import Observation
import SQLiteData
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

  /// Local row counts per synced table — the dogfood diagnostic that answers
  /// "did this table's rows actually reach this device?" at a glance. Populated on
  /// demand from the Sync detail sheet; compare the two devices side by side.
  private(set) var recordCounts: [RecordCount] = []

  /// Rows that CloudSyncKit can name as not uploaded, grouped into user-readable
  /// retry actions for the Sync detail sheet.
  private(set) var notUploadedRows: [NotUploadedDisplayRow] = []
  private(set) var isRetryingRows: Set<String> = []
  private(set) var retryError: String?

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

  /// Gather the live signals and fold them into `health`. Cheap and idempotent —
  /// safe to call on appear, on scene `.active`, on a database-change beacon, and
  /// whenever a sync cycle ends.
  func refresh() async {
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
      notUploadedRows = await makeNotUploadedRows(from: failureReport)
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
    guard isRetryingRows.insert(row.id).inserted else { return }
    retryError = nil
    defer { isRetryingRows.remove(row.id) }

    do {
      try await CloudSync.requeue(
        recordType: row.recordType,
        primaryKeys: row.primaryKeys,
        in: database
      )
      await refresh()
    } catch {
      retryError = "Couldn’t retry \(row.title): \(error.localizedDescription)"
    }
  }

  func isRetrying(_ row: NotUploadedDisplayRow) -> Bool {
    isRetryingRows.contains(row.id)
  }

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
      let report = try await CloudSync.syncFailureReport(
        in: database,
        isEngineRunning: isEngineRunning,
        isSendingChanges: isEngineRunning && syncEngine.isSendingChanges,
        isFetchingChanges: isEngineRunning && syncEngine.isFetchingChanges
      )
      syncFailureReportError = nil
      return report
    } catch {
      // A failed signal read must not make the Settings row claim “Up to date.”
      syncFailureReportError = "Couldn’t check which records have synced."
      return nil
    }
  }

  private func makeNotUploadedRows(from report: SyncFailureReport) async -> [NotUploadedDisplayRow] {
    (try? await database.read { db in
      var rows: [NotUploadedDisplayRow] = []
      for group in report.notUploaded {
        let keys = group.primaryKeys
        if group.recordType == "recipes" {
          for key in keys {
            guard let id = UUID(uuidString: key),
                  let recipe = try Recipe.find(id).fetchOne(db)
            else {
              rows.append(NotUploadedDisplayRow(
                recordType: group.recordType,
                primaryKeys: [key],
                title: "Recipe on this device",
                detail: "Couldn’t read its title"
              ))
              continue
            }
            rows.append(NotUploadedDisplayRow(
              recordType: group.recordType,
              primaryKeys: [key],
              title: recipe.title,
              detail: "Recipe"
            ))
          }
        } else if Self.isRecipeChildRecordType(group.recordType) {
          var keysByRecipeID: [UUID: [String]] = [:]
          var titlesByRecipeID: [UUID: String] = [:]
          for key in keys {
            guard let id = UUID(uuidString: key),
                  let recipeID = Self.recipeID(
                    for: group.recordType,
                    primaryKey: id,
                    in: db
                  ),
                  let recipe = try Recipe.find(recipeID).fetchOne(db)
            else { continue }
            keysByRecipeID[recipeID, default: []].append(key)
            titlesByRecipeID[recipeID] = recipe.title
          }
          let recipeIDs = keysByRecipeID.keys.sorted {
            titlesByRecipeID[$0, default: ""] < titlesByRecipeID[$1, default: ""]
          }
          for recipeID in recipeIDs {
            let title = titlesByRecipeID[recipeID] ?? "Recipe on this device"
            let recipeKeys = keysByRecipeID[recipeID] ?? []
            rows.append(NotUploadedDisplayRow(
              recordType: group.recordType,
              primaryKeys: recipeKeys,
              title: title,
              detail: "\(recipeKeys.count) \(Self.pluralizedTableName(group.recordType))"
            ))
          }
          let resolvedKeys = Set(keysByRecipeID.values.flatMap { $0 })
          let missingKeys = keys.filter { !resolvedKeys.contains($0) }
          if !missingKeys.isEmpty {
            rows.append(Self.aggregateRow(for: group, keys: missingKeys))
          }
        } else {
          rows.append(Self.aggregateRow(for: group, keys: keys))
        }
      }
      return rows
    }) ?? report.notUploaded.map { Self.aggregateRow(for: $0, keys: $0.primaryKeys) }
  }

  nonisolated private static func aggregateRow(
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

  nonisolated private static func recipeID(
    for recordType: String,
    primaryKey: UUID,
    in db: Database
  ) -> UUID? {
    switch recordType {
    case "recipeSources": try? RecipeSource.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeImportRef": try? RecipeImportRef.find(primaryKey).fetchOne(db)?.recipeID
    case "ingredientSections": try? IngredientSection.find(primaryKey).fetchOne(db)?.recipeID
    case "ingredientLines": try? IngredientLine.find(primaryKey).fetchOne(db)?.recipeID
    case "instructionSections": try? InstructionSection.find(primaryKey).fetchOne(db)?.recipeID
    case "instructionSteps": try? InstructionStep.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeNotes": try? RecipeNote.find(primaryKey).fetchOne(db)?.recipeID
    case "recipePhotos": try? RecipePhoto.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeServeWith": try? RecipeServeWith.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeTags": try? RecipeTag.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeCategories": try? RecipeCategory.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeEquipment": try? RecipeEquipment.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeVariations": try? RecipeVariation.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeActiveVariations": try? RecipeActiveVariation.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeRelatedRecipes": try? RecipeRelatedRecipe.find(primaryKey).fetchOne(db)?.recipeID
    case "recipeDeliberationLog": try? RecipeDeliberationLogEntry.find(primaryKey).fetchOne(db)?.recipeID
    default: nil
    }
  }

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

struct NotUploadedDisplayRow: Identifiable, Sendable {
  let recordType: String
  let primaryKeys: [String]
  let title: String
  let detail: String

  var id: String { "\(recordType):\(primaryKeys.joined(separator: ","))" }
}
