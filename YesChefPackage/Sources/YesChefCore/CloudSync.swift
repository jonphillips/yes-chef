import CloudKit
import CloudSyncKit
import Dependencies
import SQLiteData

/// Yes Chef's binding of the shared `CloudSync` core (jon-platform ADR-0003). The
/// sync-control logic — the enablement gate, gated start, scene redrain, and the
/// `PendingRecordZoneChange` poll — now lives once in `CloudSyncKit`, shared with
/// galavant (both apps had forked it line-for-line). This thin facade holds the two
/// things that are genuinely Yes Chef's: its `CloudSyncConfiguration` (container id +
/// gate keys) and `makeSyncEngine`, which lists the app's synced `@Table` types and so
/// can't lift. Everything else forwards to `CloudSync`, passing `configuration`.
public enum YesChefCloudSync {
  /// The per-app constants — the only thing that differed from galavant's copy.
  public static let configuration = CloudSyncConfiguration(
    containerIdentifier: "iCloud.com.jonphillips.yeschef",
    enabledDefaultsKey: "YesChefCloudKitSyncEnabled",
    enabledEnvironmentKey: "YES_CHEF_CLOUDKIT_SYNC_ENABLED",
    enabledLaunchArgument: "-YesChefCloudKitSyncEnabled",
    restoreRequiresManualEnablementDefaultsKey: "YesChefCloudKitSyncRestoreRequiresManualEnablement"
  )

  /// Yes Chef's store identity and migration closure for the shared backup workflow.
  public static let databaseBackupConfiguration = DatabaseBackupConfiguration(
    displayName: "Yes Chef",
    backupFilenamePrefix: "YesChef-Backup-",
    preRestoreFilenamePrefix: "YesChef-PreRestore-",
    restoreStagingFilenamePrefix: "YesChef-Restore-",
    identifyingTableNames: ["recipes"],
    declaredSchemaVersion: 54,
    lastPreRestoreDefaultsKey: "YesChefDatabaseBackupLastPreRestorePath",
    cloudSync: configuration,
    liveStoreURL: { try YesChefDatabaseStorage.liveSharedDatabaseURL() },
    migrate: { try DependencyValues.migrateRestoreCandidate(at: $0) }
  )

#if DEBUG
  public static let automaticBackupConfiguration: AutomaticBackupConfiguration? = nil
#else
  public static let automaticBackupConfiguration: AutomaticBackupConfiguration? = AutomaticBackupConfiguration(
    filenamePrefix: "YesChef-Auto-",
    libraryCountTableName: "recipes",
    retention: .init(daily: 14, monthly: 6),
    installIDDefaultsKey: "YesChefAutomaticBackupInstallID",
    enabledDefaultsKey: "YesChefAutomaticBackupEnabled"
  )
#endif

  public typealias BootstrapMode = CloudSync.BootstrapMode
  public typealias StartResult = CloudSync.StartResult
  public typealias PendingRecordZoneRedrainResult = CloudSync.PendingRecordZoneRedrainResult

  public static var containerIdentifier: String { configuration.containerIdentifier }
  public static var enabledDefaultsKey: String { configuration.enabledDefaultsKey }

  /// The shared table matcher set used by failure reporting, diagnosis, and retry.
  public static let syncedTables = SyncedTables(
    Recipe.self, RecipeSource.self, IngredientSection.self, IngredientLine.self,
    InstructionSection.self, InstructionStep.self, RecipeNote.self, RecipeServeWith.self,
    RecipePhoto.self, Facet.self, Category.self,
    RecipeCategory.self, RecipeImportRef.self, MealPlanItem.self,
    Menu.self, MenuItem.self, MenuPlacement.self, PrepPlanStepRecord.self, Workbench.self,
    WorkbenchCandidate.self, WorkbenchLogEntry.self, WorkbenchReference.self,
    RecipeVariation.self, RecipeRelatedRecipe.self, RecipeDeliberationLogEntry.self,
    GroceryList.self, GroceryAreaAssignment.self, GroceryItem.self, GroceryItemSource.self,
    PantryItem.self, AISettingsRecord.self, Learning.self
  )

  /// These types were removed from the engine. Purge their CloudKit records and
  /// SQLiteData metadata; never include a type that remains in `syncedTables`.
  public static let retiredRecordTypes = ["categorySeedStates", "categorySeedTombstones", "tags", "recipeTags"]

  // SQLiteData can begin its automatic initial fetch just after start returns. Polling
  // once per second and requiring two idle snapshots lets that fetch become observable;
  // the one-minute bound keeps cleanup from waiting indefinitely during a long sync.
  private static let retiredPurgeIdlePollInterval: Duration = .seconds(1)
  private static let retiredPurgeIdlePollLimit = 60 // 60-second bound / 1-second poll interval.
  private static let retiredPurgeRequiredIdleReads = 2

