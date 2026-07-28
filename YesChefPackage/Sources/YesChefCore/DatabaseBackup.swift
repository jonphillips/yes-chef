import Dependencies
import Foundation
import Observation
import SQLiteData

public enum YesChefDatabaseBackup {
  public enum BackupError: Error, LocalizedError {
    case destinationAlreadyExists(URL)

    public var errorDescription: String? {
      switch self {
      case let .destinationAlreadyExists(url):
        "A backup already exists at \(url.lastPathComponent)."
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

  private static func stampSchemaVersion(on snapshotURL: URL) throws -> Int {
    let snapshotDatabase = try DatabaseQueue(path: snapshotURL.path)
    return try snapshotDatabase.write { db in
      let schemaVersion = try Int.fetchOne(db, sql: #"SELECT COUNT(*) FROM "grdb_migrations""#) ?? 0
      try db.execute(sql: "PRAGMA user_version = \(schemaVersion)")
      return schemaVersion
    }
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
