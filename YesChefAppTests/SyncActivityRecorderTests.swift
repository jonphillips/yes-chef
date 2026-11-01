import Dependencies
import Foundation
import Testing
import YesChefCore
@testable import YesChef

@MainActor
@Suite
struct SyncActivityRecorderTests {
  @Test
  func fetchStateFlipsAreRecordedUsingInjectedSource() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let enabled = true
    var fetching = false
    var countCalls = 0
    let recorder = SyncActivityRecorder(
      source: SyncActivitySource(
        isEnabled: { enabled },
        isFetching: { fetching },
        counts: {
          countCalls += 1
          return ["recipes": countCalls <= 2 ? 10 : 12]
        }
      ),
      ledgerURL: root.appendingPathComponent("activity.json")
    )
    let start = Date(timeIntervalSince1970: 10_000)

    await recorder.poll(now: start)
    fetching = true
    await recorder.poll(now: start.addingTimeInterval(1))
    fetching = false
    await recorder.poll(now: start.addingTimeInterval(2))

    #expect(recorder.ledger.entries.map(\.kind) == [.launch, .fetchStarted, .fetchEnded])
    #expect(countCalls == 3)
    #expect(recorder.latestCounts.map(\.name) == ["recipes"])
    #expect(recorder.ledger.fetchSummary(since: start).empty == 0)
    await recorder.flushPendingSave()
  }

  @Test
  func fetchEndFiveSecondsLaterUsesFreshCounts() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var fetching = false
    var countCalls = 0
    let recorder = SyncActivityRecorder(
      source: SyncActivitySource(
        isEnabled: { true },
        isFetching: { fetching },
        counts: {
          countCalls += 1
          return ["recipes": countCalls <= 2 ? 10 : 11]
        }
      ),
      ledgerURL: root.appendingPathComponent("activity.json")
    )
    let start = Date(timeIntervalSince1970: 15_000)

    await recorder.poll(now: start)
    fetching = true
    await recorder.poll(now: start.addingTimeInterval(1))
    fetching = false
    await recorder.poll(now: start.addingTimeInterval(6))

    #expect(countCalls == 3)
    #expect(recorder.ledger.entries.last?.tableCounts == ["recipes": 11])
    await recorder.flushPendingSave()
  }

  @Test
  func countsAreThrottledAndSyncOffRecordsNothing() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var enabled = false
    var countCalls = 0
    let recorder = SyncActivityRecorder(
      source: SyncActivitySource(
        isEnabled: { enabled },
        isFetching: { false },
        counts: {
          countCalls += 1
          return ["recipes": countCalls]
        }
      ),
      ledgerURL: root.appendingPathComponent("activity.json")
    )
    let start = Date(timeIntervalSince1970: 20_000)

    await recorder.poll(now: start)
    #expect(recorder.ledger.entries.isEmpty)
    enabled = true
    await recorder.poll(now: start.addingTimeInterval(1))
    await recorder.scenePhaseChanged(isForeground: true, now: start.addingTimeInterval(15))
    await recorder.scenePhaseChanged(isForeground: false, now: start.addingTimeInterval(29))
    #expect(countCalls == 1)
    await recorder.scenePhaseChanged(isForeground: true, now: start.addingTimeInterval(31))

    #expect(countCalls == 2)
    #expect(recorder.ledger.entries.map(\.kind) == [.launch, .foreground, .background, .foreground])
    await recorder.flushPendingSave()
  }

  @Test
  func liveCountReadIncludesEverySyncedTable() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("YesChefSyncActivityRecorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try await withDependencies {
      try $0.bootstrapDatabase()
    } operation: {
      let recorder = SyncActivityRecorder(
        source: SyncActivitySource(isEnabled: { true }, isFetching: { false }, counts: nil),
        ledgerURL: root.appendingPathComponent("activity.json")
      )
      await recorder.poll(now: Date(timeIntervalSince1970: 30_000))

      #expect(recorder.latestCounts.map(\.name) == YesChefCloudSync.syncedTables.recordTypes.sorted())
      await recorder.flushPendingSave()
    }
  }
}
