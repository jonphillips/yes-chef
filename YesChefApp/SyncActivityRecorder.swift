import Dependencies
import Foundation
import Observation
import SQLiteData
import YesChefCore

struct SyncActivitySource {
  var isEnabled: () -> Bool
  var isFetching: () -> Bool
  var counts: (() async throws -> [String: Int])?
}

private actor SyncActivityLedgerWriter {
  private var latestGeneration: UInt64 = 0

  func save(_ ledger: SyncActivityLedger, to url: URL, generation: UInt64) throws {
    guard generation > latestGeneration else { return }
    latestGeneration = generation
    try SyncActivityLedgerFile.save(ledger, to: url)
  }
}

@MainActor
@Observable
final class SyncActivityRecorder {
  private static let pollInterval = Duration.seconds(1)
  private static let countInterval: TimeInterval = 30 // The brief caps COUNT(*) at once per 30 seconds.
  private static let sampleInterval: TimeInterval = 5 * 60 // Five minutes × 60 seconds per minute.
  // An hour is 60 minutes × 60 seconds per minute.
  static let hourWindow: TimeInterval = 60 * 60
  // A day is 24 hours.
  static let dayWindow: TimeInterval = 24 * hourWindow

  private(set) var ledger = SyncActivityLedger()
  private(set) var latestCounts: [RecordCount] = []

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var syncEngine
  @ObservationIgnored private let source: SyncActivitySource?
  @ObservationIgnored private let ledgerURL: URL?
  @ObservationIgnored private let ledgerWriter = SyncActivityLedgerWriter()
  @ObservationIgnored private var monitorTask: Task<Void, Never>?
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private var saveGeneration: UInt64 = 0
  @ObservationIgnored private var didLaunchRecord = false
  @ObservationIgnored private var wasEnabled = false
  @ObservationIgnored private var previousFetching = false
  @ObservationIgnored private var lastCountedAt: Date?
  @ObservationIgnored private var lastSampledAt: Date?
  @ObservationIgnored private var lastSceneWasForeground: Bool?

