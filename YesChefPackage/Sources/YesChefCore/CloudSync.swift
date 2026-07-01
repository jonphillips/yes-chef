import CloudKit
import Dependencies
import Foundation
import SQLiteData

public enum YesChefCloudSync {
  public enum BootstrapMode: Sendable {
    case disabled
    case configured(startImmediately: Bool)
  }

  public enum StartResult: Equatable, Sendable {
    case disabled
    case unavailable(String)
    case started
    case failed(String)
  }

  public enum PendingRecordZoneRedrainResult: Equatable, Sendable {
    case disabled
    case noPendingChanges
    case unavailable(String)
    case restarted
    case failed(String)
  }

  public static let containerIdentifier = "iCloud.com.jonphillips.yeschef"
  public static let enabledDefaultsKey = "YesChefCloudKitSyncEnabled"
  public static let enabledEnvironmentKey = "YES_CHEF_CLOUDKIT_SYNC_ENABLED"
  public static let enabledLaunchArgument = "-YesChefCloudKitSyncEnabled"

  public static func isManuallyEnabled(
    defaults: UserDefaults = .standard,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> Bool {
    defaults.bool(forKey: enabledDefaultsKey)
      || environment[enabledEnvironmentKey] == "1"
      || environment[enabledEnvironmentKey]?.lowercased() == "true"
      || arguments.contains(enabledLaunchArgument)
  }

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
        Menu.self,
        MenuItem.self,
        MenuPlacement.self,
        GroceryList.self,
        GroceryItem.self,
        GroceryItemSource.self,
        PantryItem.self,
      containerIdentifier: containerIdentifier,
      startImmediately: startImmediately
    )
  }

  public static func startIfManuallyEnabled() async -> StartResult {
    guard isManuallyEnabled()
    else { return .disabled }

    do {
      let accountStatus = try await CKContainer(identifier: containerIdentifier).accountStatus()
      guard accountStatus == .available
      else { return .unavailable(accountStatus.syncDescription) }

      @Dependency(\.defaultSyncEngine) var syncEngine
      try await syncEngine.start()
      return .started
    } catch {
      return .failed(String(describing: error))
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
    guard isManuallyEnabled(defaults: defaults, environment: environment, arguments: arguments)
    else { return .disabled }

    do {
      let database: any DatabaseWriter
      if let providedDatabase {
        database = providedDatabase
      } else {
        @Dependency(\.defaultDatabase) var defaultDatabase
        database = defaultDatabase
      }
      let pendingChangeCount = try await pendingRecordZoneChangeCount(in: database)
      guard pendingChangeCount > 0
      else { return .noPendingChanges }

      let accountStatus: CKAccountStatus
      if let providedAccountStatus {
        accountStatus = try await providedAccountStatus()
      } else {
        accountStatus = try await CKContainer(identifier: containerIdentifier).accountStatus()
      }
      guard accountStatus == .available
      else { return .unavailable(accountStatus.syncDescription) }

      if let stopSyncEngine {
        stopSyncEngine()
      } else {
        @Dependency(\.defaultSyncEngine) var syncEngine
        syncEngine.stop()
      }
      if let startSyncEngine {
        try await startSyncEngine()
      } else {
        @Dependency(\.defaultSyncEngine) var syncEngine
        try await syncEngine.start()
      }
      return .restarted
    } catch {
      return .failed(String(describing: error))
    }
  }

  public static func pendingRecordZoneChangeCount(in database: any DatabaseWriter) async throws -> Int {
    try await database.read { db in
      try pendingRecordZoneChangeCount(in: db)
    }
  }

  public static func pendingRecordZoneChangeCount(in db: Database) throws -> Int {
    try #sql(
      """
      SELECT COUNT(*)
      FROM "sqlitedata_icloud"."sqlitedata_icloud_pendingRecordZoneChanges"
      """,
      as: Int.self
    )
    .fetchOne(db) ?? 0
  }

  public static func waitForPendingRecordZoneChanges(
    in database: any DatabaseWriter,
    exceeding previousCount: Int,
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(25)
  ) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while true {
      let currentCount = try await pendingRecordZoneChangeCount(in: database)
      if currentCount > previousCount {
        return true
      }
      guard clock.now < deadline else {
        return false
      }
      try await Task.sleep(for: pollInterval)
    }
  }
}

private extension CKAccountStatus {
  var syncDescription: String {
    switch self {
    case .available:
      "available"
    case .couldNotDetermine:
      "couldNotDetermine"
    case .noAccount:
      "noAccount"
    case .restricted:
      "restricted"
    case .temporarilyUnavailable:
      "temporarilyUnavailable"
    @unknown default:
      "unknown"
    }
  }
}
