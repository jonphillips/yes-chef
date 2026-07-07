import Dependencies
import Foundation

/// A cached Compare alignment plus the content fingerprint it was computed for. The fingerprint lets a
/// reader tell whether the alignment still matches the recipes as currently written, or has gone stale
/// behind an ingredient edit (see `CompareAlignmentKey`).
public struct CachedCompareAlignment: Sendable, Equatable, Codable {
  public var contentSignature: String
  public var outcome: WorkbenchAlignedComparison

  public init(contentSignature: String, outcome: WorkbenchAlignedComparison) {
    self.contentSignature = contentSignature
    self.outcome = outcome
  }
}

public struct CompareAlignmentCacheClient: Sendable {
  public var load: @Sendable (_ identity: String) async throws -> CachedCompareAlignment?
  public var save: @Sendable (_ identity: String, _ record: CachedCompareAlignment) async throws -> Void

  public init(
    load: @escaping @Sendable (_ identity: String) async throws -> CachedCompareAlignment?,
    save: @escaping @Sendable (_ identity: String, _ record: CachedCompareAlignment) async throws -> Void
  ) {
    self.load = load
    self.save = save
  }
}

extension CompareAlignmentCacheClient: DependencyKey {
  public static var liveValue: CompareAlignmentCacheClient {
    let store = CompareAlignmentCacheStore.live()
    return CompareAlignmentCacheClient(
      load: { identity in
        try await store.load(identity: identity)
      },
      save: { identity, record in
        try await store.save(record, identity: identity)
      }
    )
  }

  public static var testValue: CompareAlignmentCacheClient {
    let store = InMemoryCompareAlignmentCacheStore()
    return CompareAlignmentCacheClient(
      load: { identity in
        await store.load(identity: identity)
      },
      save: { identity, record in
        await store.save(record, identity: identity)
      }
    )
  }
}

extension DependencyValues {
  public var compareAlignmentCache: CompareAlignmentCacheClient {
    get { self[CompareAlignmentCacheClient.self] }
    set { self[CompareAlignmentCacheClient.self] = newValue }
  }
}

/// Device-local, LRU-bounded disk cache for Compare alignments. `internal` (not `private`) so the LRU
/// and cold-start-persistence behavior can be unit-tested directly against a temp directory.
actor CompareAlignmentCacheStore {
  private static let directoryName = "YesChef"
  private static let fileName = "WorkbenchCompareAlignmentCache.json"

  private let fileURL: URL?
  private let maxEntries: Int

  private var didLoad = false
  private var entries: [String: CachedCompareAlignment] = [:]
  private var usageOrder: [String] = []

  static func live(
    fileManager: FileManager = .default,
    maxEntries: Int = 50
  ) -> CompareAlignmentCacheStore {
    CompareAlignmentCacheStore(
      fileURL: try? liveFileURL(fileManager: fileManager),
      maxEntries: maxEntries
    )
  }

  init(fileURL: URL?, maxEntries: Int) {
    self.fileURL = fileURL
    self.maxEntries = maxEntries
  }

  func load(identity: String) throws -> CachedCompareAlignment? {
    try loadStateIfNeeded()
    touch(identity)
    return entries[identity]
  }

  func save(_ record: CachedCompareAlignment, identity: String) throws {
    try loadStateIfNeeded()
    entries[identity] = record
    touch(identity)
    trimToBudget()
    try persist()
  }

  private func loadStateIfNeeded() throws {
    guard !didLoad else { return }
    didLoad = true

    guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
    let data = try Data(contentsOf: fileURL)
    entries = try JSONDecoder().decode([String: CachedCompareAlignment].self, from: data)
    usageOrder = entries.keys.sorted()
    trimToBudget()
  }

  private func touch(_ identity: String) {
    guard entries[identity] != nil else { return }
    usageOrder.removeAll { $0 == identity }
    usageOrder.append(identity)
  }

  private func trimToBudget() {
    let knownKeys = Set(entries.keys)
    usageOrder.removeAll { !knownKeys.contains($0) }
    for key in entries.keys where !usageOrder.contains(key) {
      usageOrder.append(key)
    }

    while entries.count > maxEntries, let evicted = usageOrder.first {
      usageOrder.removeFirst()
      entries.removeValue(forKey: evicted)
    }
  }

  private func persist() throws {
    guard let fileURL else { return }

    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let data = try JSONEncoder.cacheEncoder.encode(entries)
    try data.write(to: fileURL, options: .atomic)
  }

  private static func liveFileURL(fileManager: FileManager) throws -> URL {
    let applicationSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    return applicationSupportURL
      .appendingPathComponent(directoryName, isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
  }
}

private actor InMemoryCompareAlignmentCacheStore {
  private var entries: [String: CachedCompareAlignment] = [:]

  func load(identity: String) -> CachedCompareAlignment? {
    entries[identity]
  }

  func save(_ record: CachedCompareAlignment, identity: String) {
    entries[identity] = record
  }
}

private extension JSONEncoder {
  static var cacheEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
