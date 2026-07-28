import Dependencies
import Foundation
import Observation
import SQLiteData

public enum YesChefDatabaseBackup {
  public enum BackupError: Error, LocalizedError {
    case destinationAlreadyExists(URL)
    case notYesChefBackup
    case invalidSchemaVersionMarker
    case backupIsNewerThanThisApp(backup: Int, current: Int)

    public var errorDescription: String? {
      switch self {
      case let .destinationAlreadyExists(url):
        "A backup already exists at \(url.lastPathComponent)."
      case .notYesChefBackup:
        "This file is not a Yes Chef backup."
      case .invalidSchemaVersionMarker:
        "This Yes Chef backup has an invalid schema version marker."
      case let .backupIsNewerThanThisApp(backup, current):
        "This backup uses schema version \(backup), but this app can restore through version \(current). Update Yes Chef before restoring it."
      }
    }
  }

  public struct Snapshot: Equatable, Sendable {
    public let fileURL: URL
    public let schemaVersion: Int

    public init(fileURL: URL, schemaVersion: Int) {
      self.fileURL = fileURL
      self.schemaVersion = schemaVersion
    }
  }

  public struct PreparedRestore: Equatable, Sendable {
    public let fileURL: URL
    public let schemaVersion: Int

    public init(fileURL: URL, schemaVersion: Int) {
      self.fileURL = fileURL
      self.schemaVersion = schemaVersion
    }
  }

  public static func defaultFilename(
    for date: Date,
    calendar: Calendar = .current
  ) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "YesChef-Backup-%04d-%02d-%02d.sqlite",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  /// Creates a self-contained snapshot using SQLite's consistent `VACUUM INTO` copy.
  public static func snapshot(
    from database: any DatabaseWriter,
    to destinationURL: URL,
    fileManager: FileManager = .default
  ) async throws -> Snapshot {
    guard !fileManager.fileExists(atPath: destinationURL.path) else {
      throw BackupError.destinationAlreadyExists(destinationURL)
    }

    var completed = false
    defer {
      if !completed {
        try? fileManager.removeItem(at: destinationURL)
      }
    }

    try await database.vacuum(into: destinationURL.path)
    let schemaVersion = try stampSchemaVersion(on: destinationURL)
    completed = true
    return Snapshot(fileURL: destinationURL, schemaVersion: schemaVersion)
  }

