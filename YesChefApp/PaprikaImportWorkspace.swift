import Foundation
import YesChefCore
import ZIPFoundation

enum PaprikaImportWorkspace {
  static func parseExport(from sourceURL: URL) async throws -> PaprikaHTMLImportResult {
    try await Task.detached(priority: .userInitiated) {
      let sourceURL = try copySecurityScopedFileToTemporaryLocation(sourceURL)
      let fileManager = FileManager.default
      let workspaceURL = fileManager.temporaryDirectory
        .appendingPathComponent("YesChefPaprikaImport-\(UUID().uuidString)", isDirectory: true)
      try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
      defer {
        try? fileManager.removeItem(at: workspaceURL)
        try? fileManager.removeItem(at: sourceURL)
      }

      let unzippedURL = workspaceURL.appendingPathComponent("unzipped", isDirectory: true)
      try fileManager.createDirectory(at: unzippedURL, withIntermediateDirectories: true)
      try fileManager.unzipItem(at: sourceURL, to: unzippedURL)
      let exportURL = try locatePaprikaExportRoot(in: unzippedURL, fileManager: fileManager)
      return try PaprikaHTMLImporter.parseExport(at: exportURL, fileManager: fileManager)
    }.value
  }

  private static func copySecurityScopedFileToTemporaryLocation(_ sourceURL: URL) throws -> URL {
    let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessing {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    let destinationURL = fileManager.temporaryDirectory
      .appendingPathComponent("PaprikaExport-\(UUID().uuidString)")
      .appendingPathExtension("zip")
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
    return destinationURL
  }

  private static func locatePaprikaExportRoot(
    in directoryURL: URL,
    fileManager: FileManager
  ) throws -> URL {
    if isPaprikaExportRoot(directoryURL, fileManager: fileManager) {
      return directoryURL
    }

    let childURLs = try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )
    if let match = childURLs.first(where: { isPaprikaExportRoot($0, fileManager: fileManager) }) {
      return match
    }

    throw PaprikaImportUIError.exportRootNotFound
  }

  private static func isPaprikaExportRoot(_ url: URL, fileManager: FileManager) -> Bool {
    fileManager.fileExists(atPath: url.appendingPathComponent("index.html").path)
      && fileManager.fileExists(atPath: url.appendingPathComponent("Recipes", isDirectory: true).path)
  }
}

enum PaprikaImportUIError: LocalizedError {
  case exportRootNotFound

  var errorDescription: String? {
    switch self {
    case .exportRootNotFound:
      "Could not find a Paprika HTML export folder in the selected ZIP."
    }
  }
}