  init(source: SyncActivitySource? = nil, ledgerURL: URL? = nil) {
    self.source = source
    self.ledgerURL = ledgerURL ?? Self.liveLedgerURL()
    if let ledgerURL = self.ledgerURL, FileManager.default.fileExists(atPath: ledgerURL.path) {
      do {
        ledger = try SyncActivityLedgerFile.load(from: ledgerURL)
        latestCounts = Self.displayCounts(ledger.entries.last?.tableCounts ?? [:])
      } catch {
        AppLog.sync.warning("Could not decode sync activity ledger; starting a new log: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  deinit { monitorTask?.cancel() }

  func start() {
    guard monitorTask == nil else { return }
    monitorTask = Task { [weak self] in
      guard let self else { return }
      await poll(now: Date())
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.pollInterval)
        guard !Task.isCancelled else { return }
        await poll(now: Date())
      }
    }
  }

  func scenePhaseChanged(isForeground: Bool, now: Date = Date()) async {
    guard isEnabled() else { return }
    if !didLaunchRecord { await begin(now: now) }
    guard lastSceneWasForeground != isForeground else { return }
    lastSceneWasForeground = isForeground
    await record(isForeground ? .foreground : .background, now: now)
  }

  /// One poll is exposed internally so app-target tests can drive state transitions without
  /// waiting on a real CloudKit engine or wall-clock timer.
  func poll(now: Date) async {
    guard isEnabled() else {
      wasEnabled = false
      previousFetching = false
      return
    }
    if !didLaunchRecord { await begin(now: now) }
    if !wasEnabled {
      wasEnabled = true
      previousFetching = false
    }

    let fetching = isFetching()
    if fetching != previousFetching {
      previousFetching = fetching
      await record(fetching ? .fetchStarted : .fetchEnded, now: now)
      if fetching { lastSampledAt = now }
    } else if fetching, let lastSampledAt,
              now.timeIntervalSince(lastSampledAt) >= Self.sampleInterval {
      self.lastSampledAt = now
      await record(.sample, now: now)
    }
  }

  var lastArrival: Date? { ledger.lastArrival }
  func rowsArrived(in interval: TimeInterval, now: Date = Date()) -> Int {
    ledger.rowsArrived(since: now.addingTimeInterval(-interval))
  }
  func fetchSummary(in interval: TimeInterval, now: Date = Date()) -> (total: Int, empty: Int) {
    ledger.fetchSummary(since: now.addingTimeInterval(-interval))
  }

  func flushPendingSave() async {
    await pendingSave?.value
  }

  private func begin(now: Date) async {
    didLaunchRecord = true
    await record(.launch, now: now)
  }

  private func isEnabled() -> Bool {
    source?.isEnabled() ?? YesChefCloudSync.isManuallyEnabled()
  }

  private func isFetching() -> Bool {
    source?.isFetching() ?? (syncEngine.isRunning && syncEngine.isFetchingChanges)
  }

  private func record(_ kind: SyncActivityLedger.Kind, now: Date) async {
    let counts: [String: Int]
    let alwaysCount = kind == .fetchStarted || kind == .fetchEnded || kind == .sample
    if alwaysCount || (lastCountedAt.map { now.timeIntervalSince($0) >= Self.countInterval } ?? true) {
      do {
        counts = try await readCounts()
        lastCountedAt = now
      } catch {
        AppLog.sync.warning("Could not count synced rows: \(error.localizedDescription, privacy: .public)")
        counts = ledger.entries.last?.tableCounts ?? [:]
      }
    } else {
      counts = ledger.entries.last?.tableCounts ?? [:]
    }

    let previous = ledger.entries.last
    if kind == .sample, previous?.tableCounts == counts { return }
    let entry = SyncActivityLedger.Entry(date: now, kind: kind, tableCounts: counts)
    ledger.append(entry)
    latestCounts = Self.displayCounts(counts)
    let delta = entry.totalCount - (previous?.totalCount ?? entry.totalCount)
    let tableDeltas = counts.keys.sorted().compactMap { table -> String? in
      let change = counts[table, default: 0] - (previous?.tableCounts[table, default: 0] ?? counts[table, default: 0])
      guard change != 0 else { return nil }
      return "\(table)\(change > 0 ? "+" : "")\(change)"
    }.joined(separator: ",")
    let suffix = tableDeltas.isEmpty ? "" : " \(tableDeltas)"
    AppLog.sync.notice("sync-activity \(kind.rawValue, privacy: .public) total=\(entry.totalCount, privacy: .public) delta=\(delta, privacy: .public)\(suffix, privacy: .public)")
    scheduleSave()
  }

  private func scheduleSave() {
    guard let ledgerURL else { return }
    saveGeneration &+= 1
    let generation = saveGeneration
    let snapshot = ledger
    let writer = ledgerWriter
    let previousSave = pendingSave
    pendingSave = Task.detached {
      await previousSave?.value
      do {
        try await writer.save(snapshot, to: ledgerURL, generation: generation)
      } catch {
        AppLog.sync.warning("Could not save sync activity ledger: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func readCounts() async throws -> [String: Int] {
    if let count = source?.counts { return try await count() }
    return try await database.read { db in
      try YesChefCloudSync.syncedTables.recordTypes.reduce(into: [:]) { result, table in
        let escaped = table.replacingOccurrences(of: "\"", with: "\"\"")
        result[table] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \"\(escaped)\"") ?? 0
      }
    }
  }

  nonisolated private static func displayCounts(_ counts: [String: Int]) -> [RecordCount] {
    counts.keys.sorted().map { RecordCount(name: $0, count: counts[$0, default: 0]) }
  }

  private static func liveLedgerURL() -> URL? {
    do {
      let directory = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      return SyncActivityLedgerFile.fileURL(applicationSupportDirectory: directory)
    } catch {
      AppLog.sync.warning("Could not resolve Application Support for sync activity; the ledger will remain in memory: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