  // MARK: Enablement gate (forwarded)

  public static func isManuallyEnabled(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    return CloudSync.isManuallyEnabled(
      configuration: configuration, defaults: defaults, environment: environment,
      arguments: arguments
    )
  }

  public static func setManuallyEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
    CloudSync.setManuallyEnabled(enabled, configuration: configuration, defaults: defaults)
  }

  /// A restore always begins as a new local sync peer. This persistent gate beats launch
  /// arguments and environment variables until the user deliberately turns sync back on.
  public static func disableForRestore(defaults: UserDefaults = .standard) {
    CloudSync.disableForRestore(configuration: configuration, defaults: defaults)
  }

  /// True only while a restore has deliberately held sync off. The Settings UI uses this to put
  /// a final confirmation in front of the first CloudKit merge after a restore.
  public static func isDisabledByRestore(defaults: UserDefaults = .standard) -> Bool {
    CloudSync.isDisabledByRestore(configuration: configuration, defaults: defaults)
  }

  public static func persistManualEnablementFromLaunchEnvironment(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) {
    CloudSync.persistManualEnablementFromLaunchEnvironment(
      configuration: configuration, defaults: defaults, environment: environment,
      arguments: arguments
    )
  }

  // MARK: Start / redrain / pending (forwarded)

  public static func startIfManuallyEnabled() async -> StartResult {
    let result = await CloudSync.startIfManuallyEnabled(configuration: configuration)
    guard case .started = result else { return result }

    Task(priority: .background) {
      await purgeRetiredRecordTypesWhenIdle()
    }
    return result
  }

  private static func purgeRetiredRecordTypesWhenIdle() async {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.defaultSyncEngine) var syncEngine
    @Dependency(\.continuousClock) var clock
    guard syncEngine.isRunning else { return }

    var consecutiveIdleReads = 0
    for _ in 0..<retiredPurgeIdlePollLimit {
      if !syncEngine.isSynchronizing {
        consecutiveIdleReads += 1
        if consecutiveIdleReads == retiredPurgeRequiredIdleReads { break }
      } else {
        consecutiveIdleReads = 0
      }
      do {
        try await clock.sleep(for: retiredPurgeIdlePollInterval)
      } catch {
        return
      }
    }
    guard consecutiveIdleReads == retiredPurgeRequiredIdleReads else {
      AppLog.dataIntegrity.debug("Retired CloudKit sync cleanup skipped because sync did not become idle in time")
      return
    }
    guard syncEngine.isRunning else { return }

    let pendingChangeCount: Int
    do {
      pendingChangeCount = try await CloudSync.pendingRecordZoneChangeCount(in: database)
    } catch {
      AppLog.dataIntegrity.error(
        "Couldn’t check pending changes before retired sync cleanup: \(String(describing: error), privacy: .public)"
      )
      return
    }
    guard pendingChangeCount == 0 else { return }

    let client = CloudKitLeftoverClient(
      database: CKContainer(identifier: configuration.containerIdentifier).privateCloudDatabase
    )
    do {
      let result = try await CloudSync.purgeRetiredRecordTypes(
        retiredRecordTypes, tables: syncedTables, in: database, client: client
      )
      let purgedCount = result.purgedCountsByType.values.reduce(0, +)
      guard purgedCount > 0 || !result.failures.isEmpty else { return }

      var summary = result.purgedCountsByType.keys.sorted().map { recordType in
        "\(recordType): purged \(result.purgedCountsByType[recordType, default: 0])"
      }
      summary += result.failures.keys.sorted { $0.recordName < $1.recordName }.map { recordID in
        "\(recordID.recordName): \(result.failures[recordID] ?? "Unknown error")"
      }
      let message = "Retired CloudKit sync cleanup: \(summary.joined(separator: "; "))"
      if result.failures.isEmpty {
        AppLog.dataIntegrity.notice("\(message, privacy: .public)")
      } else {
        AppLog.dataIntegrity.warning("\(message, privacy: .public)")
      }
    } catch {
      AppLog.dataIntegrity.error(
        "Retired CloudKit sync cleanup failed: \(String(describing: error), privacy: .public)"
      )
    }
  }

  public static func redrainPendingRecordZoneChangesIfManuallyEnabled(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    database providedDatabase: (any DatabaseWriter)? = nil,
    accountStatus providedAccountStatus: (() async throws -> CKAccountStatus)? = nil,
    stopSyncEngine: (() -> Void)? = nil,
    startSyncEngine: (() async throws -> Void)? = nil
  ) async -> PendingRecordZoneRedrainResult {
    await CloudSync.redrainPendingRecordZoneChangesIfManuallyEnabled(
      configuration: configuration, defaults: defaults, environment: environment,
      arguments: arguments, database: providedDatabase,
      accountStatus: providedAccountStatus, stopSyncEngine: stopSyncEngine,
      startSyncEngine: startSyncEngine
    )
  }

  public static func pendingRecordZoneChangeCount(in database: any DatabaseWriter) async throws -> Int {
    try await CloudSync.pendingRecordZoneChangeCount(in: database)
  }

  public static func pendingRecordZoneChangeCount(in db: Database) throws -> Int {
    try CloudSync.pendingRecordZoneChangeCount(in: db)
  }

  public static func waitForPendingRecordZoneChanges(
    in database: any DatabaseWriter,
    exceeding previousCount: Int,
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(25)
  ) async throws -> Bool {
    try await CloudSync.waitForPendingRecordZoneChanges(
      in: database, exceeding: previousCount, timeout: timeout, pollInterval: pollInterval
    )
  }

  public static func syncFailureReport(
    in database: any DatabaseWriter,
    isEngineRunning: Bool,
    isSendingChanges: Bool,
    isFetchingChanges: Bool,
    now: Date = .now,
    verdictCache: SyncFailureVerdictCache
  ) async throws -> SyncFailureReportResult {
    try await CloudSync.syncFailureReport(in: database, tables: syncedTables,
      isEngineRunning: isEngineRunning, isSendingChanges: isSendingChanges,
      isFetchingChanges: isFetchingChanges, now: now, verdictCache: verdictCache)
  }

  public static func syncFailureDiagnosis(
    in database: any DatabaseWriter,
    isEngineRunning: Bool,
    isSendingChanges: Bool,
    isFetchingChanges: Bool,
    now: Date = .now,
    verdictCache: SyncFailureVerdictCache
  ) async throws -> SyncFailureDiagnosis {
    try await CloudSync.syncFailureDiagnosis(in: database, tables: syncedTables,
      isEngineRunning: isEngineRunning, isSendingChanges: isSendingChanges,
      isFetchingChanges: isFetchingChanges, now: now, verdictCache: verdictCache)
  }

  public static func requeue(
    recordType: String,
    primaryKeys: [String],
    in database: any DatabaseWriter,
    verdictCache: SyncFailureVerdictCache
  ) async throws -> SyncRequeueResult {
    try await CloudSync.requeue(recordType: recordType, primaryKeys: primaryKeys, tables: syncedTables,
      in: database, verdictCache: verdictCache)
  }

  public static func leftoverCheck(
    in database: any DatabaseWriter,
    client: any CloudSyncLeftoverClient,
    isEngineRunning: Bool,
    pendingChangeCount: Int,
    isSendingChanges: Bool,
    fetchStartedAt: Date
  ) async throws -> CloudSyncLeftoverCheckResult {
    try await CloudSync.leftoverCheck(
      in: database,
      tables: syncedTables,
      client: client,
      isEngineRunning: isEngineRunning,
      pendingChangeCount: pendingChangeCount,
      isSendingChanges: isSendingChanges,
      fetchStartedAt: fetchStartedAt
    )
  }

  public static func deleteLeftovers(
    _ recordIDs: [CKRecord.ID],
    using client: any CloudSyncLeftoverClient
  ) async throws -> CloudSyncDeleteLeftoversResult {
    try await CloudSync.deleteLeftovers(recordIDs, using: client)
  }

  // MARK: Engine construction (domain-bound — stays here)

  /// Construct the sync engine over Yes Chef's synced tables. This is the one method
  /// that can't lift: it names the app's `@Table` types. Every product a synced table
  /// belongs to must be registered here (and in `project.yml` deps) or a regenerate
  /// silently drops it.
  public static func makeSyncEngine(
    for database: any DatabaseWriter,
    startImmediately: Bool
  ) throws -> SyncEngine {
    try SyncEngine(
      for: database,
      tables:
        Recipe.self,
        RecipeSource.self,
        IngredientSection.self,
        IngredientLine.self,
        InstructionSection.self,
        InstructionStep.self,
        RecipeNote.self,
        RecipeServeWith.self,
        RecipePhoto.self,
        Facet.self,
        Category.self,
        RecipeCategory.self,
        RecipeImportRef.self,
        MealPlanItem.self,
        Menu.self,
        MenuItem.self,
        MenuPlacement.self,
        PrepPlanStepRecord.self,
        Workbench.self,
        WorkbenchCandidate.self,
        WorkbenchLogEntry.self,
        WorkbenchReference.self,
        RecipeVariation.self,
        RecipeRelatedRecipe.self,
        RecipeDeliberationLogEntry.self,
        GroceryList.self,
        GroceryAreaAssignment.self,
        GroceryItem.self,
        GroceryItemSource.self,
        PantryItem.self,
        AISettingsRecord.self,
        Learning.self,
      containerIdentifier: configuration.containerIdentifier,
      startImmediately: startImmediately
    )
  }
}
