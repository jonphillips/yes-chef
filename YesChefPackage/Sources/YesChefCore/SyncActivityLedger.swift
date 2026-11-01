import Foundation

public struct SyncActivityLedger: Codable, Equatable, Sendable {
  public static let maximumEntries = 1_000

  public enum Kind: String, Codable, CaseIterable, Sendable {
    case launch
    case foreground
    case background
    case fetchStarted
    case fetchEnded
    case sample
  }

  public struct Entry: Codable, Equatable, Sendable {
    public var date: Date
    public var kind: Kind
    public var totalCount: Int
    public var tableCounts: [String: Int]

    public init(date: Date, kind: Kind, tableCounts: [String: Int]) {
      self.date = date
      self.kind = kind
      self.tableCounts = tableCounts
      self.totalCount = tableCounts.values.reduce(0, +)
    }
  }

  public private(set) var entries: [Entry]
  public private(set) var startedAt: Date?
  public private(set) var rowsSinceStart: Int

  public init(entries: [Entry] = []) {
    self.entries = Array(entries.suffix(Self.maximumEntries))
    self.startedAt = entries.first?.date
    self.rowsSinceStart = entries.indices.dropFirst().reduce(into: 0) { total, index in
      total += max(0, entries[index].totalCount - entries[index - 1].totalCount)
    }
  }

  public mutating func append(_ entry: Entry) {
    if startedAt == nil { startedAt = entry.date }
    if let previous = entries.last {
      rowsSinceStart += max(0, entry.totalCount - previous.totalCount)
    }
    entries.append(entry)
    if entries.count > Self.maximumEntries {
      entries.removeFirst(entries.count - Self.maximumEntries)
    }
  }

  public var lastArrival: Date? {
    guard entries.count > 1 else { return nil }
    return entries.indices.dropFirst().reversed().first(where: { entries[$0].totalCount > entries[$0 - 1].totalCount })
      .map { entries[$0].date }
  }

  public func rowsArrived(since date: Date) -> Int {
    guard entries.count > 1 else { return 0 }
    return entries.indices.dropFirst().reduce(into: 0) { total, index in
      guard entries[index].date >= date else { return }
      total += max(0, entries[index].totalCount - entries[index - 1].totalCount)
    }
  }

  public func fetchSummary(since date: Date) -> (total: Int, empty: Int) {
    let fetchIndices = entries.indices.filter { entries[$0].kind == .fetchEnded && entries[$0].date >= date }
    return (fetchIndices.count, fetchIndices.filter { index in
      guard let startIndex = (0..<index).reversed().first(where: { entries[$0].kind == .fetchStarted }) else {
        return true
      }
      return entries[index].totalCount <= entries[startIndex].totalCount
    }.count)
  }

  public var csv: String {
    let tables = Set(entries.flatMap { $0.tableCounts.keys }).sorted()
    let header = ["date", "kind", "total"] + tables
    let dateFormatter = ISO8601DateFormatter()
    let rows = entries.map { entry in
      [Self.csvField(dateFormatter.string(from: entry.date)), entry.kind.rawValue, String(entry.totalCount)] +
        tables.map { String(entry.tableCounts[$0, default: 0]) }
    }
    return ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n")
  }

  private static func csvField(_ value: String) -> String {
    guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

public enum SyncActivityLedgerFile {
  public static let fileName = "SyncActivityLedger.json"

  public static func fileURL(applicationSupportDirectory: URL) -> URL {
    applicationSupportDirectory.appendingPathComponent(fileName, isDirectory: false)
  }

  public static func load(from url: URL) throws -> SyncActivityLedger {
    try JSONDecoder().decode(SyncActivityLedger.self, from: Data(contentsOf: url))
  }

  public static func save(_ ledger: SyncActivityLedger, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONEncoder().encode(ledger)
    try data.write(to: url, options: .atomic)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(values)
  }
}
