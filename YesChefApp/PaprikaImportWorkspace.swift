import Foundation
import YesChefCore
import ZIPFoundation
import zlib

enum PaprikaImportWorkspace {
  static func parseExport(from sourceURL: URL) async throws -> PaprikaHTMLImportResult {
    try await Task.detached(priority: .userInitiated) {
      let sourceURL = try copySecurityScopedFileToTemporaryLocation(sourceURL, preferredExtension: "zip")
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

  static func parseRecipeBackup(from sourceURL: URL) async throws -> PaprikaRecipeBackupParseResult {
    try await Task.detached(priority: .userInitiated) {
      let sourceURL = try copySecurityScopedFileToTemporaryLocation(
        sourceURL,
        preferredExtension: "paprikarecipes"
      )
      defer { try? FileManager.default.removeItem(at: sourceURL) }

      let archive = try Archive(url: sourceURL, accessMode: .read)
      let decoder = JSONDecoder()
      let dateFormatter = paprikaBackupCreatedDateFormatter()
      var records: [PaprikaRecipeBackupRecord] = []
      var skippedEntryCount = 0

      for entry in archive where entry.type == .file && entry.path.hasSuffix(".paprikarecipe") {
        do {
          var compressedData = Data()
          _ = try archive.extract(entry, skipCRC32: true) { chunk in
            compressedData.append(chunk)
          }
          let payload = try decoder.decode(
            PaprikaRecipeBackupPayload.self,
            from: compressedData.gunzipped()
          )
          guard
            let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty,
            let createdText = payload.created,
            let created = dateFormatter.date(from: createdText)
          else {
            skippedEntryCount += 1
            continue
          }
          records.append(
            PaprikaRecipeBackupRecord(
              name: name,
              sourceName: payload.source,
              sourceURL: payload.sourceURL,
              created: created
            )
          )
        } catch {
          skippedEntryCount += 1
        }
      }

      guard !records.isEmpty else { throw PaprikaImportUIError.backupArchiveEmpty }
      return PaprikaRecipeBackupParseResult(records: records, skippedEntryCount: skippedEntryCount)
    }.value
  }

  private static func copySecurityScopedFileToTemporaryLocation(
    _ sourceURL: URL,
    preferredExtension: String
  ) throws -> URL {
    let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessing {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    let destinationURL = fileManager.temporaryDirectory
      .appendingPathComponent("PaprikaImport-\(UUID().uuidString)")
      .appendingPathExtension(preferredExtension)
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

  private static func paprikaBackupCreatedDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.timeZone = .current
    return formatter
  }
}

private struct PaprikaRecipeBackupPayload: Decodable {
  var name: String?
  var source: String?
  var sourceURL: String?
  var created: String?

  enum CodingKeys: String, CodingKey {
    case name
    case source
    case sourceURL = "source_url"
    case created
  }
}

private extension Data {
  func gunzipped() throws -> Data {
    var stream = z_stream()
    let initStatus = inflateInit2_(
      &stream,
      16 + MAX_WBITS,
      ZLIB_VERSION,
      Int32(MemoryLayout<z_stream>.size)
    )
    guard initStatus == Z_OK else { throw GzipError.initializationFailed(initStatus) }
    defer { inflateEnd(&stream) }

    var output = Data()
    output.reserveCapacity(count * 2)

    let status = try withUnsafeBytes { inputBuffer -> Int32 in
      guard let inputBaseAddress = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
        return Z_STREAM_END
      }
      stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBaseAddress)
      stream.avail_in = uInt(count)

      var status = Z_OK
      while status != Z_STREAM_END {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        status = buffer.withUnsafeMutableBufferPointer { outputBuffer in
          stream.next_out = outputBuffer.baseAddress
          stream.avail_out = uInt(outputBuffer.count)
          return inflate(&stream, Z_NO_FLUSH)
        }
        guard status == Z_OK || status == Z_STREAM_END else {
          throw GzipError.inflateFailed(status)
        }
        let producedByteCount = buffer.count - Int(stream.avail_out)
        output.append(buffer, count: producedByteCount)
      }
      return status
    }

    guard status == Z_STREAM_END else { throw GzipError.incompleteStream(status) }
    return output
  }
}

private enum GzipError: LocalizedError {
  case initializationFailed(Int32)
  case inflateFailed(Int32)
  case incompleteStream(Int32)

  var errorDescription: String? {
    switch self {
    case let .initializationFailed(status):
      "Could not initialize Paprika backup decompression (\(status))."
    case let .inflateFailed(status):
      "Could not decompress a Paprika backup recipe (\(status))."
    case let .incompleteStream(status):
      "Paprika backup decompression ended before the recipe was complete (\(status))."
    }
  }
}

enum PaprikaImportUIError: LocalizedError {
  case exportRootNotFound
  case backupArchiveEmpty

  var errorDescription: String? {
    switch self {
    case .exportRootNotFound:
      "Could not find a Paprika HTML export folder in the selected ZIP."
    case .backupArchiveEmpty:
      "Could not find readable recipes in the selected Paprika backup."
    }
  }
}