  /// The applied Yes Chef migration count. Migration registrations are append-only, so this is
  /// the restore compatibility version stamped on exported snapshots.
  public static func schemaVersion(in databaseURL: URL) throws -> Int {
    do {
      var configuration = Configuration()
      configuration.readonly = true
      let database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
      defer { try? database.close() }
      return try database.read { db in
        guard try databaseContainsRecipeSchema(db) else {
          throw BackupError.notYesChefBackup
        }
        return try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "grdb_migrations""#) ?? 0
      }
    } catch let error as BackupError {
      throw error
    } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
      throw BackupError.notYesChefBackup
    } catch {
      throw error
    }
  }

  /// Copies, validates, and forward-migrates a candidate. SQLiteData's sync bookkeeping is in a
  /// separate attached metadatabase, so `VACUUM INTO` never puts it in this main-store snapshot.
  /// The caller removes that live metadatabase after swapping the closed store.
  public static func prepareRestore(
    from sourceURL: URL,
    to stagingURL: URL,
    currentSchemaVersion: Int,
    migrate: @escaping @Sendable (URL) throws -> Void
  ) async throws -> PreparedRestore {
    try await Task.detached {
      try prepareRestoreSynchronously(
        from: sourceURL,
        to: stagingURL,
        currentSchemaVersion: currentSchemaVersion,
        migrate: migrate
      )
    }
    .value
  }

  /// Replaces a closed live store with a prepared restore. The main database file is replaced
  /// with `FileManager.replaceItemAt`, while all SQLite and CloudKit sidecars are discarded so
  /// the next bootstrap starts as a fresh local sync peer.
  public static func replaceLiveStore(
    at liveStoreURL: URL,
    with preparedRestore: PreparedRestore,
    syncMetadataURL: URL,
    fileManager: FileManager = .default
  ) throws {
    try removeSQLiteSidecars(for: preparedRestore.fileURL, fileManager: fileManager)
    _ = try fileManager.replaceItemAt(
      liveStoreURL,
      withItemAt: preparedRestore.fileURL,
      backupItemName: nil,
      options: []
    )
    try removeSQLiteSidecars(for: liveStoreURL, fileManager: fileManager)
    try removeDatabaseAndSQLiteSidecars(for: syncMetadataURL, fileManager: fileManager)
  }

  private static func stampSchemaVersion(on snapshotURL: URL) throws -> Int {
    let snapshotDatabase = try DatabaseQueue(path: snapshotURL.path)
    defer { try? snapshotDatabase.close() }
    let schemaVersion = try schemaVersion(in: snapshotURL)
    try snapshotDatabase.write { db in
      try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
    }
    return schemaVersion
  }

  private static func prepareRestoreSynchronously(
    from sourceURL: URL,
    to stagingURL: URL,
    currentSchemaVersion: Int,
    migrate: @escaping @Sendable (URL) throws -> Void,
    fileManager: FileManager = .default
  ) throws -> PreparedRestore {
    guard !fileManager.fileExists(atPath: stagingURL.path) else {
      throw BackupError.destinationAlreadyExists(stagingURL)
    }

    var completed = false
    defer {
      if !completed {
        try? fileManager.removeItem(at: stagingURL)
      }
    }

    try fileManager.copyItem(at: sourceURL, to: stagingURL)
    let backupSchemaVersion = try schemaVersion(in: stagingURL)
    let stampedSchemaVersion = try schemaVersionMarker(in: stagingURL)
    guard stampedSchemaVersion == backupSchemaVersion, backupSchemaVersion > 0 else {
      throw BackupError.invalidSchemaVersionMarker
    }
    guard backupSchemaVersion <= currentSchemaVersion else {
      throw BackupError.backupIsNewerThanThisApp(
        backup: backupSchemaVersion,
        current: currentSchemaVersion
      )
    }

    if backupSchemaVersion < currentSchemaVersion {
      try migrate(stagingURL)
    }
    let migratedSchemaVersion = try schemaVersion(in: stagingURL)
    guard migratedSchemaVersion == currentSchemaVersion else {
      throw BackupError.invalidSchemaVersionMarker
    }
    let stampedMigratedSchemaVersion = try stampSchemaVersion(on: stagingURL)
    guard stampedMigratedSchemaVersion == currentSchemaVersion else {
      throw BackupError.invalidSchemaVersionMarker
    }
    try checkpointPreparedStore(at: stagingURL)
    // `migrateRestoreCandidate` attaches a metadatabase while it opens the staging database;
    // remove that transient sidecar so only the main snapshot is eligible for the swap.
    try removeDatabaseAndSQLiteSidecars(
      for: YesChefDatabaseStorage.syncMetadataURL(
        for: stagingURL,
        containerIdentifier: YesChefCloudSync.containerIdentifier
      ),
      fileManager: fileManager
    )
    completed = true
    return PreparedRestore(fileURL: stagingURL, schemaVersion: migratedSchemaVersion)
  }

  private static func schemaVersionMarker(in databaseURL: URL) throws -> Int {
    do {
      var configuration = Configuration()
      configuration.readonly = true
      let database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
      defer { try? database.close() }
      return try database.read { db in
        try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
      }
    } catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB {
      throw BackupError.notYesChefBackup
    } catch {
      throw error
    }
  }

  private static func databaseContainsRecipeSchema(_ db: Database) throws -> Bool {
    let tableNames = try String.fetchAll(
      db,
      sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('grdb_migrations', 'recipes')"
    )
    return Set(tableNames) == Set(["grdb_migrations", "recipes"])
  }

  private static func checkpointPreparedStore(at databaseURL: URL) throws {
    let database = try DatabaseQueue(path: databaseURL.path)
    defer { try? database.close() }
    _ = try database.writeWithoutTransaction { db in
      try db.checkpoint(.truncate)
    }
  }

  private static func removeSQLiteSidecars(for databaseURL: URL, fileManager: FileManager) throws {
    for suffix in ["-wal", "-shm"] {
      let sidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
      guard fileManager.fileExists(atPath: sidecarURL.path) else { continue }
      try fileManager.removeItem(at: sidecarURL)
    }
  }

  private static func removeDatabaseAndSQLiteSidecars(
    for databaseURL: URL,
    fileManager: FileManager
  ) throws {
    if fileManager.fileExists(atPath: databaseURL.path) {
      try fileManager.removeItem(at: databaseURL)
    }
    try removeSQLiteSidecars(for: databaseURL, fileManager: fileManager)
  }
}

