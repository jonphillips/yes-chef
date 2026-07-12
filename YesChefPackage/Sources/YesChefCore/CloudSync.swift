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
    enabledLaunchArgument: "-YesChefCloudKitSyncEnabled"
  )

  public typealias BootstrapMode = CloudSync.BootstrapMode
  public typealias StartResult = CloudSync.StartResult
  public typealias PendingRecordZoneRedrainResult = CloudSync.PendingRecordZoneRedrainResult

  public static var containerIdentifier: String { configuration.containerIdentifier }
  public static var enabledDefaultsKey: String { configuration.enabledDefaultsKey }

  // MARK: Enablement gate (forwarded)

  public static func isManuallyEnabled(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    CloudSync.isManuallyEnabled(
      configuration: configuration, defaults: defaults, environment: environment,
      arguments: arguments
    )
  }

  public static func setManuallyEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
    CloudSync.setManuallyEnabled(enabled, configuration: configuration, defaults: defaults)
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
    await CloudSync.startIfManuallyEnabled(configuration: configuration)
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
        RecipePhoto.self,
        Tag.self,
        Category.self,
        Equipment.self,
        RecipeTag.self,
        RecipeCategory.self,
        RecipeEquipment.self,
        RecipeImportRef.self,
        MealPlanItem.self,
        MealPlanDayOrder.self,
        Menu.self,
        MenuItem.self,
        MenuPlacement.self,
        Workbench.self,
        WorkbenchCandidate.self,
        WorkbenchLogEntry.self,
        RecipeVariation.self,
        GroceryList.self,
        GroceryItem.self,
        GroceryItemSource.self,
        PantryItem.self,
        AISettingsRecord.self,
      containerIdentifier: configuration.containerIdentifier,
      startImmediately: startImmediately
    )
  }
}
