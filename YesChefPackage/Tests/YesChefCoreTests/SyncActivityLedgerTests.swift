import Foundation
import Testing
import YesChefCore

@Suite
struct SyncActivityLedgerTests {
  @Test
  func appendKeepsOnlyNewestThousandEntries() {
    var ledger = SyncActivityLedger()
    for second in 0..<1_005 {
      ledger.append(.init(
        date: Date(timeIntervalSince1970: TimeInterval(second)),
        kind: .sample,
        tableCounts: ["recipes": second]
      ))
    }
    #expect(ledger.entries.count == 1_000)
    #expect(ledger.entries.first?.date == Date(timeIntervalSince1970: 5))
    #expect(ledger.rowsSinceStart == 1_004)
  }

  @Test
  func lastArrivalSkipsEntriesWithoutGrowth() {
    let base = Date(timeIntervalSince1970: 1_000)
    let ledger = SyncActivityLedger(entries: [
      .init(date: base, kind: .launch, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(10), kind: .sample, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(20), kind: .fetchEnded, tableCounts: ["recipes": 12]),
      .init(date: base.addingTimeInterval(30), kind: .sample, tableCounts: ["recipes": 12]),
    ])
    #expect(ledger.lastArrival == base.addingTimeInterval(20))
  }

  @Test
  func arrivalWindowsCountOnlyGrowthAfterBoundary() {
    let now = Date(timeIntervalSince1970: 10_000)
    let ledger = SyncActivityLedger(entries: [
      .init(date: now.addingTimeInterval(-90_000), kind: .launch, tableCounts: ["recipes": 100]),
      .init(date: now.addingTimeInterval(-86_399), kind: .fetchEnded, tableCounts: ["recipes": 105]),
      .init(date: now.addingTimeInterval(-3_600), kind: .fetchEnded, tableCounts: ["recipes": 108]),
      .init(date: now, kind: .sample, tableCounts: ["recipes": 110]),
    ])
    #expect(ledger.rowsArrived(since: now.addingTimeInterval(-3_600)) == 5)
    #expect(ledger.rowsArrived(since: now.addingTimeInterval(-86_400)) == 10)
    #expect(ledger.rowsSinceStart == 10)
  }

  @Test
  func fetchSummaryCountsFetchesWithNoGrowth() {
    let base = Date(timeIntervalSince1970: 1_000)
    let ledger = SyncActivityLedger(entries: [
      .init(date: base, kind: .launch, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(1), kind: .fetchStarted, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(2), kind: .fetchEnded, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(3), kind: .fetchStarted, tableCounts: ["recipes": 10]),
      .init(date: base.addingTimeInterval(4), kind: .fetchEnded, tableCounts: ["recipes": 12]),
    ])
    let summary = ledger.fetchSummary(since: base)
    #expect(summary.total == 2)
    #expect(summary.empty == 1)
  }

  @Test
  func csvHasHeaderAndEachTableColumn() {
    let ledger = SyncActivityLedger(entries: [
      .init(date: Date(timeIntervalSince1970: 1), kind: .launch, tableCounts: ["recipes": 4, "menus": 2]),
    ])
    #expect(ledger.csv.split(separator: "\n").first == "date,kind,total,menus,recipes")
    #expect(ledger.csv.contains(",launch,6,2,4"))
  }

  @Test
  func jsonRoundTripsAndCorruptFileIsRejected() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = SyncActivityLedgerFile.fileURL(applicationSupportDirectory: directory)
    let ledger = SyncActivityLedger(entries: [
      .init(date: Date(timeIntervalSince1970: 42), kind: .launch, tableCounts: ["recipes": 3]),
    ])
    try SyncActivityLedgerFile.save(ledger, to: file)
    #expect(try SyncActivityLedgerFile.load(from: file) == ledger)
    try Data("not-json".utf8).write(to: file)
    #expect(throws: (any Error).self) { try SyncActivityLedgerFile.load(from: file) }
  }
}