@MainActor
@Observable
public final class YesChefDatabaseBackupExportModel {
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  public private(set) var isPreparing = false
  public private(set) var errorMessage: String?

  public init() {}

  public func prepareBackupForExport() async -> YesChefDatabaseBackup.Snapshot? {
    guard !isPreparing else { return nil }

    isPreparing = true
    defer { isPreparing = false }

    let stagingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChef-Backup-\(uuid().uuidString).sqlite", isDirectory: false)

    do {
      let snapshot = try await YesChefDatabaseBackup.snapshot(from: database, to: stagingURL)
      errorMessage = nil
      return snapshot
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  public func defaultFilename() -> String {
    YesChefDatabaseBackup.defaultFilename(for: now)
  }

  public func discard(_ snapshot: YesChefDatabaseBackup.Snapshot) {
    try? FileManager.default.removeItem(at: snapshot.fileURL)
  }

  public func recordExportFailure(_ error: any Error) {
    errorMessage = error.localizedDescription
  }

  public func dismissError() {
    errorMessage = nil
  }
}

@MainActor
@Observable
public final class YesChefDatabaseBackupRestoreModel {
  private static let preRestoreDirectoryName = "Pre-Restore Backups"
  private static let preRestoreDefaultsKey = "YesChefDatabaseBackupLastPreRestorePath"
  private static let preRestoreFilenamePrefix = "YesChef-PreRestore-"
  private static let stagingFilenamePrefix = "YesChef-Restore-"

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var syncEngine
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  public private(set) var preparedRestore: YesChefDatabaseBackup.PreparedRestore?
  public private(set) var isPreparing = false
  public private(set) var isRestoring = false
  public private(set) var errorMessage: String?
  public private(set) var hasUndoableRestore = false

  public init() {
    hasUndoableRestore = Self.lastPreRestoreURL != nil
  }

  public var isPrepared: Bool {
    get { preparedRestore != nil }
    set {
      guard !newValue else { return }
      discardPreparedRestore()
    }
  }

  public var isErrorPresented: Bool {
    get { errorMessage != nil }
    set {
      guard !newValue else { return }
      dismissError()
    }
  }

  public func prepareRestore(from sourceURL: URL) async {
    guard !isPreparing, !isRestoring else { return }

    isPreparing = true
    defer { isPreparing = false }
    let accessedSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if accessedSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      discardPreparedRestore()
      let liveStoreURL = try YesChefDatabaseStorage.liveSharedDatabaseURL()
      let workingDirectory = try restoreWorkingDirectory(for: liveStoreURL)
      discardStaleRestoreCandidates(in: workingDirectory)
      let stagingURL = workingDirectory.appendingPathComponent(
        "\(Self.stagingFilenamePrefix)\(uuid().uuidString).sqlite",
        isDirectory: false
      )
      preparedRestore = try await YesChefDatabaseBackup.prepareRestore(
        from: sourceURL,
        to: stagingURL,
        currentSchemaVersion: try YesChefDatabaseBackup.schemaVersion(in: liveStoreURL),
        migrate: DependencyValues.migrateRestoreCandidate(at:)
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Makes a new automatic safety snapshot, stops sync, and swaps in the already-validated
  /// candidate. The app must then be relaunched so its dependency-owned database connection opens
  /// the new file with sync disabled.
  public func restorePreparedBackup() async -> Bool {
    guard let preparedRestore, !isRestoring else { return false }

    isRestoring = true
    defer { isRestoring = false }
    var beganDatabaseClose = false

    do {
      let liveStoreURL = try YesChefDatabaseStorage.liveSharedDatabaseURL()
      let syncMetadataURL = try YesChefDatabaseStorage.attachedSyncMetadataURL(
        in: database,
        fallbackFor: liveStoreURL,
        containerIdentifier: YesChefCloudSync.containerIdentifier
      )
      let preRestoreURL = try makePreRestoreURL(for: liveStoreURL)
      _ = try await YesChefDatabaseBackup.snapshot(from: database, to: preRestoreURL)

      syncEngine.stop()
      beganDatabaseClose = true
      try database.close()
      try YesChefDatabaseBackup.replaceLiveStore(
        at: liveStoreURL,
        with: preparedRestore,
        syncMetadataURL: syncMetadataURL
      )
      YesChefCloudSync.disableForRestore()
      recordSuccessfulPreRestore(at: preRestoreURL)
      self.preparedRestore = nil
      errorMessage = nil
      return true
    } catch {
      discardPreparedRestore()
      errorMessage = beganDatabaseClose
        ? "Yes Chef could not finish the restore and must be reopened before you can keep using it. \(error.localizedDescription)"
        : error.localizedDescription
      return false
    }
  }

  public func prepareUndo() async {
    guard let lastPreRestoreURL else {
      errorMessage = "There is no automatic pre-restore backup to undo."
      return
    }
    await prepareRestore(from: lastPreRestoreURL)
  }

  public func discardPreparedRestore() {
    guard let preparedRestore else { return }
    try? FileManager.default.removeItem(at: preparedRestore.fileURL)
    self.preparedRestore = nil
  }

  public func dismissError() {
    errorMessage = nil
  }

  public func recordImportFailure(_ error: any Error) {
    errorMessage = error.localizedDescription
  }

  private func restoreWorkingDirectory(for liveStoreURL: URL) throws -> URL {
    let directoryURL = liveStoreURL
      .deletingLastPathComponent()
      .appendingPathComponent(Self.preRestoreDirectoryName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    return directoryURL
  }

  private func makePreRestoreURL(for liveStoreURL: URL) throws -> URL {
    let directoryURL = try restoreWorkingDirectory(for: liveStoreURL)
    return directoryURL.appendingPathComponent(
      "\(Self.preRestoreFilenamePrefix)\(uuid().uuidString).sqlite",
      isDirectory: false
    )
  }

  private func discardStaleRestoreCandidates(in directoryURL: URL) {
    let candidatePrefixes = [Self.stagingFilenamePrefix, ".\(Self.stagingFilenamePrefix)"]
    for fileURL in (try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil
    )) ?? [] where candidatePrefixes.contains(where: fileURL.lastPathComponent.hasPrefix) {
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  private func recordSuccessfulPreRestore(at preRestoreURL: URL) {
    let directoryURL = preRestoreURL.deletingLastPathComponent()
    let preRestoreURLs = (try? FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: nil
    )) ?? []
    for fileURL in preRestoreURLs where
      fileURL != preRestoreURL && fileURL.lastPathComponent.hasPrefix(Self.preRestoreFilenamePrefix)
    {
      try? FileManager.default.removeItem(at: fileURL)
    }
    UserDefaults.standard.set(preRestoreURL.path, forKey: Self.preRestoreDefaultsKey)
    hasUndoableRestore = true
  }

  private var lastPreRestoreURL: URL? {
    Self.lastPreRestoreURL
  }

  private static var lastPreRestoreURL: URL? {
    guard
      let path = UserDefaults.standard.string(forKey: preRestoreDefaultsKey),
      FileManager.default.fileExists(atPath: path)
    else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }
}
