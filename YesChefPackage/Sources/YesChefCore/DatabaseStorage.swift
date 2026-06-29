import Foundation

public enum YesChefDatabaseStorage {
  public static let appGroupIdentifier = "group.com.jonphillips.yeschef"
  public static let databaseFileName = "SQLiteData.db"

  public enum StorageError: Error, Equatable, LocalizedError {
    case missingAppGroupContainer(String)

    public var errorDescription: String? {
      switch self {
      case let .missingAppGroupContainer(identifier):
        "Could not locate the app group container for \(identifier)."
      }
    }
  }

  public static func sharedDatabaseURL(appGroupContainerURL: URL) -> URL {
    appGroupContainerURL.appendingPathComponent(databaseFileName, isDirectory: false)
  }

  public static func legacyDatabaseURL(applicationSupportDirectory: URL) -> URL {
    applicationSupportDirectory.appendingPathComponent(databaseFileName, isDirectory: false)
  }

  public static func liveSharedDatabaseURL(fileManager: FileManager = .default) throws -> URL {
    guard
      let appGroupContainerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      )
    else {
      throw StorageError.missingAppGroupContainer(appGroupIdentifier)
    }
    return sharedDatabaseURL(appGroupContainerURL: appGroupContainerURL)
  }

  public static func liveLegacyDatabaseURL(fileManager: FileManager = .default) throws -> URL {
    // The legacy .path checks match SQLiteData's .absoluteString default only because Apple's libsqlite3 enables URI filenames; revisit if GRDB/SQLiteData URI handling changes.
    let applicationSupportDirectory = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return legacyDatabaseURL(applicationSupportDirectory: applicationSupportDirectory)
  }

  public static func prepareLiveSharedStore(fileManager: FileManager = .default) throws -> URL {
    let sharedDatabaseURL = try liveSharedDatabaseURL(fileManager: fileManager)
    let legacyDatabaseURL = try liveLegacyDatabaseURL(fileManager: fileManager)
    try migrateLegacyDatabaseIfNeeded(
      from: legacyDatabaseURL,
      to: sharedDatabaseURL,
      fileManager: fileManager
    )
    return sharedDatabaseURL
  }

  public static func migrateLegacyDatabaseIfNeeded(
    from legacyDatabaseURL: URL,
    to sharedDatabaseURL: URL,
    fileManager: FileManager = .default
  ) throws {
    let sharedDirectoryURL = sharedDatabaseURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: sharedDirectoryURL,
      withIntermediateDirectories: true
    )

    guard
      fileManager.fileExists(atPath: legacyDatabaseURL.path),
      !fileManager.fileExists(atPath: sharedDatabaseURL.path)
    else { return }

    try moveStoreFile(
      from: legacyDatabaseURL,
      to: sharedDatabaseURL,
      fileManager: fileManager
    )
    for suffix in ["-wal", "-shm"] {
      try moveStoreFile(
        from: URL(fileURLWithPath: legacyDatabaseURL.path + suffix),
        to: URL(fileURLWithPath: sharedDatabaseURL.path + suffix),
        fileManager: fileManager
      )
    }
  }

  private static func moveStoreFile(
    from sourceURL: URL,
    to destinationURL: URL,
    fileManager: FileManager
  ) throws {
    guard
      fileManager.fileExists(atPath: sourceURL.path),
      !fileManager.fileExists(atPath: destinationURL.path)
    else { return }

    try fileManager.moveItem(at: sourceURL, to: destinationURL)
  }
}
